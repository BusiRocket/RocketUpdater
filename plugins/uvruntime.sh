#!/bin/bash

PLUGIN_NAME="uv Runtime"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=55
PLUGIN_TIMEOUT_SECONDS=600
PLUGIN_SCHEDULE_ACTION=run

# The uv first on PATH, launchd's included, is the standalone install in
# ~/.local/bin, which Homebrew never touches: on 2026-11-23 uvtools upgraded
# every tool with uv 0.13.6 while Homebrew already had 0.13.9. A Homebrew uv
# is the homebrew plugin's job, so only the standalone copy is updated here.
update_uvruntime() {
    local uv_path="$HOME/.local/bin/uv"
    if [ ! -x "$uv_path" ]; then
        echo_skip "No standalone uv in ~/.local/bin"
        return 20
    fi

    local version_before
    version_before=$("$uv_path" --version 2>&1)
    echo_info "uv: Updating the standalone install ($version_before)..."

    local update_output
    if ! update_output=$("$uv_path" self update 2>&1); then
        printf '%s\n' "$update_output"
        echo_error "uv self update failed"
        return 1
    fi
    printf '%s\n' "$update_output"

    local version_after
    version_after=$("$uv_path" --version 2>&1)
    if [ "$version_after" != "$version_before" ]; then
        echo_change "uv $version_before -> $version_after"
    fi
    echo_success "Standalone uv is current ($version_after)"
    return 0
}
