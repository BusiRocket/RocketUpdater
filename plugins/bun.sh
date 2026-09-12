#!/bin/bash

PLUGIN_NAME="Bun Cache Report"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=60
PLUGIN_SCHEDULE_ACTION=run

update_bun() {
    if ! command_exists bun; then
        echo_skip "Bun is not installed"
        return 20
    fi

    # `bun pm cache` needs a package.json in the cwd or above and exits 1
    # without one (a scheduled run from $HOME), so fall back to bun's default
    # cache location instead of failing the plugin.
    local cache_path
    if ! cache_path=$(bun pm cache 2>/dev/null); then
        cache_path="${BUN_INSTALL:-$HOME/.bun}/install/cache"
        echo_warning "bun pm cache needs a package.json here; assuming ${cache_path}"
    fi

    printf 'bun_cache path=%s\n' "$cache_path"
    if [ -d "$cache_path" ]; then
        du -sh "$cache_path" 2>&1
    fi
    echo_warning "Bun cache removal remains manual because the current cache is low value"
    return 0
}
