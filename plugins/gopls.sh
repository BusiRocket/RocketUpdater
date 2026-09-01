#!/bin/bash

PLUGIN_NAME="gopls"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=50
PLUGIN_TIMEOUT_SECONDS=900
PLUGIN_SCHEDULE_ACTION=run

update_gopls() {
    if ! command_exists go; then
        echo_skip "Go is not installed"
        return 20
    fi

    echo_info "gopls: Updating with the installed Go toolchain..."
    if ! GOBIN="$HOME/go/bin" GOTOOLCHAIN=local \
        go install golang.org/x/tools/gopls@latest 2>&1; then
        echo_error "gopls update failed"
        return 1
    fi

    if [ ! -x "$HOME/go/bin/gopls" ]; then
        echo_error "gopls install returned success but no binary exists"
        return 1
    fi

    "$HOME/go/bin/gopls" version 2>&1
    return 0
}
