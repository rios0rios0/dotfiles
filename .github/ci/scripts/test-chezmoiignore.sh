#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
IGNORE_FILE="$REPO_ROOT/.chezmoiignore"
EXIT_CODE=0

# The kernel string and OS name that the platform matrix below repeats, and the stack's four
# files, each named once here so a rename lands in every row at the same time.
WSL_KERNEL="6.18.33.2-microsoft-standard-WSL2"
WINDOWS_OS="windows"
LINUX_OS="linux"
ANDROID_OS="android"
METAL_KERNEL="6.11.0-generic"
BRIDGE_UNIT="ssh-agent-bridge"
OLLAMA_UNIT="ollama.service"
SYSTEMD_DIR=".config/systemd"
TAILSCALE_UP=".local/bin/tailscale-up"
TAILSCALE_WRAPPER=".local/bin/tailscale"
BACKUP_SCRIPT=".local/bin/omniroute-backup"
BACKUP_SERVICE=".config/systemd/user/omniroute-backup.service"
BACKUP_TIMER=".config/systemd/user/omniroute-backup.timer"
RESTORE_SCRIPT=".local/bin/omniroute-restore"

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
            *)
                echo "[test-chezmoiignore] FAIL: check_platform does not know the option '$1'" >&2
                EXIT_CODE=1
                ;;
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
check_platform "$LINUX_OS" \
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
check_platform "$ANDROID_OS" \
    --ignore "windows-*.ps1" \
    --ignore "linux-*.sh" \
    --include ".termux" \
    --include ".config/mcphub"

# Claude Code's look: Linux gets settings.json and the status line script from ~/.claude and
# nothing else there; Android keeps the trust dialog and gets no status line. Windows, where
# Claude Code is no longer installed, gets neither ~/.claude nor ~/.claude.json. The AI content
# of ~/.claude (CLAUDE.md, rules, agents, commands, skills) is aisync's, not chezmoi's.
check_platform "$LINUX_OS" \
    --include-line ".claude" \
    --include-line ".claude.json" \
    --include ".claude/settings.json" \
    --include ".claude/statusline-command.sh" \
    --ignore-line ".claude/.claude.json"

check_platform "$WINDOWS_OS" \
    --ignore-line ".claude" \
    --ignore-line ".claude.json"

check_platform "$ANDROID_OS" \
    --include-line ".claude" \
    --include-line ".claude.json" \
    --include ".claude/settings.json" \
    --include ".claude/.claude.json" \
    --ignore-line ".claude/statusline-command.sh"

# WSL's settings live in Windows' %UserProfile%\.wslconfig, so only Windows gets the file.
check_platform "$WINDOWS_OS" --include-line ".wslconfig"
check_platform "$LINUX_OS" --ignore-line ".wslconfig"
check_platform "$ANDROID_OS" --ignore-line ".wslconfig"

# PowerShell 7's profile, which Windows Terminal dot-sources; on Linux the same path is pwsh's own
# profile, and nothing here installs pwsh there.
check_platform "$WINDOWS_OS" --include-line ".config/powershell"
check_platform "$LINUX_OS" --ignore-line ".config/powershell"
check_platform "$ANDROID_OS" --ignore-line ".config/powershell"

# The JetBrains themes are staged for the one script that fans them out, on Linux; Windows lost
# its counterpart with the Toolbox, and Android never had one.
check_platform "$LINUX_OS" --include ".local/share/jetbrains-themes"
check_platform "$WINDOWS_OS" --ignore-line ".local/share/jetbrains-themes"
check_platform "$ANDROID_OS" --ignore-line ".local/share/jetbrains-themes"

# ggshield's pre-commit hook is wired on Linux alone, and so is the ~/.config/git/ignore that
# answers its `git check-ignore` (ggshield runs git without the global config, so
# `core.excludesFile` never reaches it).
check_platform "$LINUX_OS" --include-line ".config/git/ignore"
check_platform "$WINDOWS_OS" --ignore-line ".config/git/ignore"
check_platform "$ANDROID_OS" --ignore-line ".config/git/ignore"

# Git checks commit signatures against an allowed-signers file. .ssh is not deployed on Linux, so
# Linux gets its copy beside .config/git/ignore, and Windows and Android read the one in .ssh.
check_platform "$LINUX_OS" --include-line ".config/git/allowed_signers"
check_platform "$WINDOWS_OS" --ignore-line ".config/git/allowed_signers"
check_platform "$ANDROID_OS" --ignore-line ".config/git/allowed_signers"

# Atuin's client config: every zsh records its history through Atuin, on Linux and Termux alike;
# Windows runs no zsh.
check_platform "$LINUX_OS" --include-line ".config/atuin"
check_platform "$ANDROID_OS" --include-line ".config/atuin"
check_platform "$WINDOWS_OS" --ignore-line ".config/atuin"

