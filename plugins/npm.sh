#!/bin/bash

PLUGIN_NAME="NPM"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=50
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run
# Cache removal lives only in the manual npm cleanup guard; scheduled runs
# never clean or verify the cache because both can rewrite cache state.

check_npm() {
    command_exists npm
}

check_ncu() {
    command_exists ncu
}

record_npm_integrity_event() {
    local violations=$1

    if declare -F log_event >/dev/null 2>&1 && [ -n "${ROCKETUPDATER_EVENT_LOG:-}" ]; then
        log_event error integrity npm failed 0 "$violations" || true
    fi
}

# run_guarded_global_install SELECTED_PACKAGE COMMAND [ARG...] snapshots the
# global package tree around one install so damage to any other package is
# detected instead of silently shipped. Returns 0 on success, 1 on a plain
# install failure with an intact tree, and 2 on an integrity violation.
run_guarded_global_install() {
    local selected_package=$1
    shift
    local before_snapshot
    local after_snapshot
    local install_status
    local violations

    if ! before_snapshot=$(snapshot_global_npm_packages); then
        echo_error "Global npm snapshot failed before installing $selected_package"
        return 2
    fi

    "$@" 2>&1
    install_status=$?

    if ! after_snapshot=$(snapshot_global_npm_packages); then
        echo_error "Global npm snapshot failed after installing $selected_package"
        return 2
    fi

    violations=$(compare_global_npm_snapshots "$before_snapshot" "$after_snapshot" "$selected_package")

    if [ -n "$violations" ]; then
        printf '%s\n' "$violations"
        echo_error "Global npm package tree damaged around $selected_package; stopping global updates"
        record_npm_integrity_event "target=$selected_package $violations"
        return 2
    fi

    if [ "$install_status" -ne 0 ]; then
        return 1
    fi

    return 0
}

report_npm_cache_sizes() {
    local cache_subdirectory
    for cache_subdirectory in "$HOME/.npm/_cacache" "$HOME/.npm/_npx"; do
        if [ -d "$cache_subdirectory" ]; then
            du -sk "$cache_subdirectory" 2>&1
        fi
    done
}

update_npm() {
    local has_failures=0

    if ! check_npm; then
        echo_skip "NPM is not installed. Skipping..."
        return 20
    fi

    # Update npm itself
    echo_info "NPM: Updating npm..."
    run_guarded_global_install npm npm install -g npm@latest
    case $? in
    1)
        has_failures=1
        echo_warning "npm self-update failed"
        ;;
    2) return 1 ;;
    esac

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
            # fd 3, not stdin: `npm install` inherits the loop's stdin and can
            # drain the rest of the list, which would update the first package
            # and report success for all of them (measured in the homebrew
            # plugin with `brew upgrade`).
            while read -r line <&3; do
                # Extract package name (first non-empty field) and new version (after →)
                local pkg_name new_version
                pkg_name=$(echo "$line" | awk '{print $1}')
                new_version=$(echo "$line" | awk -F'→' '{print $2}' | awk '{print $1}')

                if [ -n "$pkg_name" ] && [ -n "$new_version" ]; then
                    echo "  → Updating $pkg_name to $new_version..."
                    run_guarded_global_install "$pkg_name" \
                        npm install -g "${pkg_name}@${new_version}"
                    case $? in
                    1)
                        has_failures=1
                        echo_warning "Failed to update global package: $pkg_name@$new_version"
                        ;;
                    2) return 1 ;;
                    esac
                fi
            done 3< <(echo "$outdated_output" | grep "→")
        else
            echo_skip "All global packages are up to date"
        fi
    else
        echo_warning "npm-check-updates (ncu) not installed. Install with: npm install -g npm-check-updates"

        # Fallback: list outdated packages
        echo_info "NPM: Checking for outdated global packages..."
        npm outdated -g 2>&1 || true
    fi

    echo_info "NPM: Cache sizes (report only; removal lives in --clean npm):"
    report_npm_cache_sizes

    if [ "$has_failures" -eq 1 ]; then
        echo_error "NPM update completed with errors"
        return 1
    fi

    echo_success "NPM update completed"
    return 0
}
