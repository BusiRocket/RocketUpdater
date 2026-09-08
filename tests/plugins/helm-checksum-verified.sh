#!/bin/bash

# helm-diff's own installer claims in a comment to verify a SHA256 and never
# does, so the plugin has to establish the reference itself: fetch the published
# checksums, confirm the archive against them, and only then compare the binary
# inside it with the one installed. This test proves the whole chain reaches
# "verified", and that the answer is cached — the release tree is deleted before
# the second run, which must still succeed without a download.
#
# It drives scripts/run-plugin.sh rather than sourcing the libraries by hand,
# because that is what the runner does and hand-sourcing hides the one failure
# that actually happened here: every helper worked and the runner did not load
# any of them, so the plugin reported nothing to verify and exited zero.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/lib/helm_plugin_release_source.sh"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-helm-verified.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

PLUGIN_VERSION_UNDER_TEST=3.15.12
RELEASE_RECORD=$(helm_plugin_release_source diff "$PLUGIN_VERSION_UNDER_TEST") || {
    echo "SKIP helm checksum: this platform has no known helm-diff release asset"
    exit 0
}
IFS=$'\t' read -r REPOSITORY ARCHIVE_ASSET CHECKSUMS_ASSET ARCHIVE_MEMBER <<<"$RELEASE_RECORD"

PLUGINS_ROOT="$FIXTURE_DIR/plugins"
RELEASE_DIR="$FIXTURE_DIR/release/$REPOSITORY/releases/download/v$PLUGIN_VERSION_UNDER_TEST"
CACHE_DIR="$FIXTURE_DIR/cache"
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$PLUGINS_ROOT/helm-diff/bin" "$RELEASE_DIR" \
    "$CACHE_DIR" "$STATE_DIR" "$FIXTURE_DIR/stage/$(dirname "$ARCHIVE_MEMBER")"

# One byte string is the genuine release: it goes into the archive that the
# checksums file vouches for, and into the installed plugin.
printf 'genuine helm-diff binary\n' >"$FIXTURE_DIR/stage/$ARCHIVE_MEMBER"
cp "$FIXTURE_DIR/stage/$ARCHIVE_MEMBER" "$PLUGINS_ROOT/helm-diff/bin/diff"

cat >"$PLUGINS_ROOT/helm-diff/plugin.yaml" <<EOF
name: diff
version: "$PLUGIN_VERSION_UNDER_TEST"
EOF

tar -czf "$RELEASE_DIR/$ARCHIVE_ASSET" -C "$FIXTURE_DIR/stage" "$ARCHIVE_MEMBER"
(cd "$RELEASE_DIR" && shasum -a 256 "$ARCHIVE_ASSET" >"$CHECKSUMS_ASSET")

cat >"$FIXTURE_DIR/bin/helm" <<EOF
#!/bin/bash
printf 'helm %s\n' "\$*" >>"\$PLUGIN_TEST_STATE/commands.log"
case "\$1 \$2" in
"plugin list")
    printf 'NAME\tVERSION\tTYPE\n'
    printf 'diff\t%s\tcli/v1\n' "$PLUGIN_VERSION_UNDER_TEST"
    ;;
"env HELM_PLUGINS") printf '"%s"\n' "$PLUGINS_ROOT" ;;
esac
exit 0
EOF

# Downloads are counted, not merely allowed: the point of caching the reference
# is that a second run costs one local hash, and a curl that still runs would
# mean every scheduled run re-downloads tens of megabytes.
cat >"$FIXTURE_DIR/bin/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >>"$PLUGIN_TEST_STATE/curl.log"
exec /usr/bin/curl "$@"
EOF
chmod +x "$FIXTURE_DIR/bin/"*

run_plugin() {
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" \
        PLUGIN_TEST_STATE="$STATE_DIR" \
        ROCKETUPDATER_EVENT_LOG="$STATE_DIR/events.log" \
        ROCKETUPDATER_HELM_RELEASE_BASE_URL="file://$FIXTURE_DIR/release" \
        ROCKETUPDATER_HELM_CACHE_DIR="$CACHE_DIR" \
        /bin/bash "$ROOT_DIR/scripts/run-plugin.sh" \
        "$ROOT_DIR/plugins/helm.sh" update_helm </dev/null >"$1" 2>&1
}

set +e
run_plugin "$STATE_DIR/first"
FIRST_STATUS=$?
set -e

if [ "$FIRST_STATUS" -ne 0 ]; then
    cat "$STATE_DIR/first"
    echo "RED helm checksum: the plugin failed on a genuine, matching installation"
    exit 1
fi

if ! grep -q 'matches the published release' "$STATE_DIR/first"; then
    cat "$STATE_DIR/first"
    echo "RED helm checksum: the verified verdict was not reported"
    exit 1
fi

# The runner loads plugin libraries itself. When it does not, every helper still
# works in isolation and the plugin simply verifies nothing, which is a pass
# that means the opposite of what it says.
if grep -q 'command not found' "$STATE_DIR/first"; then
    cat "$STATE_DIR/first"
    echo "RED helm checksum: the runner did not load the verification libraries"
    exit 1
fi

if [ ! -s "$CACHE_DIR/diff-$PLUGIN_VERSION_UNDER_TEST.sha256" ]; then
    echo "RED helm checksum: the verified reference digest was not cached"
    exit 1
fi

# The release is gone. A run that still passes proves the cache carried the
# reference; a run that fails proves it re-downloads on every pass.
/bin/rm -rf -- "$FIXTURE_DIR/release"
: >"$STATE_DIR/curl.log"

set +e
run_plugin "$STATE_DIR/second"
SECOND_STATUS=$?
set -e

if [ "$SECOND_STATUS" -ne 0 ]; then
    cat "$STATE_DIR/second"
    echo "RED helm checksum: the cached reference was not reused after the release went away"
    exit 1
fi

if [ -s "$STATE_DIR/curl.log" ]; then
    cat "$STATE_DIR/curl.log"
    echo "RED helm checksum: the second run downloaded the release again"
    exit 1
fi

echo "helm checksum verified contract passed"
