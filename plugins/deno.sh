#!/bin/bash

PLUGIN_NAME="Deno Cache Report"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=300
PLUGIN_SCHEDULE_ACTION=run

update_deno() {
    if ! command_exists deno; then
        echo_skip "Deno is not installed"
        return 20
    fi

    local info
    if ! info=$(deno info --json 2>&1); then
        printf '%s\n' "$info"
        return 1
    fi
    printf '%s\n' "$info"

    local origin_storage
    origin_storage=$(printf '%s\n' "$info" |
        sed -n 's/.*"originStorage": *"\([^"]*\)".*/\1/p')
    if [ -n "$origin_storage" ] && [ -d "$origin_storage" ]; then
        echo_warning "Deno origin storage exists at $origin_storage; preserve it"
    fi

    if ! deno clean --dry-run 2>&1; then
        echo_error "Deno cache preview failed"
        return 1
    fi

    return 0
}
