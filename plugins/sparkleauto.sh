#!/bin/bash

PLUGIN_NAME="Sparkle Automatic Updates"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=55
PLUGIN_TIMEOUT_SECONDS=300
PLUGIN_SCHEDULE_ACTION=run

# Sparkle apps have no shell updater, but every one of them obeys two user
# defaults: check on its own and install what it finds. Turning both on lets
# each app update itself through its signed feed, which is safer than any
# bundle swap done from here. An app whose Info.plist forbids automatic
# installs (SUAllowsAutomaticUpdates false) is left as it is. A sandboxed app
# reads its defaults from its container, so that is where they are written.
update_sparkleauto() {
    if [ ! -x /usr/libexec/PlistBuddy ]; then
        echo_skip "PlistBuddy is unavailable"
        return 20
    fi

    local app_root=${ROCKETUPDATER_SPARKLE_APP_ROOT:-/Applications}
    local enabled_count=0
    local app_path
    for app_path in "$app_root"/*.app "$app_root"/*/*.app "$HOME"/Applications/*.app; do
        [ -d "$app_path" ] || continue
        local info_plist="$app_path/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$info_plist" >/dev/null 2>&1 || continue

        local allows_automatic
        allows_automatic=$(/usr/libexec/PlistBuddy -c "Print :SUAllowsAutomaticUpdates" "$info_plist" 2>/dev/null)
        [ "$allows_automatic" = false ] && continue

        local bundle_id
        bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$info_plist" 2>/dev/null) || continue
        [ -n "$bundle_id" ] || continue

        local defaults_domain="$bundle_id"
        local container_preferences="$HOME/Library/Containers/$bundle_id/Data/Library/Preferences"
        if [ -d "$container_preferences" ]; then
            defaults_domain="$container_preferences/$bundle_id"
        fi

        if [ "$(defaults read "$defaults_domain" SUAutomaticallyUpdate 2>/dev/null)" = 1 ] &&
            [ "$(defaults read "$defaults_domain" SUEnableAutomaticChecks 2>/dev/null)" = 1 ]; then
            continue
        fi

        if defaults write "$defaults_domain" SUEnableAutomaticChecks -bool true &&
            defaults write "$defaults_domain" SUAutomaticallyUpdate -bool true; then
            echo_change "automatic updates on for $(basename "$app_path")"
            enabled_count=$((enabled_count + 1))
        else
            echo_warning "Could not enable automatic updates for $(basename "$app_path")"
        fi
    done

    echo_success "Sparkle apps update themselves ($enabled_count newly enabled)"
    return 0
}
