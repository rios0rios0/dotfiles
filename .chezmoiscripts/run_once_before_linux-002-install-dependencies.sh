#!/bin/bash

# update the package list (once, upfront — all apt installs below reuse this cache)
sudo apt update

# =========================================================================================================
# Requirements for this repository to work properly
requirements=(
    "git"
    "curl"
    "zip"           # required for SDKMan
    "unzip"         # required for SDKMan
    "age"           # required for Chezmoi (decrypt files with SSH)
    "gpg"           # required for import and export GPGs
    "gpg-agent"     # required for import and export GPGs
    "zsh"           # required as the target shell (must be installed before oh-my-zsh and shell change)
    "eza"           # it's for "ls" highlighting (https://github.com/eza-community/eza)
    "sqlite3"       # it's for managing ZSH history (https://github.com/larkery/zsh-histdb)
    "bsdmainutils"  # hexdump is a utility for displaying file contents in hexadecimal required by GVM (Go Version Manager)
    "binutils"      # required by GVM (Go Version Manager)
    "bison"         # required by GVM (Go Version Manager)
    "gcc"           # required for many things and GVM
    "clang"         # required by some Go/Rust/C toolchains as an alternative to gcc
    "make"          # required for many things and GVM
)
sudo apt install --no-install-recommends --yes "${requirements[@]}"
# =========================================================================================================
# Hardware
hardware=(
    "htop"          # it's for monitoring system resources
    "screenfetch"   # it's for displaying system information
)
sudo apt install --no-install-recommends --yes "${hardware[@]}"
# =========================================================================================================
# Utilities
utilities=(
    #"imagemagick"       # it's for image manipulation (convert, identify, etc.) TODO: better to use on Windows?
    "jq"                # it's for parsing JSON
    "yq"                # it's for parsing YAML
    "bat"               # it's for cat with syntax highlighting (https://github.com/sharkdp/bat)
    "ripgrep"           # it's for recursively searching files with regex (https://github.com/BurntSushi/ripgrep)
    "silversearcher-ag" # it's for searching files (https://github.com/ggreer/the_silver_searcher)
    "inotify-tools"     # it's for watching file changes ("inotifywait")
    "dos2unix"          # it's for converting text files between Unix and DOS formats
    "expect"            # it's for automating interactive applications (used in some scripts)
    "aria2"             # cURL alternative with many features (command is aria2c)
    "file"              # it's for determining file types
    "parallel"          # it runs many threads of a command at the same time
    "cloc"              # it's for counting lines of code
    "rename"            # it's for bulk file renaming
    "whois"             # it's for domain lookup
    "ffmpeg"            # it's for media processing (used by conversion aliases in .zshrc)
    "rsync"             # it's for file synchronization
    "asciinema"         # it's for recording terminal sessions (https://asciinema.org/)
    "shellcheck"        # it's for static analysis of shell scripts (used by `make lint`)
    "postgresql-client" # provides the `psql` client only (no server, unlike the `postgresql` package)
)
sudo apt install --no-install-recommends --yes "${utilities[@]}"
# =========================================================================================================
# =========================================================================================================
# https://ohmyz.sh/#install
install_oh_my_zsh() {
    if [[ -d "${ZSH:-$HOME/.oh-my-zsh}" ]]; then
        echo "[configure-deps] oh-my-zsh is already installed, skipping" >&2
        return
    fi
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
}

