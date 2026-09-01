#!/bin/bash

PLUGIN_NAME="Docker"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=70
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=report
# Report-only: container, image, volume, network, and build-cache removal is a
# separate human decision recorded in TODO.md, never a scheduled operation.

check_docker() {
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

report_docker() {
    if ! check_docker; then
        echo_skip "Docker is not running or not installed"
        return 20
    fi

    echo_info "Docker: Reporting disk usage..."
    if ! docker system df 2>&1; then
        echo_error "Docker disk usage report failed"
        return 1
    fi

    if command_exists orbctl; then
        echo_info "OrbStack: Reporting status..."
        orbctl status 2>&1 || echo_warning "OrbStack status was unavailable"
    fi

    local orbstack_root
    for orbstack_root in "$HOME/.orbstack" "$HOME/OrbStack"; do
        if [ -d "$orbstack_root" ]; then
            du -sh "$orbstack_root" 2>&1
        fi
    done

    return 0
}

update_docker() {
    report_docker
}
