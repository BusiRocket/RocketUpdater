#!/bin/bash

PLUGIN_NAME="OSX"
PLUGIN_VERSION="2.1.0"
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

    # An upgrade to a new macOS release asks for a volume owner's password even
    # under sudo, and a run without a terminal fails that prompt every time
    # (macOS 27 on 2026-09-19, after macOS 26.7 had already downloaded). The
    # sudoers rule only allows `-d -r`, so the download still runs as a whole:
    # the auth failure is reported as the known limit rather than as an error.
    local current_major major_upgrades
    current_major=$(sw_vers -productVersion | cut -d. -f1)
    major_upgrades=$(list_major_macos_upgrades "$updates" "$current_major")

    echo_info "macOS: Downloading recommended updates..."
    # The invocation stays on its own line with exactly this argv: it is the
    # only command the sudoers rule allows, and tests/runner/sudo-mode.sh pins it.
    local download_log
    download_log=$(mktemp -t rocketupdater-softwareupdate) || return 1
    {
        sudo -n /usr/sbin/softwareupdate -d -r
        softwareupdate_status=$?
    } >"$download_log" 2>&1
    cat "$download_log"
    if [ "$softwareupdate_status" -ne 0 ]; then
        if [ -n "$major_upgrades" ] && grep -q 'Failed to authenticate' "$download_log"; then
            echo_warning "macOS: the upgrade to $(printf '%s' "$major_upgrades" | tr '\n' ' ')needs an interactive volume-owner login; downloading it stays a manual decision, and updates listed after it may not have been downloaded"
        else
            /bin/rm -f -- "$download_log"
            echo_error "macOS: Could not download recommended updates"
            return 1
        fi
    fi
    /bin/rm -f -- "$download_log"

    if echo "$updates" | grep -qi "restart"; then
        echo_warning "A downloaded update requires a restart; installing stays a manual decision"
    fi

    echo_success "macOS update download completed"
    return 0
}
