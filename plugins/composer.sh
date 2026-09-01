#!/bin/bash

PLUGIN_NAME="Composer"
PLUGIN_VERSION="1.3.0"
DISABLE=false
PLUGIN_PRIORITY=50
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

check_composer() {
    command_exists composer
}

is_homebrew_composer() {
    command_exists brew || return 1
    local composer_path
    composer_path=$(command -v composer)
    [[ $composer_path == "$(brew --prefix)"/* ]]
}

update_composer() {
    COMPOSER_HOME="${COMPOSER_HOME:-$HOME/.composer}"
    local composer_home=$COMPOSER_HOME

    if ! check_composer; then
        echo_skip "Composer is not installed. Skipping..."
        return 0
    fi

    echo_info "Composer: Clearing cache..."
    composer --no-interaction --working-dir="$HOME" clearcache || true

    if is_homebrew_composer; then
        echo_info "Composer: Homebrew-managed — upgrading via brew..."
        if ! brew upgrade composer 2>&1; then
            echo_warning "brew upgrade composer failed"
        fi
    else
        echo_info "Composer: Updating Composer itself..."
        if ! composer --no-interaction --working-dir="$HOME" self-update 2>&1; then
            echo_warning "Composer self-update failed (may require sudo)"
        fi
    fi

    # Check if global composer.json exists before updating global packages
    if [ -f "$composer_home/composer.json" ]; then
        echo_info "Composer: Updating global packages..."
        composer --no-interaction global update 2>&1 || echo_warning "Global packages update failed"
    else
        echo_skip "No global composer.json found at $composer_home. Skipping global update."
    fi

    echo_success "Composer update completed"
    return 0
}
