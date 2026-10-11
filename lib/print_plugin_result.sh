#!/bin/bash

# print_plugin_result STATUS NAME SECONDS ITEMS_FILE prints the permanent
# block for one plugin in the compact interface: a status line, then the
# messages worth keeping. Success messages are dropped because the status
# line already says it; info never reaches ITEMS_FILE.
print_plugin_result() {
    local plugin_status=$1
    local plugin_name=$2
    local duration_seconds=$3
    local items_file=$4
    local icon
    local color
    local label=''
    local duration
    local level
    local text

    case $plugin_status in
    0)
        icon='✓'
        color='\033[0;32m'
        ;;
    20)
        icon='⊘'
        color='\033[0;90m'
        label='skipped'
        ;;
    124 | 137)
        icon='✗'
        color='\033[0;31m'
        label='timed out'
        ;;
    *)
        icon='✗'
        color='\033[0;31m'
        label="failed (status $plugin_status)"
        ;;
    esac

    format_duration duration "$duration_seconds"
    printf '  %b%s\033[0m %-30s \033[90m%6s\033[0m  %b%s\033[0m\n' \
        "$color" "$icon" "$plugin_name" "$duration" "$color" "$label"

    [ -s "$items_file" ] || return 0
    while IFS=$'\t' read -r level text; do
        case $level in
        change) printf '      \033[0;32m↑\033[0m %s\n' "$text" ;;
        warning) printf '      \033[1;33m!\033[0m %s\n' "$text" ;;
        error) printf '      \033[0;31m✗\033[0m %s\n' "$text" ;;
        skip | note) printf '      \033[90m⊙ %s\033[0m\n' "$text" ;;
        esac
    done <"$items_file"
}
