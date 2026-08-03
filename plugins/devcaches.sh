#!/bin/bash

PLUGIN_NAME="DevCaches"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false}
# Cleanup: npm/yarn/pnpm must have finished downloading before pruning.
PLUGIN_PRIORITY=80

# Developer-tool caches not covered by other plugins or by Mole:
# uv (Python), pnpm content-addressable store, pip. npm/yarn/composer
# caches are handled by their own plugins.
update_devcaches() {
    # uv keeps a global wheel cache that grows unbounded. Serena MCP servers
    # (uvx) hold the cache lock while Claude Code sessions are open, so fail
    # fast instead of hanging for 300s and treat the lock as a skip.
    if command -v uv >/dev/null 2>&1; then
        echo_info "uv: Pruning unused cache entries..."
        if UV_LOCK_TIMEOUT=10 uv cache prune 2>&1; then
            echo_success "uv cache pruned"
        else
            echo_skip "uv cache locked by idle uvx servers (run 'uv cache prune --force' manually if safe)"
        fi
    else
        echo_skip "uv is not installed"
    fi

    if command -v pnpm >/dev/null 2>&1; then
        echo_info "pnpm: Pruning unreferenced packages from store..."
        pnpm store prune 2>&1 | tail -2 || true
        echo_success "pnpm store pruned"
    else
        echo_skip "pnpm is not installed"
    fi

    if command -v pip3 >/dev/null 2>&1; then
        echo_info "pip: Purging download cache..."
        pip3 cache purge 2>&1 | tail -1 || true
        echo_success "pip cache purged"
    else
        echo_skip "pip3 is not installed"
    fi

    return 0
}
