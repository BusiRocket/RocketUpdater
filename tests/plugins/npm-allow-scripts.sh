#!/bin/bash

# Contract: npm 12 blocks lifecycle scripts by default, so a global package
# whose install script is what makes it runnable must be updated with
# --allow-scripts naming it, and no other package may get that permission.
# On 2026-09-24 pnpm 12.6.0 was installed without its preinstall, leaving the
# shebang-less placeholder at `pnpm`; every Node spawnSync('pnpm') then failed
# with ENOEXEC on macOS and broke the pre-push hooks that run jscpd.
#
# Drives scripts/run-plugin.sh so the test also proves the runner loads the
# libraries the plugin needs.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-npm-allow-scripts.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
GLOBAL_ROOT="$FIXTURE_DIR/lib/node_modules"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$GLOBAL_ROOT"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/npm" <<'EOF_NPM'
#!/bin/bash
if [ "$1 $2" = "root -g" ]; then
    printf '%s\n' "$NPM_TEST_GLOBAL_ROOT"
    exit 0
fi
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/npm.log"
exit 0
EOF_NPM

cat >"$FIXTURE_DIR/bin/ncu" <<'EOF_NCU'
#!/bin/bash
printf ' pnpm        11.0.0  →  12.6.0\n'
printf ' typescript   5.0.0  →   5.1.0\n'
exit 0
EOF_NCU
chmod +x "$FIXTURE_DIR/bin/"*

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" \
    PLUGIN_TEST_STATE="$STATE_DIR" \
    NPM_TEST_GLOBAL_ROOT="$GLOBAL_ROOT" \
    ROCKETUPDATER_EVENT_LOG="$STATE_DIR/events.log" \
    /bin/bash "$ROOT_DIR/scripts/run-plugin.sh" \
    "$ROOT_DIR/plugins/npm.sh" update_npm </dev/null >"$STATE_DIR/out" 2>&1
STATUS=$?
set -e

if grep -q 'command not found' "$STATE_DIR/out"; then
    cat "$STATE_DIR/out"
    echo "RED npm allow-scripts: the runner did not load a library the plugin needs"
    exit 1
fi

if [ "$STATUS" -ne 0 ]; then
    cat "$STATE_DIR/out"
    echo "RED npm allow-scripts: update_npm failed (status $STATUS)"
    exit 1
fi

if ! grep -qx 'install -g --allow-scripts=pnpm pnpm@12.6.0' "$STATE_DIR/npm.log"; then
    cat "$STATE_DIR/npm.log"
    echo "RED npm allow-scripts: pnpm was updated without permission to run its install script"
    exit 1
fi

if ! grep -qx 'install -g typescript@5.1.0' "$STATE_DIR/npm.log"; then
    cat "$STATE_DIR/npm.log"
    echo "RED npm allow-scripts: a package outside the allowlist was granted scripts or not updated"
    exit 1
fi

echo "npm allow-scripts contract passed"
