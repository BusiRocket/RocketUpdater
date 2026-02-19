#!/bin/bash

PLUGIN_NAME="Homebrew"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_homebrew() {
    command_exists brew
}

update_homebrew() {
    if check_homebrew; then
        echo_yellow 'Homebrew: Updating...'
        brew update
        brew upgrade --greedy

        echo_yellow 'Homebrew: Cleaning...'
        brew cleanup
    fi
}
