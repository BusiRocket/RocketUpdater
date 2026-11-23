#!/bin/bash

# deno clean empties DENO_DIR, origin storage included, so it runs only when
# origin storage holds nothing and no deno process is using the cache.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/plugins/plugin-test-support.bash"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-deno.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT
export HOME="$FIXTURE_DIR/home"
export PLUGIN_TEST_STATE="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$HOME" "$PLUGIN_TEST_STATE/origin"

cat >"$FIXTURE_DIR/bin/deno" <<'EOF'
#!/bin/bash
printf 'deno %s\n' "$*" >>"$PLUGIN_TEST_STATE/commands.log"
[ "$1" = info ] && printf '{\n  "denoDir": "/x",\n  "originStorage": "%s/origin"\n}\n' "$PLUGIN_TEST_STATE"
exit 0
EOF
cat >"$FIXTURE_DIR/bin/pgrep" <<'EOF'
#!/bin/bash
[ -n "${PLUGIN_TEST_DENO_RUNNING:-}" ]
EOF
chmod +x "$FIXTURE_DIR/bin/"*

run_case() {
    : >"$PLUGIN_TEST_STATE/commands.log"
    set +e
    run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/deno.sh" update_deno "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
    STATUS=$?
    set -e
}

touch "$PLUGIN_TEST_STATE/origin/kv.sqlite3"
run_case
if [ "$STATUS" -ne 0 ] || grep -qx 'deno clean' "$PLUGIN_TEST_STATE/commands.log" ||
    ! grep -qx 'deno clean --dry-run' "$PLUGIN_TEST_STATE/commands.log"; then
    cat "$FIXTURE_DIR/output" "$PLUGIN_TEST_STATE/commands.log"
    echo "RED deno: a cache holding origin storage was cleaned ($STATUS)"
    exit 1
fi

/bin/rm -f "$PLUGIN_TEST_STATE/origin/kv.sqlite3"
PLUGIN_TEST_DENO_RUNNING=1 run_case
if [ "$STATUS" -ne 20 ] || grep -q 'deno clean' "$PLUGIN_TEST_STATE/commands.log"; then
    echo "RED deno: the cache was cleaned under a running deno ($STATUS)"
    exit 1
fi

run_case
if [ "$STATUS" -ne 0 ] || ! grep -qx 'deno clean' "$PLUGIN_TEST_STATE/commands.log"; then
    cat "$FIXTURE_DIR/output"
    echo "RED deno: an idle cache without origin storage was not cleaned ($STATUS)"
    exit 1
fi

echo "deno plugin contract passed"
