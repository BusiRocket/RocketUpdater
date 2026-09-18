#!/bin/bash

# list_macos_os_updates LISTING prints the labels in a `softwareupdate -l`
# listing that are macOS releases themselves — minor updates and major
# upgrades alike — as opposed to Safari, Xcode command line tools and the
# rest. Apple writes a non-breaking space (U+00A0) after "macOS" in the real
# output, so only the word is matched. Preparing such a download asks for a
# volume owner's password even as root (macOS 26.7 on the Mac mini, macOS 27
# on the MacBook, 2026-09-19), so an unattended run can never get past it.
list_macos_os_updates() {
    local listing=$1

    printf '%s\n' "$listing" | awk '
        /^\* Label: macOS/ {
            label = $0
            sub(/^\* Label: /, "", label)
            print label
        }
    '
}