# https://github.com/moovweb/gvm?tab=readme-ov-file
install_gvm() {
    # Query the latest stable Go release from the official endpoint.
    # https://go.dev/VERSION?m=text returns a body whose first line is "goX.Y.Z".
    local go_version
    go_version="$(curl -fsSL https://go.dev/VERSION?m=text 2>/dev/null | head -n1 | tr -d '[:space:]')" || true
    if [[ -z "$go_version" || "$go_version" != go* ]]; then
        echo "[configure-deps] ERROR: failed to resolve latest Go version from https://go.dev/VERSION?m=text" >&2
        return 1
    fi
    echo "[configure-deps] latest Go version resolved: $go_version" >&2

    if [[ ! -d "$HOME/.gvm" ]]; then
        bash < <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)
    else
        echo "[configure-deps] GVM is already installed, skipping clone" >&2
    fi

    # Source GVM to make it available in the current shell
    export GVM_ROOT="$HOME/.gvm"
    # shellcheck source=/dev/null
    [[ -s "$GVM_ROOT/scripts/gvm" ]] && source "$GVM_ROOT/scripts/gvm"

    if [[ -d "$GVM_ROOT/gos/$go_version" ]]; then
        echo "[configure-deps] $go_version is already installed, skipping" >&2
    else
        gvm install "$go_version" -B
    fi
    gvm use "$go_version" --default
}

# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
install_kubectl() {
    if command -v kubectl &>/dev/null; then
        echo "[configure-deps] kubectl is already installed, skipping" >&2
        return
    fi

    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list

    sudo apt update && sudo apt install --no-install-recommends --yes kubectl
}

# https://krew.sigs.k8s.io/docs/user-guide/setup/install/
#
# `kubectl krew` fetches its plugin index from `kubernetes-sigs/krew-index` on
# every operation. GitHub occasionally returns HTTP 500 for this repo, which
# fails `update`/`upgrade`/`install`. We retry a few times and treat persistent
# failures as non-fatal so a transient outage doesn't break `chezmoi apply`.
krew_retry() {
    local max_attempts=3
    local attempt=1
    while (( attempt <= max_attempts )); do
        if kubectl krew "$@"; then
            return 0
        fi
        echo "[configure-deps] WARN: 'kubectl krew $*' failed (attempt ${attempt}/${max_attempts})" >&2
        attempt=$(( attempt + 1 ))
        (( attempt <= max_attempts )) && sleep 5
    done
    echo "[configure-deps] WARN: 'kubectl krew $*' failed after ${max_attempts} attempts; continuing" >&2
    return 0
}

install_krew() {
    if [[ -d "${KREW_ROOT:-$HOME/.krew}" ]] && command -v kubectl-krew &>/dev/null; then
        echo "[configure-deps] krew is already installed, skipping download" >&2
    else
        (
          set -x; cd "$(mktemp -d)" &&
          OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
          ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
          KREW="krew-${OS}_${ARCH}" &&
          curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
          tar zxvf "${KREW}.tar.gz" &&
          ./"${KREW}" install krew
        )
    fi

    # Add krew to PATH for current session
    export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

    # Upgrade krew itself and all installed plugins to the latest release
    krew_retry upgrade

    krew_retry install ctx
    krew_retry install ns
}

# https://github.com/rios0rios0/terra
# https://terragrunt.gruntwork.io/docs/getting-started/install/
# https://developer.hashicorp.com/terraform/install
#
# `terra` is the cross-platform launcher that pins and fetches the matching
# `terraform`/`terragrunt` versions per project. Letting it own the install
# replaces the previous one-off `install_terraform` (HashiCorp apt repo) and
# `install_terragrunt` (direct GitHub release download) functions and keeps
# Linux/WSL aligned with Android, where this has always been the only path.
# `terra update` itself downloads the matching `terraform`/`terragrunt`
# binaries; on Linux they are vanilla `GOOS=linux` Go executables that run
# natively under glibc, so no `termux-etc-seccomp`-style wrapping is needed
# (that part is Android-only and lives in `run_after_android-003-wrap-terra-clis.sh`).
install_terra() {
    if command -v terra &>/dev/null; then
        echo "[configure-deps] terra is already installed, skipping" >&2
    else
        local installer
        local status

        installer="$(mktemp)"
        if ! curl -fsSL https://raw.githubusercontent.com/rios0rios0/terra/main/install.sh -o "$installer"; then
            echo "[configure-deps] ERROR: failed to download terra installer" >&2
            rm -f "$installer"
            return 1
        fi

        bash "$installer"
        status=$?
        rm -f "$installer"
        if [ "$status" -ne 0 ]; then return "$status"; fi
    fi

    # Keep terra itself up to date — `terra update` only refreshes
    # terraform/terragrunt and emits a warning when a newer terra exists.
    # `--force` skips the interactive prompt.
    terra self-update --force || echo "[configure-deps] WARN: terra self-update failed; continuing" >&2

    # `terra update` (alias of `install`) prompts y/N when newer
    # terraform/terragrunt versions are detected and exposes no auto-answer
    # flag in the currently installed binary. Pipe `yes` to stdin so the
    # prompts auto-confirm during unattended `chezmoi apply` runs.
    yes y | terra update
}

