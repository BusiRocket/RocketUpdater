#!/bin/bash

PLUGIN_NAME="OSX"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=100
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run
# Last: system update downloads can be large and should not delay other plugins.

check_osx() {
    [[ $OSTYPE == "darwin"* ]] && [ -x /usr/sbin/softwareupdate ]
}

report_chrome_profile_caches() {
    local chrome_cache_root="$HOME/Library/Caches/Google/Chrome"

    if [ ! -d "$chrome_cache_root" ]; then
        return 0
    fi

    echo_info "Chrome profile caches (report only; removal stays manual):"
    du -sk "$chrome_cache_root"/* 2>/dev/null || true
}

update_osx() {
    if ! check_osx; then
        echo_skip "macOS softwareupdate is unavailable. Skipping..."
        return 20
    fi

    echo_info "macOS: Checking for software updates..."

    local softwareupdate_bin=${ROCKETUPDATER_SOFTWAREUPDATE_BIN:-/usr/sbin/softwareupdate}
    local updates
    local softwareupdate_status

    if ! updates=$("$softwareupdate_bin" -l 2>&1); then
        printf '%s\n' "$updates"
        echo_error "macOS: Could not list available updates"
        return 1
    fi

    report_chrome_profile_caches

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

    if echo "$updates" | grep -qi "restart"; then
        echo_warning "A downloaded update requires a restart; installing stays a manual decision"
    fi

    echo_success "macOS update download completed"
    return 0
}
