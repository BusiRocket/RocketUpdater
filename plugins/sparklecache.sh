#!/bin/bash

PLUGIN_NAME="Sparkle Cache Report"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=120
PLUGIN_SCHEDULE_ACTION=report

report_sparklecache() {
    local sparkle_base="$HOME/Library/Caches/com.openai.codex/org.sparkle-project.Sparkle"
    local installation_root="$sparkle_base/Installation"

    if [ -L "$installation_root" ] || [ ! -d "$installation_root" ]; then
        echo_skip "No Sparkle installation cache to report"
        return 20
    fi

    local installed_plist=${ROCKETUPDATER_SPARKLE_INSTALLED_PLIST:-/Applications/ChatGPT.app/Contents/Info.plist}
    local installed_build
    installed_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
        "$installed_plist" 2>/dev/null)
    case $installed_build in
    '' | *[!0-9]*)
        echo_warning "Installed ChatGPT build is absent or nonnumeric; candidates stay unverifiable"
        installed_build=""
        ;;
    esac

    local candidate
    if [ -z "$installed_build" ] ||
        pgrep -x ChatGPT >/dev/null 2>&1 ||
        pgrep -f Autoupdate >/dev/null 2>&1 ||
        pgrep -f Updater.app >/dev/null 2>&1; then
        local blocked_reason=blocked-running
        if [ -z "$installed_build" ]; then
            blocked_reason=retained-unverifiable
        fi
        for candidate in "$installation_root"/*; do
            [ -e "$candidate" ] || continue
            printf '%s\t%s\t-\n' "$blocked_reason" "$candidate"
        done
    else
        list_sparkle_obsolete_candidates "$installation_root" "$installed_build"
    fi

    if [ -d "$sparkle_base/PersistentDownloads" ]; then
        echo_info "PersistentDownloads (report only):"
        du -sk "$sparkle_base/PersistentDownloads" 2>&1
    fi

    echo_warning "Removal happens only through the supervised --clean sparkle command"
    return 0
}

update_sparklecache() {
    report_sparklecache
}
