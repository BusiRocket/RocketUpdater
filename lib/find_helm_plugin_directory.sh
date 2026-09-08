#!/bin/bash

# find_helm_plugin_directory PLUGIN PLUGINS_ROOT prints the directory under
# PLUGINS_ROOT whose plugin.yaml declares PLUGIN, and returns 1 when there is
# not exactly one. The directory name is not the plugin name — helm-dashboard
# installs into "helm-dashboard.git" and declares "dashboard" — so the manifest
# is the only thing that maps one to the other.
find_helm_plugin_directory() {
    local plugin=$1
    local plugins_root=$2
    local manifest
    local declared_name
    local matches=()

    for manifest in "$plugins_root"/*/plugin.yaml; do
        [ -f "$manifest" ] || continue
        declared_name=$(sed -n \
            's/^name:[[:space:]]*"\{0,1\}\([^"[:space:]]*\)"\{0,1\}[[:space:]]*$/\1/p' \
            "$manifest" | head -1)
        if [ "$declared_name" = "$plugin" ]; then
            matches+=("$(dirname "$manifest")")
        fi
    done

    if [ ${#matches[@]} -ne 1 ]; then
        return 1
    fi

    printf '%s\n' "${matches[0]}"
}
