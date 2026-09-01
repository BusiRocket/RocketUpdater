#!/bin/bash

# guard_sparkle_obsolete_installations removes only staged ChatGPT Sparkle
# installations that are provably obsolete: verified stopped-app state, a
# numeric staged build lower than the installed build, and a byte-identical
# re-enumeration after the typed confirmation. PersistentDownloads is
# report-only.

sparkle_target_process_running() {
    pgrep -x ChatGPT >/dev/null 2>&1 ||
        pgrep -f Autoupdate >/dev/null 2>&1 ||
        pgrep -f Updater.app >/dev/null 2>&1
}

guard_sparkle_obsolete_installations() {
    if [ "${NONINTERACTIVE:-0}" = 1 ] || [ "${ROCKETUPDATER_LAUNCHD:-0}" = 1 ] ||
        [ ! -t 0 ] || [ ! -t 1 ]; then
        echo_error "Sparkle cleanup requires an interactive terminal"
        return 78
    fi

    local sparkle_base="$HOME/Library/Caches/com.openai.codex/org.sparkle-project.Sparkle"
    local installation_root="$sparkle_base/Installation"

    if [ -L "$installation_root" ] || [ ! -d "$installation_root" ]; then
        echo_skip "No Sparkle installation cache to clean"
        return 20
    fi

    local installed_plist=${ROCKETUPDATER_SPARKLE_INSTALLED_PLIST:-/Applications/ChatGPT.app/Contents/Info.plist}
    local installed_build
    installed_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
        "$installed_plist" 2>/dev/null)
    case $installed_build in
    '' | *[!0-9]*)
        echo_skip "Installed ChatGPT build is absent or nonnumeric; nothing was removed"
        return 20
        ;;
    esac

    if sparkle_target_process_running; then
        echo_skip "ChatGPT or its updater is running; nothing was removed"
        return 20
    fi

    local classification
    classification=$(list_sparkle_obsolete_candidates "$installation_root" "$installed_build")
    printf '%s\n' "$classification"

    if [ -d "$sparkle_base/PersistentDownloads" ]; then
        echo_info "PersistentDownloads (report only; never removed):"
        du -sk "$sparkle_base/PersistentDownloads" 2>&1
    fi

    local obsolete_candidates
    obsolete_candidates=$(printf '%s\n' "$classification" |
        awk -F '\t' '$1 == "obsolete" { print $2 }')

    if [ -z "$obsolete_candidates" ]; then
        echo_skip "No verified obsolete Sparkle installation to remove"
        return 20
    fi

    local candidate
    local candidate_kib
    local total_kib=0
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        candidate_kib=$(du -sk "$candidate" 2>/dev/null | awk '{ print $1 }')
        case $candidate_kib in
        '' | *[!0-9]*) candidate_kib=0 ;;
        esac
        total_kib=$((total_kib + candidate_kib))
        printf 'sparkle_obsolete candidate=%s installed_build=%s allocated_kib=%s\n' \
            "$candidate" "$installed_build" "$candidate_kib"
    done <<<"$obsolete_candidates"

    printf 'sparkle_obsolete total_allocated_kib=%s\n' "$total_kib"
    printf 'Type "sparkle" to remove these obsolete staged installations: '

    local answer
    IFS= read -r answer
    if [ "$answer" != sparkle ]; then
        echo_skip "Confirmation did not match; nothing was removed"
        return 20
    fi

    # The candidate set must be byte-identical after the confirmation pause;
    # anything moved in the meantime aborts before removal.
    local reenumeration
    reenumeration=$(list_sparkle_obsolete_candidates "$installation_root" "$installed_build")
    if [ "$reenumeration" != "$classification" ]; then
        echo_error "Sparkle candidates changed during confirmation; nothing was removed"
        return 1
    fi

    local has_failures=0
    local removed_any=0
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue

        if sparkle_target_process_running; then
            echo_skip "ChatGPT or its updater appeared; stopping before further removal"
            if [ "$removed_any" -ne 0 ]; then
                return 1
            fi
            return 20
        fi

        case $candidate in
        "$installation_root"/*) ;;
        *)
            echo_error "Refusing candidate outside the installation root: $candidate"
            has_failures=1
            continue
            ;;
        esac

        if rm -rf -- "$candidate"; then
            removed_any=1
            echo_success "Removed obsolete staged installation: $candidate"
        else
            has_failures=1
            echo_error "Removal failed: $candidate"
        fi
    done <<<"$obsolete_candidates"

    if [ "$has_failures" -ne 0 ]; then
        return 1
    fi

    return 0
}
