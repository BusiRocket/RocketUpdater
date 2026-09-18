#!/bin/bash

# Contract: a cask upgrade that calls sudo must fail at once instead of waiting
# on a prompt the plugin can never answer. Brew passes `sudo -A` whenever
# SUDO_ASKPASS is set, so the plugin sets it to /usr/bin/false when the run has
# no root grant, and leaves it alone when credentials are cached.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-homebrew-askpass.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

# The fixture brew records what sudo would see: with an askpass helper it runs
# it and fails when the helper yields nothing; without one it would prompt.
cat >"$FIXTURE_DIR/bin/brew" <<'EOF_BREW'
#!/bin/bash
case "$*" in
'update') exit 0 ;;
'outdated --formula --quiet') exit 0 ;;
'outdated --cask --quiet')
    printf 'sudocask\n'
    exit 0
    ;;
'upgrade --cask --no-ask --no-quit sudocask')
    printf '%s\n' "${SUDO_ASKPASS:-unset}" >>"$PLUGIN_TEST_STATE/askpass"
    if [ -n "${SUDO_ASKPASS:-}" ]; then
        "$SUDO_ASKPASS" >/dev/null 2>&1 && exit 0
        echo 'sudo: no password was provided' >&2
        exit 1
    fi
    echo 'would prompt for a password' >>"$PLUGIN_TEST_STATE/prompted"
    exit 0
    ;;
*) exit 0 ;;
esac
EOF_BREW
chmod +x "$FIXTURE_DIR/bin/brew"

run_plugin() {
    local sudo_available=$1
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" PLUGIN_TEST_STATE="$STATE_DIR" \
        SUDO_AVAILABLE="$sudo_available" /bin/bash -c '
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
    ' >"$STATE_DIR/output-$sudo_available" 2>&1
}

set +e
run_plugin false
NO_GRANT_STATUS=$?
set -e

if [ "$(cat "$STATE_DIR/askpass")" != /usr/bin/false ]; then
    echo "RED homebrew plugin: without a root grant SUDO_ASKPASS was not /usr/bin/false"
    exit 1
fi

if [ -e "$STATE_DIR/prompted" ]; then
    echo "RED homebrew plugin: a cask needing sudo reached a password prompt"
    exit 1
fi

if [ "$NO_GRANT_STATUS" -ne 1 ]; then
    echo "RED homebrew plugin: the sudo cask failing fast did not make the plugin return 1"
    exit 1
fi

/bin/rm -f -- "$STATE_DIR/askpass"

set +e
run_plugin true
GRANT_STATUS=$?
set -e

if [ "$(cat "$STATE_DIR/askpass")" != unset ]; then
    echo "RED homebrew plugin: with cached credentials SUDO_ASKPASS was set"
    exit 1
fi

if [ "$GRANT_STATUS" -ne 0 ]; then
    echo "RED homebrew plugin: the cask upgrade failed under a root grant"
    exit 1
fi

echo "GREEN homebrew plugin: sudo prompts fail fast without a grant and stay untouched with one"
