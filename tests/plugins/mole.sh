#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-mole.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/mo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/mo.log"
case "$*" in
'--version')
    printf 'mole 1.53.0\n'
    exit 0
    ;;
'clean --dry-run')
    printf 'would clean: sample\n'
    exit "${MOLE_TEST_DRY_RUN_STATUS:-0}"
    ;;
esac
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/mo"

run_report() {
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
        source "'"$ROOT_DIR"'/plugins/mole.sh"
        report_mole
    ' >"$STATE_DIR/output" 2>&1
}

# Case 1: an absent binary skips with status 20.
set +e
run_report "$FIXTURE_DIR/empty-bin"
REPORT_STATUS=$?
set -e
if [ "$REPORT_STATUS" -ne 20 ]; then
    echo "RED mole plugin: an absent mo binary did not skip with status 20"
    exit 1
fi

# Case 2: the report runs only the dry run and records version and hash.
set +e
run_report "$FIXTURE_DIR/bin"
REPORT_STATUS=$?
set -e
if [ "$REPORT_STATUS" -ne 0 ] || ! grep -q '^clean --dry-run$' "$STATE_DIR/mo.log" ||
    ! grep -q 'mole version=mole 1.53.0 sha256=[0-9a-f]' "$STATE_DIR/output"; then
    echo "RED mole plugin: the report did not run the dry run with version and hash evidence"
    exit 1
fi
if grep -Eq '^clean$|^clean [^-]' "$STATE_DIR/mo.log"; then
    echo "RED mole plugin: a non-dry-run clean was reachable"
    exit 1
fi

# Case 3: a failing dry run returns 1.
set +e
MOLE_TEST_DRY_RUN_STATUS=1 run_report "$FIXTURE_DIR/bin"
REPORT_STATUS=$?
set -e
if [ "$REPORT_STATUS" -ne 1 ]; then
    echo "RED mole plugin: a failed dry run was not returned as 1"
    exit 1
fi

echo "mole plugin contract passed"
