#!/bin/bash

# Format all shell scripts in the project with shfmt.
# Usage: ./scripts/format.sh [--check]
#   --check  Only check; exit 1 if any file would be changed (for CI).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$ROOT_DIR/lib/bash_colors.sh" ]; then
    # shellcheck source=../lib/bash_colors.sh
    source "$ROOT_DIR/lib/bash_colors.sh"
else
    echo_info() { echo "ℹ️  $*"; }
    echo_success() { echo "✅ $*"; }
    echo_warning() { echo "⚠️  $*"; }
fi

CHECK_MODE=false
if [ "${1:-}" = "--check" ]; then
    CHECK_MODE=true
fi

if ! command -v shfmt >/dev/null 2>&1; then
    echo_warning "shfmt is not installed. Install it to format shell scripts:"
    echo "  brew install shfmt"
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
