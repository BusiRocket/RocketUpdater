#!/bin/bash

PLUGIN_NAME="Mac App Store"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=60
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

# mas needs root to install an update and, without cached credentials, asks
# for the password on a terminal that a plugin does not have. So it updates in
# a run holding sudo and only lists what is outdated otherwise; the App Store's
# own automatic updates cover the rest.
update_appstore() {
    if ! command_exists mas; then
        echo_skip "mas is not installed (brew install mas)"
        return 20
    fi

    # mas warns on stderr about apps Spotlight has not indexed yet; only
    # stdout is the outdated list.
    local outdated
    local stderr_file
    stderr_file=$(mktemp -t rocketupdater-mas) || return 1
    if ! outdated=$(mas outdated 2>"$stderr_file"); then
        cat "$stderr_file"
        /bin/rm -f -- "$stderr_file"
        echo_error "mas could not list outdated apps"
        return 1
    fi
    /bin/rm -f -- "$stderr_file"
    if [ -z "$outdated" ]; then
        echo_success "App Store apps are current"
        return 0
    fi
    printf '%s\n' "$outdated"

    if [ "${SUDO_AVAILABLE:-false}" != true ]; then
        echo_note "App Store updates need sudo; run RocketUpdater by hand or let the App Store update them"
        return 0
    fi

    echo_info "App Store: Updating outdated apps..."
    if ! mas update </dev/null 2>&1; then
        echo_error "mas update failed"
        return 1
    fi
    echo_change "App Store apps"
    echo_success "App Store apps updated"
    return 0
}
