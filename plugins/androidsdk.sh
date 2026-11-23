#!/bin/bash

PLUGIN_NAME="Android SDK"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=60
PLUGIN_TIMEOUT_SECONDS=1800
PLUGIN_SCHEDULE_ACTION=run

# sdkmanager needs a Java runtime and the machine has none of its own, so the
# one Android Studio bundles is used. Licenses are never accepted on the
# owner's behalf: an update that needs a new one fails here with sdkmanager's
# message and waits for `sdkmanager --licenses` to be run by hand.
update_androidsdk() {
    local sdk_root=${ANDROID_HOME:-$HOME/Library/Android/sdk}
    local sdkmanager="$sdk_root/cmdline-tools/latest/bin/sdkmanager"
    if [ ! -x "$sdkmanager" ]; then
        echo_skip "Android SDK command-line tools are not installed"
        return 20
    fi

    # Studio and the emulator hold SDK files open; updating under them
    # leaves half-replaced packages.
    if pgrep -f 'Android Studio.app/Contents/MacOS' >/dev/null 2>&1 ||
        pgrep -f 'qemu-system' >/dev/null 2>&1; then
        echo_skip "Android Studio or an emulator is running; SDK update deferred"
        return 20
    fi

    local java_home=${JAVA_HOME:-}
    if [ -z "$java_home" ] && ! java_home=$(/usr/libexec/java_home 2>/dev/null); then
        java_home="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    fi
    if [ ! -x "$java_home/bin/java" ]; then
        echo_skip "No Java runtime for sdkmanager (install one or Android Studio)"
        return 20
    fi

    echo_info "Android SDK: Updating installed packages..."
    local update_output
    if ! update_output=$(JAVA_HOME="$java_home" ANDROID_HOME="$sdk_root" \
        "$sdkmanager" --update </dev/null 2>&1); then
        printf '%s\n' "$update_output"
        echo_error "Android SDK update failed; if a license is pending, run: $sdkmanager --licenses"
        return 1
    fi
    printf '%s\n' "$update_output"
    echo_success "Android SDK packages are current"
    return 0
}
