#!/bin/bash

# update the package list
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
    "bat"               # it's for cat with syntax highlighting (https://github.com/sharkdp/bat)
    "silversearcher-ag" # it's for searching files (https://github.com/ggreer/the_silver_searcher)
    "inotify-tools"     # it's for watching file changes ("inotifywait")
    "dos2unix"          # it's for converting text files between Unix and DOS formats
    "expect"            # it's for automating interactive applications (used in some scripts)
    "aria2"             # cURL alternative with many features (command is aria2c)
    "file"              # it's for determining file types
    "parallel"          # it runs many threads of a command at the same time
)
sudo apt install --no-install-recommends --yes "${utilities[@]}"
# =========================================================================================================
# =========================================================================================================
# https://ohmyz.sh/#install
install_oh_my_zsh() {
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
}

# https://github.com/moovweb/gvm?tab=readme-ov-file
install_gvm() {
    sudo rm -rf /home/$USER/.gvm
    bash < <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)

    # Source GVM to make it available in the current shell
    export GVM_ROOT="$HOME/.gvm"
    # shellcheck source=/dev/null
    [[ -s "$GVM_ROOT/scripts/gvm" ]] && source "$GVM_ROOT/scripts/gvm"

    gvm install go1.25.5 -B
    gvm use go1.25.5 --default
}

# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
install_kubectl() {
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list

    sudo apt update && sudo apt install --no-install-recommends --yes kubectl
}

# https://krew.sigs.k8s.io/docs/user-guide/setup/install/
install_krew() {
    (
      set -x; cd "$(mktemp -d)" &&
      OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
      ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
      KREW="krew-${OS}_${ARCH}" &&
      curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
      tar zxvf "${KREW}.tar.gz" &&
      ./"${KREW}" install krew
    )

    # Add krew to PATH for current session
    export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

    kubectl krew install ctx
    kubectl krew install ns
}

# https://developer.hashicorp.com/terraform/install
install_terraform() {
    wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com bullseye main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update && sudo apt install terraform
}

# https://terragrunt.gruntwork.io/docs/getting-started/install/
install_terragrunt() {
    curl -LO https://github.com/gruntwork-io/terragrunt/releases/download/v0.76.6/terragrunt_linux_amd64
    sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt
    sudo chmod +x /usr/local/bin/terragrunt
}

# https://sdkman.io/install/
install_sdkman() {
    curl -s "https://get.sdkman.io" | bash

    # Source SDKMAN to make it available in the current shell
    export SDKMAN_DIR="$HOME/.sdkman"
    # shellcheck source=/dev/null
    [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

    sdk install java
    sdk install gradle
}

# https://github.com/nvm-sh/nvm?tab=readme-ov-file#install--update-script
install_nvm() {
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash

    # Source NVM to make it available in the current shell
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

    nvm install --lts
    npm install -g corepack
    corepack enable
}

# https://github.com/pyenv/pyenv
install_pyenv() {
    sudo rm -rf /home/$USER/.pyenv
    curl https://pyenv.run | bash

    # Source pyenv to make it available in the current shell
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"

    # https://github.com/pyenv/pyenv/wiki#suggested-build-environment
    sudo apt install --no-install-recommends --yes build-essential libssl-dev zlib1g-dev \
      libbz2-dev libreadline-dev libsqlite3-dev curl git \
      libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

    pyenv install 3.13.2
    pyenv global 3.13.2

    # Rehash to make pyenv/pip available
    eval "$(pyenv init -)"
}

# https://pypi.org/project/azure-cli/
install_azure_cli() {
    # Ensure pip is available from pyenv's Python
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"

    pip install --upgrade pip
    pip install azure-cli
}

install_oh_my_zsh
install_gvm
install_kubectl
install_krew
install_terraform
install_terragrunt
install_sdkman
install_nvm
install_pyenv
install_azure_cli
# =========================================================================================================
