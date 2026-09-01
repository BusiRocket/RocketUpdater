#!/bin/bash

# list_sparkle_obsolete_candidates ROOT INSTALLED_BUILD prints one
# "<classification>\t<path>\t<staged_build>" line per direct Installation/*
# directory. A candidate is obsolete only when it is a real directory whose
# physical path stays under ROOT, is older than one day, holds exactly one
# nested ChatGPT.app/Contents/Info.plist within depth four, and stages a
# numeric build lower than INSTALLED_BUILD. Everything else is retained. This
# function only classifies; it never removes anything.
list_sparkle_obsolete_candidates() {
    local root=$1
    local installed_build=$2
    local candidate
    local physical_path
    local staged_plists
    local staged_plist_count
    local staged_build

    for candidate in "$root"/*; do
        [ -e "$candidate" ] || continue

        if [ -L "$candidate" ] || [ ! -d "$candidate" ]; then
            printf 'retained-unverifiable\t%s\t-\n' "$candidate"
            continue
        fi

        physical_path=$(cd "$candidate" 2>/dev/null && pwd -P)
        case $physical_path in
        "$root"/*) ;;
        *)
            printf 'retained-unverifiable\t%s\t-\n' "$candidate"
            continue
            ;;
        esac

        if [ -z "$(find "$candidate" -maxdepth 0 -mtime +0 2>/dev/null)" ]; then
            printf 'retained-young\t%s\t-\n' "$candidate"
            continue
        fi

        staged_plists=$(find "$candidate" -maxdepth 4 \
            -path '*/ChatGPT.app/Contents/Info.plist' -type f -print 2>/dev/null)
        staged_plist_count=$(printf '%s\n' "$staged_plists" |
            grep -c . || true)
        if [ "$staged_plist_count" -ne 1 ]; then
            printf 'retained-unverifiable\t%s\t-\n' "$candidate"
            continue
        fi

        staged_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
            "$staged_plists" 2>/dev/null)
        case $staged_build in
        '' | *[!0-9]*)
            printf 'retained-unverifiable\t%s\t-\n' "$candidate"
            continue
            ;;
        esac

        if [ "$staged_build" -lt "$installed_build" ]; then
            printf 'obsolete\t%s\t%s\n' "$candidate" "$staged_build"
        else
            printf 'retained-current-or-newer\t%s\t%s\n' "$candidate" "$staged_build"
        fi
    done
}
