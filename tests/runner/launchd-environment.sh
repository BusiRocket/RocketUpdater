#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

LAUNCHD_PATH="/Users/cristiandeluxe/.cargo/bin:/Users/cristiandeluxe/go/bin:/Users/cristiandeluxe/.local/bin:/Users/cristiandeluxe/Library/pnpm:/Users/cristiandeluxe/.platformio/penv/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
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
