#!/bin/bash

# Homebrew's pear wrapper hard-codes include_path to the Cellar skeleton while
# pear.conf's php_dir is the prefix tree. `pear list` works either way, but the
# first `upgrade --force Archive_Tar` removes Archive/Tar.php from the Cellar
# and installs it under the prefix, so every later upgrade dies with "Failed
# opening required 'Archive/Tar.php'" (2026-09-29). The plugin must point the
# wrapper at the configured php_dir whenever that tree holds pearcmd.php, even
# when `pear list` succeeds.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-pear-php-dir.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
PEAR_TREE="$FIXTURE_DIR/share/pear"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$FIXTURE_DIR/home" "$PEAR_TREE"
touch "$PEAR_TREE/pearcmd.php"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/brew" <<EOF
#!/bin/bash
[ "\$1" = "--prefix" ] && printf '%s\n' "$FIXTURE_DIR"
exit 0
EOF

cat >"$FIXTURE_DIR/bin/php" <<'EOF'
#!/bin/bash
exit 0
EOF

cat >"$FIXTURE_DIR/bin/pear" <<EOF
#!/bin/bash
printf 'pear %s dir=%s\n' "\$*" "\${PHP_PEAR_INSTALL_DIR:-unset}" >>"\$PLUGIN_TEST_STATE/commands.log"
case "\$1" in
config-get)
    [ "\$2" = "php_dir" ] && printf '%s\n' "$PEAR_TREE"
    ;;
list)
    cat <<'LIST'
INSTALLED PACKAGES, CHANNEL PEAR.PHP.NET:
=========================================
PACKAGE          VERSION STATE
Archive_Tar      1.6.0   stable
Console_Getopt   1.4.3   stable
LIST
    ;;
esac
exit 0
EOF

cat >"$FIXTURE_DIR/bin/pecl" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$FIXTURE_DIR/bin/"*

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" \
    SUDO_AVAILABLE=false PLUGIN_TEST_STATE="$STATE_DIR" /bin/bash -c '
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
    echo "RED pear php_dir: the plugin failed"
    exit 1
fi

for expected_package in Archive_Tar Console_Getopt; do
    if ! grep -qF "pear upgrade $expected_package dir=$PEAR_TREE" "$STATE_DIR/commands.log"; then
        echo "RED pear php_dir: $expected_package was not upgraded against the configured php_dir"
        cat "$STATE_DIR/commands.log"
        exit 1
    fi
done

echo "pear configured-php-dir contract passed"
