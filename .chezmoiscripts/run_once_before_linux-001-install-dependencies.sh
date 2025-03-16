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
    "bsdmainutils"  # hexdump is an utility for displaying file contents in hexadecimal required by GVM (Go Version Manager)
    "binutils"      # required by GVM (Go Version Manager)
    "bison"         # required by GVM (Go Version Manager)
    "gcc"           # required for many things and GVM
    "make"          # required for many things and GVM
)
sudo apt install --no-install-recommends --yes "${requirements[@]}"
# =========================================================================================================
# Hardware
hardware=(
    "htop" # it's for monitoring system resources
    "screenfetch" # it's for displaying system information
)
sudo apt install --no-install-recommends --yes "${hardware[@]}"
# =========================================================================================================
# Utilities
utilities=(
    "jq"                # it's for parsing JSON
    "bat"               # it's for cat with syntax highlighting (https://github.com/sharkdp/bat)
    "silversearcher-ag" # it's for searching files (https://github.com/ggreer/the_silver_searcher)
    "inotify-tools"     # it's for watching file changes ("inotifywait")
)
sudo apt install --no-install-recommends --yes "${utilities[@]}"
# =========================================================================================================
# =========================================================================================================
# https://ohmyz.sh/#install
install_oh_my_zsh() {
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

# https://github.com/moovweb/gvm?tab=readme-ov-file
install_gvm() {
    sudo rm -rf /home/$USER/.gvm
    bash < <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)
}

# https://sdkman.io/install/
install_sdkman() {
    curl -s "https://get.sdkman.io" | bash
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    sdk install java 23.0.2-amzn
    sdk install gradle 8.13
}

# https://github.com/nvm-sh/nvm?tab=readme-ov-file#install--update-script
install_nvm() {
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash
    nvm install --lts
    npm install -g corepack
    corepack enable
}

# https://github.com/pyenv/pyenv
install_pyenv() {
    sudo rm -rf /home/rios0rios0/.pyenv
    curl https://pyenv.run | bash
}

# https://pypi.org/project/azure-cli/
install_azure_cli() {
    pip install azure-cli
}

install_oh_my_zsh
install_gvm
install_sdkman
install_nvm
install_pyenv
#install_azure_cli
# =========================================================================================================
