#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

FAILURE_DIR=$(runner_fixture_create "$ROOT_DIR" "metadata-top-level-failure")
APPEND_DIR=$(runner_fixture_create "$ROOT_DIR" "metadata-top-level-append")
VALID_DIR=$(runner_fixture_create "$ROOT_DIR" "metadata-valid-once")
CLOSURE_DIR=$(runner_fixture_create "$ROOT_DIR" "metadata-comment-closure")
ZERO_DIR=$(runner_fixture_create "$ROOT_DIR" "metadata-zero-timeout")
UNSUPPORTED_CLOSURE_DIR=$(runner_fixture_create "$ROOT_DIR" "metadata-unsupported-closure")
FAILURE_STATE="$FAILURE_DIR/state"
APPEND_STATE="$APPEND_DIR/state"
VALID_STATE="$VALID_DIR/state"
CLOSURE_STATE="$CLOSURE_DIR/state"
ZERO_STATE="$ZERO_DIR/state"
UNSUPPORTED_CLOSURE_STATE="$UNSUPPORTED_CLOSURE_DIR/state"
mkdir -p "$FAILURE_STATE" "$APPEND_STATE" "$VALID_STATE" "$CLOSURE_STATE" "$ZERO_STATE" "$UNSUPPORTED_CLOSURE_STATE"
trap 'runner_fixture_cleanup "$FAILURE_DIR"; runner_fixture_cleanup "$APPEND_DIR"; runner_fixture_cleanup "$VALID_DIR"; runner_fixture_cleanup "$CLOSURE_DIR"; runner_fixture_cleanup "$ZERO_DIR"; runner_fixture_cleanup "$UNSUPPORTED_CLOSURE_DIR"' EXIT

cat >"$FAILURE_DIR/plugins/top_level_failure.sh" <<'EOF'
PLUGIN_NAME="Invalid failure"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run
false

update_top_level_failure() {
    return 0
}
EOF

cat >"$APPEND_DIR/plugins/top_level_append.sh" <<'EOF'
PLUGIN_NAME="Invalid append"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run
printf 'executed\n' >>"$RUNNER_TEST_STATE/top-level-sentinel"

update_top_level_append() {
    return 0
}
EOF

cat >"$VALID_DIR/plugins/valid_once.sh" <<'EOF'
PLUGIN_NAME="Valid once"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_valid_once() {
    printf 'executed\n' >>"$RUNNER_TEST_STATE/function-sentinel"
}
EOF

cat >"$CLOSURE_DIR/plugins/comment_closure.sh" <<'EOF'
PLUGIN_NAME="Comment closure"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_comment_closure() {
    return 0
} # valid Bash function closure
printf 'executed\n' >>"$RUNNER_TEST_STATE/top-level-sentinel"

later_helper() {
    return 0
}
EOF

create_zero_timeout_plugin() {
    local plugin_name=$1
    local timeout_value=$2

    cat >"$ZERO_DIR/plugins/$plugin_name.sh" <<EOF
PLUGIN_NAME="$plugin_name"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=$timeout_value
PLUGIN_SCHEDULE_ACTION=run

update_$plugin_name() {
    return 0
}
EOF
}

create_zero_timeout_plugin timeout_zero_0 0
create_zero_timeout_plugin timeout_zero_00 00
create_zero_timeout_plugin timeout_zero_000 000

