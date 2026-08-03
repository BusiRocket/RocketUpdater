#!/bin/bash

PLUGIN_NAME="PEAR"
PLUGIN_VERSION="1.3.0"
DISABLE=${DISABLE:-false}

check_pear() {
    command_exists pear
}

check_pecl() {
    command_exists pecl
}

# PHP warnings are common with newer PHP versions and drown the real output.
filter_php_noise() {
    grep -v "^PHP Warning:" | grep -v "^Warning:" | grep -v "Cannot use bool as array" || true
}

# Output is captured rather than piped so the reported status is the command's
# own and not the filter's, which would always be zero.
run_filtered() {
    local output status

    output=$("$@" 2>&1)
    status=$?
    printf '%s\n' "$output" | filter_php_noise

    return $status
}

run_pear_command() {
    local cmd=$1
    shift
    run_filtered pear "$cmd" "$@"
}

run_pecl_command() {
    local cmd=$1
    shift
    run_filtered pecl "$cmd" "$@"
}

# Prefer root, since pear and pecl write into system directories, but never let
# that stop the upgrade: without a grant, or when the privileged call fails for
# any reason, retry unprivileged. Report why the privileged attempt failed --
# discarding it makes "retrying without sudo" impossible to act on, since it
# looks identical whether sudo was refused, the ticket expired, or the command
# itself errored.
run_privileged() {
    local label=$1
    local tool=$2
    local cmd=$3
    shift 3
    local output

    if [ "${SUDO_AVAILABLE:-false}" = true ]; then
        if output=$(sudo -n "$tool" "$cmd" "$@" 2>&1); then
            printf '%s\n' "$output" | filter_php_noise
            return 0
        fi

        echo_warning "$label: privileged '$cmd' failed; retrying without sudo..."
        printf '%s\n' "$output" | filter_php_noise | grep -v '^$' | head -3
    fi

    run_filtered "$tool" "$cmd" "$@"
}

run_pear_command_privileged() {
    run_privileged "PEAR" "pear" "$@"
}

run_pecl_command_privileged() {
    run_privileged "PECL" "pecl" "$@"
}

update_pear() {
    local has_pear=false
    local has_pecl=false
    local has_failures=false

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
            echo_info "PEAR: Some cache files are root-owned; retrying as root..."
            run_pear_command_privileged "clear-cache"
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
    # An upgrade that ends in "ERROR: commit failed" must reach the summary as a
    # failure. Cache and channel steps stay advisory: they are routine noise and
    # do not mean the update did not happen.
    if [ "$has_pear" = true ]; then
        echo_info "PEAR: Upgrading PEAR itself..."
        if ! run_pear_command_privileged "upgrade" "--force" "PEAR"; then
            has_failures=true
        fi

        echo_info "PEAR: Upgrading all packages..."
        if ! run_pear_command_privileged "upgrade" "--force"; then
            has_failures=true
        fi
    fi

    # Step 4: Upgrade PECL extensions (after PEAR is fully updated)
    if [ "$has_pecl" = true ]; then
        echo_info "PECL: Upgrading installed extensions..."
        # Get list of installed PECL packages and upgrade each with --force
        local pecl_packages
        pecl_packages=$(pecl list 2>/dev/null | tail -n +4 | awk '{print $1}' | grep -v "^$")

        if [ -n "$pecl_packages" ]; then
            for pkg in $pecl_packages; do
                echo "  → Upgrading $pkg..."
                if ! run_pecl_command_privileged "upgrade" "--force" "$pkg"; then
                    has_failures=true
                fi
            done
        else
            echo_skip "No PECL extensions installed"
        fi
    fi

    if [ "$has_failures" = true ]; then
        echo_error "PEAR/PECL update finished with failed upgrades"
        return 1
    fi

    echo_success "PEAR/PECL update completed"
    return 0
}
