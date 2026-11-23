#!/bin/bash

# Each installed Node major moves to its newest release with the globals carried
# over, and the release it replaced is uninstalled unless an nvm alias pins it.
# A failed install fails the plugin instead of reporting the majors current.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/plugins/plugin-test-support.bash"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-nodeversions.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT
export HOME="$FIXTURE_DIR/home"
export NVM_DIR="$HOME/.nvm"
mkdir -p "$FIXTURE_DIR/bin" "$NVM_DIR/alias" "$NVM_DIR/versions/node/v22.1.0" "$NVM_DIR/versions/node/v24.1.0"

cat >"$NVM_DIR/nvm.sh" <<'EOF'
nvm() {
    printf 'nvm %s\n' "$*" >>"$NVM_DIR/nvm.log"
    case $1 in
    version) cat "$NVM_DIR/current-$2" ;;
    install)
        [ -n "${PLUGIN_TEST_INSTALL_FAILS:-}" ] && return 3
        [ -f "$NVM_DIR/next-$2" ] && cp "$NVM_DIR/next-$2" "$NVM_DIR/current-$2"
        return 0
        ;;
    esac
    return 0
}
EOF

reset_fixture() {
    printf 'v22.1.0\n' >"$NVM_DIR/current-22"
    printf 'v22.2.0\n' >"$NVM_DIR/next-22"
    printf 'v24.1.0\n' >"$NVM_DIR/current-24"
    printf '24\n' >"$NVM_DIR/alias/default"
    : >"$NVM_DIR/nvm.log"
}

reset_fixture
set +e
run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/nodeversions.sh" update_nodeversions "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ] ||
    ! grep -qx 'nvm install 22 --reinstall-packages-from=v22.1.0 --no-progress' "$NVM_DIR/nvm.log" ||
    ! grep -qx 'nvm uninstall v22.1.0' "$NVM_DIR/nvm.log" ||
    grep -q 'nvm uninstall v24' "$NVM_DIR/nvm.log"; then
    cat "$FIXTURE_DIR/output" "$NVM_DIR/nvm.log"
    echo "RED nodeversions: majors were not updated with only the superseded release removed ($STATUS)"
    exit 1
fi

reset_fixture
printf 'v22.1.0\n' >"$NVM_DIR/alias/legacy"
run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/nodeversions.sh" update_nodeversions "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
if grep -q 'nvm uninstall' "$NVM_DIR/nvm.log"; then
    echo "RED nodeversions: a release an alias pins was uninstalled"
    exit 1
fi
/bin/rm -f "$NVM_DIR/alias/legacy"

reset_fixture
set +e
PLUGIN_TEST_INSTALL_FAILS=1 run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/nodeversions.sh" update_nodeversions "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
STATUS=$?
set -e
if [ "$STATUS" -ne 1 ] || grep -q 'nvm uninstall' "$NVM_DIR/nvm.log"; then
    cat "$FIXTURE_DIR/output"
    echo "RED nodeversions: a failed install returned $STATUS or still uninstalled a release"
    exit 1
fi

echo "nodeversions plugin contract passed"
