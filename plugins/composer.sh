#!/bin/bash

PLUGIN_NAME="Composer"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_composer() {
    command_exists composer
}

update_composer() {
    if check_composer; then
        echo 'Composer: Updating...'
        composer clearcache
        composer self-update
        echo 'Composer: Updating Global Packages'
        composer global update
    fi
}
