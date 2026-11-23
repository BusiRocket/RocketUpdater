#!/bin/bash

# quarantine_helm_plugin_binary PLUGIN VERSION PLUGINS_ROOT moves the plugin's
# installed binary to the Trash and prints its old path, so a binary that does
# not match its published release cannot run until the plugin is reinstalled.
# The Trash keeps it for inspection. Returns 1 when it cannot be located or moved.
quarantine_helm_plugin_binary() {
    local plugin=$1
    local version=$2
    local plugins_root=$3
    local trash_command=${ROCKETUPDATER_TRASH_COMMAND:-/usr/bin/trash}
    local record
    local plugin_dir
    local installed_binary

    record=$(helm_plugin_release_source "$plugin" "$version") || return 1
    plugin_dir=$(find_helm_plugin_directory "$plugin" "$plugins_root") || return 1
    installed_binary="$plugin_dir/bin/$(basename "$(printf '%s' "$record" | cut -f4)")"
    [ -f "$installed_binary" ] || return 1
    "$trash_command" "$installed_binary" || return 1
    printf '%s\n' "$installed_binary"
}
