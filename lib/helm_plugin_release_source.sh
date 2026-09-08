#!/bin/bash

# helm_plugin_release_source PLUGIN VERSION prints one
# "<repository>\t<archive_asset>\t<checksums_asset>\t<archive_member>" record
# describing where the published release for an installed helm plugin lives and
# which file inside its archive is the binary that gets installed. It returns 1
# when the plugin or the running platform is not one this project knows how to
# verify, because guessing an asset name would turn a missing download into a
# fabricated verdict. This function only names files; it downloads nothing.
helm_plugin_release_source() {
    local plugin=$1
    local version=$2
    local operating_system
    local machine
    local platform

    operating_system=$(uname -s)
    machine=$(uname -m)

    case $plugin in
    diff)
        case "$operating_system/$machine" in
        Darwin/arm64) platform=macos-arm64 ;;
        Darwin/x86_64) platform=macos-amd64 ;;
        Linux/aarch64 | Linux/arm64) platform=linux-arm64 ;;
        Linux/x86_64) platform=linux-amd64 ;;
        *) return 1 ;;
        esac
        printf 'databus23/helm-diff\thelm-diff-%s.tgz\thelm-diff_%s_checksums.txt\tdiff/bin/diff\n' \
            "$platform" "$version"
        ;;
    dashboard)
        case "$operating_system/$machine" in
        Darwin/arm64) platform=Darwin_arm64 ;;
        Darwin/x86_64) platform=Darwin_x86_64 ;;
        Linux/aarch64 | Linux/arm64) platform=Linux_arm64 ;;
        Linux/x86_64) platform=Linux_x86_64 ;;
        *) return 1 ;;
        esac
        printf 'komodorio/helm-dashboard\thelm-dashboard_%s_%s.tar.gz\thelm-dashboard_%s_checksums.txt\thelm-dashboard\n' \
            "$version" "$platform" "$version"
        ;;
    *)
        return 1
        ;;
    esac
}
