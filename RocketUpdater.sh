#!/bin/bash

set -e

# Get the directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/bash_colors.sh"

echo_blue 'Starting Script'

# Function to check if necessary commands exist
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to run a specific plugin
run_plugin() {
    local plugin=$1
    if [ -f "$SCRIPT_DIR/plugins/$plugin.sh" ]; then
        source "$SCRIPT_DIR/plugins/$plugin.sh"
        if [ "$DISABLE" != "true" ]; then
            plugin_name=$(basename "$plugin" .sh)
            echo_cyan "Updating $plugin_name..."
            update_"$plugin_name"
        else
            echo_yellow "Plugin $plugin is disabled."
        fi
    else
        echo_red "Plugin $plugin not found."
    fi
}

# Function to handle errors and continue execution
try() {
    "$@" || echo_red "Command failed: $*"
}

# Check if a specific plugin was passed as an argument
if [ -n "$1" ]; then
    run_plugin "$1"
    exit 0
fi

# Check if the plugins directory exists and is not empty
if [ -d "$SCRIPT_DIR/plugins" ] && [ "$(ls -A "$SCRIPT_DIR"/plugins/*.sh 2>/dev/null)" ]; then
    echo_blue 'Including Plugins...'
    for plugin in "$SCRIPT_DIR"/plugins/*.sh; do
        plugin_name=$(basename "$plugin" .sh)
        echo_cyan "- $plugin_name..."
        source "$plugin"
    done
else
    echo_red 'No plugins found. Please ensure the plugins directory exists and contains plugins.'
fi

# Check if we are inside a conda environment
if [ -n "$CONDA_DEFAULT_ENV" ]; then
    echo_yellow "Deactivating the current conda environment ($CONDA_DEFAULT_ENV)."
    conda deactivate
fi

echo_blue 'Updating Plugins...'
if [ -d "$SCRIPT_DIR/plugins" ] && [ "$(ls -A "$SCRIPT_DIR"/plugins/*.sh 2>/dev/null)" ]; then
    for plugin in "$SCRIPT_DIR"/plugins/*.sh; do
        source "$plugin"
        plugin_name=$(basename "$plugin" .sh)
        if [ "$DISABLE" != "true" ]; then
            echo_cyan "Updating $plugin_name..."
            try update_"$plugin_name"
        else
            echo_yellow "Plugin $plugin_name is disabled."
        fi
    done
else
    echo_red 'No plugins found to update.'
fi
