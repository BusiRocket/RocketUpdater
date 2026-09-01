#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while IFS= read -r test_file; do
    printf 'Running %s\n' "${test_file#"$ROOT_DIR"/}"
    "$test_file"
done < <(find "$ROOT_DIR/tests" -mindepth 2 -maxdepth 2 -type f -name '*.sh' -print | LC_ALL=C sort)
