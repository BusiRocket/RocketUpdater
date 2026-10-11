#!/bin/bash

PLUGIN_NAME="Mole"
PLUGIN_VERSION="3.0.0"
DISABLE=false
PLUGIN_PRIORITY=90
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=report
# Scheduled runs stay report-only: Mole's clean target set changes with the
# third-party binary, so no fixed guard can prove its candidates are
# reconstructable unattended. A manual run is the owner at the keyboard, and
# there `update_mole` runs Mole's real clean.

check_mole() {
    command -v mo >/dev/null 2>&1
}

# Mole's user sweep removes every child of ~/Library/Logs and ~/Library/Caches,
# which took RocketUpdater's own event log and lock directory mid-run on
# 2026-10-11. The real clean runs only while Mole's whitelist protects both.
mole_protects_rocketupdater() {
    local whitelist="$HOME/.config/mole/whitelist"
    local protected_path

    for protected_path in Library/Logs/RocketUpdater Library/Caches/RocketUpdater; do
        # Mole expands a literal ~ and $HOME itself, so match those spellings.
        # shellcheck disable=SC2088
        if ! /usr/bin/grep -qxF -e "~/$protected_path" -e "\$HOME/$protected_path" \
            -e "$HOME/$protected_path" "$whitelist" 2>/dev/null; then
            return 1
        fi
    done
}

print_mole_identity() {
    local mole_path
    local mole_version
    mole_path=$(command -v mo)
    # The binary hash stays the authoritative identity of the target set this
    # run describes. `mo --version` opens with a blank line (1.59.1), so the
    # first non-empty line is the version.
    mole_version=$(mo --version 2>/dev/null | /usr/bin/awk 'NF { print; exit }')
    [ -n "$mole_version" ] || mole_version=unavailable
    printf 'mole version=%s sha256=%s\n' \
        "$mole_version" \
        "$(shasum -a 256 "$mole_path" 2>/dev/null | awk '{ print $1 }')"

    # Mole abandons its own dry run when a per-item size check exceeds its
    # budget, which this machine's 71 GB OrbStack blob does every time. Give it
    # a larger budget than the 30s default, still far inside the plugin timeout.
    export MOLE_TIMEOUT_DISK_VERIFY_SEC="${MOLE_TIMEOUT_DISK_VERIFY_SEC:-120}"
}

report_mole() {
    if ! check_mole; then
        echo_skip "Mole (mo) is not installed. Skipping... (brew install mole)"
        return 20
    fi

    print_mole_identity

    echo_info "Mole: Previewing clean candidates (dry run only)..."
    local dry_run_output
    local dry_run_status
    dry_run_output=$(mo clean --dry-run 2>&1)
    dry_run_status=$?
    printf '%s\n' "$dry_run_output"

    if [ "$dry_run_status" -ne 0 ]; then
        # An abandoned measurement is incomplete evidence, not a RocketUpdater
        # failure, and must not mark the whole scheduled run failed. Anything
        # else stays a failure, so unrecognized output fails loudly.
        case $dry_run_output in
        *"Dry run cancelled"* | *"size check timed out"*)
            echo_skip "Mole abandoned its own size check; the preview above is under-reported"
            return 20
            ;;
        esac
        echo_error "Mole dry run reported errors"
        return 1
    fi

    echo_note "Mole removal stays manual; the dry run above is evidence, not action"
    return 0
}

update_mole() {
    if ! check_mole; then
        echo_skip "Mole (mo) is not installed. Skipping... (brew install mole)"
        return 20
    fi

    if ! mole_protects_rocketupdater; then
        echo_warning "Mole would delete RocketUpdater's logs and lock; add ~/Library/Logs/RocketUpdater and ~/Library/Caches/RocketUpdater to ~/.config/mole/whitelist"
        return 20
    fi

    print_mole_identity

    # stdin is /dev/null here, so Mole takes its non-interactive path: user
    # caches are cleaned without a prompt, and system caches only when the
    # sudo grant RocketUpdater cached at start is still live.
    echo_info "Mole: Cleaning caches, logs and app leftovers..."
    local clean_output
    local clean_status
    clean_output=$(mo clean </dev/null 2>&1)
    clean_status=$?
    printf '%s\n' "$clean_output"

    if [ "$clean_status" -ne 0 ]; then
        echo_error "Mole clean reported errors (status $clean_status)"
        return 1
    fi

    local freed_line
    freed_line=$(printf '%s\n' "$clean_output" |
        /usr/bin/sed -e $'s/\033\\[[0-9;]*[A-Za-z]//g' |
        /usr/bin/awk '/Tracked cleanup:/ { sub(/^[^T]*/, ""); print; exit }')
    if [ -n "$freed_line" ]; then
        echo_change "Mole: $freed_line"
    else
        echo_success "Mole clean finished"
    fi
    return 0
}
