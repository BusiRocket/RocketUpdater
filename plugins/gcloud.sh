#!/bin/bash

PLUGIN_NAME="Google Cloud SDK"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_gcloud() {
    command_exists gcloud
}

update_gcloud() {
    if check_gcloud; then
        echo_yellow 'Google Cloud SDK: Updating components...'
        gcloud components update --quiet
    fi
}

