#!/bin/bash

PLUGIN_NAME="Homebrew"
PLUGIN_VERSION="1.0.1"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_homebrew() {
    command_exists brew
}

run_brew_step() {
    local step_name=$1
    local command=$2
    local output=""
    local attempt=1
    local max_attempts=3

    while [ "$attempt" -le "$max_attempts" ]; do
        output=$(eval "$command" 2>&1)
        local status=$?

        printf '%s\n' "$output"

        if [ "$status" -eq 0 ]; then
            return 0
        fi

        if [ "$attempt" -lt "$max_attempts" ]; then
            echo_warning "$step_name failed on attempt $attempt/$max_attempts. Retrying in 5 seconds..."
            sleep 5
        fi

        attempt=$((attempt + 1))
    done

    echo_error "$step_name reported errors"
    return 1
}

update_homebrew() {
    if ! check_homebrew; then
        echo_skip "Homebrew is not installed. Skipping..."
        return 0
    fi

    # The user installs their own third-party taps deliberately. Skip Homebrew's
    # tap-trust prompts so update/upgrade/cleanup process them instead of flooding
    # the run with "tap is not trusted" warnings and silently skipping formulae.
    export HOMEBREW_NO_REQUIRE_TAP_TRUST=1

    echo_yellow 'Homebrew: Updating...'
    if ! run_brew_step "Homebrew update" "brew update"; then
        return 1
    fi

    if ! run_brew_step "Homebrew upgrade" "brew upgrade --greedy"; then
        return 1
    fi

    echo_yellow 'Homebrew: Cleaning...'
    if ! run_brew_step "Homebrew cleanup" "brew cleanup"; then
        return 1
    fi

    return 0
}
