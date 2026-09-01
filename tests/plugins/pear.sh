#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-pear.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$FIXTURE_DIR/home"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/pear" <<'EOF'
#!/bin/bash
printf 'pear %s\n' "$*" >>"$PLUGIN_TEST_STATE/commands.log"
exit 0
EOF

# A broken PEAR install makes pecl emit a PHP fatal error on stdout and exit
# nonzero. The listing must never be parsed as a package list.
cat >"$FIXTURE_DIR/bin/pecl" <<'EOF'
#!/bin/bash
printf 'pecl %s\n' "$*" >>"$PLUGIN_TEST_STATE/commands.log"
if [ "$1" = "list" ]; then
    cat <<'FATAL'
PHP Fatal error:  Uncaught Error: Failed opening required 'Console/Getopt.php'
Stack trace:
#0 /opt/homebrew/share/php/pear/PEAR/Config.php(23): require_once()
#1 /opt/homebrew/share/php/pear/pearcmd.php(49): require_once('...')
#2 {main}
  thrown in /opt/homebrew/share/php/pear/System.php on line 20
FATAL
    exit 1
fi
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/pear" "$FIXTURE_DIR/bin/pecl"

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" \
    PLUGIN_TEST_STATE="$STATE_DIR" /bin/bash -c '
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

if [ "$PLUGIN_STATUS" -ne 1 ]; then
    echo "RED pear plugin: a failing pecl listing did not make the plugin return 1"
    exit 1
fi

# Nothing from the PHP stack trace may become an upgrade target.
for bogus_name in 'Warning:' 'Fatal' 'Stack' '#0' '#1' '#2' 'thrown' '{main}'; do
    if grep -qF "upgrade --force $bogus_name" "$STATE_DIR/commands.log"; then
        echo "RED pear plugin: stack-trace text was parsed as a package name: $bogus_name"
        exit 1
    fi
done

if grep -qE '→ Upgrading (Warning:|Fatal|Stack|#[0-9]|thrown)' "$STATE_DIR/output"; then
    echo "RED pear plugin: the run announced an upgrade of stack-trace text"
    exit 1
fi

if ! grep -q 'Could not list installed extensions' "$STATE_DIR/output"; then
    echo "RED pear plugin: the failing pecl listing was not reported"
    exit 1
fi

# Under a Homebrew-managed PHP the PEAR package owns read-only Cellar binaries,
# so upgrading it can only end in "permission denied (delete)". It must be left
# to brew while the other packages are still upgraded individually.
cat >"$FIXTURE_DIR/bin/brew" <<EOF
#!/bin/bash
[ "\$1" = "--prefix" ] && printf '%s\n' "$FIXTURE_DIR"
exit 0
EOF
mkdir -p "$FIXTURE_DIR/bin"
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
PEAR             1.10.18 stable
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
chmod +x "$FIXTURE_DIR/bin/brew" "$FIXTURE_DIR/bin/php" \
    "$FIXTURE_DIR/bin/pear" "$FIXTURE_DIR/bin/pecl"

: >"$STATE_DIR/commands.log"
set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" \
    PLUGIN_TEST_STATE="$STATE_DIR" /bin/bash -c '
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
' </dev/null >"$STATE_DIR/brew-output" 2>&1
BREW_PHP_STATUS=$?
set -e

if [ "$BREW_PHP_STATUS" -ne 0 ]; then
    cat "$STATE_DIR/brew-output"
    echo "RED pear plugin: a healthy Homebrew-managed PEAR did not succeed"
    exit 1
fi

if grep -qF 'pear upgrade --force PEAR' "$STATE_DIR/commands.log"; then
    echo "RED pear plugin: it tried to upgrade the Homebrew-owned PEAR package"
    exit 1
fi

for expected_package in Archive_Tar XML_Util; do
    if ! grep -qF "pear upgrade --force $expected_package" "$STATE_DIR/commands.log"; then
        echo "RED pear plugin: it did not upgrade $expected_package individually"
        exit 1
    fi
done

if ! grep -q 'owned by the Homebrew php formula' "$STATE_DIR/brew-output"; then
    echo "RED pear plugin: it did not say why PEAR itself was left alone"
    exit 1
fi

echo "pear plugin contract passed"
