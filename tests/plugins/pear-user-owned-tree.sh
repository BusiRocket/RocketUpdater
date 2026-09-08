#!/bin/bash

# Root is for a system PEAR the user cannot write. Upgrading a user-owned
# Homebrew tree as root rewrites those files as root-owned, and the next run
# without a grant — every scheduled run — then fails with
# "permission denied (delete)". The plugin must decline root in that case even
# when the run holds a passwordless grant.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-pear-owned.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
PEAR_DIR="$FIXTURE_DIR/share/pear"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$FIXTURE_DIR/home" "$PEAR_DIR/Console"
touch "$PEAR_DIR/Console/Getopt.php"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$PLUGIN_TEST_STATE/commands.log"
[ "$1" = "-n" ] && shift
exec "$@"
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
case "$1" in
config-get) printf '%s\n' "$PLUGIN_TEST_PEAR_DIR" ;;
list)
    cat <<'LIST'
INSTALLED PACKAGES, CHANNEL PEAR.PHP.NET:
=========================================
PACKAGE          VERSION STATE
Archive_Tar      1.6.0   stable
XML_Util         1.4.5   stable
LIST
    ;;
esac
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
    SUDO_AVAILABLE=true PLUGIN_TEST_STATE="$STATE_DIR" \
    PLUGIN_TEST_PEAR_DIR="$PEAR_DIR" /bin/bash -c '
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
    echo "RED pear ownership: the plugin failed on a user-owned tree"
    exit 1
fi

if grep -q '^sudo ' "$STATE_DIR/commands.log"; then
    echo "RED pear ownership: sudo was used on a tree this user can already write"
    grep '^sudo ' "$STATE_DIR/commands.log" | head -3
    exit 1
fi

if ! grep -q 'writable by this user; upgrading without root' "$STATE_DIR/output"; then
    cat "$STATE_DIR/output"
    echo "RED pear ownership: the reason for declining root was not reported"
    exit 1
fi

for expected_package in Archive_Tar XML_Util; do
    if ! grep -qF "pear upgrade --force $expected_package" "$STATE_DIR/commands.log"; then
        echo "RED pear ownership: $expected_package was not upgraded unprivileged"
        exit 1
    fi
done

echo "pear user-owned-tree contract passed"
