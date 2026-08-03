#!/bin/bash

# Lint all shell scripts in the project with shellcheck.
# Usage: ./scripts/lint.sh [severity]
#   severity  shellcheck severity floor: error, warning, info or style.
#             Defaults to style, the strictest.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$ROOT_DIR/lib/bash_colors.sh" ]; then
    # shellcheck source=../lib/bash_colors.sh
    source "$ROOT_DIR/lib/bash_colors.sh"
else
    echo_success() { echo "✅ $*"; }
    echo_warning() { echo "⚠️  $*"; }
fi

SEVERITY="${1:-style}"

if ! command -v shellcheck >/dev/null 2>&1; then
    echo_warning "shellcheck is not installed. Install it to lint shell scripts:"
    echo "  brew install shellcheck"
    exit 1
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

# -x follows sourced files so lib/bash_colors.sh resolves instead of warning.
# Project-wide exclusions live in .shellcheckrc.
if ! shellcheck -x -S "$SEVERITY" "${sh_files[@]}"; then
    echo_warning "shellcheck reported issues at severity '$SEVERITY' or above."
    exit 1
fi

echo_success "All $count shell script(s) pass shellcheck (severity: $SEVERITY)."
