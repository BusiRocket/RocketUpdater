#!/bin/bash

PLUGIN_NAME="Dart Analysis Cache Cleanup"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

# The Dart analysis server rebuilds .analysis-driver from the projects it opens;
# a file untouched for 30 days belongs to a project no editor has analysed in
# that time. They go to the Trash, so space returns when it is emptied. The
# sibling .instrumentation, .plugin_manager and .prompts are not caches.
update_dartanalysis() {
    local driver_root="$HOME/.dartServer/.analysis-driver"
    if [ ! -d "$driver_root" ]; then
        echo_skip "No Dart analysis cache"
        return 20
    fi

    if pgrep -f 'analysis_server|dart(aotruntime)? .*language-server' >/dev/null 2>&1; then
        echo_skip "A Dart analysis server is running; cache cleanup deferred"
        return 20
    fi

    # Tests point this at a stand-in; nothing else should.
    local trash_command=${ROCKETUPDATER_TRASH_COMMAND:-/usr/bin/trash}
    local old_file_count
    old_file_count=$(find "$driver_root" -xdev -type f -mtime +30 -print | wc -l | tr -d ' ')
    if [ "$old_file_count" -eq 0 ]; then
        echo_success "No Dart analysis cache older than 30 days"
        return 0
    fi

    echo_info "Dart: Moving $old_file_count analysis cache files older than 30 days to the Trash..."
    if ! find "$driver_root" -xdev -type f -mtime +30 -exec "$trash_command" {} + 2>&1; then
        echo_error "Moving old Dart analysis cache to the Trash failed"
        return 1
    fi
    echo_change "Dart analysis cache: $old_file_count old files to the Trash"
    return 0
}
