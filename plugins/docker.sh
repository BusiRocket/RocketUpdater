#!/bin/bash

PLUGIN_NAME="Docker"
PLUGIN_VERSION="1.0.0"
DISABLE=${DISABLE:-false} # To disable, set DISABLE=true

check_docker() {
    docker info > /dev/null 2>&1
}

update_docker() {
    if check_docker; then
        echo 'Docker: Removing exited containers...'
        exited_containers=$(docker ps -a -f status=exited -q)
        if [ -n "$exited_containers" ]; then
            docker rm "$exited_containers"
        else
            echo 'No exited containers.'
        fi
        echo 'Docker: Pruning dangling images...'
        docker image prune -f
        echo 'Docker: Pruning unused images...'
        docker image prune -a -f
    else
        echo 'Docker is not running. Skipping cleanup.'
    fi
}
