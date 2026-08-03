#!/bin/bash

set -e

# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/bash_colors.sh"

# Track plugin results for summary (bash 3.2 compatible)
TOTAL_PLUGINS=0
SUCCESSFUL_PLUGINS=0
FAILED_PLUGINS=0
SKIPPED_PLUGINS=0
FAILED_PLUGIN_LIST=""

echo_blue '🚀 RocketUpdater - Starting System Update'
echo_separator

# Function to check if necessary commands exist
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Plugin execution order, in the style of SysV init sequence numbers: lower
# runs first, and the gaps leave room to insert a plugin without renumbering.
#
#   10-29   bootstrap: package managers the other plugins install through
#   30-69   regular updaters (the default band)
#   70-99   cleanup, which must run after everything has finished downloading
#   100+    system updates that may force a restart
#
# A plugin that does not care about its position omits PLUGIN_PRIORITY.
DEFAULT_PLUGIN_PRIORITY=50

# Read a plugin's declared priority without polluting the caller's scope: the
# subshell discards the function definitions, which run_plugin sources anyway.
plugin_priority() {
    local priority
    priority=$(
        PLUGIN_PRIORITY=$DEFAULT_PLUGIN_PRIORITY
        # shellcheck source=/dev/null
        source "$1" >/dev/null 2>&1
        printf '%s' "$PLUGIN_PRIORITY"
    )

    case $priority in
    '' | *[!0-9]*) priority=$DEFAULT_PLUGIN_PRIORITY ;;
    esac

    printf '%s' "$priority"
}

# Emit plugin names ordered by priority, alphabetically within a priority so
# the order stays deterministic.
sorted_plugin_names() {
    local plugin_file
    for plugin_file in "$SCRIPT_DIR"/plugins/*.sh; do
        printf '%03d %s\n' "$(plugin_priority "$plugin_file")" "$(basename "$plugin_file" .sh)"
    done | sort | awk '{print $2}'
}

# Function to run a specific plugin
run_plugin() {
    local plugin=$1
    local plugin_file="$SCRIPT_DIR/plugins/$plugin.sh"

    if [ -f "$plugin_file" ]; then
        # Reset per-plugin declarations so one plugin does not inherit another's
        unset DISABLE
        unset PLUGIN_PRIORITY
        # shellcheck source=/dev/null
        source "$plugin_file"

        if [ "$DISABLE" = "true" ]; then
            echo_yellow "⏭️  Plugin $plugin is disabled."
            SKIPPED_PLUGINS=$((SKIPPED_PLUGINS + 1))
            return
        fi

        local plugin_name
        plugin_name=$(basename "$plugin" .sh)
        TOTAL_PLUGINS=$((TOTAL_PLUGINS + 1))

        echo_cyan "📦 Updating $plugin_name..."

        # Plugins run unattended, so give them no stdin to block on. A tool that
        # asks a question gets EOF and fails with it on the record, instead of
        # stalling the whole run on a prompt nobody can see (the Corepack yarn
        # shim wrote its download prompt to a discarded stderr and waited).
        if try_plugin "update_$plugin_name" </dev/null; then
            SUCCESSFUL_PLUGINS=$((SUCCESSFUL_PLUGINS + 1))
        else
            FAILED_PLUGINS=$((FAILED_PLUGINS + 1))
            if [ -z "$FAILED_PLUGIN_LIST" ]; then
                FAILED_PLUGIN_LIST="$plugin"
            else
                FAILED_PLUGIN_LIST="$FAILED_PLUGIN_LIST $plugin"
            fi
        fi

        echo_separator
    else
        echo_red "❌ Plugin $plugin not found."
    fi
}

# Function to handle plugin execution with error trapping
try_plugin() {
    local func=$1
    if type "$func" &>/dev/null; then
        if "$func"; then
            return 0
        else
            echo_red "⚠️  Command failed: $func"
            return 1
        fi
    else
        echo_red "⚠️  Function $func not defined"
        return 1
    fi
}

# Check if a specific plugin was passed as an argument
if [ -n "$1" ]; then
    run_plugin "$1"

    if [ "$FAILED_PLUGINS" -gt 0 ]; then
        exit 1
    fi

    exit 0
fi

# Function to load and update all plugins
load_and_update_plugins() {
    if [ -d "$SCRIPT_DIR/plugins" ] && [ "$(ls -A "$SCRIPT_DIR"/plugins/*.sh 2>/dev/null)" ]; then
        echo_blue '📂 Loading Plugins...'
        echo_separator

        local plugin_order
        plugin_order=$(sorted_plugin_names)

        echo_cyan "🔢 Order: $(echo "$plugin_order" | tr '\n' ' ')"
        echo_separator

        # Read the plugin list on fd 3, not stdin. Plugins run commands that
        # read stdin themselves (brew upgrade shelling out to npm install, for
        # one), and on stdin they would swallow the rest of the list and end the
        # run after the first plugin. Piping into the loop is wrong for a second
        # reason: it puts the body in a subshell, losing the summary counters.
        local plugin
        while read -r plugin <&3; do
            [ -n "$plugin" ] || continue
            run_plugin "$plugin"
        done 3<<<"$plugin_order"
    else
        echo_red '❌ No plugins found. Please ensure the plugins directory exists and contains plugins.'
    fi
}

# Function to display summary
display_summary() {
    echo ""
    echo_blue "═══════════════════════════════════════════"
    echo_blue "📊 UPDATE SUMMARY"
    echo_blue "═══════════════════════════════════════════"
    echo ""
    echo_green "✅ Successful: $SUCCESSFUL_PLUGINS"

    if [ "$FAILED_PLUGINS" -gt 0 ]; then
        echo_red "❌ Failed: $FAILED_PLUGINS"
    else
        echo "   Failed: 0"
    fi

    if [ "$SKIPPED_PLUGINS" -gt 0 ]; then
        echo_yellow "⏭️  Skipped: $SKIPPED_PLUGINS"
    fi

    echo ""
    echo_blue "───────────────────────────────────────────"

    # Show failed plugins if any
    if [ "$FAILED_PLUGINS" -gt 0 ]; then
        echo_red "Failed plugins:"
        for plugin in $FAILED_PLUGIN_LIST; do
            echo_red "  • $plugin"
        done
        echo ""
    fi

    echo_blue "═══════════════════════════════════════════"

    if [ "$FAILED_PLUGINS" -eq 0 ]; then
        echo_green "🎉 All updates completed successfully!"
    else
        echo_yellow "⚠️  Some updates failed. Check the logs above."
    fi
}

# Check if we are inside a conda environment
if [ -n "$CONDA_DEFAULT_ENV" ] && [ "$CONDA_DEFAULT_ENV" != "base" ]; then
    echo_yellow "🔄 Deactivating the current conda environment ($CONDA_DEFAULT_ENV)."
    conda deactivate
fi

echo_blue '🔄 Updating Plugins...'
echo_separator
load_and_update_plugins

# Display summary
display_summary

if [ "$FAILED_PLUGINS" -gt 0 ]; then
    exit 1
fi
