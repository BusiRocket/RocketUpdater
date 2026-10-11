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
'outdated --formula --quiet')
    printf 'conflicted\nkegonly\n'
    exit 0
    ;;
'upgrade --formula conflicted') exit 1 ;;
'upgrade --formula kegonly') exit 1 ;;
'info --json=v1 --formula conflicted')
    printf '[{"name": "conflicted", "keg_only": false, "linked_keg": null}]\n'
    exit 0
    ;;
'info --json=v1 --formula kegonly')
    printf '[{"name": "kegonly", "keg_only": true, "linked_keg": null}]\n'
    exit 0
    ;;
'outdated --cask --quiet')
    printf 'failcask\ngoodcask\ndeadcask\n'
    exit 0
    ;;
'upgrade --cask --no-ask --no-quit failcask') exit 1 ;;
'upgrade --cask --no-ask --no-quit goodcask') exit 0 ;;
'info --json=v2 --cask deadcask')
    printf '{"casks": [{"token": "deadcask", "disabled": true}]}\n'
    exit 0
    ;;
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
    source "'"$ROOT_DIR"'/lib/echo_note.sh"
    source "'"$ROOT_DIR"'/lib/echo_change.sh"
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

# A formula poured but left unlinked is named with the way to inspect it; a
# keg-only formula is unlinked by design and gets no such message.
if ! grep -q 'conflicted is installed but not linked' "$STATE_DIR/output"; then
    echo "RED homebrew plugin: an unlinked keg was not reported as a link conflict"
    exit 1
fi
if grep -q 'kegonly is installed but not linked' "$STATE_DIR/output"; then
    echo "RED homebrew plugin: a keg-only formula was reported as a link conflict"
    exit 1
fi

if ! grep -q 'goodcask' "$STATE_DIR/output" ||
    ! grep -q '↑  cask goodcask' "$STATE_DIR/output"; then
    echo "RED homebrew plugin: the upgraded cask is not reported as a change"
    exit 1
fi

# A disabled cask stays outdated forever and brew "upgrades" it as a no-op.
if grep -q '^upgrade --cask --no-ask --no-quit deadcask$' "$STATE_DIR/brew.log" ||
    ! grep -q 'cask deadcask is disabled upstream' "$STATE_DIR/output"; then
    echo "RED homebrew plugin: a disabled cask was upgraded instead of reported"
    exit 1
fi

echo "homebrew plugin contract passed"
