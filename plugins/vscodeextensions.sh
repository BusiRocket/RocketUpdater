#!/bin/bash

PLUGIN_NAME="VS Code Extensions"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=60
PLUGIN_TIMEOUT_SECONDS=900
PLUGIN_SCHEDULE_ACTION=run

# The editor's own CLI updates extensions headlessly and exits; it never opens
# a window. ROCKETUPDATER_VSCODE_CLI overrides the path for the tests.
update_vscodeextensions() {
    local code_cli=${ROCKETUPDATER_VSCODE_CLI:-"/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"}
    if [ ! -x "$code_cli" ]; then
        echo_skip "Visual Studio Code is not installed"
        return 20
    fi

    local extensions_before
    if ! extensions_before=$("$code_cli" --list-extensions --show-versions 2>&1); then
        printf '%s\n' "$extensions_before"
        echo_error "VS Code extension inventory failed"
        return 1
    fi
    if [ -z "$extensions_before" ]; then
        echo_skip "VS Code has no extensions installed"
        return 20
    fi

    echo_info "VS Code: Updating extensions..."
    if ! "$code_cli" --update-extensions 2>&1; then
        echo_error "VS Code extension update failed"
        return 1
    fi

    local extensions_after
    extensions_after=$("$code_cli" --list-extensions --show-versions 2>&1)
    if [ "$extensions_after" != "$extensions_before" ]; then
        echo_change "VS Code extensions"
    fi
    echo_success "VS Code extensions are current"
    return 0
}
