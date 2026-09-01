#!/bin/bash

PLUGIN_NAME="Cargo Source Cache Report"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=300
PLUGIN_SCHEDULE_ACTION=run

update_cargosources() {
    local source_root
    local cache_root
    source_root="$HOME/.cargo/registry/src"
    cache_root="$HOME/.cargo/registry/cache"

    if [ ! -d "$source_root" ]; then
        echo_skip "Cargo registry source cache is absent"
        return 20
    fi

    local source_count
    local archive_count
    local missing_count
    source_count=$(find "$source_root" -mindepth 2 -maxdepth 2 -type d -print |
        wc -l | tr -d ' ')
    archive_count=$(find "$cache_root" -mindepth 2 -maxdepth 2 -type f \
        -name '*.crate' -print 2>/dev/null | wc -l | tr -d ' ')
    missing_count=$(
        comm -23 \
            <(find "$source_root" -mindepth 2 -maxdepth 2 -type d -print |
                sed 's#^.*/##' | sort -u) \
            <(find "$cache_root" -mindepth 2 -maxdepth 2 -type f \
                -name '*.crate' -print 2>/dev/null |
                sed -e 's#^.*/##' -e 's/\.crate$//' | sort -u) |
            wc -l | tr -d ' '
    )

    du -sh "$source_root" "$cache_root" 2>&1
    printf 'cargo_sources extracted=%s archives=%s without_archive=%s\n' \
        "$source_count" "$archive_count" "$missing_count"
    echo_warning "Never remove the whole registry source directory"
    return 0
}
