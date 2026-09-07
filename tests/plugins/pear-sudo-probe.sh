#!/bin/bash

# The run-wide grant can be unusable inside a plugin (plugins run under
# `timeout` with stdin closed). When it is, PEAR must say so once and upgrade
# unprivileged, not print "sudo: a password is required" for every package.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-pear-sudo.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$FIXTURE_DIR/home"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$PLUGIN_TEST_STATE/commands.log"
printf 'sudo: a password is required\n' >&2
exit 1
EOF

cat >"$FIXTURE_DIR/bin/brew" <<EOF
#!/bin/bash
[ "\$1" = "--prefix" ] && printf '%s\n' "$FIXTURE_DIR"
exit 0
EOF

cat >"$FIXTURE_DIR/bin/php" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$FIXTURE_DIR/bin/pear" <<'EOF'
#!/bin/bash
printf 'pear %s\n' "$*" >>"$PLUGIN_TEST_STATE/commands.log"
if [ "$1" = "list" ]; then
    cat <<'LIST'
INSTALLED PACKAGES, CHANNEL PEAR.PHP.NET:
=========================================
PACKAGE          VERSION STATE
Archive_Tar      1.6.0   stable
Console_Getopt   1.4.3   stable
XML_Util         1.4.5   stable
LIST
fi
exit 0
EOF

cat >"$FIXTURE_DIR/bin/pecl" <<'EOF'
#!/bin/bash
printf 'pecl %s\n' "$*" >>"$PLUGIN_TEST_STATE/commands.log"
exit 0
EOF

chmod +x "$FIXTURE_DIR/bin/"*

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" \
    SUDO_AVAILABLE=true PLUGIN_TEST_STATE="$STATE_DIR" /bin/bash -c '
    set -u
    source "'"$ROOT_DIR"'/lib/print_message.sh"
    source "'"$ROOT_DIR"'/lib/echo_info.sh"
    source "'"$ROOT_DIR"'/lib/echo_success.sh"
    source "'"$ROOT_DIR"'/lib/echo_warning.sh"
    source "'"$ROOT_DIR"'/lib/echo_error.sh"
    source "'"$ROOT_DIR"'/lib/echo_skip.sh"
    source "'"$ROOT_DIR"'/lib/command_exists.sh"
    source "'"$ROOT_DIR"'/plugins/pear.sh"
    update_pear
' </dev/null >"$STATE_DIR/output" 2>&1
PLUGIN_STATUS=$?
set -e

if [ "$PLUGIN_STATUS" -ne 0 ]; then
    cat "$STATE_DIR/output"
    echo "RED pear sudo probe: an unusable grant made the plugin fail"
    exit 1
fi

SUDO_CALLS=$(grep -c '^sudo ' "$STATE_DIR/commands.log" | tr -d ' ')
if [ "$SUDO_CALLS" -ne 1 ]; then
    echo "RED pear sudo probe: sudo was called $SUDO_CALLS times; expected one probe"
    cat "$STATE_DIR/commands.log"
    exit 1
fi

if ! grep -q 'root grant is not usable here' "$STATE_DIR/output"; then
    echo "RED pear sudo probe: the unusable grant was not reported once"
    exit 1
fi

# The packages still get upgraded, just without root.
for expected_package in Archive_Tar Console_Getopt XML_Util; do
    if ! grep -qF "pear upgrade --force $expected_package" "$STATE_DIR/commands.log"; then
        echo "RED pear sudo probe: $expected_package was not upgraded unprivileged"
        exit 1
    fi
done

echo "pear sudo-probe contract passed"
