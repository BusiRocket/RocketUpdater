#!/bin/bash

PLUGIN_NAME="Homebrew"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run
# Bootstrap: the other plugins update binaries Homebrew installs, so it goes first.

check_homebrew() {
    command_exists brew
}

# run_brew_step NAME MAX_ATTEMPTS COMMAND [ARG...] runs the exact argv without
# a shell round-trip; the caller chooses how many attempts the step deserves.
run_brew_step() {
    local step_name=$1
    local max_attempts=$2
    shift 2
    local attempt=1
    local step_status

    while [ "$attempt" -le "$max_attempts" ]; do
        "$@" 2>&1
        step_status=$?

        if [ "$step_status" -eq 0 ]; then
            return 0
        fi

        if [ "$attempt" -lt "$max_attempts" ]; then
            echo_warning "$step_name failed on attempt $attempt/$max_attempts. Retrying in 5 seconds..."
            sleep 5
        fi

        attempt=$((attempt + 1))
    done

    echo_error "$step_name reported errors"
    return 1
}

# Upgrading the node formula replaces the Node/npm runtime, so the global npm
# package tree is snapshotted around it; nothing outside the formula may change.
run_node_formula_upgrade() {
    if ! command_exists npm; then
        run_brew_step "Upgrade of formula node" 1 brew upgrade --formula node
        return $?
    fi

    local before_snapshot
    local after_snapshot
    local upgrade_status
    local violations

    if ! before_snapshot=$(snapshot_global_npm_packages); then
        echo_error "Global npm snapshot failed before upgrading node"
        return 1
    fi

    run_brew_step "Upgrade of formula node" 1 brew upgrade --formula node
    upgrade_status=$?

    if ! after_snapshot=$(snapshot_global_npm_packages); then
        echo_error "Global npm snapshot failed after upgrading node"
        return 1
    fi

    violations=$(compare_global_npm_snapshots "$before_snapshot" "$after_snapshot" "")

    if [ -n "$violations" ]; then
        printf '%s\n' "$violations"
        echo_error "Global npm package tree damaged by the node formula upgrade"
        if declare -F log_event >/dev/null 2>&1 && [ -n "${ROCKETUPDATER_EVENT_LOG:-}" ]; then
            log_event error integrity homebrew failed 0 "target=node $violations" || true
        fi
        return 1
    fi

    return "$upgrade_status"
}

# list_brew_outdated KIND prints one outdated package name per line. Homebrew
# writes deprecation and tap warnings to stderr, so stderr is kept apart from
# the name list: merging them made the plugin try to upgrade a warning line.
list_brew_outdated() {
    local kind=$1
    local stderr_file=$2
    local names
    local status

    names=$(brew outdated "--$kind" --quiet 2>"$stderr_file")
    status=$?

    if [ "$status" -ne 0 ]; then
        return "$status"
    fi

    # A package name is a single token, optionally tap-qualified. Anything else
    # is stray output and must never reach brew upgrade.
    printf '%s\n' "$names" | grep -E '^[A-Za-z0-9@._+-]+(/[A-Za-z0-9@._+-]+){0,2}$' || true
    return 0
}

update_homebrew() {
    if ! check_homebrew; then
        echo_skip "Homebrew is not installed"
        return 20
    fi

    export HOMEBREW_NO_ASK=1
    # The user installs their own third-party taps deliberately, but the blanket
    # HOMEBREW_NO_REQUIRE_TAP_TRUST is deprecated and printed a warning on every
    # brew call. Trust is now recorded per tap in ~/.homebrew/trust.json via
    # `brew trust --tap`; a tap added later is reported here rather than trusted
    # silently, which is the point of the supported mechanism.
    # Only these casks auto-update themselves in ways worth overriding; a
    # blanket --greedy retries deterministic postflight failures forever.
    export HOMEBREW_UPGRADE_GREEDY_CASKS="codexbar goplaces"

    local failed_items=""

    echo_info 'Homebrew: Updating...'
    if ! run_brew_step "Homebrew update" 3 brew update; then
        return 1
    fi

    echo_info 'Homebrew: Enumerating outdated formulae...'
    local brew_stderr
    brew_stderr=$(mktemp -t rocketupdater-brew-outdated) || return 1
    local outdated_formulae
    if ! outdated_formulae=$(list_brew_outdated formula "$brew_stderr"); then
        cat "$brew_stderr"
        /bin/rm -f -- "$brew_stderr"
        echo_error "Homebrew could not enumerate outdated formulae"
        return 1
    fi

    # Upgrade one item at a time so one broken formula or cask cannot mask or
    # abort the rest, and never retry a deterministic upgrade failure.
    #
    # The list is fed on fd 3, not stdin: `brew upgrade` reads stdin and drained
    # the rest of the list, so a run upgraded one package and then behaved as if
    # the remaining ones were already done.
    local item
    while IFS= read -r item <&3; do
        [ -n "$item" ] || continue
        echo_info "Homebrew: Upgrading formula $item..."
        if [ "$item" = node ]; then
            if ! run_node_formula_upgrade; then
                failed_items="$failed_items $item"
            fi
        elif ! run_brew_step "Upgrade of formula $item" 1 brew upgrade --formula "$item"; then
            failed_items="$failed_items $item"
        fi
    done 3<<<"$outdated_formulae"

    echo_info 'Homebrew: Enumerating outdated casks...'
    local outdated_casks
    if ! outdated_casks=$(list_brew_outdated cask "$brew_stderr"); then
        cat "$brew_stderr"
        /bin/rm -f -- "$brew_stderr"
        echo_error "Homebrew could not enumerate outdated casks"
        return 1
    fi
    /bin/rm -f -- "$brew_stderr"

    while IFS= read -r item <&3; do
        [ -n "$item" ] || continue
        echo_info "Homebrew: Upgrading cask $item..."
        if ! run_brew_step "Upgrade of cask $item" 1 \
            brew upgrade --cask --no-ask --no-quit "$item"; then
            failed_items="$failed_items $item"
        fi
    done 3<<<"$outdated_casks"

    if [ -n "$failed_items" ]; then
        echo_error "Homebrew items failed:$failed_items"
        return 1
    fi

    echo_success "Homebrew packages updated"
    return 0
}
