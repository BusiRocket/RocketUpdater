#!/bin/bash

# Contract: the softwareupdate download runs without a controlling terminal.
# softwareupdate opens /dev/tty directly for the volume-owner password, so in
# a terminal run the prompt waited until the plugin's 1800s timeout on
# 2026-09-19 (exit 124); without a controlling tty it fails at once with
# "Failed to authenticate", which the plugin already reports as the known
# limit. The plugin is run under a real pty here so the difference shows.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    echo "osx no controlling tty contract skipped: python3 is unavailable"
    exit 0
fi

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-osx-tty.XXXXXX")
STATE_DIR="$FIXTURE_DIR/state"
mkdir -p "$FIXTURE_DIR/bin" "$STATE_DIR" "$FIXTURE_DIR/home"
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

cat >"$FIXTURE_DIR/bin/sudo" <<'EOF_SUDO'
#!/bin/bash
if ( : </dev/tty ) 2>/dev/null; then
    printf 'tty=yes\n' >>"$PLUGIN_TEST_STATE/tty.log"
else
    printf 'tty=no\n' >>"$PLUGIN_TEST_STATE/tty.log"
fi
printf '%s\n' "$*" >>"$PLUGIN_TEST_STATE/sudo.log"
exit 0
EOF_SUDO

cat >"$FIXTURE_DIR/bin/fake-softwareupdate" <<'EOF_SU'
#!/bin/bash
if [ "$1" = "-l" ]; then
    printf 'Software Update found the following new or updated software:\n* Label: Safari27.0TahoeAuto-27.0\n\tTitle: Safari, Version: 27.0, Size: 249465KiB, Recommended: YES,\n'
fi
exit 0
EOF_SU
chmod +x "$FIXTURE_DIR/bin/"*

PATH="$FIXTURE_DIR/bin:/usr/bin:/bin" HOME="$FIXTURE_DIR/home" PLUGIN_TEST_STATE="$STATE_DIR" \
    ROCKETUPDATER_SOFTWAREUPDATE_BIN="$FIXTURE_DIR/bin/fake-softwareupdate" \
    python3 - "$ROOT_DIR/scripts/run-plugin.sh" "$ROOT_DIR/plugins/osx.sh" <<'EOF_PY' >"$STATE_DIR/output" 2>&1
import os, pty, sys, time
runner, plugin = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["/bin/bash", runner, plugin, "update_osx"])
deadline = time.time() + 60
while time.time() < deadline:
    try:
        os.read(fd, 4096)
    except OSError:
        break
    wpid, _ = os.waitpid(pid, os.WNOHANG)
    if wpid:
        break
    time.sleep(0.1)
else:
    os.kill(pid, 9)
    sys.exit(1)
EOF_PY
STATUS=$?

if [ "$STATUS" -ne 0 ]; then
    cat "$STATE_DIR/output"
    echo "RED osx no controlling tty: plugin run under a pty did not finish"
    exit 1
fi
if [ "$(cat "$STATE_DIR/tty.log" 2>/dev/null)" != "tty=no" ]; then
    echo "RED osx no controlling tty: the download still had a controlling terminal ($(cat "$STATE_DIR/tty.log" 2>/dev/null))"
    exit 1
fi
if [ "$(cat "$STATE_DIR/sudo.log")" != "-n /usr/sbin/softwareupdate -d -r" ]; then
    echo "RED osx no controlling tty: the download argv left the sudoers allowlist"
    exit 1
fi

echo "osx no controlling tty contract passed"
