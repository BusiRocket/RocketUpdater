#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

FIXTURE_DIR=$(runner_fixture_create "$ROOT_DIR" "scheduled-safety")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$STATE_DIR"
trap 'runner_fixture_cleanup "$FIXTURE_DIR"' EXIT

for command_name in rm find brew npm docker mo softwareupdate npx yarn uv pnpm pip3; do
    cat >"$FIXTURE_DIR/bin/$command_name" <<EOF
#!/bin/bash
printf '%s %s\\n' "$command_name" "\$*" >>"$STATE_DIR/commands.log"
exit 0
EOF
    chmod +x "$FIXTURE_DIR/bin/$command_name"
done

cat >"$FIXTURE_DIR/plugins/a_removals.sh" <<'EOF'
PLUGIN_NAME="Removal fixture"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=report

update_a_removals() {
    rm -rf "$HOME/fixture-removal"
    find "$HOME" -name fixture -delete
    find "$HOME" -name fixture -exec rm -rf {} \;
}

report_a_removals() {
    printf 'report a_removals\n'
}
EOF

cat >"$FIXTURE_DIR/plugins/b_cache_cleanup.sh" <<'EOF'
PLUGIN_NAME="Cache cleanup fixture"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=20
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=report

update_b_cache_cleanup() {
    brew cleanup --prune=all
    npm cache clean --force
    npx -y clear-npx-cache
    yarn cache clean
    uv cache prune
    pnpm store prune
    pip3 cache purge
    mo clean
}

report_b_cache_cleanup() {
    printf 'report b_cache_cleanup\n'
}
EOF

cat >"$FIXTURE_DIR/plugins/c_docker_cleanup.sh" <<'EOF'
PLUGIN_NAME="Docker cleanup fixture"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=30
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=report

update_c_docker_cleanup() {
    docker container prune -f
    docker image prune -a -f
    docker volume prune -f
    docker network prune -f
    docker builder prune -f
}

report_c_docker_cleanup() {
    printf 'report c_docker_cleanup\n'
}
EOF

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" RUNNER_TEST_STATE="$STATE_DIR" \
    /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" --scheduled >"$STATE_DIR/output" 2>&1
RUNNER_STATUS=$?
set -e

if [ "$RUNNER_STATUS" -ne 0 ] || ! grep -q 'report a_removals' "$STATE_DIR/output" ||
    ! grep -q 'report b_cache_cleanup' "$STATE_DIR/output" || ! grep -q 'report c_docker_cleanup' "$STATE_DIR/output"; then
    echo "RED scheduled safety: --scheduled does not dispatch report actions"
    exit 1
fi

if [ -s "$STATE_DIR/sudo.log" ]; then
    echo "RED scheduled safety: scheduled mode attempted sudo capability discovery"
    exit 1
fi

if [ -f "$STATE_DIR/commands.log" ] &&
    grep -Eq '^(rm|find) |^brew cleanup|^npm cache clean|^npx .*clear-npx-cache|^yarn cache clean|^uv cache prune|^pnpm store prune|^pip3 cache purge|^mo clean|^docker .*prune' "$STATE_DIR/commands.log"; then
    echo "RED scheduled safety: a destructive update command was reachable from --scheduled"
    exit 1
fi

echo "scheduled safety contract passed"
