#!/bin/bash

# render_plugin_progress NAME ITEMS_FILE RUN_LOG consumes one plugin's merged
# output on stdin. Everything goes to RUN_LOG; leveled records other than info
# go to ITEMS_FILE for the result block; the terminal only ever shows one live
# line with a spinner, the elapsed time and the latest thing the plugin said.
render_plugin_progress() {
    local plugin_name=$1
    local items_file=$2
    local run_log=$3
    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local frame_index=0
    local started_at=$SECONDS
    local columns
    local status_width
    local status_text=''
    local cleaned
    local elapsed
    local line
    local level
    local text

    columns=$(/usr/bin/tput cols 2>/dev/null) || columns=80
    [ -n "$columns" ] || columns=80
    status_width=$((columns - ${#plugin_name} - 16))
    [ "$status_width" -gt 10 ] || status_width=10

    printf '\033[?25l'
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in
        *$'\036TICK')
            # A tick can land after a partial line a tool is still writing.
            line=${line%$'\036TICK'}
            [ -z "$line" ] || printf '%s\n' "$line" >>"$run_log"
            ;;
        $'\036'*)
            line=${line#$'\036'}
            level=${line%%$'\t'*}
            text=${line#*$'\t'}
            printf '[%s] %s\n' "$level" "$text" >>"$run_log"
            if [ "$level" = info ]; then
                strip_terminal_controls cleaned "$text"
                [ -z "$cleaned" ] || status_text=$cleaned
            else
                printf '%s\t%s\n' "$level" "$text" >>"$items_file"
            fi
            ;;
        *)
            printf '%s\n' "$line" >>"$run_log"
            strip_terminal_controls cleaned "$line"
            [ -z "$cleaned" ] || status_text=$cleaned
            ;;
        esac

        format_duration elapsed $((SECONDS - started_at))
        printf '\r\033[K  \033[36m%s\033[0m %s \033[90m%s  %s\033[0m' \
            "${frames[frame_index]}" "$plugin_name" "$elapsed" "${status_text:0:status_width}"
        frame_index=$(((frame_index + 1) % ${#frames[@]}))
    done
    printf '\r\033[K\033[?25h'
}
