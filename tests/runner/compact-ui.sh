#!/bin/bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

FIXTURE_DIR=$(mktemp -d "$ROOT_DIR/.runner-fixture-compact.XXXXXX")
trap '/bin/rm -rf -- "$FIXTURE_DIR"' EXIT

fail() {
    echo "RED compact UI: $1"
    exit 1
}

# shellcheck source=../../lib/print_message.sh
source "$ROOT_DIR/lib/print_message.sh"
# shellcheck source=../../lib/format_duration.sh
source "$ROOT_DIR/lib/format_duration.sh"
# shellcheck source=../../lib/strip_terminal_controls.sh
source "$ROOT_DIR/lib/strip_terminal_controls.sh"
# shellcheck source=../../lib/render_plugin_progress.sh
source "$ROOT_DIR/lib/render_plugin_progress.sh"
# shellcheck source=../../lib/print_plugin_result.sh
source "$ROOT_DIR/lib/print_plugin_result.sh"

value=""

# Durations stay short whatever their size.
format_duration value 7
[ "$value" = 7s ] || fail "7 seconds rendered as $value"
format_duration value 192
[ "$value" = 3m12s ] || fail "192 seconds rendered as $value"
format_duration value 3725
[ "$value" = 1h02m ] || fail "3725 seconds rendered as $value"

# Progress redraws, colors, tabs and emoji never reach the live line.
strip_terminal_controls value $'10%\r55%\r\033[0;32m✔︎ Bottle\tfzf\033[0m'
[ "$value" = 'Bottle fzf' ] || fail "stripped line was [$value]"

# Under the compact interface a leveled message is a record, not a line.
record=$(ROCKETUPDATER_UI=compact print_message warning 'disk is low')
[ "$record" = $'\036warning\tdisk is low' ] || fail "record was [$record]"
plain=$(ROCKETUPDATER_UI=compact print_message plain 'raw text')
[ "$plain" = 'raw text' ] || fail "plain line became [$plain]"

# The renderer logs everything, keeps non-info records, and drops ticks.
ITEMS_FILE="$FIXTURE_DIR/items"
RUN_LOG="$FIXTURE_DIR/run.log"
: >"$ITEMS_FILE"
: >"$RUN_LOG"
printf '%s\n' \
    $'\036info\tUpgrading fzf' \
    'raw tool output' \
    $'\036TICK' \
    $'partial\036TICK' \
    $'\036change\tformula fzf' \
    $'\036warning\tadvisory' |
    render_plugin_progress Homebrew "$ITEMS_FILE" "$RUN_LOG" >"$FIXTURE_DIR/screen"

grep -q 'raw tool output' "$RUN_LOG" || fail "raw output missing from the run log"
grep -q '^partial$' "$RUN_LOG" || fail "a partial line before a tick was lost"
grep -q '\[info\] Upgrading fzf' "$RUN_LOG" || fail "info record missing from the run log"
grep -q 'TICK' "$RUN_LOG" && fail "ticks leaked into the run log"
[ "$(cat "$ITEMS_FILE")" = $'change\tformula fzf\nwarning\tadvisory' ] ||
    fail "items file was [$(cat "$ITEMS_FILE")]"
grep -q 'Upgrading fzf' "$FIXTURE_DIR/screen" || fail "the live line never showed the info text"

# The result block shows the status line and the kept items, not successes.
printf 'success\tdone\n' >>"$ITEMS_FILE"
result=$(print_plugin_result 1 Homebrew 192 "$ITEMS_FILE")
case $result in
*'Homebrew'*'3m12s'*'failed (status 1)'*'formula fzf'*'advisory'*) ;;
*) fail "result block was [$result]" ;;
esac
case $result in
*done*) fail "a success item was repeated under the status line" ;;
esac

echo "compact UI contract passed"
