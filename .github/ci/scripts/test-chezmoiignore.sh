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
    local kernel=""
    local label

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ignore) shift; must_ignore+=("$1") ;;
            --include) shift; must_include+=("$1") ;;
            --kernel) shift; kernel="$1" ;;
        esac
        shift
    done

    label="os=$os"
    [[ -n "$kernel" ]] && label="$label kernel=$kernel"

    # Render the .chezmoiignore template for this OS
    # chezmoi execute-template doesn't support overriding .chezmoi.os,
    # so we preprocess the template by substituting .chezmoi.os with the target value
    #
    # .chezmoi.kernel gets the same treatment, because "linux" alone does not say whether a
    # machine is WSL: the real kernel of whatever host runs this suite would otherwise decide
    # the WSL-gated assertions, passing on a developer's WSL box and failing on a CI runner.
    # Substituting a literal makes both branches assertable anywhere. The rendered value stays
    # a string, which is what `| toString` in the template already expects.
    local rendered
    rendered=$(sed -e "s/\.chezmoi\.os/\"$os\"/g" \
                   ${kernel:+-e "s/\.chezmoi\.kernel/\"$kernel\"/g"} "$IGNORE_FILE" \
        | chezmoi execute-template 2>/dev/null) || {
        echo "[test-chezmoiignore] FAIL: failed to render .chezmoiignore for $label" >&2
        EXIT_CODE=1
        return
    }

    # Check patterns that must be in the ignore list (i.e., excluded)
    for pattern in "${must_ignore[@]}"; do
        if ! echo "$rendered" | grep -qF "$pattern"; then
            echo "[test-chezmoiignore] FAIL ($label): expected '$pattern' to be IGNORED but it was not" >&2
            EXIT_CODE=1
        fi
    done

    # Check patterns that must NOT be in the ignore list (i.e., included)
    for pattern in "${must_include[@]}"; do
        if echo "$rendered" | grep -qF "$pattern"; then
            echo "[test-chezmoiignore] FAIL ($label): expected '$pattern' to be INCLUDED but it was ignored" >&2
            EXIT_CODE=1
        fi
    done

    echo "[test-chezmoiignore] PASS: $label" >&2
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
    --include ".termux" \
    --include ".config/mcphub"

# WSL vs bare-metal Linux. The SSH agent bridge relays a Windows named pipe, so it must ship
# on WSL and nowhere else -- on bare metal its unit would point at an npiperelay.exe that is
# never installed. The only signal separating the two is the kernel release string.
check_platform "linux" --kernel "6.18.33.2-microsoft-standard-WSL2" \
    --include ".config/systemd"

check_platform "linux" --kernel "6.11.0-generic" \
    --ignore ".config/systemd"

# The bridge is Linux-only regardless of kernel: the other platforms either are Windows
# already or have no Windows agent to reach.
check_platform "windows" --kernel "6.18.33.2-microsoft-standard-WSL2" \
    --ignore ".config/systemd"

check_platform "android" --kernel "6.18.33.2-microsoft-standard-WSL2" \
    --ignore ".config/systemd"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-chezmoiignore] all platform logic tests passed" >&2
fi

exit $EXIT_CODE
