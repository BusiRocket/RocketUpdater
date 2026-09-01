#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

FIXTURE_DIR=$(runner_fixture_create "$ROOT_DIR" "result-aggregation")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$STATE_DIR"
trap 'runner_fixture_cleanup "$FIXTURE_DIR"' EXIT

create_plugin() {
    local filename=$1
    local function_name=$2
    local status=$3
    local disabled=$4
    cat >"$FIXTURE_DIR/plugins/$filename.sh" <<EOF
PLUGIN_NAME="$filename"
PLUGIN_VERSION="1.0.0"
DISABLE=$disabled
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_$function_name() {
    return $status
}
EOF
}

create_plugin a_success a_success 0 false
create_plugin b_failure b_failure 1 false
create_plugin c_skipped c_skipped 20 false
create_plugin d_timeout d_timeout 124 false

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" RUNNER_TEST_STATE="$STATE_DIR" \
    /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" >"$STATE_DIR/failures.out" 2>&1
FAILURE_STATUS=$?
set -e

if [ "$FAILURE_STATUS" -ne 1 ] || ! grep -q 'Total: 4' "$STATE_DIR/failures.out" ||
    ! grep -q 'Successful: 1' "$STATE_DIR/failures.out" || ! grep -q 'Failed: 2' "$STATE_DIR/failures.out" ||
    ! grep -q 'Skipped: 1' "$STATE_DIR/failures.out"; then
    echo "RED result aggregation: 0, 1, 20, and 124 were not counted as 1 success, 2 failures, and 1 skip"
    exit 1
fi

rm -f "$FIXTURE_DIR/plugins/b_failure.sh" "$FIXTURE_DIR/plugins/d_timeout.sh"
create_plugin e_disabled e_disabled 0 true
set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" RUNNER_TEST_STATE="$STATE_DIR" \
    /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" >"$STATE_DIR/disabled.out" 2>&1
DISABLED_STATUS=$?
set -e

if [ "$DISABLED_STATUS" -ne 0 ] || ! grep -q 'Total: 3' "$STATE_DIR/disabled.out" ||
    ! grep -q 'Successful: 1' "$STATE_DIR/disabled.out" || ! grep -q 'Skipped: 2' "$STATE_DIR/disabled.out" ||
    ! grep -q 'No plugin failures' "$STATE_DIR/disabled.out" || grep -q 'All updates completed' "$STATE_DIR/disabled.out"; then
    echo "RED result aggregation: disabled plugins were not counted as skips with the no-failure summary"
    exit 1
fi

echo "result aggregation contract passed"
