#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-omzsh.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
ZSH_DIR="$FIXTURE_DIR/ohmyzsh"
PLUGIN_REPO="$ZSH_DIR/custom/plugins/zsh-autosuggestions"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$ZSH_DIR/tools" "$PLUGIN_REPO/.git"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$ZSH_DIR/tools/upgrade.sh" <<'EOF'
#!/bin/zsh
exit 0
EOF
chmod +x "$ZSH_DIR/tools/upgrade.sh"

# git pull fails with a dropped TLS handshake until the configured attempt,
# reproducing the transient github.com failure seen in a real run.
cat >"$FIXTURE_DIR/bin/git" <<'EOF'
#!/bin/bash
case "$1" in
diff) exit 0 ;;
ls-files) exit 0 ;;
pull)
    attempt=$(cat "$PLUGIN_TEST_STATE/pull-attempts" 2>/dev/null || printf 0)
    attempt=$((attempt + 1))
    printf '%s\n' "$attempt" >"$PLUGIN_TEST_STATE/pull-attempts"
    if [ "$attempt" -lt "${OMZSH_TEST_SUCCEED_ON:-1}" ]; then
        echo "fatal: unable to access 'https://github.com/zsh-users/zsh-autosuggestions/': LibreSSL SSL_connect: SSL_ERROR_SYSCALL in connection to github.com:443" >&2
        exit 1
    fi
    echo "Already up to date."
    exit 0
    ;;
esac
exit 0
EOF
cat >"$FIXTURE_DIR/bin/zsh" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/git" "$FIXTURE_DIR/bin/zsh"

run_plugin() {
    : >"$STATE_DIR/pull-attempts"
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" \
        ZSH="$1" PLUGIN_TEST_STATE="$STATE_DIR" OMZSH_RETRY_DELAY_SECONDS=0 \
        /bin/bash -c '
        set -u
        source "'"$ROOT_DIR"'/lib/print_message.sh"
        source "'"$ROOT_DIR"'/lib/echo_info.sh"
        source "'"$ROOT_DIR"'/lib/echo_success.sh"
        source "'"$ROOT_DIR"'/lib/echo_warning.sh"
        source "'"$ROOT_DIR"'/lib/echo_error.sh"
        source "'"$ROOT_DIR"'/lib/echo_skip.sh"
        source "'"$ROOT_DIR"'/lib/command_exists.sh"
        source "'"$ROOT_DIR"'/plugins/omzsh.sh"
        update_omzsh
    ' >"$STATE_DIR/output" 2>&1
}

# Case 1: an absent Oh My Zsh skips with 20, not 0.
set +e
run_plugin "$FIXTURE_DIR/absent"
STATUS=$?
set -e
if [ "$STATUS" -ne 20 ]; then
    echo "RED omzsh: an absent Oh My Zsh did not skip with status 20"
    exit 1
fi

# Case 2: a transient TLS failure that clears on the second attempt must not
# fail the run.
set +e
OMZSH_TEST_SUCCEED_ON=2 run_plugin "$ZSH_DIR"
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ]; then
    cat "$STATE_DIR/output"
    echo "RED omzsh: a transient git failure was not retried into success"
    exit 1
fi
if ! grep -q 'retrying in' "$STATE_DIR/output"; then
    echo "RED omzsh: the retry was silent"
    exit 1
fi

# Case 3: a remote that stays unreachable still fails, after bounded attempts.
set +e
OMZSH_TEST_SUCCEED_ON=99 run_plugin "$ZSH_DIR"
STATUS=$?
set -e
if [ "$STATUS" -ne 1 ]; then
    echo "RED omzsh: a permanently unreachable remote did not fail the plugin"
    exit 1
fi
if [ "$(cat "$STATE_DIR/pull-attempts")" != 3 ]; then
    echo "RED omzsh: the retry count is not bounded at three attempts"
    exit 1
fi

echo "omzsh plugin contract passed"
