#!/bin/bash

# format_duration VARIABLE SECONDS stores a short human duration (12s, 3m05s,
# 1h02m) in VARIABLE without a subshell, because the progress line calls it on
# every redraw.
format_duration() {
    local target=$1
    local total=$2

    if [ "$total" -lt 60 ]; then
        printf -v "$target" '%ds' "$total"
    elif [ "$total" -lt 3600 ]; then
        printf -v "$target" '%dm%02ds' $((total / 60)) $((total % 60))
    else
        printf -v "$target" '%dh%02dm' $((total / 3600)) $((total % 3600 / 60))
    fi
}
