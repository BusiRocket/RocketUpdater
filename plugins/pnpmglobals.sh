#!/bin/bash

PLUGIN_NAME="pnpm Globals"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=60
PLUGIN_TIMEOUT_SECONDS=900
PLUGIN_SCHEDULE_ACTION=run

# pnpm keeps its own global tree, separate from npm's, so the npm plugin's
# "all globals up to date" never covered it. That tree includes a pnpm, which
# is the one first on PATH, so it is updated too rather than left behind.
update_pnpmglobals() {
    if ! command_exists pnpm; then
        echo_skip "pnpm is not installed"
        return 20
    fi

    local globals_before
    if ! globals_before=$(pnpm list --global --depth=0 2>&1); then
        printf '%s\n' "$globals_before"
        echo_error "pnpm global inventory failed"
        return 1
    fi
    case $globals_before in
    *'dependencies:'*) ;;
    *)
        echo_skip "pnpm has no global packages"
        return 20
        ;;
    esac

    echo_info "pnpm: Updating global packages..."
    if ! pnpm update --global --latest 2>&1; then
        echo_error "pnpm global update failed"
        return 1
    fi

    local globals_after
    globals_after=$(pnpm list --global --depth=0 2>&1)
    printf '%s\n' "$globals_after"
    if [ "$globals_after" != "$globals_before" ]; then
        echo_change "pnpm globals"
    fi
    echo_success "pnpm globals are current"
    return 0
}
