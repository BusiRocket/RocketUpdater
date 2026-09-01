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

    local cache_path
    if ! cache_path=$(bun pm cache 2>&1); then
        printf '%s\n' "$cache_path"
        return 1
    fi

    printf 'bun_cache path=%s\n' "$cache_path"
    if [ -d "$cache_path" ]; then
        du -sh "$cache_path" 2>&1
    fi
    echo_warning "Bun cache removal remains manual because the current cache is low value"
    return 0
}
