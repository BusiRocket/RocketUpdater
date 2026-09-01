#!/bin/bash

# guard_npm_public_cache clears the npm user cache only after proving the cache
# root is the real user-owned directory and every indexed request resolves to
# the public registry.npmjs.org authority with no userinfo. Any private,
# local, credentialed, unknown, or unparseable authority makes the step
# report-only.
guard_npm_public_cache() {
    if [ "${NONINTERACTIVE:-0}" = 1 ] || [ "${ROCKETUPDATER_LAUNCHD:-0}" = 1 ] ||
        [ ! -t 0 ] || [ ! -t 1 ]; then
        echo_error "npm cache removal requires an interactive terminal"
        return 78
    fi

    if ! command_exists npm; then
        echo_skip "npm is not installed"
        return 20
    fi

    local npm_root="$HOME/.npm"
    local cache_root="$npm_root/_cacache"

    if [ -L "$npm_root" ] || [ ! -d "$npm_root" ] || [ ! -O "$npm_root" ]; then
        echo_error "The npm cache root is missing, symlinked, or not user-owned: $npm_root"
        return 20
    fi

    if [ -L "$cache_root" ] || [ ! -d "$cache_root" ]; then
        echo_skip "No _cacache directory to remove"
        return 20
    fi

    # Every indexed request must parse and resolve to exactly the public
    # registry authority. One bad entry keeps the whole cache.
    local request_keys
    request_keys=$(find "$cache_root/index-v5" -type f -print 2>/dev/null |
        while IFS= read -r index_file; do
            sed -n 's/.*"key":"\([^"]*\)".*/\1/p' "$index_file"
        done)

    local request_key
    local unsafe_key=""
    while IFS= read -r request_key; do
        [ -n "$request_key" ] || continue
        case $request_key in
        'make-fetch-happen:request-cache:https://registry.npmjs.org/'*) ;;
        *)
            unsafe_key=$request_key
            break
            ;;
        esac
    done <<<"$request_keys"

    if [ -n "$unsafe_key" ]; then
        echo_warning "Cached request outside the public registry; nothing was removed: $unsafe_key"
        return 20
    fi

    local allocated_kib
    allocated_kib=$(du -sk "$cache_root" 2>/dev/null | awk '{ print $1 }')
    printf 'npm_public_cache root=%s allocated_kib=%s\n' "$cache_root" "${allocated_kib:-0}"
    printf 'Type "npm" to remove the public-registry npm cache: '

    local answer
    IFS= read -r answer
    if [ "$answer" != npm ]; then
        echo_skip "Confirmation did not match; nothing was removed"
        return 20
    fi

    if ! npm cache clean --force 2>&1; then
        echo_error "npm cache removal command failed"
        return 1
    fi

    echo_success "Public-registry npm cache removed"
    return 0
}
