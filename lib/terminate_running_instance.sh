#!/bin/bash

# Terminates the RocketUpdater run recorded in the lock directory's run.pid so
# a --force run can take the lock. The pid is trusted only while ps shows it is
# still a RocketUpdater.sh process; a reused pid is left alone. The whole
# process tree is signalled at once because bash defers its EXIT trap until
# the plugin it is waiting on returns. Prints the terminated pid on success.
# Returns 0 when nothing was running or the run is gone, 1 when it survived.
terminate_running_instance() {
    local lock_directory=$1
    local pid_file="$lock_directory/run.pid"
    local pid
    local command_line
    local tree
    local attempt

    [ -f "$pid_file" ] || return 0
    pid=$(<"$pid_file")
    case $pid in
    '' | *[!0-9]*) return 0 ;;
    esac
    command_line=$(ps -o command= -p "$pid" 2>/dev/null) || return 0
    case $command_line in
    *RocketUpdater.sh*) ;;
    *) return 0 ;;
    esac

    tree=$(list_process_tree "$pid")
    # shellcheck disable=SC2086
    kill -TERM $tree 2>/dev/null || true
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
        # shellcheck disable=SC2086
        kill -KILL $tree 2>/dev/null || true
        for attempt in 1 2 3 4 5; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 1
        done
    fi
    if kill -0 "$pid" 2>/dev/null; then
        return 1
    fi
    printf '%s\n' "$pid"
}
