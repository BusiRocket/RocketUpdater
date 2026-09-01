#!/bin/bash

PLUGIN_NAME="Google Cloud SDK"
PLUGIN_VERSION="1.1.0"
DISABLE=false
PLUGIN_PRIORITY=50
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

check_gcloud() {
    command_exists gcloud
}

# Homebrew's gcloud-cli cask builds a Python virtualenv in its postflight by
# pip-installing wheels from github.com. Under the `brew` process that pip
# resolves DNS with EAI_NONAME and the cask upgrade reverts, leaving the SDK
# files at the new version but the bin/ wrappers unlinked (gcloud disappears
# from PATH). The same steps succeed outside brew, so this plugin runs after
# Homebrew and repairs the state: relink the wrappers and rebuild the optional
# virtualenv. Idempotent, so it is a no-op on a healthy install.
heal_gcloud_cli() {
    command_exists brew || return 0

    local brew_prefix
    brew_prefix=$(brew --prefix)
    [ -x "$brew_prefix/share/google-cloud-sdk/bin/gcloud" ] || return 0

    local name
    for name in bq docker-credential-gcloud gcloud gsutil; do
        if [ ! -e "$brew_prefix/bin/$name" ]; then
            ln -sf "../share/google-cloud-sdk/bin/$name" "$brew_prefix/bin/$name"
            echo_info "Relinked $name (Homebrew left it unlinked)."
        fi
    done
    if [ ! -e "$brew_prefix/bin/git-credential-gcloud" ]; then
        ln -sf "../share/google-cloud-sdk/bin/git-credential-gcloud.sh" \
            "$brew_prefix/bin/git-credential-gcloud"
        echo_info "Relinked git-credential-gcloud (Homebrew left it unlinked)."
    fi

    # The virtualenv is optional (extension binary modules); core gcloud works
    # without it. Rebuild only when it is absent or broken, and never fail the
    # plugin over it. `describe` exits non-zero when the virtualenv is missing.
    if gcloud config virtualenv describe >/dev/null 2>&1; then
        return 0
    fi
    local py
    py=$(printf '%s\n' "$brew_prefix"/opt/python@3.*/libexec/bin/python | sort -V | tail -1)
    [ -x "$py" ] || return 0

    echo_info 'Google Cloud SDK: Rebuilding virtualenv (Homebrew postflight left it broken)...'
    if CLOUDSDK_PYTHON="$py" gcloud config virtualenv create --python-to-use "$py" >/dev/null 2>&1 &&
        CLOUDSDK_PYTHON="$py" gcloud config virtualenv enable >/dev/null 2>&1; then
        echo_success 'Google Cloud SDK: virtualenv rebuilt.'
    else
        echo_warning 'Google Cloud SDK: virtualenv rebuild failed (core gcloud still works).'
    fi
}

update_gcloud() {
    heal_gcloud_cli

    if check_gcloud; then
        echo_info 'Google Cloud SDK: Updating components...'
        gcloud components update --quiet
    fi
}
