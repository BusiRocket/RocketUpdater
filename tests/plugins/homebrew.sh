#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-homebrew.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/brew" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/brew.log"
case "$*" in
'update') exit 0 ;;
'outdated --formula --quiet') exit 0 ;;
'outdated --cask --quiet')
    printf 'failcask\ngoodcask\n'
    exit 0
    ;;
'upgrade --cask --no-ask --no-quit failcask') exit 1 ;;
'upgrade --cask --no-ask --no-quit goodcask') exit 0 ;;
*) exit 0 ;;
esac
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
' >"$STATE_DIR/output" 2>&1
PLUGIN_STATUS=$?
set -e

if [ "$PLUGIN_STATUS" -ne 1 ]; then
    echo "RED homebrew plugin: a failed cask upgrade did not make the plugin return 1"
    exit 1
fi

if ! grep -q '^upgrade --cask --no-ask --no-quit failcask$' "$STATE_DIR/brew.log" ||
    ! grep -q '^upgrade --cask --no-ask --no-quit goodcask$' "$STATE_DIR/brew.log"; then
    echo "RED homebrew plugin: both casks were not attempted after the first failure"
    exit 1
fi

if grep -q 'cleanup' "$STATE_DIR/brew.log"; then
    echo "RED homebrew plugin: update_homebrew reached a cleanup command"
    exit 1
fi

if ! grep -q 'failcask' "$STATE_DIR/output"; then
    echo "RED homebrew plugin: the failed item is not named in the plugin output"
    exit 1
fi

echo "homebrew plugin contract passed"
