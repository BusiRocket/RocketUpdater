#!/bin/bash

PLUGIN_NAME="PEAR"
PLUGIN_VERSION="1.1.0"
DISABLE=${DISABLE:-false}

check_pear() {
    command_exists pear
}

check_pecl() {
    command_exists pecl
}

run_pear_command() {
    local cmd=$1
    shift
    pear "$cmd" "$@" 2>&1 || true
}

run_pecl_command() {
    local cmd=$1
    shift
    pecl "$cmd" "$@" 2>&1 || true
}

update_pear() {
    local has_pear=false
    local has_pecl=false
    
    if check_pear; then
        has_pear=true
    fi
    
    if check_pecl; then
        has_pecl=true
    fi
    
    if [ "$has_pear" = false ] && [ "$has_pecl" = false ]; then
        echo_skip "PEAR and PECL are not installed. Skipping..."
        return 0
    fi

    # PEAR updates
    if [ "$has_pear" = true ]; then
        echo_info "PEAR: Clearing cache..."
        run_pear_command "clear-cache"

        echo_info "PEAR: Updating channels..."
        run_pear_command "update-channels"

        echo_info "PEAR: Upgrading PEAR itself..."
        run_pear_command "upgrade" "PEAR"

        echo_info "PEAR: Upgrading all packages..."
        run_pear_command "upgrade-all"
    fi

    # PECL updates
    if [ "$has_pecl" = true ]; then
        echo_info "PECL: Updating channels..."
        run_pecl_command "update-channels"

        echo_info "PECL: Upgrading all extensions..."
        run_pecl_command "upgrade"
    fi

    echo_success "PEAR/PECL update completed"
    return 0
}
