#!/bin/bash

PLUGIN_NAME="Conda Cache Clean"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=55
PLUGIN_TIMEOUT_SECONDS=600
PLUGIN_SCHEDULE_ACTION=run

# Removes downloaded package archives and the repodata index only. Extracted
# packages stay, because environments hard-link into them; --packages and
# --force-pkgs-dirs are never used.
update_condacache() {
    if ! command_exists conda; then
        echo_skip "Conda is not installed"
        return 20
    fi

    echo_info "Conda: Removing downloaded archives and index cache..."
    if ! conda clean --tarballs --index-cache --yes 2>&1; then
        echo_error "conda clean failed"
        return 1
    fi
    echo_success "Conda download cache cleaned"
    return 0
}
