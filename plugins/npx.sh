#!/bin/bash

PLUGIN_NAME="NPX"
PLUGIN_VERSION="1.1.0"
DISABLE=${DISABLE:-false}

check_npx() {
    command_exists npx
}

update_npx() {
    if ! check_npx; then
        echo_skip "NPX is not installed. Skipping..."
        return 0
    fi

    # Clear npx cache (use -y to auto-confirm package installation)
    echo_info "NPX: Clearing cache..."
    npx -y clear-npx-cache 2>/dev/null || true

    # Note: update-browserslist-db requires a project with package.json
    # We'll skip this as it's project-specific, not a global update
    echo_skip "Browserslist DB update skipped (requires project-level package.json)"
    echo_info "  → Run 'npx update-browserslist-db@latest' in your project directories"

    echo_success "NPX tasks completed"
    return 0
}
