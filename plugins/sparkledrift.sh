#!/bin/bash

PLUGIN_NAME="Sparkle Feed Inventory"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=60
PLUGIN_TIMEOUT_SECONDS=900
PLUGIN_SCHEDULE_ACTION=run

update_sparkledrift() {
    if ! command_exists curl || [ ! -x /usr/libexec/PlistBuddy ]; then
        echo_skip "curl or PlistBuddy is unavailable"
        return 20
    fi

    local app_path
    for app_path in /Applications/*.app /Applications/*/*.app "$HOME"/Applications/*.app; do
        [ -d "$app_path" ] || continue

        local feed_url
        feed_url=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" \
            "$app_path/Contents/Info.plist" 2>/dev/null) || continue

        local app_name
        app_name=$(basename "$app_path")

        case "$feed_url" in
        https://*) ;;
        *)
            printf 'sparkle app=%s status=unsupported-feed\n' "$app_name"
            continue
            ;;
        esac

        local local_version
        local_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$app_path/Contents/Info.plist" 2>/dev/null) || local_version="unknown"

        local appcast
        if ! appcast=$(curl -fsL --connect-timeout 5 --max-time 20 \
            --proto '=https' "$feed_url" 2>/dev/null); then
            printf 'sparkle app=%s local=%s status=unreachable\n' \
                "$app_name" "$local_version"
            continue
        fi

        local feed_version
        feed_version=$(printf '%s' "$appcast" |
            sed -n 's/.*sparkle:shortVersionString="\([^"]*\)".*/\1/p; s/.*<sparkle:shortVersionString>\([^<]*\)<.*/\1/p' |
            head -1)
        if [ -z "$feed_version" ]; then
            feed_version=$(printf '%s' "$appcast" |
                sed -n 's/.*sparkle:version="\([^"]*\)".*/\1/p' |
                head -1)
        fi
        if [ -z "$feed_version" ]; then
            feed_version="unparsed"
        fi

        printf 'sparkle app=%s local=%s feed_first=%s status=observed\n' \
            "$app_name" "$local_version" "$feed_version"
    done

    echo_warning "Feed versions are evidence only; channel and ordering are not authoritative"
    return 0
}
