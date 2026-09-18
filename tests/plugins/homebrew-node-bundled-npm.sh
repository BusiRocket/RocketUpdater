#!/bin/bash

# Contract: upgrading the node formula rewrites the npm package the formula
# ships, and that is not damage; a package the formula does not own that
# changes in the same upgrade still is. On 2026-09-19 the guard failed every
# node upgrade because it judged the formula's own npm as foreign.
#
# Drives scripts/run-plugin.sh so the test also proves the runner loads the
# libraries the plugin needs.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-homebrew-node.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
GLOBAL_ROOT="$FIXTURE_DIR/lib/node_modules"
KEG_MANIFEST="$FIXTURE_DIR/Cellar/node/2.0.0/libexec/lib/node_modules/npm/package.json"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$GLOBAL_ROOT"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

write_package() {
    local package_name=$1
    local package_version=$2
    local package_dir="$GLOBAL_ROOT/$package_name"

    mkdir -p "$package_dir/bin"
    cat >"$package_dir/package.json" <<EOF_PKG
{
  "name": "$package_name",
  "version": "$package_version",
  "bin": { "$package_name": "bin/cli.js" }
}
EOF_PKG
    printf '#!/usr/bin/env node\n' >"$package_dir/bin/cli.js"
}

write_package npm 11.0.0
write_package typescript 5.0.0

cat >"$FIXTURE_DIR/bin/npm" <<'EOF_NPM'
#!/bin/bash
if [ "$1 $2" = "root -g" ]; then
    printf '%s\n' "$NPM_TEST_GLOBAL_ROOT"
fi
exit 0
EOF_NPM

# The fixture brew rewrites the formula's npm on upgrade and, when asked to,
# a package it does not own; its verbose listing names the keg's own npm.
cat >"$FIXTURE_DIR/bin/brew" <<'EOF_BREW'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/brew.log"
case "$*" in
'update') exit 0 ;;
'outdated --formula --quiet') printf 'node\n'; exit 0 ;;
'outdated --cask --quiet') exit 0 ;;
'ls --verbose --formula node') printf '%s\n' "$NPM_TEST_KEG_MANIFEST"; exit 0 ;;
'upgrade --formula node')
    sed -i '' 's/"version": "11.0.0"/"version": "12.0.0"/' "$NPM_TEST_GLOBAL_ROOT/npm/package.json"
    if [ -n "${NPM_TEST_DAMAGE:-}" ]; then
        sed -i '' 's/"version": "5.0.0"/"version": "5.0.1"/' "$NPM_TEST_GLOBAL_ROOT/typescript/package.json"
    fi
    exit 0
    ;;
*) exit 0 ;;
esac
EOF_BREW
chmod +x "$FIXTURE_DIR/bin/"*

run_plugin() {
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" \
        PLUGIN_TEST_STATE="$STATE_DIR" \
        NPM_TEST_GLOBAL_ROOT="$GLOBAL_ROOT" \
        NPM_TEST_KEG_MANIFEST="$KEG_MANIFEST" \
        ROCKETUPDATER_EVENT_LOG="$STATE_DIR/events.log" \
        SUDO_AVAILABLE=true \
        /bin/bash "$ROOT_DIR/scripts/run-plugin.sh" \
        "$ROOT_DIR/plugins/homebrew.sh" update_homebrew </dev/null >"$1" 2>&1
}

set +e
run_plugin "$STATE_DIR/bundled"
BUNDLED_STATUS=$?
set -e

if grep -q 'command not found' "$STATE_DIR/bundled"; then
    cat "$STATE_DIR/bundled"
    echo "RED homebrew node upgrade: the runner did not load the npm ownership libraries"
    exit 1
fi

if [ "$BUNDLED_STATUS" -ne 0 ] || grep -q 'integrity_violation' "$STATE_DIR/bundled"; then
    cat "$STATE_DIR/bundled"
    echo "RED homebrew node upgrade: the formula's own npm being rewritten was judged as damage"
    exit 1
fi

write_package npm 11.0.0

set +e
NPM_TEST_DAMAGE=1 run_plugin "$STATE_DIR/damaged"
DAMAGED_STATUS=$?
set -e

if [ "$DAMAGED_STATUS" -ne 1 ] ||
    ! grep -q '^integrity_violation package=typescript kind=changed$' "$STATE_DIR/damaged"; then
    cat "$STATE_DIR/damaged"
    echo "RED homebrew node upgrade: a foreign package changed by the upgrade was not reported"
    exit 1
fi

if grep -q 'integrity_violation package=npm' "$STATE_DIR/damaged"; then
    echo "RED homebrew node upgrade: the formula's own npm was reported alongside the real damage"
    exit 1
fi

echo "homebrew node bundled npm contract passed"
