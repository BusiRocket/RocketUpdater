#!/bin/bash

PLUGIN_NAME="Yarn Metadata Report"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=120
PLUGIN_SCHEDULE_ACTION=run

update_yarnmetadata() {
    local metadata_root
    metadata_root="$HOME/.yarn/berry/metadata"

    if [ ! -d "$metadata_root" ]; then
        echo_skip "Yarn Berry metadata cache is absent"
        return 20
    fi

    local old_file_count
    old_file_count=$(find "$metadata_root" -type f -mtime +30 -print |
        wc -l | tr -d ' ')

    du -sh "$metadata_root" 2>&1
    printf 'yarn_metadata files_older_than_30_days=%s\n' "$old_file_count"
    echo_warning "Metadata deletion remains manual"
    return 0
}
