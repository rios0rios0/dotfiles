#!/bin/bash

# update the package list
sudo apt update

# get the list of installed packages
installedPackages=$(apt list --installed 2>/dev/null)

# function to check if a package is installed
is_package_installed() {
    local packageName=$1
    echo "$installedPackages" | grep -q "$packageName"
}

# function to install a list of packages
install_package_list() {
    local packageList=("$@")
    for package in "${packageList[@]}"; do
        if ! is_package_installed "$package"; then
            sudo apt install -y "$package"
            echo "$package installed successfully..."
        else
            echo "$package is already installed..."
        fi
    done
}

# =========================================================================================================
# Requirements for this repository to work properly
requirements=(
    "git"
    "curl"
    "unzip" # required for SDK Man
)
sudo apt install zip # required for SDK Man TODO: the function to check if a package is installed is not working properly
install_package_list "${requirements[@]}"
# function to install oh-my-zsh
# https://ohmyz.sh/#install
install_oh_my_zsh() {
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}
install_oh_my_zsh
# =========================================================================================================
# Hardware
hardware=(
    "htop"
)
install_package_list "${hardware[@]}"
# =========================================================================================================
# Utilities
utilities=(
    "jq"
    "bat"
    "silversearcher-ag"
)
install_package_list "${utilities[@]}"
# =========================================================================================================
# function to install gvm
# https://github.com/moovweb/gvm?tab=readme-ov-file
install_gvm() {
    sudo rm -rf /home/rios0rios0/.gvm
    bash < <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)
}

# function to install sdkman and related packages
# https://sdkman.io/install/
install_sdkman() {
    curl -s "https://get.sdkman.io" | bash
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    sdk install java
    sdk install gradle
}

# function to install nvm
# https://github.com/nvm-sh/nvm?tab=readme-ov-file#install--update-script
install_nvm() {
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    # npm, yarn
}

# function to install pyenv
# https://github.com/pyenv/pyenv
install_pyenv() {
    sudo rm -rf /home/rios0rios0/.pyenv
    curl https://pyenv.run | bash
}

# function to install azure-cli
# https://pypi.org/project/azure-cli/
install_azure_cli() {
    pip install azure-cli
}

install_gvm
install_sdkman
install_nvm
install_pyenv
#install_azure_cli
# =========================================================================================================
