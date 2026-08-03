#!/bin/bash

PLUGIN_NAME="PEAR"
PLUGIN_VERSION="1.2.0"
DISABLE=${DISABLE:-false}

check_pear() {
    command_exists pear
}

# Plugins run with no stdin, so a password prompt cannot be answered. Report
# whether sudo already has cached credentials and let the caller skip the
# privileged steps with an actionable message rather than fail obscurely.
check_sudo_credentials() {
    sudo -n true 2>/dev/null
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

run_pear_command_sudo() {
    local cmd=$1
    shift
    # Run pear with sudo and filter out PHP warnings
    sudo -n pear "$cmd" "$@" 2>&1 | grep -v "^PHP Warning:" | grep -v "^Warning:" | grep -v "Cannot use bool as array" || true
}

run_pecl_command() {
    local cmd=$1
    shift
    # Run pecl and filter out PHP warnings (common with newer PHP versions)
    pecl "$cmd" "$@" 2>&1 | grep -v "^PHP Warning:" | grep -v "^Warning:" | grep -v "Cannot use bool as array" || true
}

run_pecl_command_sudo() {
    local cmd=$1
    shift
    # Run pecl with sudo and filter out PHP warnings
    sudo -n pecl "$cmd" "$@" 2>&1 | grep -v "^PHP Warning:" | grep -v "^Warning:" | grep -v "Cannot use bool as array" || true
}

update_pear() {
    local has_pear=false
    local has_pecl=false
    local has_sudo=false

    if check_sudo_credentials; then
        has_sudo=true
    fi

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

    # Step 1: Clear caches
    if [ "$has_pear" = true ]; then
        echo_info "PEAR: Clearing cache..."
        local clear_output
        clear_output=$(run_pear_command "clear-cache")
        printf '%s\n' "$clear_output"
        # Cache files left by previous `sudo pear upgrade` runs are root-owned,
        # so a non-sudo clear-cache reports "failed to delete". Retry with sudo.
        if echo "$clear_output" | grep -q "failed to delete"; then
            if [ "$has_sudo" = true ]; then
                echo_info "PEAR: Some cache files are root-owned; clearing with sudo..."
                run_pear_command_sudo "clear-cache"
            else
                echo_skip "Root-owned cache files left in place (no cached sudo credentials)"
            fi
        fi
    fi

    # Step 2: Update ALL channels first (fixes "unsupported protocol" error)
    # See: https://ma.ttias.be/php-pear-php-net-using-unsupported-protocol-never-happen/
    if [ "$has_pear" = true ]; then
        echo_info "PEAR: Updating channels..."
        run_pear_command "update-channels"
    fi

    if [ "$has_pecl" = true ]; then
        echo_info "PECL: Updating channels..."
        run_pecl_command "update-channels"
    fi

    # Step 3: Upgrade PEAR packages first (required before PECL upgrades)
    if [ "$has_pear" = true ]; then
        if [ "$has_sudo" = true ]; then
            echo_info "PEAR: Upgrading PEAR itself..."
            run_pear_command_sudo "upgrade" "--force" "PEAR"

            echo_info "PEAR: Upgrading all packages..."
            run_pear_command_sudo "upgrade" "--force"
        else
            echo_skip "PEAR upgrades need root; run 'sudo -v' before RocketUpdater to include them"
        fi
    fi

    # Step 4: Upgrade PECL extensions (after PEAR is fully updated)
    if [ "$has_pecl" = true ] && [ "$has_sudo" = false ]; then
        echo_skip "PECL upgrades need root; run 'sudo -v' before RocketUpdater to include them"
    elif [ "$has_pecl" = true ]; then
        echo_info "PECL: Upgrading installed extensions..."
        # Get list of installed PECL packages and upgrade each with --force
        local pecl_packages
        pecl_packages=$(pecl list 2>/dev/null | tail -n +4 | awk '{print $1}' | grep -v "^$")

        if [ -n "$pecl_packages" ]; then
            for pkg in $pecl_packages; do
                echo "  → Upgrading $pkg..."
                run_pecl_command_sudo "upgrade" "--force" "$pkg"
            done
        else
            echo_skip "No PECL extensions installed"
        fi
    fi

    echo_success "PEAR/PECL update completed"
    return 0
}
