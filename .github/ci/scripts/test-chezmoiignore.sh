#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IGNORE_FILE="$REPO_ROOT/.chezmoiignore"
EXIT_CODE=0

echo "[test-chezmoiignore] testing platform file inclusion logic..." >&2

# The local model for Claude Code is gated on nvidia-smi being on PATH, so chezmoi renders with a
# PATH that holds only itself -- plus a fake nvidia-smi for --gpu -- and the host's own driver,
# present on a developer's WSL box and absent on a CI runner, never decides an assertion.
BIN_DIRS="$(mktemp -d)"
trap 'rm -rf "$BIN_DIRS"' EXIT
mkdir -p "$BIN_DIRS/gpu" "$BIN_DIRS/nogpu"
ln -s "$(command -v chezmoi)" "$BIN_DIRS/gpu/chezmoi"
ln -s "$(command -v chezmoi)" "$BIN_DIRS/nogpu/chezmoi"
printf '#!/bin/sh\necho "NVIDIA Test GPU, 24576 MiB"\n' > "$BIN_DIRS/gpu/nvidia-smi"
chmod +x "$BIN_DIRS/gpu/nvidia-smi"

# A config of its own, naming this checkout as the source and nothing else. Without one, chezmoi
# reads the developer's real config, whose data (deviceName) a CI runner never has: the suite
# then passes locally and fails on CI, which is how a template that required deviceName once got
# through. Lacking every data key is also the strictest case for .chezmoiignore, which is
# rendered before run_before_000-verify-chezmoi-config can report a stale config.
printf 'sourceDir: "%s"\n' "$REPO_ROOT" > "$BIN_DIRS/chezmoi.yaml"

