#!/bin/bash

PLUGIN_NAME="Whisper Model Report"
PLUGIN_VERSION="1.0.0"
DISABLE=false
PLUGIN_PRIORITY=80
PLUGIN_TIMEOUT_SECONDS=60
PLUGIN_SCHEDULE_ACTION=run

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

    if [ "$found" -eq 0 ]; then
        echo_skip "No tracked Whisper model is installed"
        return 20
    fi

    find "$HOME/.cache/huggingface/hub" -maxdepth 1 -type d \
        -iname '*whisper*' -print -exec du -sh {} \; 2>/dev/null || true
    echo_warning "The 6.3 GiB OpenAI checkpoint set is one manual decision; mlx-whisper uses the separate Hugging Face cache"
    return 0
}
