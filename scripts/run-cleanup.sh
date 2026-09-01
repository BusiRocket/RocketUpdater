#!/bin/bash

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$#" -ne 1 ] || [ "${ROCKETUPDATER_MODE:-}" != clean ] ||
    [ "${NONINTERACTIVE:-0}" = 1 ] || [ "${ROCKETUPDATER_LAUNCHD:-0}" = 1 ] ||
    [ ! -t 0 ] || [ ! -t 1 ]; then
    printf '%s\n' "Cleanup dispatch requires one allowlisted operation in manual TTY mode" >&2
    exit 78
fi

case $1 in
homebrew) cleanup_guards="guard_homebrew_cleanup" ;;
npm) cleanup_guards="guard_npm_public_cache" ;;
sparkle) cleanup_guards="guard_sparkle_obsolete_installations" ;;
all)
    cleanup_guards="guard_homebrew_cleanup guard_npm_public_cache guard_sparkle_obsolete_installations"
    ;;
*)
    printf '%s\n' "Unknown cleanup operation: $1" >&2
    exit 78
    ;;
esac

# Validate the complete dispatch before sourcing any cleanup code. This keeps
# `all` fail-closed if Phase 1 has not installed every reviewed guard.
for cleanup_guard in $cleanup_guards; do
    cleanup_file="$ROOT_DIR/cleanup/$cleanup_guard.sh"
    if [ ! -f "$cleanup_file" ]; then
        printf '%s\n' "Missing cleanup guard: $cleanup_guard" >&2
        exit 78
    fi
done

for cleanup_guard in $cleanup_guards; do
    cleanup_file="$ROOT_DIR/cleanup/$cleanup_guard.sh"
    # shellcheck source=/dev/null
    source "$cleanup_file" || exit 78
done

for cleanup_guard in $cleanup_guards; do
    if ! declare -F "$cleanup_guard" >/dev/null 2>&1; then
        printf '%s\n' "Cleanup guard is not defined: $cleanup_guard" >&2
        exit 78
    fi
done

cleanup_status=0
for cleanup_guard in $cleanup_guards; do
    "$cleanup_guard"
    guard_status=$?
    case $guard_status in
    0 | 20) ;;
    *) cleanup_status=$guard_status ;;
    esac
done

exit "$cleanup_status"
