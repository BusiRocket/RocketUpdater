#!/bin/bash

# A machine with only mlx-whisper's Hugging Face models still gets a report;
# only a machine with no Whisper model at all is a skip.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/tests/plugins/plugin-test-support.bash"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.plugin-fixture-whisper.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT
export HOME="$FIXTURE_DIR/home"
mkdir -p "$FIXTURE_DIR/bin" "$HOME/.cache/huggingface/hub"

set +e
run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/whispermodels.sh" update_whispermodels "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
STATUS=$?
set -e
if [ "$STATUS" -ne 20 ]; then
    echo "RED whispermodels: no model at all returned $STATUS instead of a skip"
    exit 1
fi

mkdir -p "$HOME/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo"
set +e
run_plugin_function "$ROOT_DIR" "$ROOT_DIR/plugins/whispermodels.sh" update_whispermodels "$FIXTURE_DIR/bin" "$FIXTURE_DIR/output"
STATUS=$?
set -e
if [ "$STATUS" -ne 0 ] || ! grep -q 'whisper-large-v3-turbo' "$FIXTURE_DIR/output"; then
    cat "$FIXTURE_DIR/output"
    echo "RED whispermodels: a Hugging Face-only install was hidden ($STATUS)"
    exit 1
fi

echo "whispermodels plugin contract passed"
