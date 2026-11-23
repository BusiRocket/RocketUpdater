#!/bin/bash

PLUGIN_NAME="Yarn Metadata Cleanup"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

# Yarn Berry's registry metadata is a cache of package manifests; Yarn fetches
# them again when a resolution needs one. Files untouched for 30 days go to the
# Trash, so space returns only when the Trash is emptied. The package ZIP cache
# next to it is a live install store and is never touched.
update_yarnmetadata() {
    local metadata_root="$HOME/.yarn/berry/metadata"
    if [ ! -d "$metadata_root" ]; then
        echo_skip "Yarn Berry metadata cache is absent"
        return 20
    fi

    if pgrep -f 'yarn(\.js|\.cjs)? (install|add|up)' >/dev/null 2>&1; then
        echo_skip "A Yarn install is running; metadata cleanup deferred"
        return 20
    fi

    # Tests point this at a stand-in; nothing else should.
    local trash_command=${ROCKETUPDATER_TRASH_COMMAND:-/usr/bin/trash}
    local old_file_count
    old_file_count=$(find "$metadata_root" -xdev -type f -mtime +30 -print | wc -l | tr -d ' ')
    if [ "$old_file_count" -eq 0 ]; then
        echo_success "No Yarn metadata older than 30 days"
        return 0
    fi

    echo_info "Yarn: Moving $old_file_count metadata files older than 30 days to the Trash..."
    if ! find "$metadata_root" -xdev -type f -mtime +30 -exec "$trash_command" {} + 2>&1; then
        echo_error "Moving old Yarn metadata to the Trash failed"
        return 1
    fi
    echo_change "Yarn metadata: $old_file_count old files to the Trash"
    return 0
}