# Render .chezmoiignore for a given OS and check assertions. --ignore and --include match a
# substring of the rendered list; --ignore-line and --include-line match a whole line, for an
# entry such as .config/systemd that is also the prefix of other entries.
check_platform() {
    local os="$1"
    shift
    local must_ignore=()
    local must_include=()
    local must_ignore_line=()
    local must_include_line=()
    local kernel=""
    local gpu="nogpu"
    local label

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ignore) shift; must_ignore+=("$1") ;;
            --include) shift; must_include+=("$1") ;;
            --ignore-line) shift; must_ignore_line+=("$1") ;;
            --include-line) shift; must_include_line+=("$1") ;;
            --kernel) shift; kernel="$1" ;;
            --gpu) gpu="gpu" ;;
        esac
        shift
    done

    label="os=$os"
    [[ -n "$kernel" ]] && label="$label kernel=$kernel"
    [[ "$gpu" == "gpu" ]] && label="$label gpu"

    # Render the .chezmoiignore template for this OS
    # chezmoi execute-template doesn't support overriding .chezmoi.os,
    # so we preprocess the template by substituting .chezmoi.os with the target value
    #
    # .chezmoi.kernel gets the same treatment, because "linux" alone does not say whether a
    # machine is WSL: the real kernel of whatever host runs this suite would otherwise decide
    # the WSL-gated assertions, passing on a developer's WSL box and failing on a CI runner.
    # Substituting a literal makes both branches assertable anywhere. The rendered value stays
    # a string, which is what `| toString` in the template already expects.
    #
    # The config points chezmoi at this checkout, whose .chezmoitemplates and .chezmoidata the
    # local-model gate reads; the default source directory is another clone, or nothing on CI.
    local rendered
    rendered=$(sed -e "s/\.chezmoi\.os/\"$os\"/g" \
                   ${kernel:+-e "s/\.chezmoi\.kernel/\"$kernel\"/g"} "$IGNORE_FILE" \
        | PATH="$BIN_DIRS/$gpu" chezmoi execute-template --config "$BIN_DIRS/chezmoi.yaml" 2>/dev/null) || {
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

    # The same two checks against whole lines
    for pattern in "${must_ignore_line[@]}"; do
        if ! echo "$rendered" | grep -qxF "$pattern"; then
            echo "[test-chezmoiignore] FAIL ($label): expected the line '$pattern' to be IGNORED but it was not" >&2
            EXIT_CODE=1
        fi
    done
    for pattern in "${must_include_line[@]}"; do
        if echo "$rendered" | grep -qxF "$pattern"; then
            echo "[test-chezmoiignore] FAIL ($label): expected the line '$pattern' to be INCLUDED but it was ignored" >&2
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

# Claude Code's look: Linux gets settings.json and the status line script from ~/.claude and
# nothing else there; Windows and Android keep the rest of ~/.claude and get no status line.
# Codex's look is built into Codex, so ~/.codex/config.toml ships everywhere.
check_platform "linux" \
    --include-line ".claude" \
    --include ".claude/settings.json" \
    --include ".claude/statusline-command.sh" \
    --ignore-line ".claude/CLAUDE.md" \
    --ignore-line ".claude/.claude.json" \
    --include ".codex"

check_platform "windows" \
    --include ".claude/settings.json" \
    --include ".claude/CLAUDE.md" \
    --include ".claude/.claude.json" \
    --ignore-line ".claude/statusline-command.sh" \
    --include ".codex"

check_platform "android" \
    --include ".claude/settings.json" \
    --include ".claude/CLAUDE.md" \
    --include ".claude/.claude.json" \
    --ignore-line ".claude/statusline-command.sh" \
    --include ".codex"

# WSL vs bare-metal Linux. The SSH agent bridge relays a Windows named pipe, so it must ship
# on WSL and nowhere else -- on bare metal its unit would point at an npiperelay.exe that is
# never installed. The only signal separating the two is the kernel release string.
check_platform "linux" --kernel "6.18.33.2-microsoft-standard-WSL2" \
    --include "ssh-agent-bridge" \
    --include-line ".config/systemd"

check_platform "linux" --kernel "6.11.0-generic" \
    --ignore "ssh-agent-bridge" \
    --ignore-line ".config/systemd"

# The bridge is Linux-only regardless of kernel: the other platforms either are Windows
# already or have no Windows agent to reach.
check_platform "windows" --kernel "6.18.33.2-microsoft-standard-WSL2" \
    --ignore-line ".config/systemd"

check_platform "android" --kernel "6.18.33.2-microsoft-standard-WSL2" \
    --ignore-line ".config/systemd"

# The local model for Claude Code (claude-local) ships wherever Linux has an NVIDIA driver, WSL
# or bare metal, and nowhere else. A machine without the bridge still needs .config/systemd for
# the Ollama unit.
check_platform "linux" --kernel "6.11.0-generic" --gpu \
    --ignore "ssh-agent-bridge" \
    --include "ollama.service" \
    --include "claude-local" \
    --include-line ".config/systemd"

check_platform "linux" --kernel "6.18.33.2-microsoft-standard-WSL2" --gpu \
    --include "ssh-agent-bridge" \
    --include "ollama.service" \
    --include "claude-local" \
    --include-line ".claude-local"

# The look of claude-local's profile, in ~/.claude-local, ships with claude-local and no further.
check_platform "linux" --kernel "6.18.33.2-microsoft-standard-WSL2" \
    --ignore "ollama.service" \
    --ignore ".local/bin/claude-local" \
    --ignore-line ".claude-local"

# A Windows machine with an NVIDIA card has nvidia-smi on PATH as well, so the OS check, not the
# driver, has to keep the Linux unit and launcher off it.
check_platform "windows" --gpu \
    --ignore "ollama.service" \
    --ignore ".local/bin/claude-local" \
    --ignore-line ".claude-local" \
    --ignore-line ".config/systemd"

# Tailscale reaches every Linux machine, GPU or not. claude-remote and claude-local-task drive
# claude-local, so they ship only where it does.
check_platform "linux" --kernel "6.11.0-generic" \
    --include-line ".local/bin/tailscale-up" \
    --ignore-line ".local/bin/claude-remote" \
    --ignore-line ".local/bin/claude-local-task"

check_platform "linux" --kernel "6.18.33.2-microsoft-standard-WSL2" --gpu \
    --include-line ".local/bin/tailscale-up" \
    --include-line ".local/bin/claude-remote" \
    --include-line ".local/bin/claude-local-task"

check_platform "windows" --gpu \
    --ignore-line ".local/bin/tailscale-up" \
    --ignore-line ".local/bin/claude-remote" \
    --ignore-line ".local/bin/claude-local-task"

check_platform "android" \
    --ignore-line ".local/bin/tailscale-up" \
    --ignore-line ".local/bin/claude-remote"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-chezmoiignore] all platform logic tests passed" >&2
fi

exit $EXIT_CODE