create_unsupported_closure_plugin() {
    local plugin_name=$1
    local closure=$2

    cat >"$UNSUPPORTED_CLOSURE_DIR/plugins/$plugin_name.sh" <<EOF
PLUGIN_NAME="$plugin_name"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_$plugin_name() {
    return 0
$closure
:
printf 'executed\n' >>"\$RUNNER_TEST_STATE/$plugin_name-sentinel"

later_${plugin_name}_helper() {
    return 0
}
EOF
}

create_unsupported_closure_plugin closure_semicolon '};'
create_unsupported_closure_plugin closure_and '}&&'
create_unsupported_closure_plugin closure_or '} ||'

set +e
PATH="$FAILURE_DIR/bin:/usr/bin:/bin" HOME="$FAILURE_DIR/home" RUNNER_TEST_STATE="$FAILURE_STATE" \
    /bin/bash "$FAILURE_DIR/RocketUpdater.sh" top_level_failure >"$FAILURE_STATE/output" 2>&1
FAILURE_STATUS=$?
PATH="$APPEND_DIR/bin:/usr/bin:/bin" HOME="$APPEND_DIR/home" RUNNER_TEST_STATE="$APPEND_STATE" \
    /bin/bash "$APPEND_DIR/RocketUpdater.sh" top_level_append >"$APPEND_STATE/output" 2>&1
APPEND_STATUS=$?
PATH="$VALID_DIR/bin:/usr/bin:/bin" HOME="$VALID_DIR/home" RUNNER_TEST_STATE="$VALID_STATE" \
    /bin/bash "$VALID_DIR/RocketUpdater.sh" valid_once >"$VALID_STATE/output" 2>&1
VALID_STATUS=$?
PATH="$CLOSURE_DIR/bin:/usr/bin:/bin" HOME="$CLOSURE_DIR/home" RUNNER_TEST_STATE="$CLOSURE_STATE" \
    /bin/bash "$CLOSURE_DIR/RocketUpdater.sh" comment_closure >"$CLOSURE_STATE/output" 2>&1
CLOSURE_STATUS=$?
PATH="$ZERO_DIR/bin:/usr/bin:/bin" HOME="$ZERO_DIR/home" RUNNER_TEST_STATE="$ZERO_STATE" \
    /bin/bash "$ZERO_DIR/RocketUpdater.sh" timeout_zero_0 >"$ZERO_STATE/zero.out" 2>&1
ZERO_STATUS=$?
PATH="$ZERO_DIR/bin:/usr/bin:/bin" HOME="$ZERO_DIR/home" RUNNER_TEST_STATE="$ZERO_STATE" \
    /bin/bash "$ZERO_DIR/RocketUpdater.sh" timeout_zero_00 >"$ZERO_STATE/double-zero.out" 2>&1
DOUBLE_ZERO_STATUS=$?
PATH="$ZERO_DIR/bin:/usr/bin:/bin" HOME="$ZERO_DIR/home" RUNNER_TEST_STATE="$ZERO_STATE" \
    /bin/bash "$ZERO_DIR/RocketUpdater.sh" timeout_zero_000 >"$ZERO_STATE/triple-zero.out" 2>&1
TRIPLE_ZERO_STATUS=$?
PATH="$UNSUPPORTED_CLOSURE_DIR/bin:/usr/bin:/bin" HOME="$UNSUPPORTED_CLOSURE_DIR/home" \
    RUNNER_TEST_STATE="$UNSUPPORTED_CLOSURE_STATE" /bin/bash "$UNSUPPORTED_CLOSURE_DIR/RocketUpdater.sh" \
    closure_semicolon >"$UNSUPPORTED_CLOSURE_STATE/semicolon.out" 2>&1
SEMICOLON_CLOSURE_STATUS=$?
PATH="$UNSUPPORTED_CLOSURE_DIR/bin:/usr/bin:/bin" HOME="$UNSUPPORTED_CLOSURE_DIR/home" \
    RUNNER_TEST_STATE="$UNSUPPORTED_CLOSURE_STATE" /bin/bash "$UNSUPPORTED_CLOSURE_DIR/RocketUpdater.sh" \
    closure_and >"$UNSUPPORTED_CLOSURE_STATE/and.out" 2>&1
AND_CLOSURE_STATUS=$?
PATH="$UNSUPPORTED_CLOSURE_DIR/bin:/usr/bin:/bin" HOME="$UNSUPPORTED_CLOSURE_DIR/home" \
    RUNNER_TEST_STATE="$UNSUPPORTED_CLOSURE_STATE" /bin/bash "$UNSUPPORTED_CLOSURE_DIR/RocketUpdater.sh" \
    closure_or >"$UNSUPPORTED_CLOSURE_STATE/or.out" 2>&1
OR_CLOSURE_STATUS=$?
set -e

if [ "$FAILURE_STATUS" -ne 78 ] || [ "$APPEND_STATUS" -ne 78 ] || [ -e "$APPEND_STATE/top-level-sentinel" ] ||
    [ "$VALID_STATUS" -ne 0 ] || [ "$(wc -l <"$VALID_STATE/function-sentinel" 2>/dev/null || printf '0')" -ne 1 ] ||
    [ "$CLOSURE_STATUS" -ne 78 ] || [ -e "$CLOSURE_STATE/top-level-sentinel" ] ||
    [ "$ZERO_STATUS" -ne 78 ] || [ "$DOUBLE_ZERO_STATUS" -ne 78 ] || [ "$TRIPLE_ZERO_STATUS" -ne 78 ] ||
    [ "$SEMICOLON_CLOSURE_STATUS" -ne 78 ] || [ "$AND_CLOSURE_STATUS" -ne 78 ] || [ "$OR_CLOSURE_STATUS" -ne 78 ] ||
    [ -e "$UNSUPPORTED_CLOSURE_STATE/closure_semicolon-sentinel" ] ||
    [ -e "$UNSUPPORTED_CLOSURE_STATE/closure_and-sentinel" ] ||
    [ -e "$UNSUPPORTED_CLOSURE_STATE/closure_or-sentinel" ]; then
    echo "RED metadata/source count: invalid plugins are not independently rejected before execution and valid plugins are not sourced exactly once"
    exit 1
fi

echo "metadata/source-count contract passed"
