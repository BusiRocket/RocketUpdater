#!/bin/bash

# Microsoft updates install without closing open apps, MAU is switched to
# download on its own once, and a helper that stops answering is a skip.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/plugins/plugin-test-support.bash"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-msupdate.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT
export HOME="$FIXTURE_DIR/home"
export PLUGIN_TEST_STATE="$FIXTURE_DIR/state"
export ROCKETUPDATER_MSUPDATE="$FIXTURE_DIR/msupdate"
mkdir -p "$FIXTURE_DIR/bin" "$HOME" "$PLUGIN_TEST_STATE"

cat >"$ROCKETUPDATER_MSUPDATE" <<'EOF'
#!/bin/bash
printf 'msupdate %s\n' "$*" >>"$PLUGIN_TEST_STATE/commands.log"
case $1 in
--list) printf '<plist><array/></plist>\n' ;;
--install) [ -n "${PLUGIN_TEST_XPC:-}" ] && printf 'Error: XPC Connection to updater invalidated\n' ;;
esac
exit 0
EOF
cat >"$FIXTURE_DIR/bin/defaults" <<'EOF'
#!/bin/bash
printf 'defaults %s\n' "$*" >>"$PLUGIN_TEST_STATE/commands.log"
[ "$1" = read ] && cat "$PLUGIN_TEST_STATE/howtocheck" 2>/dev/null
exit 0
EOF
chmod +x "$ROCKETUPDATER_MSUPDATE" "$FIXTURE_DIR/bin/defaults"

run_case() {
    : >"$PLUGIN_TEST_STATE/commands.log"
    set +e
    run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/msupdate.sh" update_msupdate "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
    STATUS=$?
    set -e
}

run_case
if [ "$STATUS" -ne 0 ] ||
    ! grep -q '^msupdate --install --wait [0-9]' "$PLUGIN_TEST_STATE/commands.log" ||
    grep -qE -- '-t|--terminate' "$PLUGIN_TEST_STATE/commands.log" ||
    ! grep -qx 'defaults write com.microsoft.autoupdate2 HowToCheck -string AutomaticDownload' "$PLUGIN_TEST_STATE/commands.log"; then
    cat "$FIXTURE_DIR/output" "$PLUGIN_TEST_STATE/commands.log"
    echo "RED msupdate: updates were not installed gently with automatic downloads on ($STATUS)"
    exit 1
fi

printf 'AutomaticDownload\n' >"$PLUGIN_TEST_STATE/howtocheck"
run_case
if grep -q '^defaults write' "$PLUGIN_TEST_STATE/commands.log"; then
    echo "RED msupdate: the download setting was rewritten although already on"
    exit 1
fi

PLUGIN_TEST_XPC=1 run_case
if [ "$STATUS" -ne 20 ]; then
    cat "$FIXTURE_DIR/output"
    echo "RED msupdate: an XPC failure during install returned $STATUS instead of a skip"
    exit 1
fi

echo "msupdate plugin contract passed"
