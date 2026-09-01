#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.cleanup-fixture-sparkle.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
FIXTURE_HOME="$FIXTURE_DIR/home"
SPARKLE_BASE="$FIXTURE_HOME/Library/Caches/com.openai.codex/org.sparkle-project.Sparkle"
INSTALL_ROOT="$SPARKLE_BASE/Installation"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/pgrep" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$CLEANUP_TEST_STATE/pgrep.log"
if [ -f "$CLEANUP_TEST_STATE/pgrep-running" ]; then
    IFS=' ' read -r pattern threshold <"$CLEANUP_TEST_STATE/pgrep-running"
    threshold=${threshold:-1}
    case "$*" in
    *"$pattern"*)
        match_count=$(cat "$CLEANUP_TEST_STATE/pgrep-matches" 2>/dev/null || printf 0)
        match_count=$((match_count + 1))
        printf '%s\n' "$match_count" >"$CLEANUP_TEST_STATE/pgrep-matches"
        if [ "$match_count" -ge "$threshold" ]; then
            exit 0
        fi
        ;;
    esac
fi
exit 1
EOF
chmod +x "$FIXTURE_DIR/bin/pgrep"

write_plist() {
    cat >"$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleVersion</key>
  <string>$2</string>
</dict>
</plist>
EOF
}

make_candidate() {
    local candidate_name=$1
    local staged_build=$2
    local candidate_dir="$INSTALL_ROOT/$candidate_name"

    mkdir -p "$candidate_dir/ChatGPT.app/Contents"
    write_plist "$candidate_dir/ChatGPT.app/Contents/Info.plist" "$staged_build"
    touch -t 202608250000 "$candidate_dir"
}

reset_fixture() {
    /bin/rm -rf -- "$SPARKLE_BASE"
    /bin/rm -f -- "$STATE_DIR/pgrep-running" "$STATE_DIR/pgrep-matches" "$STATE_DIR/pgrep.log"
    mkdir -p "$INSTALL_ROOT" "$SPARKLE_BASE/PersistentDownloads"
    printf 'payload\n' >"$SPARKLE_BASE/PersistentDownloads/download.bin"
}

write_plist "$FIXTURE_DIR/installed.plist" 7271

run_guard_with_tty() {
    local answer=$1
    local expect_file="$STATE_DIR/session.expect"

    cat >"$expect_file" <<EOF
set timeout 20
spawn /bin/bash -c {
    set -u
    source "$ROOT_DIR/lib/print_message.sh"
    source "$ROOT_DIR/lib/echo_info.sh"
    source "$ROOT_DIR/lib/echo_success.sh"
    source "$ROOT_DIR/lib/echo_warning.sh"
    source "$ROOT_DIR/lib/echo_error.sh"
    source "$ROOT_DIR/lib/echo_skip.sh"
    source "$ROOT_DIR/lib/command_exists.sh"
    source "$ROOT_DIR/lib/list_sparkle_obsolete_candidates.sh"
    source "$ROOT_DIR/cleanup/guard_sparkle_obsolete_installations.sh"
    guard_sparkle_obsolete_installations
}
expect {
    -re {Type "sparkle"} { send "$answer\r"; exp_continue }
    timeout { exec kill [exp_pid]; exit 99 }
    eof {}
}
catch wait wait_result
exit [lindex \$wait_result 3]
EOF

    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_HOME" \
        CLEANUP_TEST_STATE="$STATE_DIR" \
        ROCKETUPDATER_SPARKLE_INSTALLED_PLIST="$FIXTURE_DIR/installed.plist" \
        /usr/bin/expect -f "$expect_file" >"$STATE_DIR/output" 2>&1
}

# Case 1: without a TTY the guard fails closed with 78.
reset_fixture
make_candidate oldbuild 6872
set +e
PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_HOME" \
    CLEANUP_TEST_STATE="$STATE_DIR" \
    ROCKETUPDATER_SPARKLE_INSTALLED_PLIST="$FIXTURE_DIR/installed.plist" /bin/bash -c '
    set -u
    source "'"$ROOT_DIR"'/lib/print_message.sh"
    source "'"$ROOT_DIR"'/lib/echo_info.sh"
    source "'"$ROOT_DIR"'/lib/echo_success.sh"
    source "'"$ROOT_DIR"'/lib/echo_warning.sh"
    source "'"$ROOT_DIR"'/lib/echo_error.sh"
    source "'"$ROOT_DIR"'/lib/echo_skip.sh"
    source "'"$ROOT_DIR"'/lib/command_exists.sh"
    source "'"$ROOT_DIR"'/lib/list_sparkle_obsolete_candidates.sh"
    source "'"$ROOT_DIR"'/cleanup/guard_sparkle_obsolete_installations.sh"
    guard_sparkle_obsolete_installations
' </dev/null >"$STATE_DIR/no-tty-output" 2>&1
NO_TTY_STATUS=$?
set -e
if [ "$NO_TTY_STATUS" -ne 78 ] || [ ! -d "$INSTALL_ROOT/oldbuild" ]; then
    echo "RED sparkle guard: non-TTY invocation did not fail closed with 78"
    exit 1
