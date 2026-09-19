#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

FIXTURE_DIR=$(runner_fixture_create "$ROOT_DIR" "lock-force")
STATE_DIR="$FIXTURE_DIR/state"
FIFO_PATH="$STATE_DIR/blocker.fifo"
mkdir -p "$STATE_DIR"
mkfifo "$FIFO_PATH"
trap '[ -n "${FIRST_PID:-}" ] && kill "$FIRST_PID" 2>/dev/null || true; [ -n "${SECOND_PID:-}" ] && kill "$SECOND_PID" 2>/dev/null || true; [ -n "${FIRST_PID:-}" ] && wait "$FIRST_PID" 2>/dev/null || true; [ -n "${SECOND_PID:-}" ] && wait "$SECOND_PID" 2>/dev/null || true; runner_fixture_cleanup "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/plugins/blocker.sh" <<'EOF2'
PLUGIN_NAME="Blocker"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_blocker() {
    printf 'started\n' >>"$RUNNER_TEST_STATE/starts"
    if [ "$(wc -l <"$RUNNER_TEST_STATE/starts")" -ge 2 ]; then
        return 0
    fi
    read -r _ <"$RUNNER_TEST_STATE/blocker.fifo"
}
EOF2

run_fixture() {
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" RUNNER_TEST_STATE="$STATE_DIR" \
        /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" "$@"
}

# --force with --scheduled is refused before anything is touched.
run_fixture --force --scheduled blocker >"$STATE_DIR/refused.out" 2>&1
REFUSED_STATUS=$?
if [ "$REFUSED_STATUS" -ne 78 ]; then
    echo "RED lock force: --force --scheduled exit was $REFUSED_STATUS, expected 78"
    exit 1
fi

# --force with nothing running behaves like a plain run.
run_fixture --force blocker >"$STATE_DIR/idle.out" 2>&1 &
SECOND_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$STATE_DIR/starts" ] && break
    sleep 1
done
if [ ! -f "$STATE_DIR/starts" ]; then
    echo "RED lock force: idle --force run never started the plugin"
    exit 1
fi
printf '\n' >"$FIFO_PATH"
wait "$SECOND_PID"
SECOND_PID=""
/bin/rm -f "$STATE_DIR/starts"

# A blocked run is terminated and the forcing run takes over.
run_fixture blocker >"$STATE_DIR/first.out" 2>&1 &
FIRST_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$STATE_DIR/starts" ] && break
    sleep 1
done
if [ ! -f "$STATE_DIR/starts" ]; then
    echo "RED lock force: blocking fixture never started"
    exit 1
fi

run_fixture --force blocker >"$STATE_DIR/second.out" 2>&1 &
SECOND_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ "$(wc -l <"$STATE_DIR/starts")" -ge 2 ] && break
    sleep 1
done
if [ "$(wc -l <"$STATE_DIR/starts")" -lt 2 ]; then
    echo "RED lock force: forcing runner never took over the lock"
    exit 1
fi

wait "$FIRST_PID"
FIRST_STATUS=$?
FIRST_PID=""
if [ "$FIRST_STATUS" -eq 0 ]; then
    echo "RED lock force: terminated runner reported success"
    exit 1
fi

wait "$SECOND_PID"
SECOND_STATUS=$?
SECOND_PID=""
if [ "$SECOND_STATUS" -ne 0 ]; then
    echo "RED lock force: forcing runner exit was $SECOND_STATUS, expected 0"
    exit 1
fi

if ! grep -q "Terminated the running RocketUpdater" "$STATE_DIR/second.out"; then
    echo "RED lock force: forcing runner did not report the terminated run"
    exit 1
fi

if ! grep -q $'\tlock_forced\t' "$FIXTURE_DIR/home/Library/Logs/RocketUpdater/events.log"; then
    echo "RED lock force: lock_forced event was not logged"
    exit 1
fi

echo "lock force contract passed"
