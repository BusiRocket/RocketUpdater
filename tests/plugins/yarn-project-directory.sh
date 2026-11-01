#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-yarn-project.XXXXXX")
mkdir -p "$FIXTURE_DIR/bin" "$FIXTURE_DIR/home" "$FIXTURE_DIR/pnpm-project"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

# Corepack refuses to run yarn inside a project whose package.json pins
# another package manager. The updater is often launched from such a checkout,
# so the version probe has to run from $HOME, where nothing is pinned.
cat >"$FIXTURE_DIR/bin/yarn" <<'FAKE'
#!/bin/bash
if [ "$PWD" != "$HOME" ]; then
    printf 'This project is configured to use pnpm because %s/package.json has a "packageManager" field\n' "$PWD"
    exit 1
fi
printf '4.14.1\n'
FAKE
cat >"$FIXTURE_DIR/bin/corepack" <<'FAKE'
#!/bin/bash
[ "$PWD" = "$HOME" ] || { printf 'corepack ran inside %s\n' "$PWD"; exit 1; }
FAKE
chmod +x "$FIXTURE_DIR/bin/yarn" "$FIXTURE_DIR/bin/corepack"

set +e
OUTPUT=$(cd "$FIXTURE_DIR/pnpm-project" && PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" /bin/bash -c '
    set -u
    source "'"$ROOT_DIR"'/lib/print_message.sh"
    source "'"$ROOT_DIR"'/lib/echo_info.sh"
    source "'"$ROOT_DIR"'/lib/echo_success.sh"
    source "'"$ROOT_DIR"'/lib/echo_warning.sh"
    source "'"$ROOT_DIR"'/lib/echo_error.sh"
    source "'"$ROOT_DIR"'/lib/echo_skip.sh"
    source "'"$ROOT_DIR"'/lib/command_exists.sh"
    source "'"$ROOT_DIR"'/plugins/yarn.sh"
    update_yarn
' 2>&1)
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
    echo "RED yarn plugin: launched from a pnpm project it returned $STATUS"
    printf '%s\n' "$OUTPUT"
    exit 1
fi
if ! printf '%s\n' "$OUTPUT" | grep -q 'Detected version 4.x'; then
    echo "RED yarn plugin: the version was not read from \$HOME"
    exit 1
fi

echo "yarn project-directory contract passed"
