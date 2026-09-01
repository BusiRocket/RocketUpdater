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

echo "pear plugin contract passed"
