#!/bin/bash

PLUGIN_NAME="Deno Cache Clean"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=300
PLUGIN_SCHEDULE_ACTION=run

# `deno clean` empties DENO_DIR, which holds downloaded modules and compiled
# output that Deno fetches again on the next run. DENO_DIR can also hold origin
# storage (localStorage and KV data written by programs), which is nobody's
# cache, so while that exists only the preview runs.
update_deno() {
    if ! command_exists deno; then
        echo_skip "Deno is not installed"
        return 20
    fi

    local info
    if ! info=$(deno info --json 2>&1); then
        printf '%s\n' "$info"
        echo_error "deno info failed; cache left alone"
        return 1
    fi

    local origin_storage
    origin_storage=$(printf '%s\n' "$info" |
        sed -n 's/.*"originStorage": *"\([^"]*\)".*/\1/p')
    if [ -n "$origin_storage" ] && [ -d "$origin_storage" ] &&
        [ -n "$(find "$origin_storage" -mindepth 1 -print -quit 2>/dev/null)" ]; then
        echo_note "Deno origin storage holds data at $origin_storage; preview only, nothing deleted"
        deno clean --dry-run 2>&1 | sed 's/^Removed/Would remove/'
        return 0
    fi

    if pgrep -x deno >/dev/null 2>&1; then
        echo_skip "Deno is running; cache clean deferred"
        return 20
    fi

    echo_info "Deno: Cleaning the module cache..."
    if ! deno clean 2>&1; then
        echo_error "deno clean failed"
        return 1
    fi
    echo_success "Deno cache cleaned"
    return 0
}
