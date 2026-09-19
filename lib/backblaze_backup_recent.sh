#!/bin/bash

# Succeeds when Backblaze transmitted within the last 7 days. bzserv writes a
# bz_done_<date>_<n>.dat transmit log in the datacenter directory while it
# uploads, so the newest one's mtime is the last time a backup made progress.
backblaze_backup_recent() {
    local datacenter=${ROCKETUPDATER_BACKBLAZE_DATACENTER:-/Library/Backblaze.bzpkg/bzdata/bzbackup/bzdatacenter}
    local newest

    [ -d "$datacenter" ] || return 1
    newest=$(/usr/bin/find "$datacenter" -maxdepth 1 -name 'bz_done_*.dat' -mtime -7 2>/dev/null | /usr/bin/head -1)
    [ -n "$newest" ]
}
