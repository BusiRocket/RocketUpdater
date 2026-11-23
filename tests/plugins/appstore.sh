#!/bin/bash

# mas installs need root and would prompt on a terminal the plugin lacks, so it
# updates only in a run that holds sudo and lists what is outdated otherwise.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/plugins/plugin-test-support.bash"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-appstore.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT
export HOME="$FIXTURE_DIR/home"
export PLUGIN_TEST_STATE="$FIXTURE_DIR/mas.log"
mkdir -p "$FIXTURE_DIR/bin" "$HOME"

cat >"$FIXTURE_DIR/bin/mas" <<'EOF'
#!/bin/bash
printf 'mas %s\n' "$*" >>"$PLUGIN_TEST_STATE"
printf 'Warning: Found a likely App Store app that is not indexed in Spotlight\n' >&2
[ "$1" = outdated ] && [ -n "${PLUGIN_TEST_OUTDATED:-}" ] && printf '497799835 Xcode (26.1 -> 26.2)\n'
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/mas"

run_case() {
    : >"$PLUGIN_TEST_STATE"
    set +e
    run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/appstore.sh" update_appstore "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
    STATUS=$?
    set -e
}

PLUGIN_TEST_OUTDATED='' SUDO_AVAILABLE=true run_case
if [ "$STATUS" -ne 0 ] || grep -q 'mas update' "$PLUGIN_TEST_STATE"; then
    echo "RED appstore: nothing outdated still ran mas update ($STATUS)"
    exit 1
fi

PLUGIN_TEST_OUTDATED=1 SUDO_AVAILABLE=false run_case
if [ "$STATUS" -ne 0 ] || grep -q 'mas update' "$PLUGIN_TEST_STATE" || ! grep -q 'Xcode' "$FIXTURE_DIR/output"; then
    cat "$FIXTURE_DIR/output"
    echo "RED appstore: a run without sudo tried to install or hid the outdated list ($STATUS)"
    exit 1
fi

PLUGIN_TEST_OUTDATED=1 SUDO_AVAILABLE=true run_case
if [ "$STATUS" -ne 0 ] || ! grep -qx 'mas update' "$PLUGIN_TEST_STATE"; then
    cat "$FIXTURE_DIR/output"
    echo "RED appstore: a run holding sudo did not update outdated apps ($STATUS)"
    exit 1
fi

echo "appstore plugin contract passed"
