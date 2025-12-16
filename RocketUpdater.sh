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

# Function to run a specific plugin
run_plugin() {
    local plugin=$1
    local plugin_file="$SCRIPT_DIR/plugins/$plugin.sh"
    
    if [ -f "$plugin_file" ]; then
        # Reset DISABLE for each plugin
        unset DISABLE
        source "$plugin_file"
        
        if [ "$DISABLE" = "true" ]; then
            echo_yellow "⏭️  Plugin $plugin is disabled."
            SKIPPED_PLUGINS=$((SKIPPED_PLUGINS + 1))
            return
        fi
        
        plugin_name=$(basename "$plugin" .sh)
        TOTAL_PLUGINS=$((TOTAL_PLUGINS + 1))
        
        echo_cyan "📦 Updating $plugin_name..."
        
        if try_plugin "update_$plugin_name"; then
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
    exit 0
fi

# Function to load and update all plugins
load_and_update_plugins() {
    if [ -d "$SCRIPT_DIR/plugins" ] && [ "$(ls -A "$SCRIPT_DIR"/plugins/*.sh 2>/dev/null)" ]; then
        echo_blue '📂 Loading Plugins...'
        echo_separator
        
        for plugin in "$SCRIPT_DIR"/plugins/*.sh; do
            run_plugin "$(basename "$plugin" .sh)"
        done
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
