#!/bin/bash

PLUGIN_NAME="Whisper Model Report"
PLUGIN_VERSION="1.1.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=60
PLUGIN_SCHEDULE_ACTION=run

# Reports what is installed; a model is the owner's choice, never removed here.
# OpenAI checkpoints and mlx-whisper's Hugging Face repositories are separate,
# so a machine with only one of them still gets a report.
update_whispermodels() {
    local found=0
    local model_name
    for model_name in large-v3 large-v3-turbo medium small; do
        local model_path
        model_path="$HOME/.cache/whisper/$model_name.pt"
        [ -f "$model_path" ] || continue
        found=1
        if ! stat -f 'whisper_model path=%N size_bytes=%z mtime=%Sm' \
            -t '%Y-%m-%dT%H:%M:%S%z' "$model_path"; then
            return 1
        fi
    done

    local hub_models
    hub_models=$(find "$HOME/.cache/huggingface/hub" -maxdepth 1 -type d \
        -iname '*whisper*' -exec du -sh {} \; 2>/dev/null)
    if [ -n "$hub_models" ]; then
        found=1
        printf '%s\n' "$hub_models"
    fi

    if [ "$found" -eq 0 ]; then
        echo_skip "No Whisper model is installed"
        return 20
    fi
    return 0
}
