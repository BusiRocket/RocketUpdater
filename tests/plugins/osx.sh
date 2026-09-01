#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-osx.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$FIXTURE_DIR/home"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/sudo.log"
exit "${OSX_TEST_DOWNLOAD_STATUS:-0}"
EOF
chmod +x "$FIXTURE_DIR/bin/sudo"

cat >"$FIXTURE_DIR/bin/fake-softwareupdate" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/softwareupdate.log"
if [ "$1" = "-l" ]; then
    cat "$PLUGIN_TEST_STATE/listing.txt"
    exit "${OSX_TEST_LIST_STATUS:-0}"
fi
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/fake-softwareupdate"

run_osx() {
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" \
        PLUGIN_TEST_STATE="$STATE_DIR" \
        ROCKETUPDATER_SOFTWAREUPDATE_BIN="$FIXTURE_DIR/bin/fake-softwareupdate" \
        /bin/bash -c '
        set -u
        source "'"$ROOT_DIR"'/lib/print_message.sh"
        source "'"$ROOT_DIR"'/lib/echo_info.sh"
        source "'"$ROOT_DIR"'/lib/echo_success.sh"
        source "'"$ROOT_DIR"'/lib/echo_warning.sh"
        source "'"$ROOT_DIR"'/lib/echo_error.sh"
        source "'"$ROOT_DIR"'/lib/echo_skip.sh"
        source "'"$ROOT_DIR"'/lib/command_exists.sh"
        source "'"$ROOT_DIR"'/plugins/osx.sh"
        update_osx
    ' >"$STATE_DIR/output" 2>&1
}

# Case 1: no updates available downloads nothing and succeeds.
printf 'No new software available.\n' >"$STATE_DIR/listing.txt"
set +e
run_osx
OSX_STATUS=$?
set -e
if [ "$OSX_STATUS" -ne 0 ] || [ -s "$STATE_DIR/sudo.log" ]; then
    echo "RED osx plugin: the no-update path downloaded something or failed"
    exit 1
fi

# Case 2: an available update downloads with exactly the allowlisted argv.
printf 'Software Update found the following new or updated software:\n* Label: macOS Update\n' \
    >"$STATE_DIR/listing.txt"
: >"$STATE_DIR/sudo.log"
set +e
run_osx
OSX_STATUS=$?
set -e
if [ "$OSX_STATUS" -ne 0 ] ||
    [ "$(cat "$STATE_DIR/sudo.log")" != "-n /usr/sbin/softwareupdate -d -r" ]; then
    echo "RED osx plugin: the download argv is not exactly sudo -n /usr/sbin/softwareupdate -d -r"
    exit 1
fi

# Case 3: a failed listing returns 1 without downloading.
: >"$STATE_DIR/sudo.log"
set +e
OSX_TEST_LIST_STATUS=1 run_osx
OSX_STATUS=$?
set -e
if [ "$OSX_STATUS" -ne 1 ] || [ -s "$STATE_DIR/sudo.log" ]; then
    echo "RED osx plugin: a failed listing did not return 1 before downloading"
    exit 1
fi

# Case 4: a failed download returns 1.
set +e
OSX_TEST_DOWNLOAD_STATUS=1 run_osx
OSX_STATUS=$?
set -e
if [ "$OSX_STATUS" -ne 1 ]; then
    echo "RED osx plugin: a failed download did not return 1"
    exit 1
fi

# Case 5: a restart-required listing is reported as a terminal state.
printf 'Software Update found the following new or updated software:\n* Label: macOS Update\n\tAction: restart\n' \
    >"$STATE_DIR/listing.txt"
: >"$STATE_DIR/sudo.log"
set +e
run_osx
OSX_STATUS=$?
set -e
if [ "$OSX_STATUS" -ne 0 ] || ! grep -qi 'requires a restart' "$STATE_DIR/output"; then
    echo "RED osx plugin: a restart-required listing was not reported"
    exit 1
fi

if grep -Eq -- '-i |--install|--restart' "$STATE_DIR/sudo.log" "$STATE_DIR/softwareupdate.log"; then
    echo "RED osx plugin: an install or restart argv was reachable"
    exit 1
fi

echo "osx plugin contract passed"
