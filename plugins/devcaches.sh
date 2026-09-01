#!/bin/bash

PLUGIN_NAME="DevCaches"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run
# Report-only: uv, pnpm, and pip cache contents have no per-object public
# provenance proof, so their removal stays a manual decision.

report_devcache_directory() {
    local cache_label=$1
    local cache_dir=$2

    if [ -n "$cache_dir" ] && [ -d "$cache_dir" ]; then
        printf 'devcache %s=%s\n' "$cache_label" "$cache_dir"
        du -sk "$cache_dir" 2>&1
    else
        echo_skip "No $cache_label cache directory to report"
    fi
}

update_devcaches() {
    if command -v uv >/dev/null 2>&1; then
        report_devcache_directory uv "$(UV_LOCK_TIMEOUT=10 uv cache dir 2>/dev/null)"
    else
        echo_skip "uv is not installed"
    fi

    if command -v pnpm >/dev/null 2>&1; then
        report_devcache_directory pnpm-store "$(pnpm store path 2>/dev/null)"
    else
        echo_skip "pnpm is not installed"
    fi

    if command -v pip3 >/dev/null 2>&1; then
        report_devcache_directory pip "$(pip3 cache dir 2>/dev/null)"
    else
        echo_skip "pip3 is not installed"
    fi

    return 0
}
