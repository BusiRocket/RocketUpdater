#!/bin/bash

PLUGIN_NAME="Homebrew"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_homebrew() {
    command_exists brew
}

update_homebrew() {
    local brew_update_output
    local brew_upgrade_output
    local brew_cleanup_output

    if ! check_homebrew; then
        echo_skip "Homebrew is not installed. Skipping..."
        return 0
    fi

    echo_yellow 'Homebrew: Updating...'
    brew_update_output=$(brew update 2>&1)
    printf '%s\n' "$brew_update_output"

    if echo "$brew_update_output" | grep -q "^Error:"; then
        echo_error "Homebrew update reported errors"
        return 1
    fi

    brew_upgrade_output=$(brew upgrade --greedy 2>&1)
    printf '%s\n' "$brew_upgrade_output"

    if echo "$brew_upgrade_output" | grep -q "^Error:"; then
        echo_error "Homebrew upgrade reported errors"
        return 1
    fi

    echo_yellow 'Homebrew: Cleaning...'
    brew_cleanup_output=$(brew cleanup 2>&1)
    printf '%s\n' "$brew_cleanup_output"

    if echo "$brew_cleanup_output" | grep -q "^Error:"; then
        echo_error "Homebrew cleanup reported errors"
        return 1
    fi

    return 0
}
