#!/usr/bin/env bash
# Runs the repository's linters. `make lint` runs all of them; `make lint ONLY=shellcheck` runs the
# named ones (shellcheck, templates, python, powershell, syntax). Every linter runs even after one
# fails, and the exit status is non-zero when any did.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Strips the Go template directives from a shell template so shellcheck can parse what is left.
strip_shell_template() {
    sed \
        -e 's|{{ lookPath "bash" }}|/bin/bash|g' \
        -e 's|{{- lookPath "bash" -}}|/bin/bash|g' \
        -e 's|{{ \.chezmoi\.[a-zA-Z]*[^}]* }}|"placeholder"|g' \
        -e 's|{{- \.chezmoi\.[a-zA-Z]*[^}]* -}}|"placeholder"|g' \
        -e '/^{{-\? .*-\?}}$/d' \
        -e 's|{{-\? .*-\?}}||g' \
        "$1"
}

# Strips the Go template directives from a PowerShell template.
strip_powershell_template() {
    sed \
        -e '/^{{-\? .*-\?}}$/d' \
        -e 's|{{-\? .*-\?}}|"placeholder"|g' \
        "$1"
}

# A tool this machine lacks fails the linter on CI, where a skip would pass a job that checked
# nothing, and only skips it elsewhere.
missing() {
    if [[ -n "${CI:-}" ]]; then
        echo "[lint] FAIL: $1 is not installed" >&2
        return 1
    fi
    echo "[lint] SKIP: $1 is not installed" >&2
    return 0
}

# Every shell script: the plain `.sh` files, the `.sh.tmpl` templates once stripped, and the
# executables deployed to ~/.local/bin, which carry no `.sh` suffix and are picked out by their
# shebang. The CI's own scripts under .github/ci are left out.
lint_shellcheck() {
    local status=0 file target
    command -v shellcheck > /dev/null || { missing shellcheck; return; }
    while IFS= read -r -d '' file; do
        shellcheck -S warning "$file" || { echo "[lint] FAIL: $file" >&2; status=1; }
    done < <(find . -name '*.sh' -not -path './.git/*' -not -path './.github/ci/*' -print0)
    while IFS= read -r -d '' file; do
        target="$(mktemp)"
        strip_shell_template "$file" > "$target"
        shellcheck -S warning --shell=bash "$target" || { echo "[lint] FAIL: $file" >&2; status=1; }
        rm -f "$target"
    done < <(find . -name '*.sh.tmpl' -not -path './.git/*' -print0)
    while IFS= read -r -d '' file; do
        target="$file"
        if [[ "$file" == *.tmpl ]]; then
            target="$(mktemp)"
            strip_shell_template "$file" > "$target"
        fi
        if head -1 "$target" | grep -qE '^#!(/usr)?/bin/(env )?(ba)?sh' && ! shellcheck -S warning "$target"; then
            echo "[lint] FAIL: $file" >&2
            status=1
        fi
        [[ "$target" != "$file" ]] && rm -f "$target"
    done < <(find ./dot_local/bin -type f -name 'executable_*' -print0)
    return "$status"
}

# Every Go template parses, with chezmoi's own template functions (.github/ci/cmd/tmplcheck).
lint_templates() {
    command -v go > /dev/null || { missing go; return; }
    (cd .github/ci/cmd/tmplcheck && go run .)
}

# The Python embedded between `PYEOF` markers in the `modify_` files.
lint_python() {
    local status=0 file workdir extracted
    command -v ruff > /dev/null || { missing ruff; return; }
    workdir="$(mktemp -d)"
    while IFS= read -r -d '' file; do
        grep -q 'PYEOF' "$file" || continue
        extracted="$workdir/$(basename "$file" .tmpl).py"
        sed -n '/<<.*PYEOF/,/^PYEOF/{ /<<.*PYEOF/d; /^PYEOF/d; p; }' "$file" > "$extracted"
        [[ -s "$extracted" ]] || continue
        # The report names the source file, not the extracted copy.
        ruff check --select=E,W,F "$extracted" 2>&1 | sed "s|$extracted|$file|g" || { echo "[lint] FAIL: $file" >&2; status=1; }
    done < <(find . -name 'modify_*' -not -path './.git/*' -print0)
    rm -rf "$workdir"
    return "$status"
}

# Every PowerShell script, templates once stripped, through PSScriptAnalyzer.
lint_powershell() {
    local status=0 file target result
    command -v pwsh > /dev/null || { missing pwsh; return; }
    while IFS= read -r -d '' file; do
        target="$file"
        if [[ "$file" == *.tmpl ]]; then
            target="$(mktemp --suffix=.ps1)"
            strip_powershell_template "$file" > "$target"
        fi
        result="$(pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path '$target' -Severity Warning,Error -ExcludeRule PSAvoidUsingWriteHost,PSUseApprovedVerbs" 2>&1)" || true
        if [[ -n "$result" ]]; then
            echo "[lint] FAIL: $file" >&2
            echo "$result" >&2
            status=1
        fi
        [[ "$target" != "$file" ]] && rm -f "$target"
    done < <(find . \( -name '*.ps1' -o -name '*.ps1.tmpl' \) -not -path './.git/*' -print0)
    return "$status"
}

# Every JSON and YAML file parses. Templates are skipped, and so are the `modify_` files: a
# modify-template holds template code, and the JSON it produces is checked by its own test.
lint_syntax() {
    local status=0 file
    command -v jq > /dev/null || { missing jq; return; }
    command -v yq > /dev/null || { missing yq; return; }
    while IFS= read -r -d '' file; do
        jq empty "$file" 2> /dev/null || { echo "[lint] FAIL: $file (invalid JSON)" >&2; status=1; }
    done < <(find . -name '*.json' -not -path './.git/*' -not -path './.github/ci/*' -not -name '*.tmpl' -not -name 'modify_*' -print0)
    while IFS= read -r -d '' file; do
        yq eval '.' "$file" > /dev/null 2>&1 || { echo "[lint] FAIL: $file (invalid YAML)" >&2; status=1; }
    done < <(find . \( -name '*.yaml' -o -name '*.yml' \) -not -path './.git/*' -not -path './.github/ci/*' -not -name '*.tmpl' -print0)
    return "$status"
}

LINTERS=(shellcheck templates python powershell syntax)
selected=("$@")
[[ "${#selected[@]}" -gt 0 ]] || selected=("${LINTERS[@]}")

failed=()
for linter in "${selected[@]}"; do
    if ! declare -F "lint_$linter" > /dev/null; then
        echo "[lint] FAIL: no linter named '$linter' (${LINTERS[*]})" >&2
        failed+=("$linter")
        continue
    fi
    echo "[lint] $linter" >&2
    "lint_$linter" || failed+=("$linter")
done

if [[ "${#failed[@]}" -gt 0 ]]; then
    echo "[lint] FAILED: ${failed[*]}" >&2
    exit 1
fi
echo "[lint] passed: ${selected[*]}" >&2
