#!/bin/bash

PLUGIN_NAME="uv Cache Prune"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=85
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

# uv's own prune removes only cache entries no longer referenced, and takes
# uv's cache lock, so a concurrent uv either finishes first or the prune gives
# up after the timeout. Never --force, never --ci, never the directory itself.
update_uvcache() {
    if ! command_exists uv; then
        echo_skip "uv is not installed"
        return 20
    fi

    echo_info "uv: Pruning unused cache entries..."
    local prune_output
    if ! prune_output=$(UV_LOCK_TIMEOUT=30 uv cache prune 2>&1); then
        printf '%s\n' "$prune_output"
        # Every long-lived `uv run` (an MCP server, a local service) holds the
        # cache lock for as long as it runs, so a held lock is the normal state.
        case $prune_output in
        *"waiting for lock"*)
            echo_skip "uv cache is in use by a running uv process; prune deferred"
            return 20
            ;;
        esac
        echo_error "uv cache prune failed"
        return 1
    fi
    printf '%s\n' "$prune_output"
    echo_success "uv cache pruned"
    return 0
}
