#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IGNORE_FILE="$REPO_ROOT/.chezmoiignore"
EXIT_CODE=0

# The kernel string and OS name that the platform matrix below repeats, and the stack's three
# files, each named once here so a rename lands in every row at the same time.
WSL_KERNEL="6.18.33.2-microsoft-standard-WSL2"
WINDOWS_OS="windows"
BACKUP_SCRIPT=".local/bin/omniroute-backup"
BACKUP_SERVICE=".config/systemd/user/omniroute-backup.service"
BACKUP_TIMER=".config/systemd/user/omniroute-backup.timer"

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
check_platform "$WINDOWS_OS" \
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
# nothing else there; Android keeps the trust dialog and gets no status line. Windows, where
# Claude Code is no longer installed, gets neither ~/.claude nor ~/.claude.json. The AI content
# of ~/.claude (CLAUDE.md, rules, agents, commands, skills) is aisync's, not chezmoi's. Codex is
# installed on Android alone, so ~/.codex/config.toml ships nowhere else.
check_platform "linux" \
    --include-line ".claude" \
    --include-line ".claude.json" \
    --include ".claude/settings.json" \
    --include ".claude/statusline-command.sh" \
    --ignore-line ".claude/.claude.json" \
    --ignore-line ".codex"

check_platform "$WINDOWS_OS" \
    --ignore-line ".claude" \
    --ignore-line ".claude.json" \
    --ignore-line ".codex"

check_platform "android" \
    --include-line ".claude" \
    --include-line ".claude.json" \
    --include ".claude/settings.json" \
    --include ".claude/.claude.json" \
    --ignore-line ".claude/statusline-command.sh" \
    --include-line ".codex"

# The JetBrains themes are staged for the one script that fans them out, on Linux; Windows lost
# its counterpart with the Toolbox, and Android never had one.
check_platform "linux" --include ".local/share/jetbrains-themes"
check_platform "$WINDOWS_OS" --ignore-line ".local/share/jetbrains-themes"
check_platform "android" --ignore-line ".local/share/jetbrains-themes"

# ggshield's pre-commit hook is wired on Linux alone, and so is the ~/.config/git/ignore that
# answers its `git check-ignore` (ggshield runs git without the global config, so
# `core.excludesFile` never reaches it).
check_platform "linux" --include-line ".config/git/ignore"
check_platform "$WINDOWS_OS" --ignore-line ".config/git/ignore"
check_platform "android" --ignore-line ".config/git/ignore"

# WSL vs bare-metal Linux. The SSH agent bridge relays a Windows named pipe, so it must ship
# on WSL and nowhere else -- on bare metal its unit would point at an npiperelay.exe that is
# never installed. The only signal separating the two is the kernel release string.
check_platform "linux" --kernel "$WSL_KERNEL" \
    --include "ssh-agent-bridge" \
    --include-line ".config/systemd"

check_platform "linux" --kernel "6.11.0-generic" \
    --ignore "ssh-agent-bridge" \
    --ignore-line ".config/systemd"

# The bridge is Linux-only regardless of kernel: the other platforms either are Windows
# already or have no Windows agent to reach.
check_platform "$WINDOWS_OS" --kernel "$WSL_KERNEL" \
    --ignore-line ".config/systemd"

check_platform "android" --kernel "$WSL_KERNEL" \
    --ignore-line ".config/systemd"

# The local model server (Ollama) ships wherever Linux has an NVIDIA driver, WSL or bare metal, and
# nowhere else. A machine without the bridge still needs .config/systemd for the Ollama unit.
check_platform "linux" --kernel "6.11.0-generic" --gpu \
    --ignore "ssh-agent-bridge" \
    --include "ollama.service" \
    --include-line ".config/systemd"

check_platform "linux" --kernel "$WSL_KERNEL" --gpu \
    --include "ssh-agent-bridge" \
    --include "ollama.service"

check_platform "linux" --kernel "$WSL_KERNEL" \
    --ignore "ollama.service"

# A Windows machine with an NVIDIA card has nvidia-smi on PATH as well, so the OS check, not the
# driver, has to keep the Linux unit off it.
check_platform "$WINDOWS_OS" --gpu \
    --ignore "ollama.service" \
    --ignore-line ".config/systemd"

# The OmniRoute stack runs from the dotfiles checkout, where its .env lives; chezmoi deploys none
# of it, on any platform.
check_platform "linux" --kernel "$WSL_KERNEL" --gpu \
    --ignore-line "local-services"

check_platform "$WINDOWS_OS" \
    --ignore-line "local-services"

check_platform "android" \
    --ignore-line "local-services"

# Tailscale reaches every Linux machine, GPU or not. The tailscale wrapper runs Windows' CLI, which
# is WSL's client, so it ships to WSL alone: on bare metal it would shadow tailscaled's own CLI.
check_platform "linux" --kernel "6.11.0-generic" \
    --include-line ".local/bin/tailscale-up" \
    --ignore-line ".local/bin/tailscale"

check_platform "linux" --kernel "$WSL_KERNEL" --gpu \
    --include-line ".local/bin/tailscale-up" \
    --include-line ".local/bin/tailscale"

check_platform "$WINDOWS_OS" --gpu \
    --ignore-line ".local/bin/tailscale-up" \
    --ignore-line ".local/bin/tailscale"

check_platform "android" \
    --ignore-line ".local/bin/tailscale-up" \
    --ignore-line ".local/bin/tailscale"

# The OmniRoute backups serve the local stack, which runs from the dotfiles checkout on WSL alone;
# the script and both units ship there and nowhere else.
check_platform "linux" --kernel "6.11.0-generic" \
    --ignore-line "$BACKUP_SCRIPT" \
    --ignore-line "$BACKUP_SERVICE" \
    --ignore-line "$BACKUP_TIMER"

check_platform "linux" --kernel "$WSL_KERNEL" \
    --include-line "$BACKUP_SCRIPT" \
    --include-line "$BACKUP_SERVICE" \
    --include-line "$BACKUP_TIMER"

check_platform "$WINDOWS_OS" \
    --ignore-line "$BACKUP_SCRIPT" \
    --ignore-line "$BACKUP_SERVICE" \
    --ignore-line "$BACKUP_TIMER"

check_platform "android" \
    --ignore-line "$BACKUP_SCRIPT" \
    --ignore-line "$BACKUP_SERVICE" \
    --ignore-line "$BACKUP_TIMER"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-chezmoiignore] all platform logic tests passed" >&2
fi

exit $EXIT_CODE
