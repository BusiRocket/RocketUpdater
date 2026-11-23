#!/bin/bash

# PEAR's cache_dir is a per-boot temp path that is usually gone, and clearing a
# missing directory printed an error every run. The clear runs only when the
# directory exists.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/plugins/plugin-test-support.bash"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-pear-cache.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT
export HOME="$FIXTURE_DIR/home"
export PLUGIN_TEST_STATE="$FIXTURE_DIR/commands.log"
export PLUGIN_TEST_CACHE_DIR="$FIXTURE_DIR/pear-cache"
mkdir -p "$FIXTURE_DIR/bin" "$HOME"

cat >"$FIXTURE_DIR/bin/pear" <<'EOF'
#!/bin/bash
printf 'pear %s\n' "$*" >>"$PLUGIN_TEST_STATE"
[ "$*" = 'config-get cache_dir' ] && printf '%s\n' "$PLUGIN_TEST_CACHE_DIR"
exit 0
EOF
cat >"$FIXTURE_DIR/bin/pecl" <<'EOF'
#!/bin/bash
printf 'pecl %s\n' "$*" >>"$PLUGIN_TEST_STATE"
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/"*

: >"$PLUGIN_TEST_STATE"
run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/pear.sh" update_pear "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
if grep -q 'clear-cache' "$PLUGIN_TEST_STATE" || ! grep -q 'PEAR cache is absent' "$FIXTURE_DIR/output"; then
    cat "$FIXTURE_DIR/output"
    echo "RED pear cache: a missing cache directory was still cleared"
    exit 1
fi

mkdir -p "$PLUGIN_TEST_CACHE_DIR"
: >"$PLUGIN_TEST_STATE"
run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/pear.sh" update_pear "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
if ! grep -qx 'pear clear-cache' "$PLUGIN_TEST_STATE"; then
    cat "$FIXTURE_DIR/output" "$PLUGIN_TEST_STATE"
    echo "RED pear cache: an existing cache directory was not cleared"
    exit 1
fi

echo "pear cache-dir contract passed"
