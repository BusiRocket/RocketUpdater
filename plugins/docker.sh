#!/bin/bash

PLUGIN_NAME="Docker"
PLUGIN_VERSION="1.1.0"
DISABLE=${DISABLE:-false}

check_docker() {
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

update_docker() {
    if ! check_docker; then
        echo_skip "Docker is not running or not installed. Skipping..."
        return 0
    fi

    # Remove exited containers
    echo_info "Docker: Removing exited containers..."
    local exited_containers
    exited_containers=$(docker ps -a -f status=exited -q 2>/dev/null)
    
    if [ -n "$exited_containers" ]; then
        echo "$exited_containers" | xargs docker rm 2>/dev/null || true
        echo_success "Removed exited containers"
    else
        echo_skip "No exited containers to remove"
    fi

    # Remove dead containers
    echo_info "Docker: Removing dead containers..."
    local dead_containers
    dead_containers=$(docker ps -a -f status=dead -q 2>/dev/null)
    
    if [ -n "$dead_containers" ]; then
        echo "$dead_containers" | xargs docker rm -f 2>/dev/null || true
        echo_success "Removed dead containers"
    else
        echo_skip "No dead containers to remove"
    fi

    # Prune dangling images
    echo_info "Docker: Pruning dangling images..."
    docker image prune -f 2>/dev/null || true

    # Prune unused images (with confirmation skipped)
    echo_info "Docker: Pruning unused images..."
    docker image prune -a -f 2>/dev/null || true

    # Prune unused volumes
    echo_info "Docker: Pruning unused volumes..."
    docker volume prune -f 2>/dev/null || true

    # Prune unused networks
    echo_info "Docker: Pruning unused networks..."
    docker network prune -f 2>/dev/null || true

    # Prune build cache
    echo_info "Docker: Pruning build cache..."
    docker builder prune -f 2>/dev/null || true

    echo_success "Docker cleanup completed"
    return 0
}
