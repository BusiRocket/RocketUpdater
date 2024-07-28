#!/bin/bash

PLUGIN_NAME="PEAR"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_pear() {
    command_exists pear
}

update_pear() {
    if check_pear; then
        echo 'PEAR & PECL Update'
        pear clear-cache
        pear upgrade PEAR
        pear upgrade
        pecl upgrade
    fi
}
