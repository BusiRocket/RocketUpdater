#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

FIXTURE_DIR=$(runner_fixture_create "$ROOT_DIR" "lock-contention")
STATE_DIR="$FIXTURE_DIR/state"
FIFO_PATH="$STATE_DIR/blocker.fifo"
LOCK_DIRECTORY="$FIXTURE_DIR/home/Library/Caches/RocketUpdater"
mkdir -p "$STATE_DIR"
mkfifo "$FIFO_PATH"
trap '[ -n "${FIRST_PID:-}" ] && kill "$FIRST_PID" 2>/dev/null || true; [ -n "${SECOND_PID:-}" ] && kill "$SECOND_PID" 2>/dev/null || true; [ -n "${FIRST_PID:-}" ] && wait "$FIRST_PID" 2>/dev/null || true; [ -n "${SECOND_PID:-}" ] && wait "$SECOND_PID" 2>/dev/null || true; runner_fixture_cleanup "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/plugins/blocker.sh" <<'EOF'
PLUGIN_NAME="Blocker"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_blocker() {
    printf 'started\n' >>"$RUNNER_TEST_STATE/starts"
    read -r _ <"$RUNNER_TEST_STATE/blocker.fifo"
}
EOF

PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" RUNNER_TEST_STATE="$STATE_DIR" \
    /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" blocker >"$STATE_DIR/first.out" 2>&1 &
FIRST_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$STATE_DIR/starts" ] && break
    sleep 1
done

if [ ! -f "$STATE_DIR/starts" ]; then
    echo "RED lock contention: blocking fixture never started"
    exit 1
fi

if [ "$(stat -f '%Lp' "$LOCK_DIRECTORY")" != "700" ]; then
    echo "RED lock contention: lock directory mode is not 0700"
    exit 1
fi

PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" RUNNER_TEST_STATE="$STATE_DIR" \
    /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" blocker >"$STATE_DIR/second.out" 2>&1 &
SECOND_PID=$!

for _ in 1 2 3; do
    [ "$(wc -l <"$STATE_DIR/starts")" -ge 2 ] && break
    sleep 1
done

if [ "$(wc -l <"$STATE_DIR/starts")" -ge 2 ]; then
    echo "RED lock contention: second runner started the blocked plugin instead of exiting 75"
    exit 1
fi

wait "$SECOND_PID"
SECOND_STATUS=$?
if [ "$SECOND_STATUS" -ne 75 ]; then
    echo "RED lock contention: second runner exit was $SECOND_STATUS, expected 75"
    exit 1
fi

if [ "$(cat "$STATE_DIR/second.out")" != "RocketUpdater is already running" ]; then
    echo "RED lock contention: busy runner output did not match the lock contract"
    exit 1
fi

kill "$FIRST_PID" 2>/dev/null || true
wait "$FIRST_PID" 2>/dev/null || true
FIRST_PID=""
echo "lock contention contract passed"
