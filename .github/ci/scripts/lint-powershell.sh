#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

echo "[lint-powershell] linting PowerShell scripts..." >&2

# Preprocess .ps1.tmpl by stripping Go template directives
preprocess_tmpl() {
    sed \
        -e '/^{{-\? .*-\?}}$/d' \
        -e 's|{{-\? .*-\?}}|"placeholder"|g' \
        "$1"
}

# Check if pwsh is available
if ! command -v pwsh &>/dev/null; then
    echo "[lint-powershell] SKIP: pwsh not installed" >&2
    exit 0
fi

# Lint pure .ps1 files
while IFS= read -r -d '' file; do
    rel=$(realpath --relative-to="$REPO_ROOT" "$file")
    result=$(pwsh -Command "Invoke-ScriptAnalyzer -Path '$file' -Severity Warning,Error" 2>&1) || true
    if [ -n "$result" ]; then
        echo "[lint-powershell] FAIL: $rel" >&2
        echo "$result" >&2
        EXIT_CODE=1
    fi
done < <(find "$REPO_ROOT" -name '*.ps1' -not -path '*/.git/*' -not -name '*.tmpl' -print0)

# Lint .ps1.tmpl files (preprocessed)
while IFS= read -r -d '' file; do
    rel=$(realpath --relative-to="$REPO_ROOT" "$file")
    tmpfile=$(mktemp --suffix=.ps1)
    preprocess_tmpl "$file" > "$tmpfile"

    result=$(pwsh -Command "Invoke-ScriptAnalyzer -Path '$tmpfile' -Severity Warning,Error" 2>&1) || true
    if [ -n "$result" ]; then
        echo "[lint-powershell] FAIL: $rel" >&2
        echo "$result" >&2
        EXIT_CODE=1
    fi

    rm -f "$tmpfile"
done < <(find "$REPO_ROOT" -name '*.ps1.tmpl' -not -path '*/.git/*' -print0)

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[lint-powershell] all PowerShell scripts passed" >&2
fi

exit $EXIT_CODE
