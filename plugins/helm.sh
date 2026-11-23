#!/bin/bash

PLUGIN_NAME="Helm Plugins"
PLUGIN_VERSION="2.0.0"
DISABLE=false
PLUGIN_PRIORITY=50
PLUGIN_TIMEOUT_SECONDS=900
PLUGIN_SCHEDULE_ACTION=run

# Helm plugins are updated in place (owner's decision, 2026-11-23) and then
# checked, because an update hook runs a script the plugin ships and
# helm-diff's install-binary.sh claims to verify a SHA256 it never checks. The
# check proves that what is installed is byte-identical to the release the
# project published and signed off with a checksums file, so a tampered or
# broken download is reported as a failure right after it lands.
update_helm() {
    local plugins_root
    local cache_dir
    local inventory
    local verdicts
    local classification
    local plugin
    local detail
    local mismatch_found=false
    local plugin_status=0

    if ! command_exists helm; then
        echo_skip "Helm is not installed"
        return 20
    fi

    echo_info "Helm: Reporting installed plugin versions..."
    if ! inventory=$(helm plugin list 2>&1); then
        echo_error "Helm plugin inventory failed"
        printf '%s\n' "$inventory"
        return 1
    fi
    printf '%s\n' "$inventory"

    # Helm creates its plugin directory on the first install, so with nothing
    # installed the directory check below would warn about nothing.
    if [ -z "$(printf '%s\n' "$inventory" | awk 'NR > 1 && NF >= 2')" ]; then
        echo_note "No Helm plugins installed; nothing to verify"
        return 0
    fi

    local plugin_name
    while IFS= read -r plugin_name <&3; do
        [ -n "$plugin_name" ] || continue
        echo_info "Helm: Updating plugin $plugin_name..."
        if helm plugin update "$plugin_name" </dev/null 2>&1; then
            echo_change "helm plugin $plugin_name"
        else
            echo_warning "Helm plugin $plugin_name could not be updated"
            plugin_status=1
        fi
    done 3< <(printf '%s\n' "$inventory" | awk 'NR > 1 && NF >= 2 { print $1 }')

    # The versions changed, so the checks below read a fresh inventory.
    if ! inventory=$(helm plugin list 2>&1); then
        echo_error "Helm plugin inventory failed after the update"
        printf '%s\n' "$inventory"
        return 1
    fi
    printf '%s\n' "$inventory"

    plugins_root=${HELM_PLUGINS:-$(helm env HELM_PLUGINS 2>/dev/null | tr -d '"')}
    if [ -z "$plugins_root" ] || [ ! -d "$plugins_root" ]; then
        echo_warning "Helm plugin directory could not be located; checksums not verified"
        return "$plugin_status"
    fi

    cache_dir=${ROCKETUPDATER_HELM_CACHE_DIR:-$HOME/Library/Caches/RocketUpdater/helm-references}

    echo_info "Helm: Verifying installed plugin binaries against published checksums..."
    verdicts=$(printf '%s\n' "$inventory" | awk 'NR > 1 && NF >= 2 { print $1"\t"$2 }' |
        while IFS=$'\t' read -r plugin version; do
            [ -n "$plugin" ] || continue
            classify_helm_plugin_binary "$plugin" "$version" "$plugins_root" "$cache_dir"
        done)

    if [ -z "$verdicts" ]; then
        echo_warning "Helm reported no plugins to verify"
        return "$plugin_status"
    fi

    while IFS=$'\t' read -r classification plugin detail; do
        [ -n "$classification" ] || continue
        case $classification in
        verified) echo_success "Helm plugin $plugin: $detail" ;;
        mismatch)
            echo_error "Helm plugin $plugin: $detail"
            mismatch_found=true
            ;;
        *) echo_warning "Helm plugin $plugin could not be verified: $detail" ;;
        esac
    done <<<"$verdicts"

    if [ "$mismatch_found" = true ]; then
        echo_error "A Helm plugin binary does not match its published release"
        plugin_status=1
    fi

    return "$plugin_status"
}
