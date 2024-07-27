#!/bin/bash

PLUGIN_NAME="OMZSH"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_omzsh() {
    [ -d "$ZSH" ]
}

update_omzsh() {
    if check_omzsh; then
        echo 'OMZSH Updating...'
        $ZSH/tools/upgrade.sh
    fi
}
