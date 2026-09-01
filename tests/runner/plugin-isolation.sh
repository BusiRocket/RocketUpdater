#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

FIXTURE_DIR=$(runner_fixture_create "$ROOT_DIR" "plugin-isolation")
STATE_DIR="$FIXTURE_DIR/state"
EXPECTED_CWD="$(pwd -P)"
mkdir -p "$STATE_DIR"
trap 'runner_fixture_cleanup "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/plugins/a_exit9.sh" <<'EOF'
PLUGIN_NAME="Exit 9"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_a_exit9() {
    exit 9
}
EOF

cat >"$FIXTURE_DIR/plugins/b_exit_trap.sh" <<'EOF'
PLUGIN_NAME="Exit trap"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=20
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_b_exit_trap() {
    trap 'printf trapped >>"$RUNNER_TEST_STATE/trap"' EXIT
    printf 'trap fixture ran\n'
}
EOF

cat >"$FIXTURE_DIR/plugins/c_change_directory.sh" <<'EOF'
PLUGIN_NAME="Change directory"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=30
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_c_change_directory() {
    cd /
    pwd
}
EOF

cat >"$FIXTURE_DIR/plugins/d_disable_errexit.sh" <<'EOF'
PLUGIN_NAME="Disable errexit"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=40
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_d_disable_errexit() {
    set +e
    false
    printf 'errexit fixture ran\n'
}
EOF

cat >"$FIXTURE_DIR/plugins/e_verify_parent_cwd.sh" <<'EOF'
PLUGIN_NAME="Verify parent cwd"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=50
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_e_verify_parent_cwd() {
    pwd -P >"$RUNNER_TEST_STATE/later-cwd"
}
EOF

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" RUNNER_TEST_STATE="$STATE_DIR" \
    /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" >"$STATE_DIR/output" 2>&1
RUNNER_STATUS=$?
set -e

if ! grep -q 'UPDATE SUMMARY' "$STATE_DIR/output"; then
    echo "RED plugin isolation: exit 9 terminated the parent before its summary"
    exit 1
fi

if ! grep -q 'trap fixture ran' "$STATE_DIR/output" || ! grep -q 'errexit fixture ran' "$STATE_DIR/output"; then
    echo "RED plugin isolation: one fixture mutated the parent before later fixtures ran"
    exit 1
fi

if [ "$(cat "$STATE_DIR/trap" 2>/dev/null || true)" != "trapped" ]; then
    echo "RED plugin isolation: EXIT trap did not remain confined to its child"
    exit 1
fi

if [ "$(cat "$STATE_DIR/later-cwd" 2>/dev/null || true)" != "$EXPECTED_CWD" ]; then
    echo "RED plugin isolation: cd / leaked into later plugin execution"
    exit 1
fi

if [ "$RUNNER_STATUS" -ne 1 ]; then
    echo "RED plugin isolation: exit 9 was not aggregated as one failed plugin"
    exit 1
fi

echo "plugin isolation contract passed"
