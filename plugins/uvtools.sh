#!/bin/bash

PLUGIN_NAME="uv Tools"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=60
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

update_uvtools() {
    if ! command_exists uv; then
        echo_skip "uv is not installed"
        return 20
    fi

    local tool_list
    if ! tool_list=$(uv tool list 2>&1); then
        printf '%s\n' "$tool_list"
        echo_error "uv tool inventory failed"
        return 1
    fi

    printf '%s\n' "$tool_list"

    local tools
    tools=$(printf '%s\n' "$tool_list" |
        awk '/^[a-zA-Z]/ {print $1}' |
        grep -v '^mempalace$' || true)

    if [ -z "$tools" ]; then
        echo_skip "No eligible uv tools are installed"
        return 20
    fi

    local has_failures=0
    local tool_name
    while IFS= read -r tool_name; do
        [ -n "$tool_name" ] || continue
        echo_info "uv: Upgrading $tool_name..."
        if ! UV_LOCK_TIMEOUT=30 uv tool upgrade --no-progress "$tool_name" 2>&1; then
            has_failures=1
            echo_warning "uv tool upgrade failed or was locked: $tool_name"
        fi
    done <<<"$tools"

    if [ "$has_failures" -ne 0 ]; then
        return 1
    fi

    echo_success "Eligible uv tools updated"
    return 0
}
