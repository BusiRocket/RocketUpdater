#!/bin/bash

PLUGIN_NAME="Mole"
PLUGIN_VERSION="1.1.0"
DISABLE=false
PLUGIN_PRIORITY=90
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run
# Heaviest cleanup, and the slowest step in a run: it scans the whole disk, so
# it goes after every updater and after the cheaper cleanup plugins.

check_mole() {
    command -v mo >/dev/null 2>&1
}

update_mole() {
    if ! check_mole; then
        echo_skip "Mole (mo) is not installed. Skipping... (brew install mole)"
        return 0
    fi

    # Runs without sudo: system caches are skipped, user-level caches are
    # cleaned. Mole keeps its own whitelist (mo clean --whitelist).
    # Streamed, not piped into tail: the scan takes minutes with no output of
    # its own, and a pipe would both hide the progress and hand the exit status
    # of tail to the check below, hiding every failure.
    echo_info "Mole: Running deep clean (user-level, non-interactive)..."
    if mo clean 2>&1; then
        echo_success "Mole cleanup completed"
    else
        echo_error "Mole cleanup reported errors"
        return 1
    fi

    return 0
}
