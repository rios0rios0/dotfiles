#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

echo "[lint-shellcheck] linting shell scripts..." >&2

# Preprocess a .tmpl file by stripping Go template directives
preprocess_tmpl() {
    sed \
        -e 's|{{ lookPath "bash" }}|/bin/bash|g' \
        -e 's|{{- lookPath "bash" -}}|/bin/bash|g' \
        -e 's|{{ \.chezmoi\.[a-zA-Z]*[^}]* }}|"placeholder"|g' \
        -e 's|{{- \.chezmoi\.[a-zA-Z]*[^}]* -}}|"placeholder"|g' \
        -e '/^{{-\? .*-\?}}$/d' \
        -e 's|{{-\? .*-\?}}||g' \
        "$1"
}

# Lint pure .sh files (not templates)
echo "[lint-shellcheck] checking .sh scripts..." >&2
while IFS= read -r -d '' file; do
    # skip files inside .github/ci (our own CI scripts are linted by the CI runner)
    case "$file" in
        */.github/ci/*) continue ;;
    esac

    if ! shellcheck "$file"; then
        echo "[lint-shellcheck] FAIL: $file" >&2
        EXIT_CODE=1
    fi
done < <(find "$REPO_ROOT" -name '*.sh' -not -path '*/.git/*' -not -name '*.tmpl' -print0)

# Lint .sh.tmpl files (preprocessed)
echo "[lint-shellcheck] checking .sh.tmpl scripts (preprocessed)..." >&2
while IFS= read -r -d '' file; do
    tmpfile=$(mktemp)
    preprocess_tmpl "$file" > "$tmpfile"

    if ! shellcheck --shell=bash "$tmpfile"; then
        echo "[lint-shellcheck] FAIL: $file" >&2
        EXIT_CODE=1
    fi

    rm -f "$tmpfile"
done < <(find "$REPO_ROOT" -name '*.sh.tmpl' -not -path '*/.git/*' -print0)

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[lint-shellcheck] all scripts passed" >&2
fi

exit $EXIT_CODE