# aisync's exclusions keep aifiles' Linux/WSL copies of three files off the phone; everywhere else
# ~/.config/aisync is aisync's own, so chezmoi must not create or own it.
check_platform "$ANDROID_OS" --include-line ".config/aisync"
check_platform "$LINUX_OS" --ignore-line ".config/aisync"
check_platform "$WINDOWS_OS" --ignore-line ".config/aisync"

# WSL vs bare-metal Linux. The SSH agent bridge relays a Windows named pipe, so it must ship
# on WSL and nowhere else -- on bare metal its unit would point at an npiperelay.exe that is
# never installed. The only signal separating the two is the kernel release string.
check_platform "$LINUX_OS" --kernel "$WSL_KERNEL" \
    --include "$BRIDGE_UNIT" \
    --include-line "$SYSTEMD_DIR"

check_platform "$LINUX_OS" --kernel "$METAL_KERNEL" \
    --ignore "$BRIDGE_UNIT" \
    --ignore-line "$SYSTEMD_DIR"

# The bridge is Linux-only regardless of kernel: the other platforms either are Windows
# already or have no Windows agent to reach.
check_platform "$WINDOWS_OS" --kernel "$WSL_KERNEL" \
    --ignore-line "$SYSTEMD_DIR"

check_platform "$ANDROID_OS" --kernel "$WSL_KERNEL" \
    --ignore-line "$SYSTEMD_DIR"

# The local model server (Ollama) ships wherever Linux has an NVIDIA driver, WSL or bare metal, and
# nowhere else. A machine without the bridge still needs .config/systemd for the Ollama unit.
check_platform "$LINUX_OS" --kernel "$METAL_KERNEL" --gpu \
    --ignore "$BRIDGE_UNIT" \
    --include "$OLLAMA_UNIT" \
    --include-line "$SYSTEMD_DIR"

check_platform "$LINUX_OS" --kernel "$WSL_KERNEL" --gpu \
    --include "$BRIDGE_UNIT" \
    --include "$OLLAMA_UNIT"

check_platform "$LINUX_OS" --kernel "$WSL_KERNEL" \
    --ignore "$OLLAMA_UNIT"

# A Windows machine with an NVIDIA card has nvidia-smi on PATH as well, so the OS check, not the
# driver, has to keep the Linux unit off it.
check_platform "$WINDOWS_OS" --gpu \
    --ignore "$OLLAMA_UNIT" \
    --ignore-line "$SYSTEMD_DIR"

# The OmniRoute stack runs from the dotfiles checkout, where its .env lives; chezmoi deploys none
# of it, on any platform.
check_platform "$LINUX_OS" --kernel "$WSL_KERNEL" --gpu \
    --ignore-line "local-services"

check_platform "$WINDOWS_OS" \
    --ignore-line "local-services"

check_platform "$ANDROID_OS" \
    --ignore-line "local-services"

# Tailscale reaches every Linux machine, GPU or not. The tailscale wrapper runs Windows' CLI, which
# is WSL's client, so it ships to WSL alone: on bare metal it would shadow tailscaled's own CLI.
check_platform "$LINUX_OS" --kernel "$METAL_KERNEL" \
    --include-line "$TAILSCALE_UP" \
    --ignore-line "$TAILSCALE_WRAPPER"

check_platform "$LINUX_OS" --kernel "$WSL_KERNEL" --gpu \
    --include-line "$TAILSCALE_UP" \
    --include-line "$TAILSCALE_WRAPPER"

check_platform "$WINDOWS_OS" --gpu \
    --ignore-line "$TAILSCALE_UP" \
    --ignore-line "$TAILSCALE_WRAPPER"

check_platform "$ANDROID_OS" \
    --ignore-line "$TAILSCALE_UP" \
    --ignore-line "$TAILSCALE_WRAPPER"

# The OmniRoute backups and their restore serve the local stack, which runs from the dotfiles
# checkout on WSL alone; both scripts and both units ship there and nowhere else.
check_platform "$LINUX_OS" --kernel "$METAL_KERNEL" \
    --ignore-line "$BACKUP_SCRIPT" \
    --ignore-line "$BACKUP_SERVICE" \
    --ignore-line "$BACKUP_TIMER" \
    --ignore-line "$RESTORE_SCRIPT"

check_platform "$LINUX_OS" --kernel "$WSL_KERNEL" \
    --include-line "$BACKUP_SCRIPT" \
    --include-line "$BACKUP_SERVICE" \
    --include-line "$BACKUP_TIMER" \
    --include-line "$RESTORE_SCRIPT"

check_platform "$WINDOWS_OS" \
    --ignore-line "$BACKUP_SCRIPT" \
    --ignore-line "$BACKUP_SERVICE" \
    --ignore-line "$BACKUP_TIMER" \
    --ignore-line "$RESTORE_SCRIPT"

check_platform "$ANDROID_OS" \
    --ignore-line "$BACKUP_SCRIPT" \
    --ignore-line "$BACKUP_SERVICE" \
    --ignore-line "$BACKUP_TIMER" \
    --ignore-line "$RESTORE_SCRIPT"

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-chezmoiignore] all platform logic tests passed" >&2
fi

exit $EXIT_CODE
