#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

PLIST_SOURCE="$ROOT_DIR/launchd/com.busirocket.rocketupdater.plist"

if ! plutil -lint "$PLIST_SOURCE" >/dev/null; then
    echo "RED launchd environment: the versioned LaunchAgent plist is not valid"
    exit 1
fi

# The PATH under test is the one launchd will actually use, read from the
# versioned plist, so the plist and this contract cannot drift apart.
LAUNCHD_PATH=$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:PATH' "$PLIST_SOURCE")

# Homebrew 6.0.20 documents this variable as the environment equivalent of
# --no-quit; the scheduled run must never quit a cask's running application.
if [ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:HOMEBREW_NO_UPGRADE_QUIT_CASKS' "$PLIST_SOURCE")" != 1 ] ||
    [ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:ROCKETUPDATER_LAUNCHD' "$PLIST_SOURCE")" != 1 ] ||
    [ "$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:NONINTERACTIVE' "$PLIST_SOURCE")" != 1 ]; then
    echo "RED launchd environment: the plist does not pin the noninteractive Homebrew contract"
    exit 1
fi

# The scheduled invocation must stay download-only and never name a mode that
# can delete.
if ! /usr/libexec/PlistBuddy -c 'Print :ProgramArguments' "$PLIST_SOURCE" |
    grep -q -- '--scheduled' ||
    /usr/libexec/PlistBuddy -c 'Print :ProgramArguments' "$PLIST_SOURCE" |
    grep -q -- '--clean'; then
    echo "RED launchd environment: the plist does not invoke exactly the scheduled mode"
    exit 1
fi
# shellcheck disable=SC2016 # This literal shell is the launchd environment contract.
env -i HOME=/Users/cristiandeluxe PATH="$LAUNCHD_PATH" /bin/bash -c '
for command_name in brew uv docker deno helm pip3 bun go gopls rustup cargo timeout softwareupdate lockf; do
    command -v "$command_name" >/dev/null || exit 1
done
'

FIXTURE_DIR=$(runner_fixture_create "$ROOT_DIR" "launchd-environment")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$STATE_DIR"
trap 'runner_fixture_cleanup "$FIXTURE_DIR"' EXIT

set +e
HOME="$FIXTURE_DIR/home" PATH="$LAUNCHD_PATH" NO_COLOR=1 RUNNER_TEST_STATE="$STATE_DIR" \
    /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" --scheduled --preflight-only >"$STATE_DIR/output" 2>&1
RUNNER_STATUS=$?
set -e

if [ "$RUNNER_STATUS" -ne 0 ] || ! grep -q 'backup=' "$STATE_DIR/output" || ! grep -q 'power=' "$STATE_DIR/output" ||
    ! grep -q 'load=' "$STATE_DIR/output" || ! grep -q 'disk=' "$STATE_DIR/output" || ! grep -q 'FDA=' "$STATE_DIR/output" ||
    ! grep -q 'DNS=' "$STATE_DIR/output" || ! grep -q 'sudo_mode=scheduled' "$STATE_DIR/output"; then
    echo "RED launchd environment: scheduled preflight does not validate and report launchd requirements"
    exit 1
fi

if LC_ALL=C grep -q $'\033' "$STATE_DIR/output"; then
    echo "RED launchd environment: non-TTY output contains ANSI escape sequences"
    exit 1
fi

echo "launchd environment contract passed"
