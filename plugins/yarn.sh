#!/bin/bash

PLUGIN_NAME="Yarn"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=50
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run
# Cache and metadata deletion stay manual: Berry metadata is offline resolution
# state, and cached package zips can come from private or mutable sources.

check_yarn() {
    command_exists yarn
}

check_corepack() {
    command_exists corepack
}

# get_yarn_version prints the major version, or fails with whatever yarn said
# on stderr: a Corepack shim that cannot fetch its pinned release prints
# nothing on stdout, and the run reported "Detected version .x".
get_yarn_version() {
    local output
    local major

    output=$(yarn --version </dev/null 2>&1)
    major=$(printf '%s\n' "$output" | /usr/bin/awk -F. '/^[0-9]+\.[0-9]+/ { print $1; exit }')
    if [ -z "$major" ]; then
        printf '%s\n' "$output" >&2
        return 1
    fi
    printf '%s\n' "$major"
}

report_yarn_caches() {
    local cache_directory
    for cache_directory in "$HOME/Library/Caches/Yarn" "$HOME/.yarn/berry/cache" \
        "$HOME/.yarn/berry/metadata"; do
        if [ -d "$cache_directory" ]; then
            du -sk "$cache_directory" 2>&1
        fi
    done
}

update_yarn() {
    local has_failures=0

    if ! check_yarn; then
        echo_skip "Yarn is not installed. Skipping..."
        return 20
    fi

    # When yarn is a Corepack shim, the shim defaults
    # COREPACK_ENABLE_DOWNLOAD_PROMPT to 1, so the very first `yarn --version`
    # asks on stdin before fetching the pinned release. That prompt goes to
    # stderr, which this plugin discards, so the run blocked forever with no
    # output at all. 0 keeps the download and drops the question.
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

    local yarn_major_version
    if ! yarn_major_version=$(get_yarn_version); then
        echo_error "Yarn did not report its version; see the output above"
        return 1
    fi

    echo_info "Yarn: Detected version $yarn_major_version.x"

    if [ "$yarn_major_version" = "1" ]; then
        echo_info "Yarn Classic: Updating via npm..."
        if ! npm install -g yarn@latest --force 2>&1; then
            has_failures=1
            echo_warning "Yarn update via npm failed"
        fi
    else
        if check_corepack; then
            echo_info "Yarn Berry: Updating global yarn via corepack..."
            if ! corepack prepare yarn@stable --activate 2>&1; then
                has_failures=1
                echo_warning "corepack prepare yarn@stable failed"
            fi
        else
            echo_info "Yarn Berry: corepack not found — falling back to npm..."
            if ! npm install -g yarn@latest --force 2>&1; then
                has_failures=1
                echo_warning "Yarn update via npm failed"
            fi
        fi
    fi

    if [ "$yarn_major_version" = "1" ]; then
        echo_info "Yarn: Checking global packages..."
        (cd "$HOME" && yarn global upgrade) 2>&1 ||
            echo_skip "No global packages to update"
    fi

    echo_info "Yarn: Cache and metadata sizes (report only; deletion stays manual):"
    report_yarn_caches

    if [ "$has_failures" -ne 0 ]; then
        echo_error "Yarn update completed with errors"
        return 1
    fi

    echo_success "Yarn update completed"
    return 0
}
