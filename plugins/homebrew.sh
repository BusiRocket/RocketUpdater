#!/bin/bash

PLUGIN_NAME="Homebrew"
PLUGIN_VERSION="1.1.0"
DISABLE=${DISABLE:-false}

check_homebrew() {
    command_exists brew
}

update_homebrew() {
    if ! check_homebrew; then
        echo_skip "Homebrew is not installed. Skipping..."
        return 0
    fi

    # Update Homebrew itself
    echo_info "Homebrew: Updating formulae..."
    brew update

    # Upgrade all packages
    echo_info "Homebrew: Upgrading packages..."
    brew upgrade 2>&1 || echo_warning "Some packages could not be upgraded"

    # Upgrade casks
    echo_info "Homebrew: Upgrading casks..."
    brew upgrade --cask 2>&1 || echo_warning "Some casks could not be upgraded"

    # Cleanup old versions
    echo_info "Homebrew: Cleaning up..."
    brew cleanup -s 2>&1 || true

    # Remove stale lock files
    brew cleanup --prune=all 2>&1 || true

    # Run diagnostics (optional, just for info)
    echo_info "Homebrew: Running doctor..."
    brew doctor 2>&1 || echo_warning "Homebrew doctor found some issues"

    echo_success "Homebrew update completed"
    return 0
}
