#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IGNORE_FILE="$REPO_ROOT/.chezmoiignore"
EXIT_CODE=0

echo "[test-chezmoiignore] testing platform file inclusion logic..." >&2

# Render .chezmoiignore for a given OS and check assertions
check_platform() {
    local os="$1"
    shift
    local must_ignore=()
    local must_include=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ignore) shift; must_ignore+=("$1") ;;
            --include) shift; must_include+=("$1") ;;
        esac
        shift
    done

    # Render the .chezmoiignore template for this OS
    local rendered
    rendered=$(chezmoi execute-template \
        --init \
        -d "chezmoi.os=$os" \
        -d "chezmoi.hostname=testhost" \
        -d "chezmoi.homeDir=/home/testuser" \
        < "$IGNORE_FILE" 2>/dev/null) || {
        echo "[test-chezmoiignore] FAIL: failed to render .chezmoiignore for os=$os" >&2
        EXIT_CODE=1
        return
    }

    # Check patterns that must be in the ignore list (i.e., excluded)
    for pattern in "${must_ignore[@]}"; do
        if ! echo "$rendered" | grep -qF "$pattern"; then
            echo "[test-chezmoiignore] FAIL ($os): expected '$pattern' to be IGNORED but it was not" >&2
            EXIT_CODE=1
        fi
    done

    # Check patterns that must NOT be in the ignore list (i.e., included)
    for pattern in "${must_include[@]}"; do
        if echo "$rendered" | grep -qF "$pattern"; then
            echo "[test-chezmoiignore] FAIL ($os): expected '$pattern' to be INCLUDED but it was ignored" >&2
            EXIT_CODE=1
        fi
    done

    echo "[test-chezmoiignore] PASS: os=$os" >&2
}

# Linux assertions
check_platform "linux" \
    --ignore "android-*.sh" \
    --ignore "windows-*.ps1" \
    --ignore ".termux" \
    --include ".docker" \
    --include ".kube"

# Windows assertions
check_platform "windows" \
    --ignore "linux-*.sh" \
    --ignore "android-*.sh" \
    --include ".ssh" \
    --include "AppData"

# Android assertions
check_platform "android" \
    --ignore "windows-*.ps1" \
    --ignore "linux-*.sh" \
    --ignore ".cursor" \
    --include ".termux" \
    --include ".config/mcphub"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-chezmoiignore] all platform logic tests passed" >&2
fi

exit $EXIT_CODE
