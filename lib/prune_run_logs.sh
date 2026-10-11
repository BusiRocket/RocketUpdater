#!/bin/bash

# prune_run_logs DIRECTORY KEEP removes all but the newest KEEP run-*.log files
# in DIRECTORY. They are this tool's own per-run logs, recreated on every
# manual run, so they are deleted outright rather than sent to the Trash.
prune_run_logs() {
    local directory=$1
    local keep=$2
    local run_log
    local seen=0

    while IFS= read -r run_log; do
        seen=$((seen + 1))
        if [ "$seen" -gt "$keep" ]; then
            /bin/rm -f -- "$directory/$run_log"
        fi
    done < <(cd "$directory" 2>/dev/null && /bin/ls -1t -- run-*.log 2>/dev/null)
}
