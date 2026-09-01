#!/bin/bash

# guard_homebrew_cleanup deletes Homebrew cache/temp bytes only after proving
# every dry-run candidate sits under a safe, reconstructable root, previewing
# the allocated size, and receiving the typed operation name on a real TTY.
guard_homebrew_cleanup() {
    if [ "${NONINTERACTIVE:-0}" = 1 ] || [ "${ROCKETUPDATER_LAUNCHD:-0}" = 1 ] ||
        [ ! -t 0 ] || [ ! -t 1 ]; then
        echo_error "Homebrew cleanup requires an interactive terminal"
        return 78
    fi

    if ! command_exists brew; then
        echo_skip "Homebrew is not installed"
        return 20
    fi

    local brew_prefix
    if ! brew_prefix=$(brew --prefix 2>/dev/null) || [ -z "$brew_prefix" ]; then
        echo_error "Homebrew prefix could not be resolved"
        return 1
    fi

    # Two immediate dry runs must agree before anything is removed; a changing
    # candidate set means Homebrew state is moving under us.
    local first_preview
    local second_preview
    first_preview=$(HOMEBREW_NO_AUTO_UPDATE=1 brew cleanup -n --prune=all 2>&1) || true
    second_preview=$(HOMEBREW_NO_AUTO_UPDATE=1 brew cleanup -n --prune=all 2>&1) || true

    local first_candidates
    local second_candidates
    first_candidates=$(printf '%s\n' "$first_preview" |
        sed -n 's/^Would remove: //p' | sed 's/ ([^)]*)$//' | LC_ALL=C sort)
    second_candidates=$(printf '%s\n' "$second_preview" |
        sed -n 's/^Would remove: //p' | sed 's/ ([^)]*)$//' | LC_ALL=C sort)

    if [ "$first_candidates" != "$second_candidates" ]; then
        printf '%s\n' "$first_preview"
        echo_error "Homebrew dry-run candidates changed between previews"
        return 1
    fi

    if [ -z "$first_candidates" ]; then
        echo_skip "Homebrew has no removal candidates"
        return 20
    fi

    local candidate
    local unsafe_candidate=""
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        case $candidate in
        "$HOME/Library/Caches/Homebrew"/*) ;;
        "$brew_prefix/var/homebrew/tmp"/*) ;;
        "$brew_prefix"/lib/python*/site-packages/__pycache__ | \
            "$brew_prefix"/lib/python*/site-packages/__pycache__/*) ;;
        *)
            unsafe_candidate=$candidate
            break
            ;;
        esac
    done <<<"$first_candidates"

    printf '%s\n' "$first_candidates"

    if [ -n "$unsafe_candidate" ]; then
        echo_warning "Candidate outside the safe roots; nothing was removed: $unsafe_candidate"
        return 20
    fi

    local total_kib=0
    local candidate_kib
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        candidate_kib=$(du -sk "$candidate" 2>/dev/null | awk '{ print $1 }')
        case $candidate_kib in
        '' | *[!0-9]*) candidate_kib=0 ;;
        esac
        total_kib=$((total_kib + candidate_kib))
    done <<<"$first_candidates"

    printf 'homebrew_cleanup allocated_kib=%s\n' "$total_kib"
    printf 'Type "homebrew" to remove these candidates: '

    local answer
    IFS= read -r answer
    if [ "$answer" != homebrew ]; then
        echo_skip "Confirmation did not match; nothing was removed"
        return 20
    fi

    if ! HOMEBREW_NO_AUTO_UPDATE=1 brew cleanup --prune=all 2>&1; then
        echo_error "Homebrew removal command failed"
        return 1
    fi

    echo_success "Homebrew cache and temporary files removed"
    return 0
}
