#!/bin/bash

PLUGIN_NAME="Homebrew Health"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=20
PLUGIN_TIMEOUT_SECONDS=900
PLUGIN_SCHEDULE_ACTION=run

# Severity split: a formula whose dependency is absent is broken and must fail
# the run. `brew doctor` output is advisory by Homebrew's own definition - on
# any lived-in machine it always has something to say - so it is reported
# without failing. A health check that is permanently red teaches the reader to
# ignore failures, which is worse than not checking at all.
update_brewhealth() {
    if ! command_exists brew; then
        echo_skip "Homebrew is not installed"
        return 20
    fi

    local has_failures=0

    echo_info "Homebrew: Checking missing dependencies..."
    local missing_output
    if ! missing_output=$(brew missing 2>&1); then
        has_failures=1
    fi
    if [ -n "$missing_output" ]; then
        printf '%s\n' "$missing_output"
    fi

    echo_info "Homebrew: Previewing autoremove candidates..."
    if ! brew autoremove --dry-run 2>&1; then
        echo_warning "Homebrew could not preview autoremove candidates"
    fi

    echo_info "Homebrew: Running doctor (advisory)..."
    if ! brew doctor 2>&1; then
        echo_warning "brew doctor reported advisory findings above; they do not fail the run"
    fi

    if [ "$has_failures" -ne 0 ]; then
        echo_error "Homebrew has formulae whose dependencies are missing"
        return 1
    fi

    echo_success "Homebrew health checks passed"
    return 0
}
