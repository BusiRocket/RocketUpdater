#!/bin/bash

# helm_reference_digest PLUGIN VERSION CACHE_DIR prints the SHA256 of the
# binary that the published release for PLUGIN VERSION actually contains, and
# returns 1 with a reason on stderr when it cannot establish one.
#
# The chain is the one helm-diff's own install-binary.sh claims to run and does
# not: fetch the checksums file the project publishes, download the release
# archive, hash the archive and compare it against that file, and only then
# extract the archive and hash the binary inside it. An archive that fails the
# comparison is discarded, never extracted.
#
# The result is cached per plugin and version because the archive is tens of
# megabytes and the answer cannot change for a released version: after the
# first run, verification costs one local hash of the installed binary.
#
# Nothing is ever extracted onto disk. The member is streamed straight into
# shasum, so an archive that turned out to be hostile never becomes a file, and
# this function needs no recursive delete to clean up after itself.
helm_reference_digest() {
    local plugin=$1
    local version=$2
    local cache_dir=$3
    local base_url=${ROCKETUPDATER_HELM_RELEASE_BASE_URL:-https://github.com}
    local record
    local repository
    local archive_asset
    local checksums_asset
    local archive_member
    local cache_file
    local cached_digest
    local work_dir
    local expected_digest
    local actual_digest
    local member_digest

    if ! record=$(helm_plugin_release_source "$plugin" "$version"); then
        printf 'no published release is known for %s %s on this platform\n' \
            "$plugin" "$version" >&2
        return 1
    fi
    IFS=$'\t' read -r repository archive_asset checksums_asset archive_member <<<"$record"

    cache_file="$cache_dir/$plugin-$version.sha256"
    if [ -f "$cache_file" ]; then
        cached_digest=$(cat "$cache_file" 2>/dev/null)
        case $cached_digest in
        [0-9a-f]*)
            if [ ${#cached_digest} -eq 64 ]; then
                printf '%s\n' "$cached_digest"
                return 0
            fi
            ;;
        esac
    fi

    if ! mkdir -p "$cache_dir"; then
        printf 'the reference digest cache directory could not be created\n' >&2
        return 1
    fi

    if ! work_dir=$(mktemp -d "$cache_dir/download.XXXXXX"); then
        printf 'a download directory for %s could not be created\n' "$plugin" >&2
        return 1
    fi

    if ! _helm_reference_digest_fetch \
        "$base_url/$repository/releases/download/v$version/$checksums_asset" \
        "$work_dir/checksums.txt"; then
        printf 'the checksums file for %s %s could not be downloaded\n' \
            "$plugin" "$version" >&2
        _helm_reference_digest_discard "$work_dir"
        return 1
    fi

    expected_digest=$(awk -v asset="$archive_asset" \
        '$2 == asset || $2 == "*" asset { print $1; exit }' \
        "$work_dir/checksums.txt")
    if [ ${#expected_digest} -ne 64 ]; then
        printf '%s is not listed in the published checksums for %s %s\n' \
            "$archive_asset" "$plugin" "$version" >&2
        _helm_reference_digest_discard "$work_dir"
        return 1
    fi

    if ! _helm_reference_digest_fetch \
        "$base_url/$repository/releases/download/v$version/$archive_asset" \
        "$work_dir/$archive_asset"; then
        printf 'the release archive for %s %s could not be downloaded\n' \
            "$plugin" "$version" >&2
        _helm_reference_digest_discard "$work_dir"
        return 1
    fi

    actual_digest=$(shasum -a 256 "$work_dir/$archive_asset" | awk '{ print $1 }')
    if [ "$actual_digest" != "$expected_digest" ]; then
        printf 'the downloaded %s does not match its published checksum\n' \
            "$archive_asset" >&2
        _helm_reference_digest_discard "$work_dir"
        return 1
    fi

    member_digest=$(tar -xzOf "$work_dir/$archive_asset" "$archive_member" 2>/dev/null |
        shasum -a 256 | awk '{ print $1 }')
    if [ "${PIPESTATUS[0]}" -ne 0 ] || [ ${#member_digest} -ne 64 ]; then
        printf '%s could not be read from %s\n' "$archive_member" "$archive_asset" >&2
        _helm_reference_digest_discard "$work_dir"
        return 1
    fi

    # The cache entry is written whole and moved into place, so an interrupted
    # run cannot leave a truncated digest that later reads as a mismatch.
    printf '%s\n' "$member_digest" >"$work_dir/digest"
    mv -f "$work_dir/digest" "$cache_file"
    _helm_reference_digest_discard "$work_dir"

    printf '%s\n' "$member_digest"
}

# The download directory only ever holds flat files, which is what lets this
# clean up without a recursive delete.
_helm_reference_digest_discard() {
    local work_dir=$1
    local leftover

    for leftover in "$work_dir"/*; do
        [ -e "$leftover" ] || continue
        /bin/rm -f -- "$leftover"
    done
    rmdir "$work_dir" 2>/dev/null || true
}

# HTTPS is pinned for the default remote so a redirect cannot downgrade the
# transport; tests point the base URL at a local file:// tree instead.
_helm_reference_digest_fetch() {
    local url=$1
    local destination=$2

    case $url in
    file://*)
        curl -fsS --max-time 900 -o "$destination" "$url"
        ;;
    *)
        curl -fsSL --proto '=https' --tlsv1.2 --max-time 900 \
            -o "$destination" "$url"
        ;;
    esac
}
