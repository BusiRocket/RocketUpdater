#!/bin/bash

# `brew upgrade` reads its stdin. When the loop fed the outdated list on stdin,
# the first upgrade drained the rest of it, so a run upgraded exactly one
# formula and one cask and then reported success for everything.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-homebrew-stdin.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/brew" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/brew.log"
case "$*" in
'outdated --formula --quiet')
    printf 'alpha\nbravo\ncharlie\n'
    ;;
'outdated --cask --quiet')
    printf 'delta\necho\n'
    ;;
upgrade*)
    # Real brew consumes stdin; reproduce that exactly.
    cat >/dev/null
    ;;
esac
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/brew"

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
    source "'"$ROOT_DIR"'/plugins/homebrew.sh"
    update_homebrew
' </dev/null >"$STATE_DIR/output" 2>&1
PLUGIN_STATUS=$?
set -e

if [ "$PLUGIN_STATUS" -ne 0 ]; then
    cat "$STATE_DIR/output"
    echo "RED homebrew stdin: the plugin failed on a healthy fixture"
    exit 1
fi

for expected in \
    'upgrade --formula alpha' \
    'upgrade --formula bravo' \
    'upgrade --formula charlie' \
    'upgrade --cask --no-ask --no-quit delta' \
    'upgrade --cask --no-ask --no-quit echo'; do
    if ! grep -qx "$expected" "$STATE_DIR/brew.log"; then
        echo "RED homebrew stdin: '$expected' never ran; the list was drained"
        cat "$STATE_DIR/brew.log"
        exit 1
    fi
done

echo "homebrew stdin-drain contract passed"
