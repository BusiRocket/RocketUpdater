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
            # Parse ncu output and install each package
            echo "$outdated_output" | grep "→" | while read -r line; do
                # Extract package name and new version
                local pkg_info
                pkg_info=$(echo "$line" | sed -E 's/.*(@[^@]+).*→.*([0-9]+\.[0-9]+\.[0-9]+).*/\1@\2/' | sed 's/^[[:space:]]*//')
                
                if [ -n "$pkg_info" ]; then
                    npm install -g "$pkg_info" 2>&1 || true
                fi
            done
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

    echo_success "NPM update completed"
    return 0
}
