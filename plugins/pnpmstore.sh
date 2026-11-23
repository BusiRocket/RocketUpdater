#!/bin/bash

PLUGIN_NAME="pnpm Store Prune"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=85
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

# pnpm's prune removes only packages no project references any more, from the
# store the active pnpm uses. The older v10 and v3 stores are left alone:
# projects still pin pnpm 10 and 9, and only a matching pnpm may prune them.
update_pnpmstore() {
    if ! command_exists pnpm; then
        echo_skip "pnpm is not installed"
        return 20
    fi

    local store_path
    if ! store_path=$(pnpm store path 2>/dev/null) || [ ! -d "$store_path" ]; then
        echo_skip "pnpm has no store to prune"
        return 20
    fi

    # A prune during an install could drop a package the install is linking.
    if pgrep -f 'pnpm (install|add|update|i )' >/dev/null 2>&1; then
        echo_skip "A pnpm install is running; store prune deferred"
        return 20
    fi

    echo_info "pnpm: Pruning unreferenced packages from $store_path..."
    if ! pnpm store prune 2>&1; then
        echo_error "pnpm store prune failed"
        return 1
    fi
    echo_success "pnpm store pruned"
    return 0
}
