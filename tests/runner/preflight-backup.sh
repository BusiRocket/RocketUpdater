#!/bin/bash

# Contract: a Backblaze transmit within the last 7 days counts as a backup, so
# the preflight reports backup=backblaze and does not warn about Time Machine.
# An older transmit does not count.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

FIXTURE_DIR=$(runner_fixture_create "$ROOT_DIR" "preflight-backup")
STATE_DIR="$FIXTURE_DIR/state"
DATACENTER_DIR="$STATE_DIR/bzdatacenter"
mkdir -p "$STATE_DIR" "$DATACENTER_DIR"
trap 'runner_fixture_cleanup "$FIXTURE_DIR"' EXIT

run_preflight_only() {
    PATH="$FIXTURE_DIR/bin:/opt/homebrew/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" NO_COLOR=1 \
        RUNNER_TEST_STATE="$STATE_DIR" ROCKETUPDATER_BACKBLAZE_DATACENTER="$DATACENTER_DIR" \
        /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" --preflight-only >"$1" 2>&1
}

: >"$DATACENTER_DIR/bz_done_20260917_0.dat"
run_preflight_only "$STATE_DIR/recent.out"
if ! grep -q '^preflight backup=backblaze$' "$STATE_DIR/recent.out"; then
    cat "$STATE_DIR/recent.out"
    echo "RED preflight backup: a Backblaze transmit from today was not reported as backup=backblaze"
    exit 1
fi
if grep -q 'Time Machine' "$STATE_DIR/recent.out"; then
    echo "RED preflight backup: a recent Backblaze transmit still warned about Time Machine"
    exit 1
fi

touch -t "$(/bin/date -v-10d '+%Y%m%d%H%M')" "$DATACENTER_DIR/bz_done_20260917_0.dat"
run_preflight_only "$STATE_DIR/stale.out"
if grep -q '^preflight backup=backblaze$' "$STATE_DIR/stale.out"; then
    echo "RED preflight backup: a 10-day-old Backblaze transmit was reported as backup=backblaze"
    exit 1
fi

echo "preflight backup contract passed"
