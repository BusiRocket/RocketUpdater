#!/bin/bash

# pip must never touch a package conda installed. On 2026-08-24 `pip-review
# --auto` in base replaced conda's pydantic-core 2.46.4 with 2.48.0, pydantic
# refused to import, and every conda command crashed from then on while the
# plugin kept reporting success. Only packages conda lists from the `pypi`
# channel may be upgraded with pip, and never in base, which is conda itself.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-conda.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/conda" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/conda.log"
case "$*" in
'env list')
    printf '# conda environments:\n#\nbase                 /x/base\nwork                 /x/envs/work\n'
    ;;
'list -n work')
    printf '# packages in environment at /x/envs/work:\n#\n# Name Version Build Channel\n'
    printf 'numpy                     2.3.0           py314_0    conda-forge\n'
    printf 'requests-oauth            1.2.0           pypi_0     pypi\n'
    ;;
'update -n base'*)
    [ -n "${PLUGIN_TEST_SELF_UPDATE_FAILS:-}" ] && exit 1
    ;;
esac
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/conda"

run_plugin() {
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" PLUGIN_TEST_STATE="$STATE_DIR" /bin/bash -c '
        set -u
        source "'"$ROOT_DIR"'/lib/print_message.sh"
        source "'"$ROOT_DIR"'/lib/echo_info.sh"
        source "'"$ROOT_DIR"'/lib/echo_success.sh"
        source "'"$ROOT_DIR"'/lib/echo_warning.sh"
        source "'"$ROOT_DIR"'/lib/echo_error.sh"
        source "'"$ROOT_DIR"'/lib/echo_skip.sh"
        source "'"$ROOT_DIR"'/plugins/conda.sh"
        get_latest_stable_python() { echo 3.14; }
        update_conda
    ' </dev/null >"$STATE_DIR/output" 2>&1
}

set +e
run_plugin
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
    cat "$STATE_DIR/output"
    echo "RED conda plugin: a healthy fixture did not succeed"
    exit 1
fi
if grep -q 'pip-review' "$STATE_DIR/conda.log"; then
    echo "RED conda plugin: pip-review still upgrades conda-managed packages"
    exit 1
fi
if grep -q -- '-n base pip' "$STATE_DIR/conda.log"; then
    echo "RED conda plugin: pip ran inside base"
    grep -- '-n base pip' "$STATE_DIR/conda.log"
    exit 1
fi
if ! grep -qx 'run -n work pip install --upgrade requests-oauth' "$STATE_DIR/conda.log"; then
    echo "RED conda plugin: the pypi-channel package was not upgraded with pip"
    cat "$STATE_DIR/conda.log"
    exit 1
fi
if grep -q 'pip install --upgrade.*numpy' "$STATE_DIR/conda.log"; then
    echo "RED conda plugin: pip upgraded a conda-forge package"
    exit 1
fi

: >"$STATE_DIR/conda.log"
set +e
PLUGIN_TEST_SELF_UPDATE_FAILS=1 run_plugin
STATUS=$?
set -e
if [ "$STATUS" -ne 1 ]; then
    cat "$STATE_DIR/output"
    echo "RED conda plugin: a failed conda self-update returned $STATUS instead of failing"
    exit 1
fi

echo "conda pip-boundary contract passed"
