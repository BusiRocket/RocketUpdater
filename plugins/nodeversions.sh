#!/bin/bash

PLUGIN_NAME="nvm Node Versions"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=55
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

# Brings each installed Node major to its latest release, carrying the global
# packages over, then uninstalls the superseded release of that major. A major
# never changes, and a release that an nvm alias names exactly is kept, since
# something pinned it. A removed release comes back with `nvm install`.
update_nodeversions() {
    local nvm_dir=${NVM_DIR:-$HOME/.nvm}
    if [ ! -s "$nvm_dir/nvm.sh" ]; then
        echo_skip "nvm is not installed"
        return 20
    fi

    # nvm.sh reads unset variables throughout; the plugin runs in its own process.
    set +u
    # shellcheck source=/dev/null
    . "$nvm_dir/nvm.sh" --no-use

    local majors
    majors=$(find "$nvm_dir/versions/node" -mindepth 1 -maxdepth 1 -type d -name 'v*' -print 2>/dev/null |
        sed 's#.*/v##; s#\..*##' | sort -un)
    if [ -z "$majors" ]; then
        echo_skip "nvm has no Node versions installed"
        return 20
    fi

    local pinned_versions
    pinned_versions=$(cat "$nvm_dir"/alias/* 2>/dev/null)

    local has_failures=0
    local major
    for major in $majors; do
        local installed_before
        installed_before=$(nvm version "$major")
        # nvm refuses --reinstall-packages-from when the target is already
        # installed, so a current major must never reach `nvm install`.
        local latest
        latest=$(nvm version-remote "$major" 2>/dev/null)
        case $latest in
        v[0-9]*) ;;
        *)
            echo_warning "nvm could not resolve the latest Node $major"
            has_failures=1
            continue
            ;;
        esac
        if [ "$latest" = "$installed_before" ]; then
            continue
        fi
        echo_info "nvm: Updating Node $major ($installed_before -> $latest)..."
        if ! nvm install "$major" --reinstall-packages-from="$installed_before" --no-progress 2>&1; then
            echo_warning "nvm could not update Node $major"
            has_failures=1
            continue
        fi

        local installed_after
        installed_after=$(nvm version "$major")
        if [ "$installed_after" = "$installed_before" ]; then
            continue
        fi
        echo_change "Node $installed_before -> $installed_after"

        if printf '%s\n' "$pinned_versions" | grep -qx "$installed_before"; then
            echo_note "Keeping $installed_before: an nvm alias names it"
        elif ! nvm uninstall "$installed_before" 2>&1; then
            echo_warning "nvm could not uninstall the superseded $installed_before"
        fi
    done

    if [ "$has_failures" -ne 0 ]; then
        return 1
    fi
    echo_success "nvm Node versions are current within their majors"
    return 0
}
