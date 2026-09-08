#!/bin/bash

# Load average counts processes blocked on I/O, so a backup daemon pushes it
# over the CPU count while the machine is mostly idle. Degrading on that alone
# defers every plugin and makes the schedule inert. Measured idle decides.
#
# The production file calls /usr/sbin/sysctl and /usr/bin/top by absolute path,
# which is right for a launchd job and impossible to fake through PATH, so the
# copy under test has those two paths rewritten to the fixture's fakes. What is
# exercised is the decision, not the lookup.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.runner-fixture-loadgate.XXXXXX")
mkdir -p "$FIXTURE_DIR/bin"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/sysctl" <<'EOF'
#!/bin/bash
case "$2" in
vm.loadavg) printf '{ 22.00 18.00 17.00 }\n' ;;
hw.logicalcpu | hw.ncpu) printf '16\n' ;;
*) printf '\n' ;;
esac
EOF

cat >"$FIXTURE_DIR/bin/top" <<'EOF'
#!/bin/bash
printf 'CPU usage: 20.00%% user, 10.00%% sys, %s%% idle\n' "$FAKE_CPU_IDLE"
EOF
chmod +x "$FIXTURE_DIR/bin/sysctl" "$FIXTURE_DIR/bin/top"

sed -e "s#/usr/sbin/sysctl#$FIXTURE_DIR/bin/sysctl#g" \
    -e "s#/usr/bin/top#$FIXTURE_DIR/bin/top#g" \
    "$ROOT_DIR/lib/run_preflight.sh" >"$FIXTURE_DIR/run_preflight.sh"

read_gate() {
    FAKE_CPU_IDLE=$1 RUN_ID=loadgate ROCKETUPDATER_EVENT_LOG="$FIXTURE_DIR/events.log" \
        /bin/bash -c '
        set -u
        source "'"$ROOT_DIR"'/lib/print_message.sh"
        source "'"$ROOT_DIR"'/lib/echo_info.sh"
        source "'"$ROOT_DIR"'/lib/echo_success.sh"
        source "'"$ROOT_DIR"'/lib/echo_warning.sh"
        source "'"$ROOT_DIR"'/lib/echo_error.sh"
        source "'"$ROOT_DIR"'/lib/echo_skip.sh"
        source "'"$ROOT_DIR"'/lib/log_event.sh"
        source "'"$ROOT_DIR"'/lib/command_exists.sh"
        source "'"$FIXTURE_DIR"'/run_preflight.sh"
        run_preflight manual
        printf "preflight_status=%s\n" "$?"
    ' 2>&1
}

# An I/O-bound machine: load 22 on 16 CPUs, but 75% idle. Not degraded.
IDLE_OUTPUT=$(read_gate 75.00)
if ! printf '%s\n' "$IDLE_OUTPUT" | grep -q 'preflight_status=0'; then
    printf '%s\n' "$IDLE_OUTPUT" | grep -E 'preflight (load|status)'
    echo "RED preflight load gate: an idle machine was degraded on load average alone"
    exit 1
fi

if ! printf '%s\n' "$IDLE_OUTPUT" | grep -q 'cpu_idle=75.00'; then
    echo "RED preflight load gate: the measured idle is not reported"
    exit 1
fi

# A genuinely saturated machine: load 22 and 0% idle. Degraded, as before.
BUSY_OUTPUT=$(read_gate 0.0)
if ! printf '%s\n' "$BUSY_OUTPUT" | grep -q 'preflight_status=20'; then
    echo "RED preflight load gate: saturation must return the degraded status 20"
    exit 1
fi

echo "preflight load-gate contract passed"
