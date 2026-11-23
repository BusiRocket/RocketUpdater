#!/bin/bash

# Every Sparkle app gets automatic checks and installs turned on in the domain
# it actually reads (its container when sandboxed), except an app whose
# Info.plist forbids automatic installs. Apps already on are not rewritten.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/plugins/plugin-test-support.bash"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-sparkleauto.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT
export HOME="$FIXTURE_DIR/home"
export ROCKETUPDATER_SPARKLE_APP_ROOT="$FIXTURE_DIR/Applications"
export PLUGIN_TEST_STATE="$FIXTURE_DIR/defaults.db"
mkdir -p "$FIXTURE_DIR/bin" "$HOME/Library/Containers/test.sandboxed/Data/Library/Preferences"
: >"$PLUGIN_TEST_STATE"

# The real defaults would write to the owner's preferences whatever HOME says.
cat >"$FIXTURE_DIR/bin/defaults" <<'EOF'
#!/bin/bash
case $1 in
read) awk -v d="$2" -v k="$3" '$1 == d && $2 == k { print $3; found = 1 } END { exit !found }' "$PLUGIN_TEST_STATE" ;;
write) printf '%s %s 1\n' "$2" "$3" >>"$PLUGIN_TEST_STATE" ;;
esac
EOF
chmod +x "$FIXTURE_DIR/bin/defaults"

make_app() {
    local name=$1 bundle_id=$2 extra=$3
    mkdir -p "$ROCKETUPDATER_SPARKLE_APP_ROOT/$name.app/Contents"
    cat >"$ROCKETUPDATER_SPARKLE_APP_ROOT/$name.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
$extra
</dict></plist>
EOF
}

FEED='<key>SUFeedURL</key><string>https://example.invalid/appcast.xml</string>'
make_app Plain test.plain "$FEED"
make_app Sandboxed test.sandboxed "$FEED"
make_app Forbidden test.forbidden "$FEED<key>SUAllowsAutomaticUpdates</key><false/>"
make_app NoSparkle test.nosparkle ""
make_app AlreadyOn test.already "$FEED"
printf 'test.already SUAutomaticallyUpdate 1\ntest.already SUEnableAutomaticChecks 1\n' >>"$PLUGIN_TEST_STATE"

set +e
run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/sparkleauto.sh" update_sparkleauto "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
STATUS=$?
set -e

SANDBOX_DOMAIN="$HOME/Library/Containers/test.sandboxed/Data/Library/Preferences/test.sandboxed"
if [ "$STATUS" -ne 0 ] ||
    ! grep -qx 'test.plain SUAutomaticallyUpdate 1' "$PLUGIN_TEST_STATE" ||
    ! grep -qx 'test.plain SUEnableAutomaticChecks 1' "$PLUGIN_TEST_STATE" ||
    ! grep -qxF "$SANDBOX_DOMAIN SUAutomaticallyUpdate 1" "$PLUGIN_TEST_STATE" ||
    grep -q '^test.sandboxed ' "$PLUGIN_TEST_STATE"; then
    cat "$FIXTURE_DIR/output" "$PLUGIN_TEST_STATE"
    echo "RED sparkleauto: automatic updates were not enabled in each app's own domain ($STATUS)"
    exit 1
fi
if grep -q 'test.forbidden\|test.nosparkle' "$PLUGIN_TEST_STATE"; then
    echo "RED sparkleauto: an app that forbids automatic updates, or is not Sparkle, was changed"
    exit 1
fi
if [ "$(grep -c '^test.already ' "$PLUGIN_TEST_STATE")" -ne 2 ] || ! grep -q '2 newly enabled' "$FIXTURE_DIR/output"; then
    cat "$FIXTURE_DIR/output"
    echo "RED sparkleauto: an app already on was rewritten or the count is wrong"
    exit 1
fi

echo "sparkleauto plugin contract passed"
