#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

PRODUCTION_OSX_PLUGIN="$ROOT_DIR/plugins/osx.sh"
PRODUCTION_SUDO_COUNT=$(rg -c '(^|[[:space:]])sudo([[:space:]]|$)' "$PRODUCTION_OSX_PLUGIN" 2>/dev/null || true)

if [ "$PRODUCTION_SUDO_COUNT" != 1 ] ||
    ! rg -q '^[[:space:]]*sudo -n /usr/sbin/softwareupdate -d -r[[:space:]]*$' "$PRODUCTION_OSX_PLUGIN"; then
    echo "RED sudo mode: production osx plugin must contain only sudo -n /usr/sbin/softwareupdate -d -r"
    exit 1
fi

FIXTURE_DIR=$(runner_fixture_create "$ROOT_DIR" "sudo-mode")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$STATE_DIR"
trap 'runner_fixture_cleanup "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$RUNNER_TEST_STATE/sudo.log"
if [ "$1" = "-n" ]; then
    shift
fi
"$@"
EOF

cat >"$FIXTURE_DIR/bin/softwareupdate" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$RUNNER_TEST_STATE/softwareupdate.log"
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/sudo" "$FIXTURE_DIR/bin/softwareupdate"

cat >"$FIXTURE_DIR/plugins/osx.sh" <<'EOF'
PLUGIN_NAME="OSX"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_osx() {
    sudo -n softwareupdate -d -r
}
EOF

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" RUNNER_TEST_STATE="$STATE_DIR" \
    /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" --scheduled osx >"$STATE_DIR/output" 2>&1
RUNNER_STATUS=$?
set -e

if [ "$RUNNER_STATUS" -ne 0 ] || [ "$(cat "$STATE_DIR/sudo.log" 2>/dev/null || true)" != "-n softwareupdate -d -r" ] ||
    [ "$(cat "$STATE_DIR/softwareupdate.log" 2>/dev/null || true)" != "-d -r" ]; then
    echo "RED sudo mode: scheduled execution did not restrict sudo to softwareupdate -d -r"
    exit 1
fi

echo "scheduled sudo-mode contract passed"
