#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "[lint-python] extracting and linting embedded Python..." >&2

# Find all modify_* files that might contain embedded Python
count=0
while IFS= read -r -d '' file; do
    rel=$(realpath --relative-to="$REPO_ROOT" "$file")

    # Extract Python blocks between PYEOF markers
    if grep -q 'PYEOF' "$file"; then
        tmpfile="$TMPDIR/$(basename "$file" .tmpl).py"
        sed -n '/<<.*PYEOF/,/^PYEOF/{ /<<.*PYEOF/d; /^PYEOF/d; p; }' "$file" > "$tmpfile"

        if [ -s "$tmpfile" ]; then
            count=$((count + 1))
            if ! ruff check --select=E,W,F "$tmpfile" 2>&1 | sed "s|$tmpfile|$rel|g"; then
                echo "[lint-python] FAIL: $rel" >&2
                EXIT_CODE=1
            fi
        fi
    fi
done < <(find "$REPO_ROOT" -name 'modify_*' -not -path '*/.git/*' -print0)

echo "[lint-python] checked $count files with embedded Python" >&2

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[lint-python] all embedded Python passed" >&2
fi

exit $EXIT_CODE
