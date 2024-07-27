#!/bin/bash

PLUGIN_NAME="NPX"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_npx() {
    command_exists npx
}

update_npx() {
    if check_npx; then
        echo 'Updating Browsers List...'
        npx update-browserslist-db@latest
    fi
}
