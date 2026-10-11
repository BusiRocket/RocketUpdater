#!/bin/bash

# strip_terminal_controls VARIABLE TEXT stores TEXT as one printable ASCII
# line in VARIABLE: only the last carriage-return segment survives (progress
# bars redraw that way), ANSI sequences go, and so does every byte outside
# printable ASCII, whose display width the progress line cannot predict.
strip_terminal_controls() {
    local target=$1
    local text=$2
    local before
    local after
    local LC_ALL=C

    text=${text%$'\r'}
    text=${text##*$'\r'}
    text=${text//$'\t'/ }

    while [[ $text == *$'\033['* ]]; do
        before=${text%%$'\033['*}
        after=${text#*$'\033['}
        after=${after#*[A-Za-z]}
        text=$before$after
    done

    text=${text//[!\ -~]/}
    text=${text#"${text%%[! ]*}"}
    printf -v "$target" '%s' "$text"
}