# https://sdkman.io/install/
install_sdkman() {
    if [[ -d "$HOME/.sdkman" ]]; then
        echo "[configure-deps] SDKMAN is already installed, skipping download" >&2
    else
        curl -s "https://get.sdkman.io" | bash
    fi

    # Source SDKMAN to make it available in the current shell
    export SDKMAN_DIR="$HOME/.sdkman"
    # shellcheck source=/dev/null
    [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

    # SDKMAN writes download headers/post-install hooks to `$SDKMAN_DIR/tmp`
    # before running curl. The directory occasionally goes missing (e.g. after
    # a manual cleanup) and `sdk install` fails with
    # "curl: Failed to open .../*.headers.tmp". Recreate it defensively.
    mkdir -p "$SDKMAN_DIR/tmp"

    # Keep SDKMAN itself up to date so candidate metadata (new Java/Gradle
    # versions, broker URLs) refreshes on every apply.
    sdk selfupdate force >/dev/null 2>&1 || echo "[configure-deps] WARN: sdk selfupdate failed; continuing" >&2

    sdk install java
    sdk install gradle
}

# https://github.com/nvm-sh/nvm?tab=readme-ov-file#install--update-script
install_nvm() {
    if [[ ! -d "$HOME/.nvm" ]]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash
    else
        echo "[configure-deps] NVM is already installed, skipping download" >&2
    fi

    # Source NVM to make it available in the current shell
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

    local lts_version
    lts_version="$(nvm version-remote --lts 2>/dev/null)" || true
    local current_version
    current_version="$(nvm current 2>/dev/null)" || true

    if [[ -n "$lts_version" && "$current_version" == "$lts_version" ]]; then
        echo "[configure-deps] Node.js LTS $lts_version is already installed, skipping" >&2
    else
        nvm install --lts
    fi

    npm install -g corepack
    corepack enable
}

# https://github.com/pyenv/pyenv
install_pyenv() {
    local python_version="3.13.2"

    if [[ ! -d "$HOME/.pyenv" ]]; then
        curl https://pyenv.run | bash
    else
        echo "[configure-deps] pyenv is already installed, skipping clone" >&2
    fi

    # Source pyenv to make it available in the current shell
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"

    # https://github.com/pyenv/pyenv/wiki#suggested-build-environment
    sudo apt install --no-install-recommends --yes build-essential libssl-dev zlib1g-dev \
      libbz2-dev libreadline-dev libsqlite3-dev curl git \
      libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

    if pyenv versions --bare 2>/dev/null | grep -qx "$python_version"; then
        echo "[configure-deps] Python $python_version is already installed, skipping build" >&2
    else
        pyenv install "$python_version"
    fi
    pyenv global "$python_version"

    # Rehash to make pyenv/pip available
    eval "$(pyenv init -)"
}

# https://cursor.com/docs/cli/installation
install_cursor_cli() {
    if command -v agent &>/dev/null; then
        echo "[configure-deps] Cursor CLI is already installed, skipping" >&2
        return
    fi
    curl https://cursor.com/install -fsSL | bash
}

# https://github.com/anthropics/claude-code
install_claude_cli() {
    if command -v claude &>/dev/null; then
        echo "[configure-deps] Claude CLI is already installed, skipping" >&2
        return
    fi
    npm install -g @anthropic-ai/claude-code
}

# https://github.com/google-gemini/gemini-cli
install_gemini_cli() {
    if command -v gemini &>/dev/null; then
        echo "[configure-deps] Gemini CLI is already installed, skipping" >&2
        return
    fi
    npm install -g @google/gemini-cli
}

# https://github.com/rios0rios0/dev-toolkit
install_dev_toolkit() {
    if command -v dev &>/dev/null; then
        echo "[configure-deps] dev-toolkit is already installed, skipping" >&2
        return
    fi

    local installer
    local status

    installer="$(mktemp)"
    if ! curl -fsSL https://raw.githubusercontent.com/rios0rios0/dev-toolkit/main/install.sh -o "$installer"; then
        echo "[dev-toolkit] ERROR: failed to download installer" >&2
        rm -f "$installer"
        return 1
    fi

    bash "$installer"
    status=$?
    rm -f "$installer"

    return "$status"
}

# https://cli.github.com/manual/installation
install_github_cli() {
    if command -v gh &>/dev/null; then
        echo "[configure-deps] GitHub CLI is already installed, skipping" >&2
        return
    fi

    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

    sudo apt update && sudo apt install --no-install-recommends --yes gh
}

# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
install_aws_cli() {
    if command -v aws &>/dev/null && aws --version 2>&1 | grep -q "aws-cli/2\."; then
        echo "[configure-deps] AWS CLI v2 is already installed, skipping" >&2
        return
    fi

    local arch
    case "$(uname -m)" in
        x86_64)          arch="x86_64"  ;;
        aarch64 | arm64) arch="aarch64" ;;
        *)
            echo "[aws-cli] ERROR: unsupported architecture: $(uname -m)" >&2
            return 1
            ;;
    esac

    (
        tmpDir="$(mktemp -d)" || {
            echo "[aws-cli] ERROR: failed to create temporary directory" >&2
            exit 1
        }

        trap 'rm -rf "$tmpDir"' EXIT
        cd "$tmpDir" || exit 1

        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip" -o awscliv2.zip
        unzip -q awscliv2.zip

        # Use --update when a previous install is present so the script is idempotent.
        local args=()
        if [ -d /usr/local/aws-cli ]; then
            args=(--bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update)
        fi
        sudo ./aws/install "${args[@]}"
    )
}