fi

# Case 2: each running target argv form blocks removal with status 20.
for process_pattern in ChatGPT Autoupdate Updater.app; do
    reset_fixture
    make_candidate oldbuild 6872
    printf '%s 1\n' "$process_pattern" >"$STATE_DIR/pgrep-running"
    set +e
    run_guard_with_tty sparkle
    GUARD_STATUS=$?
    set -e
    if [ "$GUARD_STATUS" -ne 20 ] || [ ! -d "$INSTALL_ROOT/oldbuild" ]; then
        echo "RED sparkle guard: a running $process_pattern did not block removal"
        exit 1
    fi
done

# Case 3: young, missing-manifest, nonnumeric, equal, and newer candidates are
# retained while two older builds are removed after the exact confirmation.
reset_fixture
make_candidate oldbuild 6872
make_candidate olderbuild 7119
make_candidate equalbuild 7271
make_candidate newerbuild 9999
make_candidate youngbuild 6900
touch -t "$(date -v-1H '+%Y%m%d%H%M')" "$INSTALL_ROOT/youngbuild"
mkdir -p "$INSTALL_ROOT/nomanifest"
touch -t 202608250000 "$INSTALL_ROOT/nomanifest"
make_candidate badbuild 6800
sed -i '' 's/6800/not-a-build/' "$INSTALL_ROOT/badbuild/ChatGPT.app/Contents/Info.plist"
touch -t 202608250000 "$INSTALL_ROOT/badbuild"
set +e
run_guard_with_tty sparkle
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -ne 0 ] ||
    [ -d "$INSTALL_ROOT/oldbuild" ] || [ -d "$INSTALL_ROOT/olderbuild" ] ||
    [ ! -d "$INSTALL_ROOT/equalbuild" ] || [ ! -d "$INSTALL_ROOT/newerbuild" ] ||
    [ ! -d "$INSTALL_ROOT/youngbuild" ] || [ ! -d "$INSTALL_ROOT/nomanifest" ] ||
    [ ! -d "$INSTALL_ROOT/badbuild" ] ||
    [ ! -f "$SPARKLE_BASE/PersistentDownloads/download.bin" ]; then
    cat "$STATE_DIR/output"
    echo "RED sparkle guard: the confirmed removal did not remove exactly the two older builds"
    exit 1
fi
if ! grep -q 'PersistentDownloads' "$STATE_DIR/output" ||
    ! grep -q 'sparkle_obsolete total_allocated_kib=' "$STATE_DIR/output"; then
    echo "RED sparkle guard: the preview did not report PersistentDownloads and allocated KiB"
    exit 1
fi

# Case 4: a wrong confirmation removes nothing with status 20.
reset_fixture
make_candidate oldbuild 6872
set +e
run_guard_with_tty wrong-answer
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -ne 20 ] || [ ! -d "$INSTALL_ROOT/oldbuild" ]; then
    echo "RED sparkle guard: a wrong confirmation did not keep the candidate"
    exit 1
fi

# Case 5: a target process appearing between the initial and per-candidate
# guard blocks removal.
reset_fixture
make_candidate oldbuild 6872
printf 'ChatGPT 2\n' >"$STATE_DIR/pgrep-running"
set +e
run_guard_with_tty sparkle
GUARD_STATUS=$?
set -e
if [ "$GUARD_STATUS" -ne 20 ] || [ ! -d "$INSTALL_ROOT/oldbuild" ]; then
    echo "RED sparkle guard: a late-appearing target process did not block removal"
    exit 1
fi

# Case 6: a failed removal returns 1 after attempting the other candidate.
reset_fixture
make_candidate oldbuild 6872
make_candidate olderbuild 7119
chflags uchg "$INSTALL_ROOT/oldbuild/ChatGPT.app/Contents/Info.plist"
set +e
run_guard_with_tty sparkle
GUARD_STATUS=$?
set -e
chflags -R nouchg "$INSTALL_ROOT" 2>/dev/null || true
if [ "$GUARD_STATUS" -ne 1 ] || [ ! -d "$INSTALL_ROOT/oldbuild" ] ||
    [ -d "$INSTALL_ROOT/olderbuild" ]; then
    cat "$STATE_DIR/output"
    echo "RED sparkle guard: a failed removal did not return 1 after attempting the rest"
    exit 1
fi

# Case 7: a symlinked candidate pointing outside the root is retained.
reset_fixture
mkdir -p "$FIXTURE_DIR/outside/ChatGPT.app/Contents"
write_plist "$FIXTURE_DIR/outside/ChatGPT.app/Contents/Info.plist" 6000
/bin/ln -s "$FIXTURE_DIR/outside" "$INSTALL_ROOT/linked"
make_candidate oldbuild 6872
set +e
run_guard_with_tty sparkle
GUARD_STATUS=$?
set -e
if [ ! -d "$FIXTURE_DIR/outside" ] || [ ! -e "$INSTALL_ROOT/linked" ]; then
    echo "RED sparkle guard: a symlinked candidate reached removal"
    exit 1
fi

echo "sparkle cleanup guard contract passed"
