#!/bin/bash

PLUGIN_NAME="Helm Plugin Inventory"
PLUGIN_VERSION="1.1.0"
DISABLE=false
PLUGIN_PRIORITY=50
PLUGIN_TIMEOUT_SECONDS=900
PLUGIN_SCHEDULE_ACTION=run

# Helm plugin updates stay manual because an update hook executes a script the
# plugin ships, which is a decision about trusting a download rather than a
# maintenance step. What this plugin does instead is the check those installers
# skip — helm-diff's install-binary.sh has a comment claiming it verifies a
# SHA256 and a function that does not — by proving that what is installed today
# is byte-identical to the release the project published and signed off with a
# checksums file.
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

    plugins_root=${HELM_PLUGINS:-$(helm env HELM_PLUGINS 2>/dev/null | tr -d '"')}
    if [ -z "$plugins_root" ] || [ ! -d "$plugins_root" ]; then
        echo_warning "Helm plugin directory could not be located; checksums not verified"
        return 0
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
        return 0
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

    echo_warning "Helm plugin updates remain manual because update hooks execute plugin scripts"
    return "$plugin_status"
}
