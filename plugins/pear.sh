#!/bin/bash

PLUGIN_NAME="PEAR"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=50
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

check_pear() {
    command_exists pear
}

# Homebrew's php formula ships a PEAR skeleton inside the Cellar and points
# php.ini's include_path at it, but the actual packages (Console_Getopt among
# them) are installed under the prefix. PEAR then dies with
# "Failed opening required 'Console/Getopt.php'" on every command. The wrapper
# honours PHP_PEAR_INSTALL_DIR, so point it at the tree that really holds the
# packages instead of editing the user's php.ini.
resolve_pear_install_dir() {
    if [ -n "${PHP_PEAR_INSTALL_DIR:-}" ]; then
        return 0
    fi

    if pear list >/dev/null 2>&1; then
        return 0
    fi

    local candidate
    for candidate in "$(brew --prefix 2>/dev/null)/share/pear" \
        /opt/homebrew/share/pear /usr/local/share/pear; do
        if [ -f "$candidate/Console/Getopt.php" ]; then
            export PHP_PEAR_INSTALL_DIR="$candidate"
            echo_info "PEAR: Using the package tree at $candidate"
            return 0
        fi
    done

    echo_warning "PEAR cannot find its own package tree; commands will report the failure"
    return 0
}

check_pecl() {
    command_exists pecl
}

