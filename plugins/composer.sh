#!/bin/bash

PLUGIN_NAME="Composer"
PLUGIN_VERSION="1.1.0"
DISABLE=${DISABLE:-false}

COMPOSER_HOME="${COMPOSER_HOME:-$HOME/.composer}"

check_composer() {
    command_exists composer
}

update_composer() {
    if ! check_composer; then
        echo_skip "Composer is not installed. Skipping..."
        return 0
    fi

    echo_info "Composer: Clearing cache..."
    composer clearcache 2>/dev/null || true

    echo_info "Composer: Updating Composer itself..."
    if ! composer self-update; then
        echo_warning "Composer self-update failed (may require sudo)"
    fi

    # Check if global composer.json exists before updating global packages
    if [ -f "$COMPOSER_HOME/composer.json" ]; then
        echo_info "Composer: Updating global packages..."
        composer global update
    else
        echo_skip "No global composer.json found at $COMPOSER_HOME. Skipping global update."
    fi

    echo_success "Composer update completed"
    return 0
}
