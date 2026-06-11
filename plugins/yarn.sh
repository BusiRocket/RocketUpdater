#!/bin/bash

PLUGIN_NAME="Yarn"
PLUGIN_VERSION="1.2.0"
DISABLE=${DISABLE:-false}

check_yarn() {
    command_exists yarn
}

check_corepack() {
    command_exists corepack
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

    if [ "$yarn_major_version" = "1" ]; then
        echo_info "Yarn Classic: Updating via npm..."
        npm install -g yarn@latest --force 2>&1 \
            || echo_warning "Yarn update via npm failed"
    else
        if check_corepack; then
            echo_info "Yarn Berry: Updating global yarn via corepack..."
            corepack prepare yarn@stable --activate 2>&1 \
                || echo_warning "corepack prepare yarn@stable failed"
        else
            echo_info "Yarn Berry: corepack not found — falling back to npm..."
            npm install -g yarn@latest --force 2>&1 \
                || echo_warning "Yarn update via npm failed"
        fi
    fi

    echo_info "Yarn: Cleaning cache..."
    if [ "$yarn_major_version" = "1" ]; then
        (cd "$HOME" && yarn cache clean) 2>&1 || true
    else
        if [ -f ".yarnrc.yml" ] || [ -d ".yarn" ]; then
            yarn cache clean --all 2>&1 || true
        else
            echo_skip "Yarn Berry cache is per-project; skipping (not in a Berry project)"
        fi
    fi

    if [ "$yarn_major_version" = "1" ]; then
        echo_info "Yarn: Checking global packages..."
        (cd "$HOME" && yarn global upgrade) 2>&1 \
            || echo_skip "No global packages to update"
    fi

    echo_success "Yarn update completed"
    return 0
}
