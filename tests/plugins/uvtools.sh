#!/bin/bash

# Every eligible tool must be upgraded, even if `uv` consumes its stdin: the
# same drain that made the Homebrew plugin upgrade one package per run.
# mempalace is excluded on purpose (its daemon is upgraded out of band).

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-uvtools.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/uv" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/uv.log"
case "$*" in
'tool list')
    printf 'alpha v1.0.0\n- alpha\nbravo v2.0.0\n- bravo\nmempalace v3.8.0\n- mempalace\ncharlie v3.0.0\n- charlie\n'
    ;;
'tool upgrade'*)
    # uv is free to read stdin; the plugin must not depend on it leaving the list alone.
    cat >/dev/null
    printf 'Nothing to upgrade\n'
    ;;
esac
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/uv"

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" PLUGIN_TEST_STATE="$STATE_DIR" /bin/bash -c '
    set -u
    source "'"$ROOT_DIR"'/lib/print_message.sh"
    source "'"$ROOT_DIR"'/lib/echo_info.sh"
    source "'"$ROOT_DIR"'/lib/echo_success.sh"
    source "'"$ROOT_DIR"'/lib/echo_warning.sh"
    source "'"$ROOT_DIR"'/lib/echo_error.sh"
    source "'"$ROOT_DIR"'/lib/echo_skip.sh"
    source "'"$ROOT_DIR"'/lib/command_exists.sh"
    source "'"$ROOT_DIR"'/plugins/uvtools.sh"
    update_uvtools
' </dev/null >"$STATE_DIR/output" 2>&1
PLUGIN_STATUS=$?
set -e

if [ "$PLUGIN_STATUS" -ne 0 ]; then
    cat "$STATE_DIR/output"
    echo "RED uvtools plugin: a healthy fixture did not succeed"
    exit 1
fi

for expected in alpha bravo charlie; do
    if ! grep -qx "tool upgrade --no-progress $expected" "$STATE_DIR/uv.log"; then
        echo "RED uvtools plugin: $expected was never upgraded; the list was drained"
        cat "$STATE_DIR/uv.log"
        exit 1
    fi
done

if grep -q 'tool upgrade --no-progress mempalace' "$STATE_DIR/uv.log"; then
    echo "RED uvtools plugin: mempalace must stay excluded"
    exit 1
fi

echo "uvtools plugin contract passed"
