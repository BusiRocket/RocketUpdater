#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-sparklecache.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
FIXTURE_HOME="$FIXTURE_DIR/home"
SPARKLE_BASE="$FIXTURE_HOME/Library/Caches/com.openai.codex/org.sparkle-project.Sparkle"
INSTALL_ROOT="$SPARKLE_BASE/Installation"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$SPARKLE_BASE/PersistentDownloads"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/pgrep" <<'EOF'
#!/bin/bash
if [ -f "$PLUGIN_TEST_STATE/pgrep-running" ]; then
    exit 0
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

write_plist "$FIXTURE_DIR/installed.plist" 7271

run_report() {
    PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_HOME" \
        PLUGIN_TEST_STATE="$STATE_DIR" \
        ROCKETUPDATER_SPARKLE_INSTALLED_PLIST="$FIXTURE_DIR/installed.plist" \
        /bin/bash -c '
        set -u
        source "'"$ROOT_DIR"'/lib/print_message.sh"
        source "'"$ROOT_DIR"'/lib/echo_info.sh"
        source "'"$ROOT_DIR"'/lib/echo_success.sh"
        source "'"$ROOT_DIR"'/lib/echo_warning.sh"
        source "'"$ROOT_DIR"'/lib/echo_error.sh"
        source "'"$ROOT_DIR"'/lib/echo_skip.sh"
        source "'"$ROOT_DIR"'/lib/command_exists.sh"
        source "'"$ROOT_DIR"'/lib/list_sparkle_obsolete_candidates.sh"
        source "'"$ROOT_DIR"'/plugins/sparklecache.sh"
        report_sparklecache
    ' >"$STATE_DIR/output" 2>&1
}

# Case 1: an absent installation cache skips with status 20.
set +e
run_report
REPORT_STATUS=$?
set -e
if [ "$REPORT_STATUS" -ne 20 ]; then
    echo "RED sparklecache plugin: an absent cache did not skip with status 20"
    exit 1
fi

# Case 2: candidates are classified without deleting anything.
make_candidate oldbuild 6872
make_candidate newerbuild 9999
make_candidate youngbuild 6900
touch -t "$(date -v-1H '+%Y%m%d%H%M')" "$INSTALL_ROOT/youngbuild"
mkdir -p "$INSTALL_ROOT/nomanifest"
touch -t 202608250000 "$INSTALL_ROOT/nomanifest"
printf 'payload\n' >"$SPARKLE_BASE/PersistentDownloads/download.bin"

set +e
run_report
REPORT_STATUS=$?
set -e
if [ "$REPORT_STATUS" -ne 0 ] ||
    ! grep -q "^obsolete$(printf '\t')$INSTALL_ROOT/oldbuild" "$STATE_DIR/output" ||
    ! grep -q "^retained-current-or-newer$(printf '\t')$INSTALL_ROOT/newerbuild" "$STATE_DIR/output" ||
    ! grep -q "^retained-young$(printf '\t')$INSTALL_ROOT/youngbuild" "$STATE_DIR/output" ||
    ! grep -q "^retained-unverifiable$(printf '\t')$INSTALL_ROOT/nomanifest" "$STATE_DIR/output" ||
    ! grep -q 'PersistentDownloads' "$STATE_DIR/output"; then
    cat "$STATE_DIR/output"
    echo "RED sparklecache plugin: the report did not classify every candidate"
    exit 1
fi
if [ ! -d "$INSTALL_ROOT/oldbuild" ] || [ ! -f "$SPARKLE_BASE/PersistentDownloads/download.bin" ]; then
    echo "RED sparklecache plugin: the report deleted something"
    exit 1
fi

# Case 3: a running target process blocks every candidate.
touch "$STATE_DIR/pgrep-running"
set +e
run_report
REPORT_STATUS=$?
set -e
/bin/rm -f "$STATE_DIR/pgrep-running"
if [ "$REPORT_STATUS" -ne 0 ] ||
    ! grep -q "^blocked-running$(printf '\t')$INSTALL_ROOT/oldbuild" "$STATE_DIR/output"; then
    echo "RED sparklecache plugin: a running target was not reported as blocked-running"
    exit 1
fi

echo "sparklecache plugin contract passed"
