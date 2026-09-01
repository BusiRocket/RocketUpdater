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
    mole_path=$(command -v mo)
    printf 'mole version=%s sha256=%s\n' \
        "$(mo --version 2>/dev/null | head -1)" \
        "$(shasum -a 256 "$mole_path" 2>/dev/null | awk '{ print $1 }')"

    echo_info "Mole: Previewing clean candidates (dry run only)..."
    if ! mo clean --dry-run 2>&1; then
        echo_error "Mole dry run reported errors"
        return 1
    fi

    echo_warning "Mole removal stays manual; the dry run above is evidence, not action"
    return 0
}

update_mole() {
    report_mole
}
