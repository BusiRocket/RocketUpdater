#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-yarn.XXXXXX")
mkdir -p "$FIXTURE_DIR/bin" "$FIXTURE_DIR/home"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

# A Corepack shim that cannot fetch its pinned release prints only to stderr.
cat >"$FIXTURE_DIR/bin/yarn" <<'FAKE'
#!/bin/bash
printf 'Internal Error: could not fetch yarn@4.12.0\n' >&2
exit 1
FAKE
chmod +x "$FIXTURE_DIR/bin/yarn"

set +e
OUTPUT=$(PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" /bin/bash -c '
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

if [ "$STATUS" -ne 1 ]; then
    echo "RED yarn plugin: an unreadable version returned $STATUS instead of failing"
    exit 1
fi
if printf '%s\n' "$OUTPUT" | grep -q 'Detected version \.x'; then
    echo "RED yarn plugin: an empty version was reported as .x"
    exit 1
fi
if ! printf '%s\n' "$OUTPUT" | grep -q 'could not fetch yarn'; then
    echo "RED yarn plugin: the reason yarn gave was discarded"
    exit 1
fi

echo "yarn version contract passed"
