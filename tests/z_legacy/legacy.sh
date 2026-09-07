#!/bin/bash

set -euo pipefail

# Legacy compatibility checks retained after the focused runner contracts.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TMP_DIR="$(mktemp -d "$ROOT_DIR/.regression-fixture.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/home" "$TMP_DIR/global-root"

cat >"$TMP_DIR/bin/npm" <<EOF
#!/bin/bash
if [ "\$1" = "root" ]; then
    echo "$TMP_DIR/global-root"
    exit 0
fi

if [ "\$1" = "install" ] && [ "\$2" = "-g" ] && [ "\$3" = "npm@latest" ]; then
    exit 0
fi

if [ "\$1" = "install" ] && [ "\$2" = "-g" ] && [ "\$3" = "badpkg@2.0.0" ]; then
    echo "simulated npm failure" >&2
    exit 1
fi

if [ "\$1" = "cache" ]; then
    exit 0
fi

if [ "\$1" = "outdated" ]; then
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
PATH="$TMP_DIR/bin:$PATH" HOME="$TMP_DIR/home" "$ROOT_DIR/RocketUpdater.sh" npm </dev/null >"$NPM_OUTPUT" 2>&1
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
PATH="$TMP_DIR/bin:$PATH" HOME="$TMP_DIR/home" ZSH="$ZSH_DIR" "$ROOT_DIR/RocketUpdater.sh" omzsh </dev/null >"$OMZSH_OUTPUT" 2>&1
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

# A plugin that consumes stdin must not truncate the plugin list. Reading the
# list on stdin let brew upgrade (shelling out to npm install) swallow the
# remaining plugin names, ending the run after the first plugin.
FAKE_ROOT="$TMP_DIR/fake"
mkdir -p "$FAKE_ROOT/plugins"
cp "$ROOT_DIR/RocketUpdater.sh" "$FAKE_ROOT/"
cp -R "$ROOT_DIR/lib" "$FAKE_ROOT/"
cp -R "$ROOT_DIR/scripts" "$FAKE_ROOT/"

cat >"$FAKE_ROOT/plugins/greedy.sh" <<'EOF'
PLUGIN_NAME="Greedy"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=10
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_greedy() {
    if read -r line; then
        echo "greedy plugin read: $line"
    else
        echo "greedy plugin saw EOF"
    fi
}
EOF

cat >"$FAKE_ROOT/plugins/tail_end.sh" <<'EOF'
PLUGIN_NAME="Tail end"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=90
PLUGIN_TIMEOUT_SECONDS=30
PLUGIN_SCHEDULE_ACTION=run

update_tail_end() {
    echo "tail_end plugin ran"
}
EOF

# Feed the run real data on stdin: a plugin must see EOF regardless, both so it
# cannot consume the plugin list and so it cannot block on a prompt.
STDIN_OUTPUT="$TMP_DIR/stdin-output.txt"
set +e
printf 'sentinel\n' | HOME="$TMP_DIR/home" "$FAKE_ROOT/RocketUpdater.sh" >"$STDIN_OUTPUT" 2>&1
STDIN_EXIT_CODE=$?
set -e

if [ "$STDIN_EXIT_CODE" -ne 0 ]; then
    echo "Expected the run to succeed when a plugin consumes stdin"
    cat "$STDIN_OUTPUT"
    exit 1
fi

if ! grep -q "tail_end plugin ran" "$STDIN_OUTPUT"; then
    echo "A plugin consuming stdin truncated the plugin list"
    cat "$STDIN_OUTPUT"
    exit 1
fi

if grep -q "greedy plugin read: sentinel" "$STDIN_OUTPUT"; then
    echo "A plugin was handed the run's stdin and could block on a prompt"
    cat "$STDIN_OUTPUT"
    exit 1
fi

grep -q "greedy plugin saw EOF" "$STDIN_OUTPUT"
grep -q "Successful: 2" "$STDIN_OUTPUT"

# Lower PLUGIN_PRIORITY runs first, regardless of alphabetical order.
grep -q "Order: greedy tail_end" "$STDIN_OUTPUT"

