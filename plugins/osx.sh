#!/bin/bash

PLUGIN_NAME="OSX"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_osx() {
    [[ "$OSTYPE" == "darwin"* ]]
}

update_osx() {
    if check_osx; then
        echo 'Updating OS X...'
        softwareupdate -i -
    fi
}
