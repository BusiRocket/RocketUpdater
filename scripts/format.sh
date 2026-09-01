#!/bin/bash

# Format all shell scripts in the project with shfmt.
# Usage: ./scripts/format.sh [--check]
#   --check  Only check; exit 1 if any file would be changed (for CI).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/print_message.sh
source "$ROOT_DIR/lib/print_message.sh"
# shellcheck source=../lib/echo_info.sh
source "$ROOT_DIR/lib/echo_info.sh"
# shellcheck source=../lib/echo_success.sh
source "$ROOT_DIR/lib/echo_success.sh"
# shellcheck source=../lib/echo_warning.sh
source "$ROOT_DIR/lib/echo_warning.sh"

CHECK_MODE=false
if [ "${1:-}" = "--check" ]; then
    CHECK_MODE=true
fi

if ! command -v shfmt >/dev/null 2>&1; then
    echo_warning "shfmt is not installed. Install it to format shell scripts:"
    print_message plain "  brew install shfmt"
    exit 1
fi

# Indent: 4 spaces. -s: simplify. -w: write (or -d for diff when --check)
SHFMT_OPTS=(-i 4 -s)
if [ "$CHECK_MODE" = true ]; then
    SHFMT_OPTS+=(-d)
else
    SHFMT_OPTS+=(-w)
fi

# Collect all .sh files (exclude .git)
sh_files=()
while IFS= read -r -d '' f; do
    sh_files+=("$f")
done < <(find "$ROOT_DIR" -name '*.sh' -not -path "$ROOT_DIR/.git/*" -print0)

count=${#sh_files[@]}
if [ "$count" -eq 0 ]; then
    echo_warning "No .sh files found."
    exit 0
fi

if [ "$CHECK_MODE" = true ]; then
    if ! shfmt "${SHFMT_OPTS[@]}" "${sh_files[@]}"; then
        echo_warning "Some file(s) need formatting. Run ./scripts/format.sh to fix."
        exit 1
    fi
    echo_success "All $count shell script(s) are formatted."
else
    shfmt "${SHFMT_OPTS[@]}" "${sh_files[@]}"
    echo_success "Formatting complete ($count file(s) processed)."
fi