# The Corepack yarn shim asks on stdin before fetching the pinned release, and
# writes that prompt to stderr where the plugin discards it, so the run blocked
# forever with no output. The plugin must disable the prompt. This stand-in
# fails fast instead of blocking: a test that reproduced the real hang would
# hang the suite rather than fail it.
cat >"$TMP_DIR/bin/yarn" <<'EOF'
#!/bin/bash
if [ "${COREPACK_ENABLE_DOWNLOAD_PROMPT:-1}" != "0" ]; then
    echo "! Corepack is about to download https://repo.yarnpkg.com/4.18.0/yarn.js" >&2
    exit 1
fi

echo "4.12.0"
EOF

cat >"$TMP_DIR/bin/corepack" <<'EOF'
#!/bin/bash
echo "Preparing yarn@stable for immediate activation..."
EOF

chmod +x "$TMP_DIR/bin/yarn" "$TMP_DIR/bin/corepack"

YARN_OUTPUT="$TMP_DIR/yarn-output.txt"
set +e
PATH="$TMP_DIR/bin:$PATH" HOME="$TMP_DIR/home" "$ROOT_DIR/RocketUpdater.sh" yarn </dev/null >"$YARN_OUTPUT" 2>&1
YARN_EXIT_CODE=$?
set -e

if [ "$YARN_EXIT_CODE" -ne 0 ]; then
    echo "Expected the yarn plugin to succeed against a Corepack-style shim"
    cat "$YARN_OUTPUT"
    exit 1
fi

if ! grep -q "Detected version 4.x" "$YARN_OUTPUT"; then
    echo "Yarn version probe did not disable the Corepack download prompt"
    cat "$YARN_OUTPUT"
    exit 1
fi

grep -q "Yarn update completed" "$YARN_OUTPUT"

# Name the subcommand, so an assertion can tell "pear upgrade actually ran
# unprivileged" apart from "some other pear subcommand ran". `list` must return
# a real package table: the plugin upgrades packages one by one, so an empty
# listing would mean no upgrade is attempted at all.
cat >"$TMP_DIR/bin/pear" <<'EOF'
#!/bin/bash
if [ "$1" = "list" ]; then
    cat <<'LIST'
INSTALLED PACKAGES, CHANNEL PEAR.PHP.NET:
=========================================
PACKAGE          VERSION STATE
Archive_Tar      1.6.0   stable
LIST
    exit 0
fi
echo "unprivileged pear $1 completed"
EOF

cat >"$TMP_DIR/bin/pecl" <<'EOF'
#!/bin/bash
echo "unprivileged pecl $1 completed"
EOF

chmod +x "$TMP_DIR/bin/pear" "$TMP_DIR/bin/pecl"

# Case 1: root was never granted. Without a terminal there is nothing to type a
# password into, so the run must say so and fall back to unprivileged upgrades
# rather than prompting, blocking or skipping the work.
cat >"$TMP_DIR/bin/sudo" <<'EOF'
#!/bin/bash
echo "sudo: a password is required" >&2
exit 1
EOF

chmod +x "$TMP_DIR/bin/sudo"

PEAR_OUTPUT="$TMP_DIR/pear-nosudo.txt"
set +e
PATH="$TMP_DIR/bin:$PATH" HOME="$TMP_DIR/home" "$ROOT_DIR/RocketUpdater.sh" pear </dev/null >"$PEAR_OUTPUT" 2>&1
PEAR_EXIT_CODE=$?
set -e

if [ "$PEAR_EXIT_CODE" -ne 0 ]; then
    echo "Expected the pear plugin to succeed with no sudo available"
    cat "$PEAR_OUTPUT"
    exit 1
fi

grep -q "No terminal available for a sudo prompt" "$PEAR_OUTPUT"
grep -q "PEAR/PECL update completed" "$PEAR_OUTPUT"

# Case 2: root was granted, but the privileged command fails anyway. Each step
# must report the failure and retry the same command unprivileged. A non-TTY
# run never holds a grant since the mode-aware sudo split, so the plugin is
# driven directly with SUDO_AVAILABLE=true.
cat >"$TMP_DIR/bin/sudo" <<'EOF'
#!/bin/bash
echo "sudo: unable to execute the requested command" >&2
exit 1
EOF

