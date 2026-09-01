#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-docker.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/docker.log"
case "$*" in
'info') exit "${DOCKER_TEST_INFO_STATUS:-0}" ;;
'system df')
    printf 'TYPE TOTAL ACTIVE SIZE RECLAIMABLE\n'
    exit "${DOCKER_TEST_DF_STATUS:-0}"
    ;;
esac
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/docker"

run_report() {
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" \
        PLUGIN_TEST_STATE="$STATE_DIR" /bin/bash -c '
        set -u
        source "'"$ROOT_DIR"'/lib/print_message.sh"
        source "'"$ROOT_DIR"'/lib/echo_info.sh"
        source "'"$ROOT_DIR"'/lib/echo_success.sh"
        source "'"$ROOT_DIR"'/lib/echo_warning.sh"
        source "'"$ROOT_DIR"'/lib/echo_error.sh"
        source "'"$ROOT_DIR"'/lib/echo_skip.sh"
        source "'"$ROOT_DIR"'/lib/command_exists.sh"
        source "'"$ROOT_DIR"'/plugins/docker.sh"
        report_docker
    ' >"$STATE_DIR/output" 2>&1
}

# Case 1: an unavailable daemon skips with status 20.
set +e
DOCKER_TEST_INFO_STATUS=1 run_report
REPORT_STATUS=$?
set -e
if [ "$REPORT_STATUS" -ne 20 ]; then
    echo "RED docker plugin: a down daemon did not skip with status 20"
    exit 1
fi

# Case 2: a healthy daemon produces a successful report with no removal argv.
: >"$STATE_DIR/docker.log"
set +e
run_report
REPORT_STATUS=$?
set -e
if [ "$REPORT_STATUS" -ne 0 ] || ! grep -q '^system df$' "$STATE_DIR/docker.log"; then
    echo "RED docker plugin: the report did not run docker system df successfully"
    exit 1
fi
if grep -Eq 'prune|rm |rmi' "$STATE_DIR/docker.log"; then
    echo "RED docker plugin: the report reached a removal command"
    exit 1
fi

# Case 3: a failing report command returns 1.
: >"$STATE_DIR/docker.log"
set +e
DOCKER_TEST_DF_STATUS=1 run_report
REPORT_STATUS=$?
set -e
if [ "$REPORT_STATUS" -ne 1 ]; then
    echo "RED docker plugin: a failed report command was not returned as 1"
    exit 1
fi

echo "docker plugin contract passed"
