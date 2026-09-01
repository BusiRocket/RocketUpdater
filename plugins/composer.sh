#!/bin/bash

PLUGIN_NAME="Composer"
PLUGIN_VERSION="2.0.0"
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

report_composer_cache() {
    local cache_dir
    cache_dir=$(composer --no-interaction --working-dir="$HOME" config --global cache-dir 2>/dev/null)

    if [ -n "$cache_dir" ] && [ -d "$cache_dir" ]; then
        echo_info "Composer cache (report only; removal stays manual):"
        du -sk "$cache_dir" 2>&1
    else
        echo_skip "Composer cache directory is absent"
    fi
}

update_composer() {
    COMPOSER_HOME="${COMPOSER_HOME:-$HOME/.composer}"
    local composer_home=$COMPOSER_HOME
    local has_failures=0

    if ! check_composer; then
        echo_skip "Composer is not installed. Skipping..."
        return 20
    fi

    if is_homebrew_composer; then
        echo_info "Composer: Homebrew-managed — upgrading via brew..."
        if ! brew upgrade composer 2>&1; then
            has_failures=1
            echo_warning "brew upgrade composer failed"
        fi
    else
        echo_info "Composer: Updating Composer itself..."
        if ! composer --no-interaction --working-dir="$HOME" self-update 2>&1; then
            has_failures=1
            echo_warning "Composer self-update failed (may require sudo)"
        fi
    fi

    # Check if global composer.json exists before updating global packages
    if [ -f "$composer_home/composer.json" ]; then
        echo_info "Composer: Updating global packages..."
        if ! composer --no-interaction global update 2>&1; then
            has_failures=1
            echo_warning "Global packages update failed"
        fi
    else
        echo_skip "No global composer.json found at $composer_home. Skipping global update."
    fi

    report_composer_cache

    if [ "$has_failures" -ne 0 ]; then
        echo_error "Composer update completed with errors"
        return 1
    fi

    echo_success "Composer update completed"
    return 0
}
