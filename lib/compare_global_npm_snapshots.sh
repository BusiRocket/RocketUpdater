#!/bin/bash

# compare_global_npm_snapshots BEFORE_SNAPSHOT AFTER_SNAPSHOT [SELECTED_PACKAGE]
# takes two snapshot texts, prints one integrity_violation line per package
# that disappeared, appeared, or changed without being the selected update
# target, and per selected target whose post-install state is broken. Returns
# 1 when any violation exists. It never repairs, reinstalls, or deletes
# anything.
compare_global_npm_snapshots() {
    local before_snapshot=$1
    local after_snapshot=$2
    local selected_package=${3:-}
    local has_violations=0

    local record
    local package_name
    local matched_record

    while IFS= read -r record; do
        [ -n "$record" ] || continue
        package_name=${record%%$'\t'*}
        [ "$package_name" != "$selected_package" ] || continue
        matched_record=$(printf '%s\n' "$after_snapshot" |
            awk -F '\t' -v name="$package_name" '$1 == name')
        if [ -z "$matched_record" ]; then
            printf 'integrity_violation package=%s kind=disappeared\n' "$package_name"
            has_violations=1
        fi
    done <<<"$before_snapshot"

    while IFS= read -r record; do
        [ -n "$record" ] || continue
        package_name=${record%%$'\t'*}

        if [ "$package_name" = "$selected_package" ]; then
            # An unchanged pre-existing record means the install never touched
            # the target; only a new or rewritten broken state is damage.
            matched_record=$(printf '%s\n' "$before_snapshot" |
                awk -F '\t' -v name="$package_name" '$1 == name')
            if [ "$matched_record" = "$record" ]; then
                continue
            fi
            local manifest_sha declared_version bins_status
            IFS=$'\t' read -r _ _ manifest_sha _ declared_version bins_status <<<"$record"
            if [ "$manifest_sha" = missing ] || [ "$manifest_sha" = unreadable ] ||
                [ "$declared_version" = unparsed ] || [ "$bins_status" = missing ]; then
                printf 'integrity_violation package=%s kind=broken-target\n' "$package_name"
                has_violations=1
            fi
            continue
        fi

        matched_record=$(printf '%s\n' "$before_snapshot" |
            awk -F '\t' -v name="$package_name" '$1 == name')
        if [ -z "$matched_record" ]; then
            printf 'integrity_violation package=%s kind=appeared\n' "$package_name"
            has_violations=1
        elif [ "$matched_record" != "$record" ]; then
            printf 'integrity_violation package=%s kind=changed\n' "$package_name"
            has_violations=1
        fi
    done <<<"$after_snapshot"

    # A selected target that existed before and is gone after is damage; one
    # that never existed simply failed to install and is judged by the
    # install's own exit status.
    if [ -n "$selected_package" ]; then
        matched_record=$(printf '%s\n' "$after_snapshot" |
            awk -F '\t' -v name="$selected_package" '$1 == name')
        if [ -z "$matched_record" ]; then
            matched_record=$(printf '%s\n' "$before_snapshot" |
                awk -F '\t' -v name="$selected_package" '$1 == name')
            if [ -n "$matched_record" ]; then
                printf 'integrity_violation package=%s kind=broken-target\n' "$selected_package"
                has_violations=1
            fi
        fi
    fi

    return "$has_violations"
}
