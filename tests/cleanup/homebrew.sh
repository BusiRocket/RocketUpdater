#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.cleanup-fixture-homebrew.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
FIXTURE_HOME="$FIXTURE_DIR/home"
FIXTURE_PREFIX="$FIXTURE_DIR/prefix"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" \
    "$FIXTURE_HOME/Library/Caches/Homebrew/downloads" \
    "$FIXTURE_PREFIX/var/homebrew/tmp"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

printf 'payload\n' >"$FIXTURE_HOME/Library/Caches/Homebrew/downloads/sample.tar.gz"

cat >"$FIXTURE_DIR/bin/brew" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$CLEANUP_TEST_STATE/brew.log"
case "$*" in
'--prefix')
    printf '%s\n' "$CLEANUP_TEST_PREFIX"
    ;;
'cleanup -n --prune=all')
    preview_count=$(cat "$CLEANUP_TEST_STATE/preview-count" 2>/dev/null || printf 0)
    preview_count=$((preview_count + 1))
    printf '%s\n' "$preview_count" >"$CLEANUP_TEST_STATE/preview-count"
    if [ -f "$CLEANUP_TEST_STATE/preview-$preview_count.txt" ]; then
        cat "$CLEANUP_TEST_STATE/preview-$preview_count.txt"
    else
        cat "$CLEANUP_TEST_STATE/preview-1.txt"
    fi
    ;;
'cleanup --prune=all')
    printf 'removed\n'
    exit "${CLEANUP_TEST_REMOVE_STATUS:-0}"
    ;;
esac
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/brew"

run_guard_with_tty() {
    local answer=$1
    local expect_file="$STATE_DIR/session.expect"

    cat >"$expect_file" <<EOF
set timeout 20
spawn /bin/bash -c {
    set -u
    source "$ROOT_DIR/lib/print_message.sh"
    source "$ROOT_DIR/lib/echo_info.sh"
    source "$ROOT_DIR/lib/echo_success.sh"
    source "$ROOT_DIR/lib/echo_warning.sh"
    source "$ROOT_DIR/lib/echo_error.sh"
    source "$ROOT_DIR/lib/echo_skip.sh"
    source "$ROOT_DIR/lib/command_exists.sh"
    source "$ROOT_DIR/cleanup/guard_homebrew_cleanup.sh"
    guard_homebrew_cleanup
}
expect {
    -re {Type "homebrew"} { send "$answer\r"; exp_continue }
    timeout { exec kill [exp_pid]; exit 99 }
    eof {}
}
catch wait wait_result
exit [lindex \$wait_result 3]
EOF

    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_HOME" \
        CLEANUP_TEST_STATE="$STATE_DIR" CLEANUP_TEST_PREFIX="$FIXTURE_PREFIX" \
        /usr/bin/expect -f "$expect_file" >"$STATE_DIR/output" 2>&1
}

# Case 1: without a TTY the guard fails closed with 78 before any brew call.
set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_HOME" \
    CLEANUP_TEST_STATE="$STATE_DIR" CLEANUP_TEST_PREFIX="$FIXTURE_PREFIX" \
    /bin/bash -c '
    set -u
    source "'"$ROOT_DIR"'/lib/print_message.sh"
    source "'"$ROOT_DIR"'/lib/echo_info.sh"
    source "'"$ROOT_DIR"'/lib/echo_success.sh"
    source "'"$ROOT_DIR"'/lib/echo_warning.sh"
    source "'"$ROOT_DIR"'/lib/echo_error.sh"
    source "'"$ROOT_DIR"'/lib/echo_skip.sh"
    source "'"$ROOT_DIR"'/lib/command_exists.sh"
    source "'"$ROOT_DIR"'/cleanup/guard_homebrew_cleanup.sh"
    guard_homebrew_cleanup
' </dev/null >"$STATE_DIR/no-tty-output" 2>&1
NO_TTY_STATUS=$?
set -e

if [ "$NO_TTY_STATUS" -ne 78 ] || [ -s "$STATE_DIR/brew.log" ]; then
    echo "RED homebrew cleanup guard: non-TTY invocation did not fail closed with 78"
    exit 1
fi

# Case 2: a candidate outside the safe roots skips removal with status 20.
printf 'Would remove: %s/Cellar/foo/1.0 (10 files, 1MB)\n' "$FIXTURE_PREFIX" \
    >"$STATE_DIR/preview-1.txt"
set +e
run_guard_with_tty homebrew
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -ne 20 ] || grep -q '^cleanup --prune=all$' "$STATE_DIR/brew.log"; then
    echo "RED homebrew cleanup guard: an unsafe candidate did not skip removal"
    exit 1
fi

# Case 3: a changing preview between the two dry runs aborts with failure.
: >"$STATE_DIR/brew.log"
/bin/rm -f "$STATE_DIR/preview-count"
printf 'Would remove: %s/Library/Caches/Homebrew/downloads/sample.tar.gz (1MB)\n' \
    "$FIXTURE_HOME" >"$STATE_DIR/preview-1.txt"
printf 'Would remove: %s/var/homebrew/tmp/other (1MB)\n' "$FIXTURE_PREFIX" \
    >"$STATE_DIR/preview-2.txt"
set +e
run_guard_with_tty homebrew
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -eq 0 ] || grep -q '^cleanup --prune=all$' "$STATE_DIR/brew.log"; then
    echo "RED homebrew cleanup guard: changing previews did not abort before removal"
    exit 1
fi

# Case 4: a wrong confirmation leaves the candidates in place with status 20.
: >"$STATE_DIR/brew.log"
/bin/rm -f "$STATE_DIR/preview-count" "$STATE_DIR/preview-2.txt"
set +e
run_guard_with_tty wrong-answer
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -ne 20 ] || grep -q '^cleanup --prune=all$' "$STATE_DIR/brew.log"; then
    echo "RED homebrew cleanup guard: a wrong confirmation did not skip removal"
    exit 1
fi

# Case 5: the typed operation name runs the one allowed removal command and
# reports the allocated KiB first.
: >"$STATE_DIR/brew.log"
/bin/rm -f "$STATE_DIR/preview-count"
set +e
run_guard_with_tty homebrew
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -ne 0 ] || ! grep -q '^cleanup --prune=all$' "$STATE_DIR/brew.log" ||
    ! grep -q 'homebrew_cleanup allocated_kib=' "$STATE_DIR/output"; then
    echo "RED homebrew cleanup guard: typed confirmation did not run the allowed removal"
    exit 1
fi

# Case 6: a failing removal command propagates a nonzero status.
: >"$STATE_DIR/brew.log"
/bin/rm -f "$STATE_DIR/preview-count"
set +e
CLEANUP_TEST_REMOVE_STATUS=1 run_guard_with_tty homebrew
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -eq 0 ]; then
    echo "RED homebrew cleanup guard: a failed removal command was reported as success"
    exit 1
fi

echo "homebrew cleanup guard contract passed"
