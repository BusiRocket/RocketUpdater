#!/bin/bash

PLUGIN_NAME="Composer Backup Report"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=60
PLUGIN_SCHEDULE_ACTION=run

update_composerbackups() {
    local composer_home
    composer_home="$HOME/.composer"

    if [ ! -d "$composer_home" ]; then
        echo_skip "Composer home is absent"
        return 20
    fi

    local candidates
    if ! candidates=$(find "$composer_home" -maxdepth 1 -type f \
        -name '*-old.phar' -mtime +30 -print 2>&1); then
        printf '%s\n' "$candidates"
        return 1
    fi

    if [ -z "$candidates" ]; then
        echo_skip "No Composer backup older than 30 days"
        return 20
    fi

    printf '%s\n' "$candidates"
    du -sh "$composer_home" 2>&1
    echo_warning "Backup removal remains manual"
    return 0
}
