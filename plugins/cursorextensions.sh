#!/bin/bash

PLUGIN_NAME="Cursor Extensions"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=60
PLUGIN_TIMEOUT_SECONDS=900
PLUGIN_SCHEDULE_ACTION=run

# Cursor ships the VS Code CLI under its own name, so --update-extensions
# behaves the same: headless, no window. ROCKETUPDATER_CURSOR_CLI overrides the
# path for the tests.
update_cursorextensions() {
    local cursor_cli=${ROCKETUPDATER_CURSOR_CLI:-"/Applications/Cursor.app/Contents/Resources/app/bin/cursor"}
    if [ ! -x "$cursor_cli" ]; then
        echo_skip "Cursor is not installed"
        return 20
    fi

    local extensions_before
    if ! extensions_before=$("$cursor_cli" --list-extensions --show-versions 2>&1); then
        printf '%s\n' "$extensions_before"
        echo_error "Cursor extension inventory failed"
        return 1
    fi
    if [ -z "$extensions_before" ]; then
        echo_skip "Cursor has no extensions installed"
        return 20
    fi

    echo_info "Cursor: Updating extensions..."
    if ! "$cursor_cli" --update-extensions 2>&1; then
        echo_error "Cursor extension update failed"
        return 1
    fi

    local extensions_after
    extensions_after=$("$cursor_cli" --list-extensions --show-versions 2>&1)
    if [ "$extensions_after" != "$extensions_before" ]; then
        echo_change "Cursor extensions"
    fi
    echo_success "Cursor extensions are current"
    return 0
}
