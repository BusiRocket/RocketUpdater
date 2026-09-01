#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.cleanup-fixture-npm.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
FIXTURE_HOME="$FIXTURE_DIR/home"
INDEX_DIR="$FIXTURE_HOME/.npm/_cacache/index-v5/aa/bb"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$INDEX_DIR"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/npm" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$CLEANUP_TEST_STATE/npm.log"
exit "${CLEANUP_TEST_NPM_STATUS:-0}"
EOF
chmod +x "$FIXTURE_DIR/bin/npm"

write_index() {
    printf 'hash\t{"key":"%s","integrity":"sha512-x"}\n' "$1" >"$INDEX_DIR/entry"
}

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
    source "$ROOT_DIR/cleanup/guard_npm_public_cache.sh"
    guard_npm_public_cache
}
expect {
    -re {Type "npm"} { send "$answer\r"; exp_continue }
    timeout { exec kill [exp_pid]; exit 99 }
    eof {}
}
catch wait wait_result
exit [lindex \$wait_result 3]
EOF

    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_HOME" \
        CLEANUP_TEST_STATE="$STATE_DIR" \
        /usr/bin/expect -f "$expect_file" >"$STATE_DIR/output" 2>&1
}

# Case 1: without a TTY the guard fails closed with 78 before any npm call.
write_index 'make-fetch-happen:request-cache:https://registry.npmjs.org/left-pad'
set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_HOME" \
    CLEANUP_TEST_STATE="$STATE_DIR" /bin/bash -c '
    set -u
    source "'"$ROOT_DIR"'/lib/print_message.sh"
    source "'"$ROOT_DIR"'/lib/echo_info.sh"
    source "'"$ROOT_DIR"'/lib/echo_success.sh"
    source "'"$ROOT_DIR"'/lib/echo_warning.sh"
    source "'"$ROOT_DIR"'/lib/echo_error.sh"
    source "'"$ROOT_DIR"'/lib/echo_skip.sh"
    source "'"$ROOT_DIR"'/lib/command_exists.sh"
    source "'"$ROOT_DIR"'/cleanup/guard_npm_public_cache.sh"
    guard_npm_public_cache
' </dev/null >"$STATE_DIR/no-tty-output" 2>&1
NO_TTY_STATUS=$?
set -e
if [ "$NO_TTY_STATUS" -ne 78 ] || [ -s "$STATE_DIR/npm.log" ]; then
    echo "RED npm cache guard: non-TTY invocation did not fail closed with 78"
    exit 1
fi

# Case 2: a private-registry entry keeps the cache with status 20.
write_index 'make-fetch-happen:request-cache:https://npm.internal.example.com/secret-package'
set +e
run_guard_with_tty npm
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -ne 20 ] || grep -q 'cache clean' "$STATE_DIR/npm.log" 2>/dev/null; then
    echo "RED npm cache guard: a private-registry entry did not keep the cache"
    exit 1
fi

# Case 3: a userinfo authority keeps the cache with status 20.
write_index 'make-fetch-happen:request-cache:https://user:token@registry.npmjs.org/left-pad'
set +e
run_guard_with_tty npm
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -ne 20 ] || grep -q 'cache clean' "$STATE_DIR/npm.log" 2>/dev/null; then
    echo "RED npm cache guard: a credentialed authority did not keep the cache"
    exit 1
fi

# Case 4: a wrong confirmation keeps the cache with status 20.
write_index 'make-fetch-happen:request-cache:https://registry.npmjs.org/left-pad'
set +e
run_guard_with_tty wrong-answer
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -ne 20 ] || grep -q 'cache clean' "$STATE_DIR/npm.log" 2>/dev/null; then
    echo "RED npm cache guard: a wrong confirmation did not keep the cache"
    exit 1
fi

# Case 5: a fully public cache with the typed name runs the one allowed command.
set +e
run_guard_with_tty npm
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -ne 0 ] ||
    [ "$(cat "$STATE_DIR/npm.log" 2>/dev/null)" != "cache clean --force" ] ||
    ! grep -q 'npm_public_cache root=.*allocated_kib=' "$STATE_DIR/output"; then
    echo "RED npm cache guard: the public cache path did not run npm cache clean --force"
    exit 1
fi

# Case 6: a failing removal command propagates a nonzero status.
: >"$STATE_DIR/npm.log"
set +e
CLEANUP_TEST_NPM_STATUS=1 run_guard_with_tty npm
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -eq 0 ]; then
    echo "RED npm cache guard: a failed removal command was reported as success"
    exit 1
fi

# Case 7: a symlinked ~/.npm keeps the cache with status 20.
/bin/mv "$FIXTURE_HOME/.npm" "$FIXTURE_HOME/.npm-real"
/bin/ln -s "$FIXTURE_HOME/.npm-real" "$FIXTURE_HOME/.npm"
: >"$STATE_DIR/npm.log"
set +e
run_guard_with_tty npm
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -ne 20 ] || grep -q 'cache clean' "$STATE_DIR/npm.log" 2>/dev/null; then
    echo "RED npm cache guard: a symlinked npm root did not keep the cache"
    exit 1
fi

echo "npm cache guard contract passed"