chmod +x "$TMP_DIR/bin/sudo"

PEAR_FALLBACK_OUTPUT="$TMP_DIR/pear-fallback.txt"
set +e
PATH="$TMP_DIR/bin:$PATH" HOME="$TMP_DIR/home" SUDO_AVAILABLE=true /bin/bash -c '
    set -u
    source "'"$ROOT_DIR"'/lib/print_message.sh"
    source "'"$ROOT_DIR"'/lib/echo_info.sh"
    source "'"$ROOT_DIR"'/lib/echo_success.sh"
    source "'"$ROOT_DIR"'/lib/echo_warning.sh"
    source "'"$ROOT_DIR"'/lib/echo_error.sh"
    source "'"$ROOT_DIR"'/lib/echo_skip.sh"
    source "'"$ROOT_DIR"'/lib/command_exists.sh"
    source "'"$ROOT_DIR"'/plugins/pear.sh"
    update_pear
' </dev/null >"$PEAR_FALLBACK_OUTPUT" 2>&1
PEAR_FALLBACK_EXIT_CODE=$?
set -e

if [ "$PEAR_FALLBACK_EXIT_CODE" -ne 0 ]; then
    echo "Expected the pear plugin to fall back when the privileged command fails"
    cat "$PEAR_FALLBACK_OUTPUT"
    exit 1
fi

if ! grep -q "retrying without sudo" "$PEAR_FALLBACK_OUTPUT"; then
    echo "A failing privileged pear command did not fall back to an unprivileged retry"
    cat "$PEAR_FALLBACK_OUTPUT"
    exit 1
fi

if ! grep -q "unprivileged pear upgrade completed" "$PEAR_FALLBACK_OUTPUT"; then
    echo "The unprivileged retry of 'pear upgrade' never ran"
    cat "$PEAR_FALLBACK_OUTPUT"
    exit 1
fi

# The reason the privileged attempt failed must reach the log. Without it,
# "retrying without sudo" looks the same whether sudo was refused, the ticket
# expired, or the command itself errored, and the run cannot be diagnosed.
if ! grep -q "sudo: unable to execute the requested command" "$PEAR_FALLBACK_OUTPUT"; then
    echo "The privileged failure was reported without saying why"
    cat "$PEAR_FALLBACK_OUTPUT"
    exit 1
fi

grep -q "PEAR/PECL update completed" "$PEAR_FALLBACK_OUTPUT"

# Case 3: the upgrade genuinely fails. The plugin must report failure so the
# summary cannot claim success while "ERROR: commit failed" is on screen.
cat >"$TMP_DIR/bin/pear" <<'EOF'
#!/bin/bash
if [ "$1" = "list" ]; then
    cat <<'LIST'
INSTALLED PACKAGES, CHANNEL PEAR.PHP.NET:
=========================================
PACKAGE          VERSION STATE
Archive_Tar      1.6.0   stable
LIST
    exit 0
fi

if [ "$1" = "upgrade" ]; then
    echo "ERROR: commit failed"
    exit 1
fi

echo "unprivileged pear $1 completed"
EOF

chmod +x "$TMP_DIR/bin/pear"

PEAR_FAIL_OUTPUT="$TMP_DIR/pear-fail.txt"
set +e
PATH="$TMP_DIR/bin:$PATH" HOME="$TMP_DIR/home" "$ROOT_DIR/RocketUpdater.sh" pear </dev/null >"$PEAR_FAIL_OUTPUT" 2>&1
PEAR_FAIL_EXIT_CODE=$?
set -e

if [ "$PEAR_FAIL_EXIT_CODE" -eq 0 ]; then
    echo "A failed pear upgrade was reported as a successful run"
    cat "$PEAR_FAIL_OUTPUT"
    exit 1
fi

grep -q "PEAR/PECL update finished with failed upgrades" "$PEAR_FAIL_OUTPUT"
grep -q "Command failed: update_pear" "$PEAR_FAIL_OUTPUT"

echo "All regression checks passed."
