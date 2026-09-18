#!/bin/bash

# list_major_macos_upgrades LISTING CURRENT_MAJOR prints the labels in a
# `softwareupdate -l` listing that name a macOS release whose major number is
# above the running one: the upgrades to a new macOS. Other products carry
# their own version numbers (Safari 27 ships for macOS 26), so only labels
# starting with "macOS" count. The word is followed by a non-breaking space
# (U+00A0) in the real output, so nothing after it is matched. Downloading
# such an upgrade asks for a volume owner's password even as root, so an
# unattended run can never get past it.
list_major_macos_upgrades() {
    local listing=$1
    local current_major=$2

    printf '%s\n' "$listing" | awk -v current="$current_major" '
        /^\* Label: macOS/ {
            label = $0
            sub(/^\* Label: /, "", label)
            next
        }
        /^\* Label: / { label = ""; next }
        /Version: / && label != "" {
            version = $0
            sub(/.*Version: */, "", version)
            sub(/[, ].*/, "", version)
            split(version, parts, ".")
            if (parts[1] + 0 > current + 0) print label
            label = ""
        }
    '
}
