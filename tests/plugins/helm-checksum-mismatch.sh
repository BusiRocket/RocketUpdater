#!/bin/bash

# An installed binary that is not the release it claims to be is the only thing
# this verification exists to catch, so it has to fail the plugin rather than
# warn. It also has to say both hashes: a mismatch nobody can reproduce by hand
# is a report nobody will act on. Updates run unattended, so the mismatching
# binary also goes to the Trash before anyone can run it.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/lib/helm_plugin_release_source.sh"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-helm-mismatch.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

PLUGIN_VERSION_UNDER_TEST=3.15.12
RELEASE_RECORD=$(helm_plugin_release_source diff "$PLUGIN_VERSION_UNDER_TEST") || {
    echo "SKIP helm checksum mismatch: this platform has no known helm-diff release asset"
    exit 0
}
IFS=$'\t' read -r REPOSITORY ARCHIVE_ASSET CHECKSUMS_ASSET ARCHIVE_MEMBER <<<"$RELEASE_RECORD"

PLUGINS_ROOT="$FIXTURE_DIR/plugins"
RELEASE_DIR="$FIXTURE_DIR/release/$REPOSITORY/releases/download/v$PLUGIN_VERSION_UNDER_TEST"
CACHE_DIR="$FIXTURE_DIR/cache"
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$PLUGINS_ROOT/helm-diff/bin" "$RELEASE_DIR" \
    "$CACHE_DIR" "$STATE_DIR" "$FIXTURE_DIR/stage/$(dirname "$ARCHIVE_MEMBER")"

printf 'genuine helm-diff binary\n' >"$FIXTURE_DIR/stage/$ARCHIVE_MEMBER"
# The archive and its checksum are internally consistent; what is installed is
# not what they describe. That is the shape of a tampered or half-finished
# install-binary.sh run.
printf 'something else entirely\n' >"$PLUGINS_ROOT/helm-diff/bin/diff"

cat >"$PLUGINS_ROOT/helm-diff/plugin.yaml" <<EOF
name: diff
version: "$PLUGIN_VERSION_UNDER_TEST"
EOF

tar -czf "$RELEASE_DIR/$ARCHIVE_ASSET" -C "$FIXTURE_DIR/stage" "$ARCHIVE_MEMBER"
(cd "$RELEASE_DIR" && shasum -a 256 "$ARCHIVE_ASSET" >"$CHECKSUMS_ASSET")

cat >"$FIXTURE_DIR/bin/helm" <<EOF
#!/bin/bash
case "\$1 \$2" in
"plugin list")
    printf 'NAME\tVERSION\tTYPE\n'
    printf 'diff\t%s\tcli/v1\n' "$PLUGIN_VERSION_UNDER_TEST"
    ;;
"env HELM_PLUGINS") printf '"%s"\n' "$PLUGINS_ROOT" ;;
esac
exit 0
EOF
cat >"$FIXTURE_DIR/bin/fake-trash" <<EOF
#!/bin/bash
for path in "\$@"; do
    printf '%s\n' "\$path" >>"$STATE_DIR/trashed.log"
    /bin/mv -- "\$path" "$STATE_DIR/trashed-binary"
done
EOF
chmod +x "$FIXTURE_DIR/bin/"*
INSTALLED_DIGEST=$(shasum -a 256 "$PLUGINS_ROOT/helm-diff/bin/diff" | awk '{ print $1 }')

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" \
    ROCKETUPDATER_HELM_RELEASE_BASE_URL="file://$FIXTURE_DIR/release" \
    ROCKETUPDATER_HELM_CACHE_DIR="$CACHE_DIR" \
    ROCKETUPDATER_TRASH_COMMAND="$FIXTURE_DIR/bin/fake-trash" \
    /bin/bash -c '
    set -u
    source "'"$ROOT_DIR"'/lib/print_message.sh"
    source "'"$ROOT_DIR"'/lib/echo_info.sh"
    source "'"$ROOT_DIR"'/lib/echo_success.sh"
    source "'"$ROOT_DIR"'/lib/echo_warning.sh"
    source "'"$ROOT_DIR"'/lib/echo_error.sh"
    source "'"$ROOT_DIR"'/lib/echo_skip.sh"
    source "'"$ROOT_DIR"'/lib/echo_note.sh"
    source "'"$ROOT_DIR"'/lib/echo_change.sh"
    source "'"$ROOT_DIR"'/lib/command_exists.sh"
    source "'"$ROOT_DIR"'/lib/helm_plugin_release_source.sh"
    source "'"$ROOT_DIR"'/lib/helm_reference_digest.sh"
    source "'"$ROOT_DIR"'/lib/find_helm_plugin_directory.sh"
    source "'"$ROOT_DIR"'/lib/classify_helm_plugin_binary.sh"
    source "'"$ROOT_DIR"'/lib/quarantine_helm_plugin_binary.sh"
    source "'"$ROOT_DIR"'/plugins/helm.sh"
    update_helm
' </dev/null >"$STATE_DIR/output" 2>&1
PLUGIN_STATUS=$?
set -e

if [ "$PLUGIN_STATUS" -eq 0 ]; then
    cat "$STATE_DIR/output"
    echo "RED helm checksum mismatch: the plugin passed an installed binary that is not the release"
    exit 1
fi

REFERENCE_DIGEST=$(shasum -a 256 "$FIXTURE_DIR/stage/$ARCHIVE_MEMBER" | awk '{ print $1 }')
for expected_digest in "$INSTALLED_DIGEST" "$REFERENCE_DIGEST"; do
    if ! grep -qF "$expected_digest" "$STATE_DIR/output"; then
        cat "$STATE_DIR/output"
        echo "RED helm checksum mismatch: $expected_digest was not reported, so nobody can reproduce the finding"
        exit 1
    fi
done

if grep -q 'matches the published release' "$STATE_DIR/output"; then
    cat "$STATE_DIR/output"
    echo "RED helm checksum mismatch: a mismatching binary was also reported as verified"
    exit 1
fi

if [ -e "$PLUGINS_ROOT/helm-diff/bin/diff" ] ||
    [ "$(cat "$STATE_DIR/trashed.log" 2>/dev/null)" != "$PLUGINS_ROOT/helm-diff/bin/diff" ]; then
    cat "$STATE_DIR/output"
    echo "RED helm checksum mismatch: the mismatching binary stayed runnable instead of going to the Trash"
    exit 1
fi

echo "helm checksum mismatch contract passed"
