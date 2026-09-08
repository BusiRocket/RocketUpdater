#!/bin/bash

# Load average counts processes blocked on I/O, so a backup daemon pushes it
# over the CPU count while the machine is mostly idle. Degrading on that alone
# defers every plugin and makes the schedule inert. Measured idle decides.
#
# The load and the idle percentage arrive in the user's locale — "22,00", not
# "22.00" — which is what broke the comparison before: awk compared them as
# strings. The fixture emits the comma form on purpose.
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
vm.loadavg) printf '{ %s 18,00 17,00 }\n' "${FAKE_LOAD:-22,00}" ;;
hw.logicalcpu | hw.ncpu) printf '%s\n' "${FAKE_CPUS:-16}" ;;
*) printf '\n' ;;
esac
EOF

# `top -l 2` prints two samples; the fake does the same, and FAKE_TOP_MODE
# reproduces the two ways the real one can fail on a loaded machine.
cat >"$FIXTURE_DIR/bin/top" <<'EOF'
#!/bin/bash
case "${FAKE_TOP_MODE:-ok}" in
truncated)
    # Killed by the timeout after the first sample: that sample is the average
    # since boot, not an interval measurement.
    printf 'CPU usage: 5,00%% user, 2,00%% sys, 93,00%% idle\n'
    exit 124
    ;;
missing)
    exit 127
    ;;
*)
    printf 'CPU usage: 5,00%% user, 2,00%% sys, 93,00%% idle\n'
    printf 'CPU usage: 20,00%% user, 10,00%% sys, %s%% idle\n' "$FAKE_CPU_IDLE"
    ;;
esac
EOF
chmod +x "$FIXTURE_DIR/bin/sysctl" "$FIXTURE_DIR/bin/top"

sed -e "s#/usr/sbin/sysctl#$FIXTURE_DIR/bin/sysctl#g" \
    -e "s#/usr/bin/top#$FIXTURE_DIR/bin/top#g" \
    "$ROOT_DIR/lib/run_preflight.sh" >"$FIXTURE_DIR/run_preflight.sh"

read_gate() {
    FAKE_CPU_IDLE=$1 FAKE_LOAD=${2:-22,00} FAKE_CPUS=${3:-16} \
        FAKE_TOP_MODE=${4:-ok} RUN_ID=loadgate ROCKETUPDATER_EVENT_LOG="$FIXTURE_DIR/events.log" \
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
IDLE_OUTPUT=$(read_gate 75,00)
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
BUSY_OUTPUT=$(read_gate 0,0)
if ! printf '%s\n' "$BUSY_OUTPUT" | grep -q 'preflight_status=20'; then
    echo "RED preflight load gate: saturation must return the degraded status 20"
    exit 1
fi

# The comma is not cosmetic. With load "19,70" against 8 CPUs, comparing the
# raw strings gives "1" < "8" — under the old code the gate never fired at all
# on a machine whose locale prints a decimal comma, however saturated it was.
SPANISH_OUTPUT=$(read_gate 0,0 19,70 8)
if ! printf '%s\n' "$SPANISH_OUTPUT" | grep -q 'preflight_status=20'; then
    printf '%s\n' "$SPANISH_OUTPUT" | grep -E 'preflight (load|status)'
    echo "RED preflight load gate: a comma-decimal load was compared as a string"
    exit 1
fi

# A sampler that dies after its first sample must not hand the gate that
# sample: `top -l 2`'s first line is the average since boot, so a saturated
# machine that times out the sampler would read as 93% idle and run anyway.
TRUNCATED_OUTPUT=$(read_gate 0,0 22,00 16 truncated)
if ! printf '%s\n' "$TRUNCATED_OUTPUT" | grep -q 'preflight_status=20'; then
    printf '%s\n' "$TRUNCATED_OUTPUT" | grep -E 'preflight (load|status)'
    echo "RED preflight load gate: a truncated CPU sample was accepted as idle"
    exit 1
fi

if ! printf '%s\n' "$TRUNCATED_OUTPUT" | grep -q 'cpu_idle=unknown'; then
    echo "RED preflight load gate: a failed sampler must report cpu_idle=unknown"
    exit 1
fi

# No sampler at all: fall back to the load alone, which is the old behaviour.
MISSING_OUTPUT=$(read_gate 0,0 22,00 16 missing)
if ! printf '%s\n' "$MISSING_OUTPUT" | grep -q 'preflight_status=20'; then
    echo "RED preflight load gate: an unavailable sampler must fall back to degrading"
    exit 1
fi

echo "preflight load-gate contract passed"
