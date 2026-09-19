#!/bin/bash

# Prints a pid followed by every descendant, one per line, parents first.
list_process_tree() {
    local pid=$1
    local child

    printf '%s\n' "$pid"
    for child in $(pgrep -P "$pid" 2>/dev/null); do
        list_process_tree "$child"
    done
}
