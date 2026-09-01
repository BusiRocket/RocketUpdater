#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-brewhealth.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$FIXTURE_DIR/empty-bin" "$STATE_DIR"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/brew" <<'EOF'
#!/bin/bash
printf 'brew %s\n' "$*" >>"$PLUGIN_TEST_STATE/commands.log"
case "$*" in
'missing')
    [ -n "${BREWHEALTH_TEST_MISSING:-}" ] && printf '%s\n' "$BREWHEALTH_TEST_MISSING"
    exit "${BREWHEALTH_TEST_MISSING_STATUS:-0}"
    ;;
'autoremove --dry-run') exit 0 ;;
'doctor')
    printf 'Warning: Some installed formulae are deprecated.\n'
    exit "${BREWHEALTH_TEST_DOCTOR_STATUS:-1}"
    ;;
esac
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/brew"

run_plugin() {
    PATH="$1:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" \
        PLUGIN_TEST_STATE="$STATE_DIR" /bin/bash -c '
        set -u
        source "'"$ROOT_DIR"'/lib/print_message.sh"
        source "'"$ROOT_DIR"'/lib/echo_info.sh"
        source "'"$ROOT_DIR"'/lib/echo_success.sh"
        source "'"$ROOT_DIR"'/lib/echo_warning.sh"
        source "'"$ROOT_DIR"'/lib/echo_error.sh"
        source "'"$ROOT_DIR"'/lib/echo_skip.sh"
        source "'"$ROOT_DIR"'/lib/command_exists.sh"
        source "'"$ROOT_DIR"'/plugins/brewhealth.sh"
        update_brewhealth
    ' >"$STATE_DIR/output" 2>&1
}

# Case 1: no Homebrew skips with 20.
set +e
run_plugin "$FIXTURE_DIR/empty-bin"
STATUS=$?
set -e
if [ "$STATUS" -ne 20 ]; then
    echo "RED brewhealth: an absent Homebrew did not skip with status 20"
    exit 1
fi

# Case 2: doctor warnings alone are advisory and must not fail the run.
set +e
run_plugin "$FIXTURE_DIR/bin"
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ]; then
    cat "$STATE_DIR/output"
    echo "RED brewhealth: advisory doctor findings failed the run"
    exit 1
fi
if ! grep -q 'do not fail the run' "$STATE_DIR/output" ||
    ! grep -q 'deprecated' "$STATE_DIR/output"; then
    echo "RED brewhealth: doctor findings were hidden instead of reported"
    exit 1
fi

# Case 3: a formula with a missing dependency is a real failure.
set +e
BREWHEALTH_TEST_MISSING='memo: fzf' BREWHEALTH_TEST_MISSING_STATUS=1 \
    run_plugin "$FIXTURE_DIR/bin"
STATUS=$?
set -e
if [ "$STATUS" -ne 1 ]; then
    echo "RED brewhealth: a missing dependency did not fail the run"
    exit 1
fi
if ! grep -q 'memo: fzf' "$STATE_DIR/output"; then
    echo "RED brewhealth: the missing dependency was not named"
    exit 1
fi

echo "brewhealth plugin contract passed"
