#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

echo "[lint-syntax] validating YAML/JSON files..." >&2

# Validate JSON files (skip .tmpl files and .git directory)
while IFS= read -r -d '' file; do
    rel=$(realpath --relative-to="$REPO_ROOT" "$file")
    if ! jq empty "$file" 2>/dev/null; then
        echo "[lint-syntax] FAIL: $rel (invalid JSON)" >&2
        EXIT_CODE=1
    else
        echo "[lint-syntax] PASS: $rel" >&2
    fi
done < <(find "$REPO_ROOT" -name '*.json' -not -path '*/.git/*' -not -path '*/.github/ci/*' -not -name '*.tmpl' -print0)

# Validate YAML files
while IFS= read -r -d '' file; do
    rel=$(realpath --relative-to="$REPO_ROOT" "$file")
    if ! yq eval '.' "$file" >/dev/null 2>&1; then
        echo "[lint-syntax] FAIL: $rel (invalid YAML)" >&2
        EXIT_CODE=1
    else
        echo "[lint-syntax] PASS: $rel" >&2
    fi
done < <(find "$REPO_ROOT" \( -name '*.yaml' -o -name '*.yml' \) -not -path '*/.git/*' -not -path '*/.github/ci/*' -not -name '*.tmpl' -print0)

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[lint-syntax] all YAML/JSON files valid" >&2
fi

exit $EXIT_CODE
