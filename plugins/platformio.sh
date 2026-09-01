#!/bin/bash

PLUGIN_NAME="PlatformIO Cache Report"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=300
PLUGIN_SCHEDULE_ACTION=run

update_platformio() {
    local pio_path
    pio_path="$HOME/.platformio/penv/bin/pio"

    if [ ! -x "$pio_path" ]; then
        echo_skip "PlatformIO is not installed"
        return 20
    fi

    echo_info "PlatformIO: Previewing cache-only prune..."
    if ! "$pio_path" system prune --dry-run --cache 2>&1; then
        echo_error "PlatformIO cache preview failed"
        return 1
    fi

    return 0
}
