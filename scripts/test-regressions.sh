#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"

cat >"$TMP_DIR/bin/npm" <<'EOF'
#!/bin/bash
if [ "$1" = "install" ] && [ "$2" = "-g" ] && [ "$3" = "npm@latest" ]; then
    exit 0
fi

if [ "$1" = "install" ] && [ "$2" = "-g" ] && [ "$3" = "badpkg@2.0.0" ]; then
    echo "simulated npm failure" >&2
    exit 1
fi

if [ "$1" = "cache" ]; then
    exit 0
fi

if [ "$1" = "outdated" ]; then
    exit 0
fi

exit 0
EOF

cat >"$TMP_DIR/bin/ncu" <<'EOF'
#!/bin/bash
printf ' badpkg  1.0.0  →  2.0.0\n'
EOF

cat >"$TMP_DIR/bin/git" <<'EOF'
#!/bin/bash
if [ "$1" = "diff" ]; then
    exit 1
fi

if [ "$1" = "ls-files" ]; then
    exit 0
fi

if [ "$1" = "stash" ] && [ "$2" = "push" ]; then
    echo "Saved working directory and index state WIP on main: RocketUpdater auto-stash"
    exit 0
fi

if [ "$1" = "pull" ]; then
    echo "Already up to date."
    exit 0
fi

if [ "$1" = "stash" ] && [ "$2" = "pop" ]; then
    echo "Dropped refs/stash@{0}"
    exit 0
fi

exit 0
EOF

chmod +x "$TMP_DIR/bin/npm" "$TMP_DIR/bin/ncu" "$TMP_DIR/bin/git"

NPM_OUTPUT="$TMP_DIR/npm-output.txt"
set +e
PATH="$TMP_DIR/bin:$PATH" "$ROOT_DIR/RocketUpdater.sh" npm >"$NPM_OUTPUT" 2>&1
NPM_EXIT_CODE=$?
set -e

if [ "$NPM_EXIT_CODE" -eq 0 ]; then
    echo "Expected npm plugin run to fail when a global package update fails"
    cat "$NPM_OUTPUT"
    exit 1
fi

grep -q "Failed to update global package: badpkg@2.0.0" "$NPM_OUTPUT"
grep -q "Command failed: update_npm" "$NPM_OUTPUT"

ZSH_DIR="$TMP_DIR/ohmyzsh"
mkdir -p "$ZSH_DIR/tools" "$ZSH_DIR/custom/themes/powerlevel10k/.git"

cat >"$ZSH_DIR/tools/upgrade.sh" <<'EOF'
#!/bin/zsh
exit 0
EOF

chmod +x "$ZSH_DIR/tools/upgrade.sh"

OMZSH_OUTPUT="$TMP_DIR/omzsh-output.txt"
set +e
PATH="$TMP_DIR/bin:$PATH" ZSH="$ZSH_DIR" "$ROOT_DIR/RocketUpdater.sh" omzsh >"$OMZSH_OUTPUT" 2>&1
OMZSH_EXIT_CODE=$?
set -e

if [ "$OMZSH_EXIT_CODE" -eq 0 ]; then
    :
else
    echo "Expected omzsh plugin run to succeed by stashing local changes first"
    cat "$OMZSH_OUTPUT"
    exit 1
fi

grep -q "Stashing local changes for powerlevel10k" "$OMZSH_OUTPUT"
grep -q "Restoring local changes for powerlevel10k" "$OMZSH_OUTPUT"
grep -q "Oh My Zsh update completed" "$OMZSH_OUTPUT"

echo "All regression checks passed."
