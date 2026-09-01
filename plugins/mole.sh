#!/bin/bash

PLUGIN_NAME="Mole"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=90
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=report
# Report-only: Mole's clean target set changes with the third-party binary, so
# no fixed guard can prove its candidates are reconstructable. The dry run is
# the whole scheduled surface.

check_mole() {
    command -v mo >/dev/null 2>&1
}

report_mole() {
    if ! check_mole; then
        echo_skip "Mole (mo) is not installed. Skipping... (brew install mole)"
        return 20
    fi

    local mole_path
    local mole_version
    mole_path=$(command -v mo)
    # Mole exposes no version string on this build, so the binary hash is the
    # authoritative identity of the target set this dry run describes.
    mole_version=$(mo --version 2>/dev/null | head -1)
    [ -n "$mole_version" ] || mole_version=unavailable
    printf 'mole version=%s sha256=%s\n' \
        "$mole_version" \
        "$(shasum -a 256 "$mole_path" 2>/dev/null | awk '{ print $1 }')"

    # Mole abandons its own dry run when a per-item size check exceeds its
    # budget, which this machine's 71 GB OrbStack blob does every time. Give it
    # a larger budget than the 30s default, still far inside the plugin timeout.
    export MOLE_TIMEOUT_DISK_VERIFY_SEC="${MOLE_TIMEOUT_DISK_VERIFY_SEC:-120}"

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

    echo_warning "Mole removal stays manual; the dry run above is evidence, not action"
    return 0
}

update_mole() {
    report_mole
}
