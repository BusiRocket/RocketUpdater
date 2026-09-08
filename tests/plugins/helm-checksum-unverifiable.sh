#!/bin/bash

# An archive that fails its published checksum must never become the reference:
# accepting it would launder a bad download into a "verified" verdict on every
# later run, because the reference is cached. It must also not be extracted, and
# it must not fail the plugin — a corrupt or unreachable download says nothing
# about the installed file, and treating the two alike is how a verification
# step turns into noise nobody reads.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/lib/helm_plugin_release_source.sh"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-helm-unverifiable.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

PLUGIN_VERSION_UNDER_TEST=3.15.12
RELEASE_RECORD=$(helm_plugin_release_source diff "$PLUGIN_VERSION_UNDER_TEST") || {
    echo "SKIP helm checksum unverifiable: this platform has no known helm-diff release asset"
    exit 0
}
IFS=$'\t' read -r REPOSITORY ARCHIVE_ASSET CHECKSUMS_ASSET ARCHIVE_MEMBER <<<"$RELEASE_RECORD"

PLUGINS_ROOT="$FIXTURE_DIR/plugins"
RELEASE_DIR="$FIXTURE_DIR/release/$REPOSITORY/releases/download/v$PLUGIN_VERSION_UNDER_TEST"
CACHE_DIR="$FIXTURE_DIR/cache"
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$PLUGINS_ROOT/helm-diff/bin" "$RELEASE_DIR" \
    "$CACHE_DIR" "$STATE_DIR" "$FIXTURE_DIR/stage/$(dirname "$ARCHIVE_MEMBER")"

printf 'attacker payload\n' >"$FIXTURE_DIR/stage/$ARCHIVE_MEMBER"
cp "$FIXTURE_DIR/stage/$ARCHIVE_MEMBER" "$PLUGINS_ROOT/helm-diff/bin/diff"

cat >"$PLUGINS_ROOT/helm-diff/plugin.yaml" <<EOF
name: diff
version: "$PLUGIN_VERSION_UNDER_TEST"
EOF

tar -czf "$RELEASE_DIR/$ARCHIVE_ASSET" -C "$FIXTURE_DIR/stage" "$ARCHIVE_MEMBER"
# The published checksum is for the release the project actually built, not for
# the archive that arrived. The installed binary matches the arrived archive, so
# skipping the checksum step would report "verified".
printf '%064d  %s\n' 0 "$ARCHIVE_ASSET" >"$RELEASE_DIR/$CHECKSUMS_ASSET"

cat >"$FIXTURE_DIR/bin/helm" <<EOF
#!/bin/bash
case "\$1 \$2" in
"plugin list")
    printf 'NAME\tVERSION\tTYPE\n'
    printf 'diff\t%s\tcli/v1\n' "$PLUGIN_VERSION_UNDER_TEST"
    printf 'someone-elses-plugin\t1.0.0\tcli/v1\n'
    ;;
"env HELM_PLUGINS") printf '"%s"\n' "$PLUGINS_ROOT" ;;
esac
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/"*

set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" \
    ROCKETUPDATER_HELM_RELEASE_BASE_URL="file://$FIXTURE_DIR/release" \
    ROCKETUPDATER_HELM_CACHE_DIR="$CACHE_DIR" \
    /bin/bash -c '
    set -u
    source "'"$ROOT_DIR"'/lib/print_message.sh"
    source "'"$ROOT_DIR"'/lib/echo_info.sh"
    source "'"$ROOT_DIR"'/lib/echo_success.sh"
    source "'"$ROOT_DIR"'/lib/echo_warning.sh"
    source "'"$ROOT_DIR"'/lib/echo_error.sh"
    source "'"$ROOT_DIR"'/lib/echo_skip.sh"
    source "'"$ROOT_DIR"'/lib/command_exists.sh"
    source "'"$ROOT_DIR"'/lib/helm_plugin_release_source.sh"
    source "'"$ROOT_DIR"'/lib/helm_reference_digest.sh"
    source "'"$ROOT_DIR"'/lib/find_helm_plugin_directory.sh"
    source "'"$ROOT_DIR"'/lib/classify_helm_plugin_binary.sh"
    source "'"$ROOT_DIR"'/plugins/helm.sh"
    update_helm
' </dev/null >"$STATE_DIR/output" 2>&1
PLUGIN_STATUS=$?
set -e

if [ "$PLUGIN_STATUS" -ne 0 ]; then
    cat "$STATE_DIR/output"
    echo "RED helm checksum unverifiable: an unusable download was reported as a plugin failure"
    exit 1
fi

if grep -q 'matches the published release' "$STATE_DIR/output"; then
    cat "$STATE_DIR/output"
    echo "RED helm checksum unverifiable: an archive failing its published checksum became the reference"
    exit 1
fi

if ! grep -q 'does not match its published checksum' "$STATE_DIR/output"; then
    cat "$STATE_DIR/output"
    echo "RED helm checksum unverifiable: the reason the check could not run was not reported"
    exit 1
fi

if [ -e "$CACHE_DIR/diff-$PLUGIN_VERSION_UNDER_TEST.sha256" ]; then
    echo "RED helm checksum unverifiable: a rejected archive left a cached reference digest behind"
    exit 1
fi

if [ -n "$(find "$CACHE_DIR" -name 'download.*' -print -quit)" ]; then
    echo "RED helm checksum unverifiable: the rejected download was left on disk"
    exit 1
fi

# A plugin nobody publishes checksums for is a third outcome, and it must be
# reported as such rather than silently omitted from the run's output.
if ! grep -q 'no published checksums are known' "$STATE_DIR/output"; then
    cat "$STATE_DIR/output"
    echo "RED helm checksum unverifiable: an unknown plugin was passed over without a word"
    exit 1
fi

echo "helm checksum unverifiable contract passed"
