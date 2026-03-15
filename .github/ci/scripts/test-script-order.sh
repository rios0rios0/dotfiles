#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/.chezmoiscripts"
EXIT_CODE=0

echo "[test-script-order] verifying script execution order..." >&2

# Verify that scripts sort in the correct dependency order
check_order() {
    local platform="$1"
    shift
    local expected=("$@")

    # Get actual sorted order of run_once_before scripts for this platform
    local actual=()
    while IFS= read -r line; do
        actual+=("$(basename "$line")")
    done < <(find "$SCRIPTS_DIR" -name "run_once_before_${platform}-*" -type f | sort)

    # Verify each expected prefix appears in order
    local last_idx=-1
    for expected_pattern in "${expected[@]}"; do
        local found=false
        for i in "${!actual[@]}"; do
            if [[ "${actual[$i]}" == *"$expected_pattern"* ]]; then
                if [ "$i" -le "$last_idx" ]; then
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

    echo "[test-script-order] PASS: $platform (${#actual[@]} scripts in correct order)" >&2
}

# Android: wrapper → op wrapper → gh wrapper → install deps → fonts
check_order "android" \
    "001-create-wrapper" \
    "001a-create-op-wrapper" \
    "001b-create-gh-wrapper" \
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

# Verify run_once_before sorts before run_after for each platform
for platform in android linux windows; do
    # Get the last run_once_before script name
    last_before=$(find "$SCRIPTS_DIR" -name "run_once_before_${platform}-*" -type f | sort | tail -1 || true)
    # Get the first run_after script name
    first_after=$(find "$SCRIPTS_DIR" -name "run_after_${platform}-*" -type f | sort | head -1 || true)

    if [ -n "$last_before" ] && [ -n "$first_after" ]; then
        last_before_name=$(basename "$last_before")
        first_after_name=$(basename "$first_after")
        if [[ "$last_before_name" > "$first_after_name" ]]; then
            echo "[test-script-order] FAIL ($platform): run_once_before '$last_before_name' sorts after run_after '$first_after_name'" >&2
            EXIT_CODE=1
        fi
    fi
done

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-script-order] all script ordering tests passed" >&2
fi

exit $EXIT_CODE
