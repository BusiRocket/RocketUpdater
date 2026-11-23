#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/runner/test-support.bash"

EXPECTED_GUARDS="guard_homebrew_cleanup guard_npm_public_cache guard_sparkle_obsolete_installations"
for guard_name in $EXPECTED_GUARDS; do
    if [ ! -f "$ROOT_DIR/cleanup/$guard_name.sh" ]; then
        echo "RED cleanup safety: missing allowlisted cleanup guard $guard_name"
        exit 1
    fi
done

if find "$ROOT_DIR/cleanup" -type f -name '*.sh' -print | sed 's#.*/##; s#\.sh$##' | sort | tr '\n' ' ' | grep -qv "^$EXPECTED_GUARDS $"; then
    echo "RED cleanup safety: cleanup allowlist contains an unreviewed guard"
    exit 1
fi

if rg -n --glob '*.sh' \
    'rm -rf|rm -r |find .* -delete|find .* -exec .*rm|brew cleanup|npm cache (clean|verify)|clear-npx-cache|yarn cache clean|uv cache prune|pnpm store prune|pip3 cache purge|conda clean|composer clearcache|mo clean( +[^ -]|[^ -]|$)|docker (system|container|image|volume|network|builder) prune|sudo purge|softwareupdate -ia' \
    "$ROOT_DIR" -g '!tests/**' -g '!cleanup/guard_homebrew_cleanup.sh' -g '!cleanup/guard_npm_public_cache.sh' \
    -g '!cleanup/guard_sparkle_obsolete_installations.sh' -g '!plugins/mole.sh' \
    -g '!plugins/uvcache.sh' -g '!plugins/pnpmstore.sh' -g '!plugins/condacache.sh' | grep -q .; then
    echo "RED cleanup safety: destructive command remains outside the exact cleanup allowlist"
    exit 1
fi

# Cleanup families the first pattern never knew. Each one is allowed only in
# the plugin that owns it, under the contract checked below.
if rg -n --glob '*.sh' \
    'deno clean|/usr/bin/trash|-exec trash|clear-cache|bun pm cache rm|go clean|gem cleanup|brew autoremove *($|2>|;|&&|[|])|hf cache (rm|prune)' \
    "$ROOT_DIR" -g '!tests/**' -g '!plugins/deno.sh' -g '!plugins/yarnmetadata.sh' \
    -g '!plugins/dartanalysis.sh' -g '!plugins/pear.sh' \
    -g '!lib/quarantine_helm_plugin_binary.sh' | grep -q .; then
    echo "RED cleanup safety: a cleanup command appeared outside the plugin that owns it"
    exit 1
fi

# The owner asked for scheduled runs to clean everything that rebuilds itself
# (2026-11-23), so these run unattended. Each may only use its tool's own
# conservative command; the flags that widen them stay forbidden.
if ! rg -q 'prune_output=\$\(UV_LOCK_TIMEOUT=[0-9]+ uv cache prune 2>&1\)' "$ROOT_DIR/plugins/uvcache.sh" ||
    rg -q -- 'uv cache (clean|prune.*--(force|ci))' "$ROOT_DIR/plugins/uvcache.sh"; then
    echo "RED cleanup safety: uvcache must run a plain, lock-respecting uv cache prune"
    exit 1
fi
if [ "$(rg -c 'pnpm store prune' "$ROOT_DIR/plugins/pnpmstore.sh")" != 3 ] ||
    ! rg -q 'if ! pnpm store prune 2>&1; then' "$ROOT_DIR/plugins/pnpmstore.sh" ||
    rg -q 'store/v(10|3)|store prune.*--force' "$ROOT_DIR/plugins/pnpmstore.sh"; then
    echo "RED cleanup safety: pnpmstore must prune only the active store with pnpm's own command"
    exit 1
fi
if ! rg -q 'conda clean --tarballs --index-cache --yes' "$ROOT_DIR/plugins/condacache.sh" ||
    rg -q -- 'conda clean.*(--packages|--all|--force-pkgs-dirs| -a\b)' "$ROOT_DIR/plugins/condacache.sh"; then
    echo "RED cleanup safety: condacache may remove only archives and the index cache"
    exit 1
