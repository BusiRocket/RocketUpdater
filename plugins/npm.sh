#!/bin/bash

PLUGIN_NAME="NPM"
PLUGIN_VERSION="1.1.0"
DISABLE=${DISABLE:-false}

check_npm() {
    command_exists npm
}

check_ncu() {
    command_exists ncu
}

update_npm() {
    local has_failures=0

    if ! check_npm; then
        echo_skip "NPM is not installed. Skipping..."
        return 0
    fi

    # Update npm itself
    echo_info "NPM: Updating npm..."
    npm install -g npm@latest 2>&1 || echo_warning "npm self-update failed"

    # Check for outdated global packages using ncu
    if check_ncu; then
        echo_info "NPM: Checking for outdated global packages..."

        # Get list of outdated packages and their new versions
        local outdated_output
        outdated_output=$(ncu -g 2>&1)

        if echo "$outdated_output" | grep -q "→"; then
            echo "$outdated_output"

            # Extract package names with versions and update them
            echo_info "NPM: Updating global packages..."
            # Parse ncu output format: "package  current  →  new"
            # Use awk to properly extract package name (field 1) and new version (field after →)
            while read -r line; do
                # Extract package name (first non-empty field) and new version (after →)
                local pkg_name new_version
                pkg_name=$(echo "$line" | awk '{print $1}')
                new_version=$(echo "$line" | awk -F'→' '{print $2}' | awk '{print $1}')

                if [ -n "$pkg_name" ] && [ -n "$new_version" ]; then
                    echo "  → Updating $pkg_name to $new_version..."
                    if ! npm install -g "${pkg_name}@${new_version}" 2>&1; then
                        has_failures=1
                        echo_warning "Failed to update global package: $pkg_name@$new_version"
                    fi
                fi
            done < <(echo "$outdated_output" | grep "→")
        else
            echo_skip "All global packages are up to date"
        fi
    else
        echo_warning "npm-check-updates (ncu) not installed. Install with: npm install -g npm-check-updates"

        # Fallback: list outdated packages
        echo_info "NPM: Checking for outdated global packages..."
        npm outdated -g 2>&1 || true
    fi

    # Clean cache
    echo_info "NPM: Cleaning cache..."
    npm cache clean --force 2>&1 || true

    # Verify cache
    npm cache verify 2>&1 || true

    if [ "$has_failures" -eq 1 ]; then
        echo_error "NPM update completed with errors"
        return 1
    fi

    echo_success "NPM update completed"
    return 0
}
