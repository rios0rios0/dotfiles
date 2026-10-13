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

    if ! shellcheck -S warning "$file"; then
        echo "[lint-shellcheck] FAIL: $file" >&2
        EXIT_CODE=1
    fi
done < <(find "$REPO_ROOT" -name '*.sh' -not -path '*/.git/*' -not -name '*.tmpl' -print0)

# Lint .sh.tmpl files (preprocessed)
echo "[lint-shellcheck] checking .sh.tmpl scripts (preprocessed)..." >&2
while IFS= read -r -d '' file; do
    tmpfile=$(mktemp)
    preprocess_tmpl "$file" > "$tmpfile"

    if ! shellcheck -S warning --shell=bash "$tmpfile"; then
        echo "[lint-shellcheck] FAIL: $file" >&2
        EXIT_CODE=1
    fi

    rm -f "$tmpfile"
done < <(find "$REPO_ROOT" -name '*.sh.tmpl' -not -path '*/.git/*' -print0)

# Lint the executables deployed to ~/.local/bin. They carry no .sh suffix -- it would become part
# of the command's name -- so the two globs above never see them; the shell ones are picked out
# by their shebang, templates after the same preprocessing as a .sh.tmpl.
echo "[lint-shellcheck] checking dot_local/bin executables..." >&2
while IFS= read -r -d '' file; do
    target="$file"
    if [[ "$file" == *.tmpl ]]; then
        target=$(mktemp)
        preprocess_tmpl "$file" > "$target"
    fi

    if head -1 "$target" | grep -qE '^#!(/usr)?/bin/(env )?(ba)?sh'; then
        if ! shellcheck -S warning "$target"; then
            echo "[lint-shellcheck] FAIL: $file" >&2
            EXIT_CODE=1
        fi
    fi

    [[ "$target" != "$file" ]] && rm -f "$target"
done < <(find "$REPO_ROOT/dot_local/bin" -type f -name 'executable_*' -print0)

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[lint-shellcheck] all scripts passed" >&2
fi

exit $EXIT_CODE