is_homebrew_php() {
    command_exists brew || return 1
    local php_path
    php_path=$(command -v php) || return 1
    [[ $php_path == "$(brew --prefix)"/* ]]
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
# The run-wide grant is not proof that this plugin can use it: plugins run
# under `timeout` with stdin closed, and a `sudo -n` there can still be refused.
# Probe once and remember the answer, so a refusal costs one warning instead of
# one "sudo: a password is required" per package. The answer lives in a global
# set on first use; plugin files may not run statements at the top level, so it
# is read with a default instead of being initialised there.
# TOOL is pear or pecl: they install into different directories, so the answer
# is per tool. PEAR writes packages into php_dir, PECL builds extensions into
# extension_dir, and one can be user-owned while the other is not.
target_needs_root() {
    local tool=$1
    local install_dir

    case $tool in
    pear)
        install_dir=${PHP_PEAR_INSTALL_DIR:-}
        [ -n "$install_dir" ] || install_dir=$(pear config-get php_dir 2>/dev/null)
        ;;
    pecl)
        install_dir=$(pecl config-get ext_dir 2>/dev/null)
        ;;
    esac

    # An unknown destination is treated as needing root: the old behaviour, and
    # the safe direction, since a refused grant only costs a fallback.
    [ -n "$install_dir" ] || return 0
    [ ! -w "$install_dir" ]
}

sudo_usable() {
    local tool=$1

    # Root is for a system tree the user cannot write. On a Homebrew tree the
    # user owns, upgrading as root rewrites those files as root-owned, and the
    # next run without a grant — a scheduled one always runs without it — then
    # fails with "permission denied (delete)". That is exactly how the Mac mini
    # ended up with 141 root-owned files under /opt/homebrew/share/pear.
    if ! target_needs_root "$tool"; then
        # bash 3.2 has no ${var:u}, and this file must run under the system bash.
        echo_info "$(printf '%s' "$tool" | tr '[:lower:]' '[:upper:]'): its install directory is writable by this user; upgrading without root."
        return 1
    fi

    # Whether the grant itself works is a separate question from whether this
    # destination needs it, so it is probed once and cached on its own.
    if [ -n "${PEAR_SUDO_USABLE:-}" ]; then
        [ "$PEAR_SUDO_USABLE" = yes ]
        return $?
    fi

    if [ "${SUDO_AVAILABLE:-false}" != true ]; then
        PEAR_SUDO_USABLE=no
        return 1
    fi

    local probe_output
    if probe_output=$(sudo -n true 2>&1); then
        PEAR_SUDO_USABLE=yes
        return 0
    fi

    PEAR_SUDO_USABLE=no
    # Say why: refused, expired, and "command errored" look identical otherwise.
    echo_warning "PEAR: the run's root grant is not usable here; retrying without sudo for every package."
    printf '%s\n' "$probe_output" | grep -v '^$' | head -2
    return 1
}

run_privileged() {
    local label=$1
    local tool=$2
    local cmd=$3
    shift 3
    local output

    if sudo_usable "$tool"; then
        if output=$(sudo -n "$tool" "$cmd" "$@" 2>&1); then
            printf '%s\n' "$output" | filter_php_noise
            return 0
        fi

        # An expired ticket mid-loop looks like a per-package failure; stop
        # retrying root for the rest of the plugin once sudo asks for a password.
        case $output in
        *'a password is required'* | *'no askpass program'*)
            PEAR_SUDO_USABLE=no
            echo_warning "$label: the root grant expired; the remaining packages upgrade unprivileged."
            ;;
        *)
            echo_warning "$label: privileged '$cmd' failed; retrying without sudo..."
            printf '%s\n' "$output" | filter_php_noise | grep -v '^$' | head -3
            ;;
        esac
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
        return 20
    fi

    resolve_pear_install_dir

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
        # The PEAR package owns pear/peardev/pecl. Under a Homebrew-managed PHP
        # those live in the Cellar as read-only files that Homebrew replaces
        # with the formula, so upgrading PEAR itself can only ever end in
        # "permission denied (delete)" and "ERROR: commit failed". Upgrade the
        # other packages, which live under the prefix, and leave PEAR to brew.
        local skip_pear_self=false
        if is_homebrew_php; then
            skip_pear_self=true
            echo_skip "PEAR itself is owned by the Homebrew php formula; brew upgrade php updates it"
        else
            echo_info "PEAR: Upgrading PEAR itself..."
            if ! run_pear_command_privileged "upgrade" "--force" "PEAR"; then
                has_failures=true
            fi
        fi

        echo_info "PEAR: Upgrading installed packages..."
        local pear_list_output
        local pear_packages=""
        if ! pear_list_output=$(pear list 2>/dev/null); then
            echo_error "PEAR: Could not list installed packages"
            has_failures=true
            pear_list_output=""
        fi

        if [ -n "$pear_list_output" ]; then
            pear_packages=$(printf '%s\n' "$pear_list_output" | tail -n +4 |
                awk '{print $1}' | grep -E '^[A-Za-z][A-Za-z0-9_-]*$' || true)
        fi

        if [ -n "$pear_packages" ]; then
            local pear_package
            for pear_package in $pear_packages; do
                if [ "$skip_pear_self" = true ] && [ "$pear_package" = "PEAR" ]; then
                    continue
                fi
                echo "  → Upgrading $pear_package..."
                if ! run_pear_command_privileged "upgrade" "--force" "$pear_package"; then
                    has_failures=true
                fi
            done
        else
            echo_skip "No PEAR packages to upgrade"
        fi
    fi

    # Step 4: Upgrade PECL extensions (after PEAR is fully updated)
    if [ "$has_pecl" = true ]; then
        echo_info "PECL: Upgrading installed extensions..."
        # Get list of installed PECL packages and upgrade each with --force.
        # A broken PEAR install makes `pecl list` emit a PHP fatal error, and
        # parsing that stack trace as a package list produced upgrade attempts
        # for "Warning:", "#0" and "thrown". Require a successful listing, then
        # keep only names that can actually be package names.
        local pecl_list_output
        local pecl_packages=""
        if ! pecl_list_output=$(pecl list 2>/dev/null); then
            echo_error "PECL: Could not list installed extensions"
            has_failures=true
            pecl_list_output=""
        fi

        if [ -n "$pecl_list_output" ]; then
            pecl_packages=$(printf '%s\n' "$pecl_list_output" | tail -n +4 |
                awk '{print $1}' | grep -E '^[A-Za-z][A-Za-z0-9_-]*$' || true)
        fi

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
