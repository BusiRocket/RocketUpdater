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
    'rm -rf|rm -r |find .* -delete|find .* -exec .*rm|brew cleanup|npm cache (clean|verify)|clear-npx-cache|yarn cache clean|uv cache prune|pnpm store prune|pip3 cache purge|conda clean|composer clearcache|mo clean([^ -]|$)|docker (system|container|image|volume|network|builder) prune|sudo purge|softwareupdate -ia' \
    "$ROOT_DIR" -g '!tests/**' -g '!cleanup/guard_homebrew_cleanup.sh' -g '!cleanup/guard_npm_public_cache.sh' \
    -g '!cleanup/guard_sparkle_obsolete_installations.sh' | grep -q .; then
    echo "RED cleanup safety: destructive command remains outside the exact cleanup allowlist"
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
