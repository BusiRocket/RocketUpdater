#!/bin/bash

# classify_helm_plugin_binary PLUGIN VERSION PLUGINS_ROOT CACHE_DIR prints one
# "<classification>\t<plugin>\t<detail>" line and always returns 0. The caller
# decides what a classification is worth; this function only compares.
#
# verified      the installed binary is byte-identical to the one in the
#               release archive whose published checksum was confirmed
# mismatch      it is not, which means the installed file is not the release it
#               claims to be
# unverifiable  no reference could be established at all — an unknown plugin, a
#               missing binary, or a download that failed
#
# "unverifiable" is deliberately distinct from "mismatch": a network failure
# says nothing about the installed file, and reporting the two the same way is
# how a verification step quietly becomes decorative.
classify_helm_plugin_binary() {
    local plugin=$1
    local version=$2
    local plugins_root=$3
    local cache_dir=$4
    local record
    local archive_member
    local plugin_dir
    local installed_binary
    local reference_digest
    local installed_digest
    local reason
    local diagnostics

    if ! record=$(helm_plugin_release_source "$plugin" "$version"); then
        printf 'unverifiable\t%s\tno published checksums are known for this plugin\n' \
            "$plugin"
        return 0
    fi
    archive_member=$(printf '%s' "$record" | cut -f4)

    if ! plugin_dir=$(find_helm_plugin_directory "$plugin" "$plugins_root"); then
        printf 'unverifiable\t%s\tits installation directory could not be identified\n' \
            "$plugin"
        return 0
    fi

    installed_binary="$plugin_dir/bin/$(basename "$archive_member")"
    if [ ! -f "$installed_binary" ]; then
        printf 'unverifiable\t%s\t%s is missing\n' "$plugin" "$installed_binary"
        return 0
    fi

    # Stderr is kept out of the digest capture on purpose: a stray diagnostic
    # merged into stdout would read as a changed hash and report a mismatch.
    diagnostics=$(mktemp)
    if ! reference_digest=$(helm_reference_digest "$plugin" "$version" "$cache_dir" \
        2>"$diagnostics"); then
        reason=$(tail -1 "$diagnostics")
        /bin/rm -f -- "$diagnostics"
        printf 'unverifiable\t%s\t%s\n' "$plugin" "$reason"
        return 0
    fi
    /bin/rm -f -- "$diagnostics"

    installed_digest=$(shasum -a 256 "$installed_binary" | awk '{ print $1 }')
    if [ "$installed_digest" = "$reference_digest" ]; then
        printf 'verified\t%s\t%s matches the published release %s\n' \
            "$plugin" "$installed_binary" "$version"
    else
        printf 'mismatch\t%s\t%s hashes %s, the published %s release hashes %s\n' \
            "$plugin" "$installed_binary" "$installed_digest" "$version" \
            "$reference_digest"
    fi
}
