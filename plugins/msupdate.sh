#!/bin/bash

PLUGIN_NAME="Microsoft Update Inventory"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=60
PLUGIN_TIMEOUT_SECONDS=600
PLUGIN_SCHEDULE_ACTION=run

update_msupdate() {
    local msupdate_path
    msupdate_path="/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"

    if [ ! -x "$msupdate_path" ]; then
        echo_skip "Microsoft AutoUpdate CLI is not installed"
        return 20
    fi

    local output
    if ! output=$("$msupdate_path" --list --format plist </dev/null 2>&1); then
        printf '%s\n' "$output"
        echo_error "Microsoft update inventory failed"
        return 1
    fi

    printf '%s\n' "$output"
    echo_warning "Microsoft installs remain manual while Microsoft applications are closed"
    return 0
}