# https://pypi.org/project/azure-cli/
install_azure_cli() {
    # Ensure pip is available from pyenv's Python
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"

    if pip show azure-cli &>/dev/null; then
        echo "[configure-deps] azure-cli is already installed, skipping" >&2
        return
    fi

    pip install --upgrade pip
    pip install azure-cli
}

# https://docs.gitguardian.com/ggshield-docs/getting-started
install_ggshield() {
    # Ensure pip is available from pyenv's Python (so pipx lives in the managed Python)
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"

    # Use `python -m pipx` throughout to avoid pyenv shim timing issues:
    # `pip install pipx` places the shim, but it only becomes callable after
    # `pyenv rehash`, which isn't guaranteed in a non-interactive script context.
    if ! python -m pip show pipx &>/dev/null; then
        python -m pip install --upgrade pipx
        python -m pipx ensurepath
    else
        echo "[configure-deps] pipx is already installed, skipping" >&2
    fi

    if python -m pipx list --short 2>/dev/null | grep -q '^ggshield '; then
        # ggshield prints "A new version of ggshield has been released" on
        # every invocation when out of date. Auto-upgrade keeps it current.
        echo "[configure-deps] ggshield is already installed, upgrading via pipx" >&2
        python -m pipx upgrade ggshield || echo "[configure-deps] WARN: pipx upgrade ggshield failed; continuing" >&2
    else
        python -m pipx install ggshield
    fi

    if ! python -m pipx list --short 2>/dev/null | grep -q '^ggshield '; then
        echo "[configure-deps] ERROR: ggshield installation failed" >&2
        exit 1
    fi
}

