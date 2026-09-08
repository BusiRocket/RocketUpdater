#!/bin/bash

PLUGIN_NAME="Docker"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=70
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=report
# Report-only: container, image, volume, network, and build-cache removal is a
# separate human decision recorded in TODO.md, never a scheduled operation.

# `docker info` has no connect timeout on this path: against a dead daemon it
# took 86 seconds in the 2026-09-01 canary before the plugin could skip, and a
# scheduled run pays that every night for nothing. Bound it with the coreutils
# timeout that preflight already requires.
check_docker() {
    command -v docker >/dev/null 2>&1 || return 1
    /opt/homebrew/bin/timeout --kill-after=5s 10s docker info >/dev/null 2>&1
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

    # `du` walks live container overlays, where paths vanish between readdir and
    # stat ("No such file or directory", "Stale NFS file handle"). Those lines
    # are not findings and drowned the whole run, so they are counted instead:
    # they mean the reported size is a lower bound. Anything else `du` says —
    # a permission failure, an I/O error — is a real problem with the
    # measurement and is printed, not folded into that count.
    local orbstack_root
    local du_errors
    local vanished
    local other_errors
    for orbstack_root in "$HOME/.orbstack" "$HOME/OrbStack"; do
        [ -d "$orbstack_root" ] || continue

        du_errors=$(mktemp -t rocketupdater-docker-du) || return 1
        du -sh "$orbstack_root" 2>"$du_errors"

        vanished=$(grep -cE 'No such file or directory|Stale NFS file handle' "$du_errors" | tr -d ' ')
        other_errors=$(grep -vE 'No such file or directory|Stale NFS file handle' "$du_errors" | grep -c . | tr -d ' ')

        if [ "$vanished" -gt 0 ]; then
            echo_info "Docker: $vanished paths under $orbstack_root vanished while measuring; the size above is a lower bound"
        fi

        if [ "$other_errors" -gt 0 ]; then
            echo_warning "Docker: $orbstack_root could not be measured completely:"
            grep -vE 'No such file or directory|Stale NFS file handle' "$du_errors" | head -5
        fi

        /bin/rm -f -- "$du_errors"
    done

    return 0
}

update_docker() {
    report_docker
}
