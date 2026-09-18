#!/bin/bash

# exclude_npm_snapshot_packages SNAPSHOT NAMES prints the snapshot records
# whose package name is not in NAMES (one name per line). It lets a caller
# drop the packages a formula legitimately rewrites before the two snapshots
# are compared, so the comparison only judges what nothing was allowed to touch.
exclude_npm_snapshot_packages() {
    local snapshot=$1
    local names=$2

    # BSD awk rejects a newline inside -v, so the names travel space-separated;
    # npm package names never contain spaces.
    printf '%s\n' "$snapshot" | awk -F '\t' -v list="$(printf '%s' "$names" | tr '\n' ' ')" '
        BEGIN {
            count = split(list, entries, " ")
            for (i = 1; i <= count; i++) {
                if (entries[i] != "") excluded[entries[i]] = 1
            }
        }
        $1 != "" && !($1 in excluded)
    '
}