fi
if ! sed -n '/^update_deno()/,/^}/p' "$ROOT_DIR/plugins/deno.sh" | rg -q 'originStorage' ||
    [ "$(sed -n '/originStorage/,/^}/p' "$ROOT_DIR/plugins/deno.sh" | rg -c '^\s+if ! deno clean 2>&1; then')" != 1 ]; then
    echo "RED cleanup safety: deno clean must follow the origin storage check"
    exit 1
fi
# The literal \$HOME is the source text being matched, not this shell's home.
for aged_plugin in yarnmetadata:\$HOME/.yarn/berry/metadata dartanalysis:\$HOME/.dartServer/.analysis-driver; do
    aged_file="$ROOT_DIR/plugins/${aged_plugin%%:*}.sh"
    if ! rg -qF "${aged_plugin#*:}" "$aged_file" ||
        [ "$(rg -c -- '-xdev -type f -mtime \+30 -exec "\$trash_command" \{\} \+' "$aged_file")" != 1 ] ||
        ! rg -qF 'trash_command=${ROCKETUPDATER_TRASH_COMMAND:-/usr/bin/trash}' "$aged_file" ||
        rg -q '\brm\b' "$aged_file"; then
        echo "RED cleanup safety: ${aged_plugin%%:*} must move only files older than 30 days to the Trash"
        exit 1
    fi
done

# The owner asked for a manual run to clean with Mole (2026-10-11), so the one
# real `mo clean` lives in the plugin's manual entry point. Scheduled runs call
# report_mole, which must stay dry-run only.
if [ "$(rg -c 'mo clean( +[^ -]|[^ -]|$)' "$ROOT_DIR/plugins/mole.sh")" != 1 ] ||
    ! sed -n '/^update_mole()/,/^}/p' "$ROOT_DIR/plugins/mole.sh" | rg -q 'mo clean </dev/null' ||
    sed -n '/^report_mole()/,/^}/p' "$ROOT_DIR/plugins/mole.sh" | rg -q 'mo clean( +[^ -]|[^ -]|$)' ||
    ! rg -q '^PLUGIN_SCHEDULE_ACTION=report$' "$ROOT_DIR/plugins/mole.sh"; then
    echo "RED cleanup safety: a real mo clean is reachable outside the manual update_mole"
    exit 1
fi

for guard_name in $EXPECTED_GUARDS; do
    guard_file="$ROOT_DIR/cleanup/$guard_name.sh"
    if ! rg -q -- '-t 0|-t 1|NONINTERACTIVE|ROCKETUPDATER_LAUNCHD|read -r' "$guard_file"; then
        echo "RED cleanup safety: $guard_name lacks TTY/manual confirmation enforcement"
        exit 1
    fi
done

if ! rg -q '\$HOME/Library/Caches/Homebrew|/var/homebrew/tmp|site-packages/__pycache__|cleanup -n --prune=all' \
    "$ROOT_DIR/cleanup/guard_homebrew_cleanup.sh" ||
    ! rg -q 'registry\.npmjs\.org|_cacache|npm cache clean --force' "$ROOT_DIR/cleanup/guard_npm_public_cache.sh" ||
    ! rg -q 'Installation|PersistentDownloads|pgrep|obsolete' "$ROOT_DIR/cleanup/guard_sparkle_obsolete_installations.sh"; then
    echo "RED cleanup safety: guards do not prove exact roots, provenance, and stopped-obsolete candidates"
    exit 1
fi

FIXTURE_DIR=$(runner_fixture_create "$ROOT_DIR" "cleanup-safety")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$STATE_DIR"
trap 'runner_fixture_cleanup "$FIXTURE_DIR"' EXIT

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" NONINTERACTIVE=1 RUNNER_TEST_STATE="$STATE_DIR" \
    /bin/bash "$FIXTURE_DIR/RocketUpdater.sh" --clean homebrew >"$STATE_DIR/output" 2>&1
CLEAN_STATUS=$?
set -e

if [ "$CLEAN_STATUS" -ne 78 ]; then
    echo "RED cleanup safety: --clean noninteractive mode did not fail closed with status 78"
    exit 1
fi

echo "cleanup safety contract passed"
