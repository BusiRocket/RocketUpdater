#!/bin/bash

PLUGIN_NAME="Yarn"
PLUGIN_VERSION="1.1.0"
DISABLE=${DISABLE:-false}

check_yarn() {
    command_exists yarn
}

get_yarn_version() {
    yarn --version 2>/dev/null | cut -d. -f1
}

update_yarn() {
    if ! check_yarn; then
        echo_skip "Yarn is not installed. Skipping..."
        return 0
    fi

    local yarn_major_version
    yarn_major_version=$(get_yarn_version)

    echo_info "Yarn: Detected version $yarn_major_version.x"

    # Yarn 1.x (Classic) vs Yarn 2+ (Berry) have different update mechanisms
    if [ "$yarn_major_version" = "1" ]; then
        # Yarn Classic - update via npm
        echo_info "Yarn Classic: Updating via npm..."
        npm install -g yarn@latest 2>&1 || echo_warning "Yarn update via npm failed"
    else
        # Yarn Berry (2+) - use set version
        echo_info "Yarn Berry: Updating to latest stable..."
        yarn set version stable 2>&1 || echo_warning "Yarn set version failed"
    fi

    # Clean cache
    echo_info "Yarn: Cleaning cache..."
    if [ "$yarn_major_version" = "1" ]; then
        yarn cache clean 2>&1 || true
    else
        yarn cache clean --all 2>&1 || true
    fi

    # Update global packages (Yarn 1.x only)
    if [ "$yarn_major_version" = "1" ]; then
        echo_info "Yarn: Checking global packages..."
        yarn global upgrade 2>&1 || echo_skip "No global packages to update"
    fi

    echo_success "Yarn update completed"
    return 0
}
