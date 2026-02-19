#!/bin/bash

PLUGIN_NAME="OSX"
PLUGIN_VERSION="1.1.0"
DISABLE=${DISABLE:-false}

check_osx() {
    [[ $OSTYPE == "darwin"* ]]
}

update_osx() {
    if ! check_osx; then
        echo_skip "Not running on macOS. Skipping..."
        return 0
    fi

    echo_info "macOS: Checking for software updates..."

    # List available updates first
    local updates
    updates=$(softwareupdate -l 2>&1)

    if echo "$updates" | grep -q "No new software available"; then
        echo_skip "No macOS updates available"
    else
        echo "$updates"

        echo_info "macOS: Installing available updates..."
        # -i: install
        # -a: all available updates
        # Note: Some updates may require restart
        softwareupdate -ia 2>&1 || echo_warning "Some updates could not be installed"

        # Check if restart is required
        if softwareupdate -l 2>&1 | grep -q "restart"; then
            echo_warning "A restart is required to complete some updates"
        fi
    fi

    # Clean up system caches (safe operations only)
    echo_info "macOS: Cleaning user caches..."

    # Clean user cache (safe)
    if [ -d ~/Library/Caches ]; then
        # Only clean known safe directories
        rm -rf ~/Library/Caches/com.apple.Safari/WebKitCache 2>/dev/null || true
        rm -rf ~/Library/Caches/Google/Chrome/Default/Cache 2>/dev/null || true
    fi

    # Purge memory (helps with sluggish performance)
    # Use sudo -n to avoid password prompt in automated scripts
    echo_info "macOS: Purging disk cache..."
    if sudo -n true 2>/dev/null; then
        sudo purge 2>/dev/null || echo_skip "Could not purge disk cache"
    else
        echo_skip "Skipping disk cache purge (requires sudo credentials)"
    fi

    # Rebuild Spotlight index (optional, commented out as it takes time)
    # echo_info "macOS: Rebuilding Spotlight index..."
    # sudo mdutil -E / 2>/dev/null || true

    echo_success "macOS update completed"
    return 0
}