# https://docs.astral.sh/ruff/
#
# `ruff` is a self-contained Rust binary distributed by Astral, so we install
# it via the upstream `install.sh` (drops the binary into `~/.cargo/bin/ruff`
# or `~/.local/bin/ruff` depending on the host). This replaces the previous
# `pipx install ruff` route, which:
#   1. Required a working Python + pipx toolchain.
#   2. Was fragile across pipx versions — pre-`0.15` pipx writes metadata
#      formats that newer pipx refuses to manage, leaving an unreachable
#      venv on disk with no `~/.local/bin/ruff` shim.
# Debian/Ubuntu apt repositories are not a viable alternative: only `sid` and
# `plucky` ship a `ruff` package at all, and both pin `0.0.291+dfsg1-4` (Aug
# 2023) — three years behind upstream. The `install.sh` route always pulls
# the matching latest release.
install_ruff() {
    # Skip-check covers both "already on PATH" and "installed but PATH not yet
    # refreshed" (Astral writes to `~/.local/bin/ruff` by default — that path
    # is added to `PATH` by `dot_zshenv.tmpl`, but `run_once_before_*` runs
    # before chezmoi applies files, so a fresh install in this same session
    # may not be on PATH yet).
    if command -v ruff &>/dev/null \
        || [ -x "$HOME/.local/bin/ruff" ] \
        || [ -x "$HOME/.cargo/bin/ruff" ]; then
        echo "[configure-deps] ruff is already installed, skipping" >&2
        return
    fi

    # Mirror the `install_dev_toolkit`/`install_aisync` pattern: download to a
    # temp file and check the exit status explicitly. `curl ... | sh` would
    # mask download failures because this file doesn't enable `pipefail`, so
    # a 4xx/5xx from `astral.sh` would silently leave nothing installed while
    # the function reports success.
    local installer
    local status

    installer="$(mktemp)"
    if ! curl -fsSL https://astral.sh/ruff/install.sh -o "$installer"; then
        echo "[configure-deps] ERROR: failed to download ruff installer" >&2
        rm -f "$installer"
        return 1
    fi

    # Astral's installer is POSIX `sh` (dash-tested per its shebang comment).
    sh "$installer"
    status=$?
    rm -f "$installer"
    if [ "$status" -ne 0 ]; then
        echo "[configure-deps] ERROR: ruff installer exited with status $status" >&2
        return "$status"
    fi

    # Belt-and-suspenders: verify the binary actually landed somewhere we can
    # find it, in case the installer "succeeded" against a partial/corrupt
    # download. Without this, future invocations of `make lint-python` would
    # still fail with `ruff: command not found` even though this function
    # returned cleanly.
    if ! command -v ruff &>/dev/null \
        && [ ! -x "$HOME/.local/bin/ruff" ] \
        && [ ! -x "$HOME/.cargo/bin/ruff" ]; then
        echo "[configure-deps] ERROR: ruff installer reported success but no binary found on PATH or in ~/.local/bin / ~/.cargo/bin" >&2
        return 1
    fi
}

# https://github.com/rios0rios0/aisync
# `aisync` syncs AI assistant rules/agents/skills across `~/.claude/`, `~/.cursor/`, etc.
# It replaces the legacy `run_after_*-install-ai-rules.*` scripts that used to curl
# `install-rules.sh` from `rios0rios0/guide` on every chezmoi apply.
#
# On Linux/WSL we fetch the upstream `install.sh` (same shape as
# `install_dev_toolkit` and what `terra` ships) instead of `go install`-ing from
# source. The pre-built `linux-<arch>` Go binary runs natively under glibc — no
# Termux-style `/etc/*` redirection or seccomp suppression is needed — and
# avoids requiring a working `go` toolchain on this host.
install_aisync() {
    if command -v aisync &>/dev/null; then
        echo "[configure-deps] aisync is already installed, skipping" >&2
        return
    fi

    local installer
    local status

    installer="$(mktemp)"
    if ! curl -fsSL https://raw.githubusercontent.com/rios0rios0/aisync/main/install.sh -o "$installer"; then
        echo "[configure-deps] ERROR: failed to download aisync installer" >&2
        rm -f "$installer"
        return 1
    fi

    bash "$installer"
    status=$?
    rm -f "$installer"

    return "$status"
}

