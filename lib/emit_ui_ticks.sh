#!/bin/bash

# emit_ui_ticks STATUS_FILE writes a tick record a few times a second until
# STATUS_FILE holds the plugin's exit status. The renderer blocks on read, and
# /bin/bash 3.2 has no fractional read timeout, so the ticks are what keep the
# spinner and the clock moving while a step prints nothing.
emit_ui_ticks() {
    local status_file=$1

    while [ ! -s "$status_file" ]; do
        printf '\036TICK\n' || return 0
        /bin/sleep 0.15
    done
}
