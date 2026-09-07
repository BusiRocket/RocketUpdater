#!/bin/bash

# A manual run over ssh has no terminal, so it cannot prompt — but `sudo -n`
# never prompts, it fails. On a host with a NOPASSWD rule (the Mac mini) the
# grant must therefore still be used: the early return made PEAR fail there on
# root-owned files under /opt/homebrew/share/pear.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

FIXTURE_DIR=$(runner_fixture_create "$ROOT_DIR" "sudo-nopasswd")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$STATE_DIR"
trap 'runner_fixture_cleanup "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/plugins/probe.sh" <<'EOF'
PLUGIN_NAME="Probe"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_probe() {
    printf 'SUDO_AVAILABLE=%s\n' "${SUDO_AVAILABLE:-unset}"
}
EOF

run_probe() {
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" \
        RUNNER_TEST_STATE="$STATE_DIR" \
        /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" probe </dev/null >"$STATE_DIR/output" 2>&1
}

# Case 1: sudo needs a password. With no terminal there is nothing to type into,
# so the run says so and continues unprivileged.
cat >"$FIXTURE_DIR/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$RUNNER_TEST_STATE/sudo.log"
printf 'sudo: a password is required\n' >&2
exit 1
EOF
chmod +x "$FIXTURE_DIR/bin/sudo"

set +e
run_probe
PROBE_STATUS=$?
set -e

if [ "$PROBE_STATUS" -ne 0 ]; then
    cat "$STATE_DIR/output"
    echo "RED sudo nopasswd: a password-only sudo did not finish the run"
    exit 1
fi

if ! grep -q 'SUDO_AVAILABLE=false' "$STATE_DIR/output" ||
    ! grep -q 'No terminal available for a sudo prompt' "$STATE_DIR/output"; then
    cat "$STATE_DIR/output"
    echo "RED sudo nopasswd: a password-only sudo was not reported as no grant"
    exit 1
fi

# Case 2: NOPASSWD. `sudo -n true` succeeds without a prompt, so the privileged
# paths stay enabled even though stdin is not a terminal.
: >"$STATE_DIR/sudo.log"
cat >"$FIXTURE_DIR/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$RUNNER_TEST_STATE/sudo.log"
[ "$1" = "-n" ] && shift
[ "$1" = "-v" ] && exit 0
exec "$@"
EOF
chmod +x "$FIXTURE_DIR/bin/sudo"

set +e
run_probe
PROBE_STATUS=$?
set -e

if [ "$PROBE_STATUS" -ne 0 ]; then
    cat "$STATE_DIR/output"
    echo "RED sudo nopasswd: a passwordless sudo did not finish the run"
    exit 1
fi

if ! grep -q 'SUDO_AVAILABLE=true' "$STATE_DIR/output"; then
    cat "$STATE_DIR/output"
    echo "RED sudo nopasswd: a passwordless grant was not used without a terminal"
    exit 1
fi

# It must never prompt: only the non-interactive forms may be called.
if grep -qvE '^-n ' "$STATE_DIR/sudo.log"; then
    echo "RED sudo nopasswd: sudo was called in a form that can prompt"
    cat "$STATE_DIR/sudo.log"
    exit 1
fi

echo "sudo nopasswd contract passed"
