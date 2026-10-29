#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/.chezmoiscripts"
EXIT_CODE=0

echo "[test-script-order] verifying script execution order..." >&2

# Verify that scripts sort in the correct dependency order. PHASE picks the before-scripts (the
# default) or the after-scripts, which chezmoi orders the same way among themselves.
check_order() {
    local platform="$1"
    shift
    local expected=("$@")
    local phase="${PHASE:-before}"

    # Get actual sorted order of the platform's before scripts, run_once_ and run_before_ alike.
    # chezmoi orders scripts by target name, which drops the `run_*_` attributes, so the sort
    # key is the name without them.
    local actual=()
    while IFS= read -r line; do
        actual+=("$line")
    # LC_ALL=C is required: chezmoi orders scripts by Go byte comparison, whereas
    # a locale-aware sort (e.g. en_US.UTF-8) ignores the '-' separator and would
    # place "001a-create-op-wrapper" before "001-create-wrapper".
    done < <(find "$SCRIPTS_DIR" \( -name "run_once_${phase}_${platform}-*" -o -name "run_onchange_${phase}_${platform}-*" \
        -o -name "run_${phase}_${platform}-*" \) -type f \
        -printf '%f\n' | sed -E "s/^run_(once_|onchange_)?${phase}_//" | LC_ALL=C sort)

    # Verify each expected prefix appears in order
    local last_idx=-1
    for expected_pattern in "${expected[@]}"; do
        local found=false
        for i in "${!actual[@]}"; do
            if [[ "${actual[$i]}" == *"$expected_pattern"* ]]; then
                if [[ "$i" -le "$last_idx" ]]; then
                    echo "[test-script-order] FAIL ($platform): '$expected_pattern' sorts before a previous dependency" >&2
                    EXIT_CODE=1
                fi
                last_idx=$i
                found=true
                break
            fi
        done
        if ! $found; then
            echo "[test-script-order] FAIL ($platform): expected script matching '$expected_pattern' not found" >&2
            EXIT_CODE=1
        fi
    done

    echo "[test-script-order] PASS: $platform $phase (${#actual[@]} scripts in correct order)" >&2
}

# Android: wrapper → op → gh → golangci-lint → acli → claude wrappers → install deps → fonts
check_order "android" \
    "001-create-wrapper" \
    "001a-create-op-wrapper" \
    "001b-create-gh-wrapper" \
    "001c-create-golangci-lint-wrapper" \
    "001d-create-acli-wrapper" \
    "001e-create-claude-wrapper" \
    "002-install-dependencies" \
    "003-install-fonts"

# Linux: op wrapper → install deps → configure deps → fonts → export key
check_order "linux" \
    "001-create-op-wrapper" \
    "002-install-dependencies" \
    "003-configure-dependencies" \
    "004-install-fonts" \
    "005-export-private-key"

# Windows: install deps → configure deps → fonts → export key
check_order "windows" \
    "001-install-dependencies" \
    "002-configure-dependencies" \
    "003-install-fonts" \
    "004-export-private-key"

# After the files: aisync's pull lands after the Sentry CLI's skill and the LSP plugins, so a first
# sync gives aifiles' copy of what they write the last word.
PHASE=after check_order "linux" \
    "007-setup-sentry-cli" \
    "012-setup-claude-lsp" \
    "014-sync-aifiles"

PHASE=after check_order "android" \
    "006-setup-sentry-cli" \
    "008-sync-aifiles"

# Atuin: the login comes before the one-time import, whose sync uploads what it imported. Both are
# after-scripts, so the files (the client's config) and the installers (atuin, sqlite3) come first.
PHASE=after check_order "linux" \
    "016-login-atuin" \
    "017-import-atuin-history"

PHASE=after check_order "android" \
    "009-login-atuin" \
    "010-import-atuin-history"

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-script-order] all script ordering tests passed" >&2
fi

exit $EXIT_CODE
