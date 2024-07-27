#!/bin/bash

PLUGIN_NAME="NPM"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_npm() {
    command_exists npm
}

update_npm() {
    if check_npm; then
        echo 'NPM: Updating...'
        ncu -g -u
        echo 'NPM: Cleaning Cache...'
        npm cache clean -g --force
    fi
}
