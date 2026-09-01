#!/bin/bash

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/print_message.sh
source "$ROOT_DIR/lib/print_message.sh" || exit 78
# shellcheck source=../lib/echo_info.sh
source "$ROOT_DIR/lib/echo_info.sh" || exit 78
# shellcheck source=../lib/echo_success.sh
source "$ROOT_DIR/lib/echo_success.sh" || exit 78
# shellcheck source=../lib/echo_warning.sh
source "$ROOT_DIR/lib/echo_warning.sh" || exit 78
# shellcheck source=../lib/echo_error.sh
source "$ROOT_DIR/lib/echo_error.sh" || exit 78
# shellcheck source=../lib/echo_skip.sh
source "$ROOT_DIR/lib/echo_skip.sh" || exit 78

if [ "$#" -ne 2 ]; then
    print_message plain "Usage: $0 FILE FUNCTION" >&2
    exit 78
fi

PLUGIN_FILE=$1
PLUGIN_FUNCTION=$2
PLUGIN_FILENAME=${PLUGIN_FILE##*/}
PLUGIN_BASENAME=${PLUGIN_FILENAME%.sh}

case $PLUGIN_BASENAME in
'' | *[!a-zA-Z0-9_]*)
    echo_error "Invalid plugin filename: $PLUGIN_FILE" >&2
    exit 78
    ;;
esac

case $PLUGIN_FUNCTION in
"update_$PLUGIN_BASENAME" | "report_$PLUGIN_BASENAME") ;;
*)
    echo_error "Invalid plugin function: $PLUGIN_FUNCTION" >&2
    exit 78
    ;;
esac

# shellcheck source=../lib/command_exists.sh
source "$ROOT_DIR/lib/command_exists.sh" || exit 78
# shellcheck source=../lib/log_event.sh
source "$ROOT_DIR/lib/log_event.sh" || exit 78
# shellcheck source=../lib/snapshot_global_npm_packages.sh
source "$ROOT_DIR/lib/snapshot_global_npm_packages.sh" || exit 78
# shellcheck source=../lib/compare_global_npm_snapshots.sh
source "$ROOT_DIR/lib/compare_global_npm_snapshots.sh" || exit 78
# shellcheck source=../lib/list_sparkle_obsolete_candidates.sh
source "$ROOT_DIR/lib/list_sparkle_obsolete_candidates.sh" || exit 78
# shellcheck source=/dev/null
source "$PLUGIN_FILE" || exit $?

if ! declare -F "$PLUGIN_FUNCTION" >/dev/null 2>&1; then
    echo_error "Plugin function is not defined: $PLUGIN_FUNCTION" >&2
    exit 78
fi

"$PLUGIN_FUNCTION"
exit $?
