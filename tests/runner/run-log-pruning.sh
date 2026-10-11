#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.runner-fixture-run-log-pruning.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

# 33 run logs with increasing mtimes, plus files the pruning must never touch.
index=1
while [ "$index" -le 33 ]; do
    run_log=$(printf 'run-20261011T%06dZ.%d.log' "$index" "$index")
    : >"$FIXTURE_DIR/$run_log"
    /usr/bin/touch -t "$(printf '20261011%04d' "$index")" "$FIXTURE_DIR/$run_log"
    index=$((index + 1))
done
: >"$FIXTURE_DIR/events.jsonl"
: >"$FIXTURE_DIR/scheduled.log"

/bin/bash -c '
    set -u
    source "'"$ROOT_DIR"'/lib/prune_run_logs.sh"
    prune_run_logs "'"$FIXTURE_DIR"'" 30
'

remaining=$(/bin/ls -1 "$FIXTURE_DIR" | grep -c '^run-.*\.log$')
if [ "$remaining" -ne 30 ]; then
    echo "RED run log pruning: expected 30 run logs to remain, found $remaining"
    exit 1
fi

for oldest in 1 2 3; do
    if [ -e "$FIXTURE_DIR/$(printf 'run-20261011T%06dZ.%d.log' "$oldest" "$oldest")" ]; then
        echo "RED run log pruning: an old run log survived while a newer one could be removed"
        exit 1
    fi
done

if [ ! -e "$FIXTURE_DIR/events.jsonl" ] || [ ! -e "$FIXTURE_DIR/scheduled.log" ]; then
    echo "RED run log pruning: a file other than a run log was removed"
    exit 1
fi

# Literal source text, not an expansion.
# shellcheck disable=SC2016
if ! grep -q 'source "\$SCRIPT_DIR/lib/prune_run_logs.sh"' "$ROOT_DIR/RocketUpdater.sh" ||
    ! grep -q 'prune_run_logs "\$EVENT_DIRECTORY" 30' "$ROOT_DIR/RocketUpdater.sh"; then
    echo "RED run log pruning: RocketUpdater does not prune its run logs"
    exit 1
fi

echo "run log pruning contract passed"
