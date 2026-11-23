#!/bin/bash

# Sourced by plugin tests (the .bash suffix keeps the regression runner from
# executing it as a test). Runs one plugin function the way the runner does:
# a fresh bash with the message helpers loaded, shims first on PATH, no stdin.
# Callers export HOME and any variable the plugin reads before calling it.
run_plugin_function() {
    local root_dir=$1
    local plugin_file=$2
    local function_name=$3
    local shim_dir=$4
    local output_file=$5

    PATH="$shim_dir:/usr/bin:/bin" /bin/bash -c '
        set -u
        for helper in print_message echo_info echo_success echo_warning echo_error echo_skip echo_note echo_change command_exists; do
            source "$1/lib/$helper.sh"
        done
        source "$2"
        "$3"
    ' plugin-test "$root_dir" "$plugin_file" "$function_name" </dev/null >"$output_file" 2>&1
}
