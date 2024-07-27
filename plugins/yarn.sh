#!/bin/bash

PLUGIN_NAME="Yarn"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_yarn() {
    command_exists yarn
}

update_yarn() {
    if check_yarn; then
        echo 'Updating Yarn...'
        yarn set version stable
    fi
}
