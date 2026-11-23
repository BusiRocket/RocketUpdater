#!/bin/bash

PLUGIN_NAME="Microsoft AutoUpdate"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=60
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

update_msupdate() {
    local msupdate_path=${ROCKETUPDATER_MSUPDATE:-"/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"}

    if [ ! -x "$msupdate_path" ]; then
        echo_skip "Microsoft AutoUpdate CLI is not installed"
        return 20
    fi

    # Between runs MAU itself downloads what it finds, even in a run where
    # its helper does not answer below.
    if [ "$(defaults read com.microsoft.autoupdate2 HowToCheck 2>/dev/null)" != AutomaticDownload ]; then
        if defaults write com.microsoft.autoupdate2 HowToCheck -string AutomaticDownload; then
            echo_change "Microsoft AutoUpdate now downloads updates automatically"
        else
            echo_warning "Could not switch Microsoft AutoUpdate to automatic downloads"
        fi
    fi

    local output
    if ! output=$("$msupdate_path" --list --format plist </dev/null 2>&1); then
        printf '%s\n' "$output"
        echo_error "Microsoft update inventory failed"
        return 1
    fi

    printf '%s\n' "$output"
    # msupdate exits 0 even when its helper is not running, after printing
    # only this line; that is no inventory at all, not an empty one.
    case $output in
    *"XPC Connection to updater invalidated"*)
        echo_skip "Microsoft AutoUpdate did not answer (XPC connection invalidated); no inventory this run"
        return 20
        ;;
    esac
    # No --terminate: an app that is open keeps running and MAU finishes its
    # update the next time it is closed, instead of closing it on the owner.
    echo_info "Microsoft: Installing available updates..."
    local install_output
    if ! install_output=$("$msupdate_path" --install --wait 1500 </dev/null 2>&1); then
        printf '%s\n' "$install_output"
        echo_error "Microsoft update install failed"
        return 1
    fi
    printf '%s\n' "$install_output"
    case $install_output in
    *"XPC Connection to updater invalidated"*)
        echo_skip "Microsoft AutoUpdate stopped answering during the install"
        return 20
        ;;
    esac
    echo_success "Microsoft updates installed or queued"
    return 0
}