# https://github.com/rios0rios0/ccswitch
# `ccswitch` monitors Claude Code usage and rotates between backup Claude accounts
# when the active account's limits are exhausted. Installed like `aisync`: fetch the
# upstream `install.sh`, which downloads the pre-built `linux-<arch>` binary into
# ~/.local/bin. The shell integration (claude wrapper + daemon start) lives in
# `dot_zshrc.tmpl`.
install_ccswitch() {
    if command -v ccswitch &>/dev/null; then
        echo "[configure-deps] ccswitch is already installed, skipping" >&2
        return
    fi

    local installer
    local status

    installer="$(mktemp)"
    if ! curl -fsSL https://raw.githubusercontent.com/rios0rios0/ccswitch/main/install.sh -o "$installer"; then
        echo "[configure-deps] ERROR: failed to download ccswitch installer" >&2
        rm -f "$installer"
        return 1
    fi

    bash "$installer"
    status=$?
    rm -f "$installer"

    return "$status"
}

# https://developer.atlassian.com/cloud/acli/guides/install-linux/
# Atlassian only publishes a rolling `latest` endpoint (no versioned URLs, no checksums/signatures),
# so pinning or cryptographic verification is not possible upstream; the install tracks the latest
# stable channel officially recommended by Atlassian.
install_acli() {
    if command -v acli &>/dev/null; then
        echo "[configure-deps] acli is already installed, skipping" >&2
        return
    fi

    local arch
    case "$(uname -m)" in
        x86_64)          arch="amd64" ;;
        aarch64 | arm64) arch="arm64" ;;
        *)
            echo "[acli] ERROR: unsupported architecture: $(uname -m)" >&2
            return 1
            ;;
    esac

    (
        tmpDir="$(mktemp -d)" || {
            echo "[acli] ERROR: failed to create temporary directory" >&2
            exit 1
        }

        trap 'rm -rf "$tmpDir"' EXIT
        cd "$tmpDir" || exit 1

        curl -fsSL "https://acli.atlassian.com/linux/latest/acli_linux_${arch}.tar.gz" -o acli.tar.gz
        # The archive nests the binary under `acli_<version>-stable_linux_<arch>/acli`,
        # so strip the versioned top-level directory to extract the binary directly.
        tar -xzf acli.tar.gz --strip-components=1
        sudo install -m 0755 acli /usr/local/bin/acli
    )
}

# https://www.speedtest.net/apps/cli
install_speedtest_cli() {
    if command -v speedtest &>/dev/null; then
        echo "[configure-deps] speedtest is already installed, skipping" >&2
        return
    fi

    curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo os=debian dist=bookworm bash
    sudo apt install --no-install-recommends --yes speedtest
}

install_oh_my_zsh
# change the default shell to zsh so that new terminal sessions start in zsh
# sudo usermod is used to avoid an interactive password prompt from chsh
sudo usermod --shell "$(which zsh)" "$USER"
install_gvm || exit 1
install_kubectl
install_krew
install_terra
install_sdkman
install_nvm
install_pyenv

install_cursor_cli
install_claude_cli
install_ccswitch
install_gemini_cli
install_dev_toolkit

install_github_cli
install_aws_cli
install_azure_cli

install_ggshield
install_ruff
install_aisync

install_acli

install_speedtest_cli
# =========================================================================================================
