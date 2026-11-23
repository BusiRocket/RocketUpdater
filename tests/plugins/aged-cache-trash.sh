#!/bin/bash

# The Yarn metadata and Dart analysis plugins move only files older than 30
# days to the Trash, never newer ones, and stand down while their tool runs.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/plugins/plugin-test-support.bash"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-aged-cache.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT
export HOME="$FIXTURE_DIR/home"
export PLUGIN_TEST_STATE="$FIXTURE_DIR/trashed.log"
export ROCKETUPDATER_TRASH_COMMAND="$FIXTURE_DIR/bin/fake-trash"
mkdir -p "$FIXTURE_DIR/bin"

cat >"$ROCKETUPDATER_TRASH_COMMAND" <<'EOF'
#!/bin/bash
for path in "$@"; do
    printf '%s\n' "$path" >>"$PLUGIN_TEST_STATE"
    /bin/rm -f -- "$path"
done
EOF
cat >"$FIXTURE_DIR/bin/pgrep" <<'EOF'
#!/bin/bash
[ -n "${PLUGIN_TEST_TOOL_RUNNING:-}" ]
EOF
chmod +x "$FIXTURE_DIR/bin/"*

check_plugin() {
    local plugin=$1 cache_root=$2
    mkdir -p "$cache_root/sub"
    touch -t 202001010000 "$cache_root/sub/old"
    touch "$cache_root/sub/new"
    : >"$PLUGIN_TEST_STATE"

    set +e
    PLUGIN_TEST_TOOL_RUNNING=1 run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/$plugin.sh" "update_$plugin" "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
    local status=$?
    set -e
    if [ "$status" -ne 20 ] || [ -s "$PLUGIN_TEST_STATE" ]; then
        echo "RED $plugin: files were trashed while the tool was running ($status)"
        exit 1
    fi

    set +e
    run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/$plugin.sh" "update_$plugin" "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
    status=$?
    set -e
    if [ "$status" -ne 0 ] || [ "$(cat "$PLUGIN_TEST_STATE")" != "$cache_root/sub/old" ] || [ ! -f "$cache_root/sub/new" ]; then
        cat "$FIXTURE_DIR/output" "$PLUGIN_TEST_STATE"
        echo "RED $plugin: not exactly the file older than 30 days went to the Trash ($status)"
        exit 1
    fi
}

check_plugin yarnmetadata "$HOME/.yarn/berry/metadata"
check_plugin dartanalysis "$HOME/.dartServer/.analysis-driver"

echo "aged cache trash contract passed"
