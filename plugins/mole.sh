#!/bin/bash

PLUGIN_NAME="Mole"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false}

check_mole() {
    command -v mo >/dev/null 2>&1
}

update_mole() {
    if ! check_mole; then
        echo_skip "Mole (mo) is not installed. Skipping... (brew install mole)"
        return 0
    fi

    # Runs without sudo: system caches are skipped, user-level caches are
    # cleaned. Mole keeps its own whitelist (mo clean --whitelist).
    echo_info "Mole: Running deep clean (user-level, non-interactive)..."
    if mo clean 2>&1 | tail -6; then
        echo_success "Mole cleanup completed"
    else
        echo_error "Mole cleanup reported errors"
        return 1
    fi

    return 0
}
