#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

FIXTURE_DIR=$(runner_fixture_create "$ROOT_DIR" "plugin-timeout")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$STATE_DIR"
trap '[ -f "$STATE_DIR/child.pid" ] && kill "$(cat "$STATE_DIR/child.pid")" 2>/dev/null || true; [ -n "${RUNNER_PID:-}" ] && kill "$RUNNER_PID" 2>/dev/null || true; [ -n "${RUNNER_PID:-}" ] && wait "$RUNNER_PID" 2>/dev/null || true; runner_fixture_cleanup "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/plugins/sleeper.sh" <<'EOF'
PLUGIN_NAME="Sleeper"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=1
PLUGIN_SCHEDULE_ACTION=run

update_sleeper() {
    (
        while true; do
            sleep 1
        done
    ) &
    printf '%s\n' "$!" >"$RUNNER_TEST_STATE/child.pid"
    while true; do
        sleep 1
    done
}
EOF

PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" RUNNER_TEST_STATE="$STATE_DIR" \
    /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" sleeper >"$STATE_DIR/output" 2>&1 &
RUNNER_PID=$!

# Preflight runs before any plugin — disk, DNS, and now a two-sample `top` when
# the load is above the CPU count — so on a busy machine the plugin starts well
# after five seconds. Waiting only that long made this test fail for load rather
# than for the contract it checks.
for _ in $(seq 1 60); do
    [ -f "$STATE_DIR/child.pid" ] && break
    sleep 1
done

if [ ! -f "$STATE_DIR/child.pid" ]; then
    echo "RED plugin timeout: fixture child never started"
    exit 1
fi

# The plugin's own timeout is 1s, but the runner gives it `--kill-after=30s`, so
# a runner that is doing the right thing can still take half a minute to exit.
for _ in $(seq 1 60); do
    if ! kill -0 "$RUNNER_PID" 2>/dev/null; then
        break
    fi
    sleep 1
done

if kill -0 "$RUNNER_PID" 2>/dev/null; then
    echo "RED plugin timeout: runner did not terminate the plugin at its declared timeout"
    exit 1
fi

wait "$RUNNER_PID"
RUNNER_STATUS=$?
if [ "$RUNNER_STATUS" -ne 1 ] || ! grep -Eq 'status=124|status 124|timed out' "$STATE_DIR/output"; then
    echo "RED plugin timeout: timeout status 124 was not aggregated as a failure"
    exit 1
fi

CHILD_PID=$(cat "$STATE_DIR/child.pid")
if kill -0 "$CHILD_PID" 2>/dev/null; then
    echo "RED plugin timeout: fixture descendant survived timeout cleanup"
    exit 1
fi

echo "plugin timeout contract passed"
