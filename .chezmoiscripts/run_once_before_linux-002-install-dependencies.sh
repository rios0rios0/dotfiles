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
    local go_version="go1.25.5"

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

    kubectl krew install ctx
    kubectl krew install ns
}

# https://developer.hashicorp.com/terraform/install
install_terraform() {
    if command -v terraform &>/dev/null; then
        echo "[configure-deps] terraform is already installed, skipping" >&2
        return
    fi

    wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com bullseye main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update && sudo apt install terraform
}

# https://terragrunt.gruntwork.io/docs/getting-started/install/
install_terragrunt() {
    local target_version="v0.76.6"

    if command -v terragrunt &>/dev/null; then
        local current_version
        current_version="$(terragrunt --version 2>/dev/null | grep -oP 'v[\d.]+')" || true
        if [[ "$current_version" == "$target_version" ]]; then
            echo "[configure-deps] terragrunt $target_version is already installed, skipping" >&2
            return
        fi
    fi

    curl -LO "https://github.com/gruntwork-io/terragrunt/releases/download/${target_version}/terragrunt_linux_amd64"
    sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt
    sudo chmod +x /usr/local/bin/terragrunt
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

# https://github.com/rios0rios0/devforge
install_devforge() {
    if command -v dev &>/dev/null; then
        echo "[configure-deps] devforge is already installed, skipping" >&2
        return
    fi

    local installer
    local status

    installer="$(mktemp)"
    if ! curl -fsSL https://raw.githubusercontent.com/rios0rios0/devforge/main/install.sh -o "$installer"; then
        echo "[devforge] ERROR: failed to download installer" >&2
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
install_gvm
install_kubectl
install_krew
install_terraform
install_terragrunt
install_sdkman
install_nvm
install_pyenv

install_cursor_cli
install_claude_cli
install_gemini_cli
install_devforge

install_github_cli
install_azure_cli

install_speedtest_cli
# =========================================================================================================
