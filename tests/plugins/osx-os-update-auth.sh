#!/bin/bash

# Contract: when the listing carries a macOS release and the download fails on
# the volume-owner authentication prompt, the plugin reports the limit and
# succeeds, because that prompt cannot be answered without a terminal and the
# sudoers rule only allows `-d -r`. Both wordings seen on 2026-09-19 count:
# "Failed to authenticate" (MacBook, macOS 27) and the LocalAuthentication
# error with "Password rejected (3)" (Mac mini, macOS 26.7, Spanish locale).
# Any other download failure still fails, and a listing without a macOS
# release never gets the exemption.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-osx-major.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$FIXTURE_DIR/home"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/sudo" <<'EOF_SUDO'
#!/bin/bash
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/sudo.log"
printf 'Downloaded: macOS Tahoe  26.7\n'
case "${OSX_TEST_AUTH_FAILURE:-}" in
'') ;;
mini)
    printf 'Failed to download & prepare update: Error Domain=SUOSUNotificationManagerErrorDomain Code=104 "(null)" UserInfo={NSUnderlyingError=0x86ad46bb0 {Error Domain=com.apple.LocalAuthentication Code=-1 "Password rejected (3)" UserInfo={NSDebugDescription=Password rejected (3), NSLocalizedDescription=Error de autenticación.}}}\n'
    exit 1
    ;;
*)
    printf 'Failed to authenticate\n'
    exit 1
    ;;
esac
exit "${OSX_TEST_DOWNLOAD_STATUS:-0}"
EOF_SUDO

cat >"$FIXTURE_DIR/bin/fake-softwareupdate" <<'EOF_SU'
#!/bin/bash
if [ "$1" = "-l" ]; then
    cat "$PLUGIN_TEST_STATE/listing.txt"
fi
exit 0
EOF_SU

chmod +x "$FIXTURE_DIR/bin/"*

run_osx() {
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" \
        PLUGIN_TEST_STATE="$STATE_DIR" \
        ROCKETUPDATER_SOFTWAREUPDATE_BIN="$FIXTURE_DIR/bin/fake-softwareupdate" \
        /bin/bash "$ROOT_DIR/scripts/run-plugin.sh" \
        "$ROOT_DIR/plugins/osx.sh" update_osx </dev/null >"$1" 2>&1
}

# The listing is byte-exact from softwareupdate on 2026-09-19: Apple writes a
# non-breaking space (U+00A0, \xc2\xa0) after "macOS", which is what made the
# first version of this detection miss the real output while passing a
# hand-typed one.
NBSP=$(printf '\xc2\xa0')
cat >"$STATE_DIR/listing.txt" <<EOF_LIST
Software Update found the following new or updated software:
* Label: Safari27.0TahoeAuto-27.0
	Title: Safari, Version: 27.0, Size: 249465KiB, Recommended: YES,
* Label: macOS${NBSP}Tahoe${NBSP} 26.7-25G229
	Title: macOS${NBSP}Tahoe${NBSP} 26.7, Version: 26.7, Size: 2960352KiB, Recommended: YES, Action: restart,
* Label: macOS${NBSP}27-26A428
	Title: macOS${NBSP}27, Version: 27, Size: 11727573KiB, Recommended: YES, Action: restart,
EOF_LIST

# Case 1: the MacBook wording of the auth failure is the known limit.
set +e
OSX_TEST_AUTH_FAILURE=1 run_osx "$STATE_DIR/major"
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ] || ! grep -q "macOS${NBSP}27-26A428" "$STATE_DIR/major" ||
    ! grep -q "macOS${NBSP}Tahoe${NBSP} 26.7-25G229" "$STATE_DIR/major" ||
    ! grep -q 'volume-owner login' "$STATE_DIR/major"; then
    cat "$STATE_DIR/major"
    echo "RED osx os update: the volume-owner auth limit was not reported as a warning"
    exit 1
fi
if grep -q 'Safari27.0TahoeAuto-27.0.*volume-owner' "$STATE_DIR/major"; then
    echo "RED osx os update: Safari 27 was taken for a macOS release"
    exit 1
fi
if [ "$(cat "$STATE_DIR/sudo.log")" != "-n /usr/sbin/softwareupdate -d -r" ]; then
    echo "RED osx os update: the download argv left the sudoers allowlist"
    exit 1
fi

# Case 1b: the Mac mini wording (LocalAuthentication, Spanish locale) too.
set +e
OSX_TEST_AUTH_FAILURE=mini run_osx "$STATE_DIR/mini"
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ] || ! grep -q 'volume-owner login' "$STATE_DIR/mini"; then
    cat "$STATE_DIR/mini"
    echo "RED osx os update: the LocalAuthentication wording was not recognised"
    exit 1
fi

# Case 2: any other download failure still fails the plugin.
set +e
OSX_TEST_DOWNLOAD_STATUS=1 run_osx "$STATE_DIR/other"
STATUS=$?
set -e
if [ "$STATUS" -ne 1 ]; then
    cat "$STATE_DIR/other"
    echo "RED osx os update: a download failure without the auth prompt did not return 1"
    exit 1
fi

# Case 3: the same auth text without a macOS release listed is not exempted.
cat >"$STATE_DIR/listing.txt" <<EOF_LIST
Software Update found the following new or updated software:
* Label: Safari27.0TahoeAuto-27.0
	Title: Safari, Version: 27.0, Size: 249465KiB, Recommended: YES,
EOF_LIST
set +e
OSX_TEST_AUTH_FAILURE=1 run_osx "$STATE_DIR/minor"
STATUS=$?
set -e
if [ "$STATUS" -ne 1 ]; then
    cat "$STATE_DIR/minor"
    echo "RED osx os update: an auth failure without a macOS release listed was exempted"
    exit 1
fi

echo "osx os update auth contract passed"
