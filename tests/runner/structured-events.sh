#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

FIXTURE_DIR=$(runner_fixture_create "$ROOT_DIR" "structured-events")
STATE_DIR="$FIXTURE_DIR/state"
EVENT_LOG="$FIXTURE_DIR/home/Library/Logs/RocketUpdater/events.log"
EVENT_DIRECTORY="$FIXTURE_DIR/home/Library/Logs/RocketUpdater"
SANITIZED_EVENT_LOG="$STATE_DIR/sanitized-events.log"
mkdir -p "$STATE_DIR"
trap 'runner_fixture_cleanup "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/plugins/event_fixture.sh" <<'EOF'
PLUGIN_NAME="Event fixture"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_event_fixture() {
    printf 'event fixture completed\n'
}
EOF

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" RUNNER_TEST_STATE="$STATE_DIR" NO_COLOR=1 \
    /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" event_fixture >"$STATE_DIR/output" 2>&1
RUNNER_STATUS=$?
set -e

if [ "$RUNNER_STATUS" -ne 0 ] || [ ! -f "$EVENT_LOG" ]; then
    echo "RED structured events: runner did not create the authoritative event log"
    exit 1
fi

if [ "$(stat -f '%Lp' "$EVENT_DIRECTORY")" != "700" ] || [ "$(stat -f '%Lp' "$EVENT_LOG")" != "600" ] ||
    ! awk -F '\t' 'NF != 8 { exit 1 } { ids[$1] = 1 } END { exit length(ids) != 1 }' "$EVENT_LOG"; then
    echo "RED structured events: event records do not preserve 0600 eight-field sanitized run data"
    exit 1
fi

RUN_ID=$(awk -F '\t' 'NR == 1 { print $1 }' "$EVENT_LOG")
if ! [[ $RUN_ID =~ ^[0-9]{8}T[0-9]{6}Z\.[0-9]+$ ]] || LC_ALL=C grep -q $'\033' "$STATE_DIR/output"; then
    echo "RED structured events: run ID is not one UTC basic timestamp plus PID or non-TTY output contains ANSI"
    exit 1
fi

for event_name in run_start preflight plugin_start plugin_end run_end; do
    if ! awk -F '\t' -v event_name="$event_name" '$4 == event_name { found = 1 } END { exit !found }' "$EVENT_LOG"; then
        echo "RED structured events: missing $event_name event"
        exit 1
    fi
done

ROCKETUPDATER_EVENT_LOG=$SANITIZED_EVENT_LOG
RUN_ID=$'run\tid\nvalue'
export ROCKETUPDATER_EVENT_LOG RUN_ID
source "$ROOT_DIR/lib/log_event.sh"
log_event $'warn\tlevel' $'custom\nevent' $'plug\rin' $'sta\ttus' $'1\n2' $'message\twith\ncontrols\r'

if [ "$(wc -l <"$SANITIZED_EVENT_LOG")" -ne 1 ] ||
    ! awk -F '\t' 'NF == 8 && $1 == "run id value" && $3 == "warn level" && $4 == "custom event" && $5 == "plug in" && $6 == "sta tus" && $7 == "1 2" && $8 == "message with controls " { valid = 1 } END { exit !valid }' "$SANITIZED_EVENT_LOG"; then
    echo "RED structured events: log_event did not sanitize every caller-controlled field into one TSV record"
    exit 1
fi

echo "structured events contract passed"
