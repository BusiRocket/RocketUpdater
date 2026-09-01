#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.runner-fixture-npm-integrity.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
GLOBAL_ROOT="$FIXTURE_DIR/lib/node_modules"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$GLOBAL_ROOT"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/npm" <<'EOF'
#!/bin/bash
if [ "$1 $2" = "root -g" ]; then
    printf '%s\n' "$NPM_TEST_GLOBAL_ROOT"
    exit 0
fi
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/npm"

write_package() {
    local package_name=$1
    local package_version=$2
    local bin_target=$3
    local package_dir="$GLOBAL_ROOT/$package_name"

    mkdir -p "$package_dir"
    cat >"$package_dir/package.json" <<EOF
{
  "name": "$package_name",
  "version": "$package_version",
  "bin": { "$(basename "$package_name")": "$bin_target" }
}
EOF
    mkdir -p "$package_dir/$(dirname "$bin_target")"
    printf '#!/usr/bin/env node\n' >"$package_dir/$bin_target"
}

take_snapshot() {
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" NPM_TEST_GLOBAL_ROOT="$GLOBAL_ROOT" /bin/bash -c '
        set -u
        source "'"$ROOT_DIR"'/lib/snapshot_global_npm_packages.sh"
        snapshot_global_npm_packages
    '
}

run_compare() {
    /bin/bash -c '
        set -u
        source "'"$ROOT_DIR"'/lib/compare_global_npm_snapshots.sh"
        compare_global_npm_snapshots "$@"
    ' compare "$(cat "$1")" "$(cat "$2")" "${3:-}"
}

write_package alpha 1.0.0 dist/index.js
write_package target 1.0.0 dist/index.js
write_package '@scope/tool' 2.0.0 bin/tool.js
take_snapshot >"$STATE_DIR/before"

if ! grep -q '^@scope/tool' "$STATE_DIR/before" || ! grep -q '^alpha' "$STATE_DIR/before"; then
    echo "RED npm integrity: the snapshot missed a scoped or unscoped package"
    exit 1
fi

# Case 1: a valid change to the exact selected target is allowed.
write_package target 2.0.0 dist/index.js
take_snapshot >"$STATE_DIR/after"
if ! run_compare "$STATE_DIR/before" "$STATE_DIR/after" target >"$STATE_DIR/verdict"; then
    cat "$STATE_DIR/verdict"
    echo "RED npm integrity: a valid selected-target change was reported as damage"
    exit 1
fi

# Case 2: an unrelated disappearance is a violation.
/bin/rm -rf -- "$GLOBAL_ROOT/alpha"
take_snapshot >"$STATE_DIR/after"
if run_compare "$STATE_DIR/before" "$STATE_DIR/after" target >"$STATE_DIR/verdict" ||
    ! grep -q 'package=alpha kind=disappeared' "$STATE_DIR/verdict"; then
    echo "RED npm integrity: an unrelated disappearance was not reported"
    exit 1
fi
write_package alpha 1.0.0 dist/index.js

# Case 3: a scoped package change outside the target is a violation.
write_package '@scope/tool' 3.0.0 bin/tool.js
take_snapshot >"$STATE_DIR/after"
if run_compare "$STATE_DIR/before" "$STATE_DIR/after" target >"$STATE_DIR/verdict" ||
    ! grep -q 'package=@scope/tool kind=changed' "$STATE_DIR/verdict"; then
    echo "RED npm integrity: a scoped-package change was not reported"
    exit 1
fi
write_package '@scope/tool' 2.0.0 bin/tool.js

# Case 4: a selected target with a missing declared bin is broken.
take_snapshot >"$STATE_DIR/before"
/bin/rm -f -- "$GLOBAL_ROOT/target/dist/index.js"
take_snapshot >"$STATE_DIR/after"
if run_compare "$STATE_DIR/before" "$STATE_DIR/after" target >"$STATE_DIR/verdict" ||
    ! grep -q 'package=target kind=broken-target' "$STATE_DIR/verdict"; then
    echo "RED npm integrity: a selected target with a missing bin was not reported"
    exit 1
fi
write_package target 2.0.0 dist/index.js

# Case 5: the real-world null-version residue (no package.json, no dist) is
# both visible in the snapshot and a broken selected target.
take_snapshot >"$STATE_DIR/before"
/bin/rm -rf -- "$GLOBAL_ROOT/target"
mkdir -p "$GLOBAL_ROOT/target/node_modules"
take_snapshot >"$STATE_DIR/after"
if ! grep -q "^target$(printf '\t')" "$STATE_DIR/after" ||
    ! awk -F '\t' '$1 == "target" && $3 == "missing" { found = 1 } END { exit !found }' \
        "$STATE_DIR/after"; then
    echo "RED npm integrity: the null-version residue fixture is invisible to the snapshot"
    exit 1
fi
if run_compare "$STATE_DIR/before" "$STATE_DIR/after" target >"$STATE_DIR/verdict" ||
    ! grep -q 'package=target kind=broken-target' "$STATE_DIR/verdict"; then
    echo "RED npm integrity: the null-version residue was not reported as a broken target"
    exit 1
fi
write_package target 2.0.0 dist/index.js

# Case 6: an unexpected appearance outside the target is a violation.
take_snapshot >"$STATE_DIR/before"
write_package intruder 1.0.0 dist/index.js
take_snapshot >"$STATE_DIR/after"
if run_compare "$STATE_DIR/before" "$STATE_DIR/after" target >"$STATE_DIR/verdict" ||
    ! grep -q 'package=intruder kind=appeared' "$STATE_DIR/verdict"; then
    echo "RED npm integrity: an unexpected appearance was not reported"
    exit 1
fi

# Case 7: a symlinked global root is rejected before any enumeration.
/bin/mv "$GLOBAL_ROOT" "$FIXTURE_DIR/lib/node_modules_real"
/bin/ln -s "$FIXTURE_DIR/lib/node_modules_real" "$GLOBAL_ROOT"
if take_snapshot >"$STATE_DIR/after" 2>/dev/null; then
    echo "RED npm integrity: a symlinked global root was accepted"
    exit 1
fi

echo "global npm integrity contract passed"
