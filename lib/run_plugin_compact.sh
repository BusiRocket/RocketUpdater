#!/bin/bash

# run_plugin_compact ROOT NAME TIMEOUT FILE FUNCTION ITEMS_FILE RUN_LOG runs one
# plugin exactly as the verbose path does, but behind the progress renderer,
# and returns the plugin's own exit status. The pipeline's subshells cannot
# return it, so it travels through a temporary file that also stops the ticks.
run_plugin_compact() {
    local root_dir=$1
    local plugin_name=$2
    local timeout_seconds=$3
    local plugin_file=$4
    local plugin_function=$5
    local items_file=$6
    local run_log=$7
    local status_file
    local plugin_status

    status_file=$(/usr/bin/mktemp -t rocketupdater-status) || return 70

    {
        emit_ui_ticks "$status_file" &
        ROCKETUPDATER_UI=compact /opt/homebrew/bin/timeout --kill-after=30s "$timeout_seconds" \
            /bin/bash "$root_dir/scripts/run-plugin.sh" "$plugin_file" "$plugin_function" \
            </dev/null 2>&1
        printf '%s\n' "$?" >"$status_file"
        wait
    } | render_plugin_progress "$plugin_name" "$items_file" "$run_log"

    plugin_status=$(/bin/cat "$status_file")
    /bin/rm -f -- "$status_file"
    return "${plugin_status:-70}"
}
