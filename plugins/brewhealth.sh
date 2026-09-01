#!/bin/bash

PLUGIN_NAME="Homebrew Health"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=20
PLUGIN_TIMEOUT_SECONDS=900
PLUGIN_SCHEDULE_ACTION=run

update_brewhealth() {
    if ! command_exists brew; then
        echo_skip "Homebrew is not installed"
        return 20
    fi

    local has_failures=0

    echo_info "Homebrew: Checking missing dependencies..."
    if ! brew missing 2>&1; then
        has_failures=1
    fi

    echo_info "Homebrew: Previewing autoremove candidates..."
    if ! brew autoremove --dry-run 2>&1; then
        has_failures=1
    fi

    echo_info "Homebrew: Running doctor..."
    if ! brew doctor 2>&1; then
        has_failures=1
    fi

    if [ "$has_failures" -ne 0 ]; then
        echo_warning "Homebrew health reported actionable findings"
        return 1
    fi

    echo_success "Homebrew health checks passed"
    return 0
}
