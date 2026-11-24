#!/bin/bash

# Contract: a pinned formula is a note, never an upgrade attempt or a failure,
# and in a run without sudo a cask whose app belongs to another user is left
# alone, because brew would fail at sudo only after copying the app into the
# Caskroom, where the copy blocks every later upgrade. Under a root grant, or
# when the app is the user's own, the cask is upgraded as usual.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-homebrew-pinned.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
APPS_DIR="$FIXTURE_DIR/Applications"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$APPS_DIR/Shared.app"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/brew" <<'EOF_BREW'
#!/bin/bash
case "$*" in
'update') exit 0 ;;
'outdated --formula --quiet')
    printf 'heldformula\nfreeformula\n'
    exit 0
    ;;
'list --pinned')
    printf 'heldformula\n'
    exit 0
    ;;
'outdated --cask --quiet')
    printf 'sharedcask\n'
    exit 0
    ;;
'list --cask sharedcask')
    printf '/caskroom/sharedcask/.metadata/config.json\n/caskroom/sharedcask/1.0/Shared.app\n'
    exit 0
    ;;
upgrade*)
    printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/upgrades"
    case "$*" in
    *heldformula*)
        echo 'Error: Not upgrading 1 pinned package:' >&2
        exit 1
        ;;
    esac
    exit 0
    ;;
*) exit 0 ;;
esac
EOF_BREW

# The fixture app belongs to whoever runs the test; `id -un` is what changes.
cat >"$FIXTURE_DIR/bin/id" <<'EOF_ID'
#!/bin/bash
if [ "$*" = '-un' ] && [ -n "${PLUGIN_TEST_USER:-}" ]; then
    printf '%s\n' "$PLUGIN_TEST_USER"
    exit 0
fi
exec /usr/bin/id "$@"
EOF_ID
chmod +x "$FIXTURE_DIR/bin/brew" "$FIXTURE_DIR/bin/id"

run_plugin() {
    local label=$1 sudo_available=$2 user=$3
    /bin/rm -f -- "$STATE_DIR/upgrades"
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" PLUGIN_TEST_STATE="$STATE_DIR" \
        PLUGIN_TEST_USER="$user" ROCKETUPDATER_APPLICATIONS_DIR="$APPS_DIR" \
        SUDO_AVAILABLE="$sudo_available" /bin/bash -c '
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
    ' >"$STATE_DIR/output-$label" 2>&1
}

# No grant, app owned by someone else: neither the pin nor the cask is touched.
set +e
run_plugin foreign false someone-else
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
    echo "RED homebrew plugin: a pinned formula or a skipped cask failed the plugin (status $STATUS)"
    cat "$STATE_DIR/output-foreign"
    exit 1
fi
if grep -q heldformula "$STATE_DIR/upgrades"; then
    echo "RED homebrew plugin: brew upgrade ran on a pinned formula"
    exit 1
fi
if ! grep -qx 'upgrade --formula freeformula' "$STATE_DIR/upgrades"; then
    echo "RED homebrew plugin: the unpinned formula was not upgraded"
    exit 1
fi
if grep -q sharedcask "$STATE_DIR/upgrades"; then
    echo "RED homebrew plugin: without sudo, a cask whose app belongs to another user was upgraded"
    exit 1
fi
if ! grep -q 'heldformula is pinned' "$STATE_DIR/output-foreign" ||
    ! grep -q 'sharedcask left for a run holding sudo' "$STATE_DIR/output-foreign"; then
    echo "RED homebrew plugin: the pin or the skipped cask was not reported"
    cat "$STATE_DIR/output-foreign"
    exit 1
fi

# No grant, but the app is the user's own: brew needs no sudo for it.
set +e
run_plugin own false "$(/usr/bin/id -un)"
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ] || ! grep -q 'upgrade --cask --no-ask --no-quit sharedcask' "$STATE_DIR/upgrades"; then
    echo "RED homebrew plugin: a cask whose app the user owns was not upgraded without sudo"
    exit 1
fi

# Root grant: the other user's app is upgraded, brew can take it over.
set +e
run_plugin grant true someone-else
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ] || ! grep -q 'upgrade --cask --no-ask --no-quit sharedcask' "$STATE_DIR/upgrades"; then
    echo "RED homebrew plugin: under a root grant the other user's cask was not upgraded"
    exit 1
fi

echo "GREEN homebrew plugin: pinned formulae are notes and foreign-owned casks wait for sudo"
