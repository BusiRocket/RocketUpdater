#!/bin/bash

# Homebrew prints deprecation and tap warnings on stderr during `brew outdated`.
# Merging that stderr into the name list made the plugin run
# `brew upgrade --formula "Warning: Calling ..."` on every run.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-homebrew-noise.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/brew" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/brew.log"
case "$*" in
'update') exit 0 ;;
'outdated --formula --quiet')
    printf 'Warning: Calling HOMEBREW_NO_REQUIRE_TAP_TRUST is deprecated! Use `brew trust` instead.\n' >&2
    printf 'bun\noven-sh/bun/bun\n'
    exit 0
    ;;
'outdated --cask --quiet')
    printf 'Warning: Calling `postflight` is deprecated! Use `postflight_steps` instead.\n' >&2
    printf '  /opt/homebrew/Library/Taps/openclaw/homebrew-tap/Casks/goplaces.rb:37\n' >&2
    printf 'warp\n'
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
    source "'"$ROOT_DIR"'/lib/command_exists.sh"
    source "'"$ROOT_DIR"'/plugins/homebrew.sh"
    update_homebrew
' >"$STATE_DIR/output" 2>&1
PLUGIN_STATUS=$?
set -e

if [ "$PLUGIN_STATUS" -ne 0 ]; then
    echo "RED homebrew noise: warnings on stderr made the plugin fail"
    cat "$STATE_DIR/output"
    exit 1
fi

if grep -qi 'upgrade .*warning' "$STATE_DIR/brew.log" ||
    grep -q 'upgrade .*goplaces.rb' "$STATE_DIR/brew.log"; then
    echo "RED homebrew noise: a stderr warning line was passed to brew upgrade"
    cat "$STATE_DIR/brew.log"
    exit 1
fi

# Apart from the name list, not lost: a warning is how Homebrew says a tap is
# broken or a formula deprecated, and a successful enumeration must still show it.
for warning in 'HOMEBREW_NO_REQUIRE_TAP_TRUST is deprecated' 'postflight' 'goplaces.rb:37'; do
    if ! grep -qF "$warning" "$STATE_DIR/output"; then
        echo "RED homebrew noise: the warning '$warning' was discarded instead of shown"
        exit 1
    fi
done

for expected in \
    'upgrade --formula bun' \
    'upgrade --formula oven-sh/bun/bun' \
    'upgrade --cask --no-ask --no-quit warp'; do
    if ! grep -qx "$expected" "$STATE_DIR/brew.log"; then
        echo "RED homebrew noise: missing '$expected'"
        cat "$STATE_DIR/brew.log"
        exit 1
    fi
done

echo "homebrew stderr-noise contract passed"
