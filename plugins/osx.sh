#!/bin/bash

PLUGIN_NAME="OSX"
PLUGIN_VERSION="1.1.0"
DISABLE=false
PLUGIN_PRIORITY=100
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run
# Last: system update downloads can be large and should not delay other plugins.

check_osx() {
    [[ $OSTYPE == "darwin"* ]] && [ -x /usr/sbin/softwareupdate ]
}

update_osx() {
    if ! check_osx; then
        echo_skip "macOS softwareupdate is unavailable. Skipping..."
        return 20
    fi

    echo_info "macOS: Checking for software updates..."

    local updates
    local softwareupdate_status

    if ! updates=$(/usr/sbin/softwareupdate -l 2>&1); then
        printf '%s\n' "$updates"
        echo_error "macOS: Could not list available updates"
        return 1
    fi

    if echo "$updates" | grep -q "No new software available"; then
        echo_skip "No macOS updates available"
        return 0
    fi

    printf '%s\n' "$updates"
    echo_info "macOS: Downloading recommended updates..."
    sudo -n /usr/sbin/softwareupdate -d -r
    softwareupdate_status=$?
    if [ "$softwareupdate_status" -ne 0 ]; then
        echo_error "macOS: Could not download recommended updates"
        return 1
    fi

    echo_success "macOS update download completed"
    return 0
}
