#!/bin/bash

PLUGIN_NAME="Cursor Agent"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=60
PLUGIN_TIMEOUT_SECONDS=600
PLUGIN_SCHEDULE_ACTION=run

# Cursor Agent's native install lives outside Homebrew and npm and is updated
# with its own subcommand.
update_cursoragent() {
    local agent_path="$HOME/.local/bin/cursor-agent"
    if [ ! -x "$agent_path" ]; then
        echo_skip "No native Cursor Agent install in ~/.local/bin"
        return 20
    fi

    local version_before
    version_before=$("$agent_path" --version 2>&1)
    echo_info "Cursor Agent: Updating ($version_before)..."
    if ! "$agent_path" update 2>&1; then
        echo_error "Cursor Agent update failed"
        return 1
    fi

    local version_after
    version_after=$("$agent_path" --version 2>&1)
    if [ "$version_after" != "$version_before" ]; then
        echo_change "Cursor Agent $version_before -> $version_after"
    fi
    echo_success "Cursor Agent is current ($version_after)"
    return 0
}
