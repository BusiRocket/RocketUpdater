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

# Case 4: `du` errors on live container overlays are counted, not printed. A
# real run drowned in hundreds of "No such file or directory" lines.
mkdir -p "$FIXTURE_DIR/home/OrbStack/containers"
cat >"$FIXTURE_DIR/bin/du" <<'EOF'
#!/bin/bash
printf 'du: %s/containers/gone: No such file or directory\n' "$2" >&2
printf 'du: %s/containers/stale: Stale NFS file handle\n' "$2" >&2
printf '25G\t%s\n' "$2"
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/du"

: >"$STATE_DIR/docker.log"
set +e
run_report
REPORT_STATUS=$?
set -e

if [ "$REPORT_STATUS" -ne 0 ]; then
    cat "$STATE_DIR/output"
    echo "RED docker plugin: du errors made the report fail"
    exit 1
fi

if grep -q 'No such file or directory' "$STATE_DIR/output" ||
    grep -q 'Stale NFS file handle' "$STATE_DIR/output"; then
    echo "RED docker plugin: raw du errors reached the run output"
    exit 1
fi

if ! grep -q '2 paths under .* vanished while measuring' "$STATE_DIR/output"; then
    echo "RED docker plugin: the unreadable paths were not reported as a count"
    cat "$STATE_DIR/output"
    exit 1
fi

if ! grep -q '25G' "$STATE_DIR/output"; then
    echo "RED docker plugin: the measured size is missing from the report"
    exit 1
fi

# Case 5: a hung daemon must be given up on quickly. `docker info` has no
# connect timeout of its own; against a dead daemon it took 86 seconds before
# the plugin could skip, and a scheduled run paid that every night.
cat >"$FIXTURE_DIR/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/docker.log"
if [ "$*" = "info" ]; then
    sleep 120
fi
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/docker"

: >"$STATE_DIR/docker.log"
STARTED_AT=$(date +%s)
set +e
run_report
REPORT_STATUS=$?
set -e
ELAPSED=$(($(date +%s) - STARTED_AT))

if [ "$REPORT_STATUS" -ne 20 ]; then
    cat "$STATE_DIR/output"
    echo "RED docker plugin: a hung daemon did not skip with status 20"
    exit 1
fi

if [ "$ELAPSED" -gt 30 ]; then
    echo "RED docker plugin: the hung daemon was waited on for ${ELAPSED}s; it must be bounded"
    exit 1
fi

# Case 6: a permission or I/O failure is not container churn. Folding every du
# error into the "vanished" count hides a measurement that actually broke.
# Case 5 left behind a docker that hangs on `info`; restore a healthy one.
cat >"$FIXTURE_DIR/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/docker.log"
case "$*" in
'system df') printf 'TYPE TOTAL ACTIVE SIZE RECLAIMABLE\n' ;;
esac
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/docker"

cat >"$FIXTURE_DIR/bin/du" <<'EOF'
#!/bin/bash
printf 'du: %s/containers/gone: No such file or directory\n' "$2" >&2
printf 'du: %s/private: Permission denied\n' "$2" >&2
printf '25G\t%s\n' "$2"
exit 1
EOF
chmod +x "$FIXTURE_DIR/bin/du"

: >"$STATE_DIR/docker.log"
set +e
run_report
REPORT_STATUS=$?
set -e

if ! grep -q 'Permission denied' "$STATE_DIR/output"; then
    cat "$STATE_DIR/output"
    echo "RED docker plugin: a real du failure was hidden as ordinary churn"
    exit 1
fi

if ! grep -q '1 paths under .* vanished' "$STATE_DIR/output"; then
    cat "$STATE_DIR/output"
    echo "RED docker plugin: the transient errors were not counted separately"
    exit 1
fi

echo "docker plugin contract passed"
