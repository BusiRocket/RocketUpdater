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
    # Run pear and filter out PHP warnings (common with newer PHP versions)
    pear "$cmd" "$@" 2>&1 | grep -v "^PHP Warning:" | grep -v "^Warning:" | grep -v "Cannot use bool as array" || true
}

run_pecl_command() {
    local cmd=$1
    shift
    # Run pecl and filter out PHP warnings (common with newer PHP versions)
    pecl "$cmd" "$@" 2>&1 | grep -v "^PHP Warning:" | grep -v "^Warning:" | grep -v "Cannot use bool as array" || true
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
        run_pear_command "upgrade" "--force" "PEAR"

        echo_info "PEAR: Upgrading all packages..."
        run_pear_command "upgrade-all" "--force"
    fi

    # PECL updates
    if [ "$has_pecl" = true ]; then
        echo_info "PECL: Updating channels..."
        run_pecl_command "update-channels"

        echo_info "PECL: Upgrading all extensions..."
        run_pecl_command "upgrade" "--force"
    fi

    echo_success "PEAR/PECL update completed"
    return 0
}
