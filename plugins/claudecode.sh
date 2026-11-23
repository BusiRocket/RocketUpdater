#!/bin/bash

PLUGIN_NAME="Claude Code"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=60
PLUGIN_TIMEOUT_SECONDS=600
PLUGIN_SCHEDULE_ACTION=run

# The native installer lives outside Homebrew and npm. It updates itself while
# a session runs; this is the fallback for a machine where no session started
# for days. It touches the executable only, never marketplaces or plugins.
update_claudecode() {
    local claude_path="$HOME/.local/bin/claude"
    if [ ! -x "$claude_path" ]; then
        echo_skip "No native Claude Code install in ~/.local/bin"
        return 20
    fi

    local version_before
    version_before=$("$claude_path" --version 2>&1)
    echo_info "Claude Code: Updating ($version_before)..."
    if ! "$claude_path" update 2>&1; then
        echo_error "Claude Code update failed"
        return 1
    fi

    local version_after
    version_after=$("$claude_path" --version 2>&1)
    if [ "$version_after" != "$version_before" ]; then
        echo_change "Claude Code $version_before -> $version_after"
    fi
    echo_success "Claude Code is current ($version_after)"
    return 0
}
