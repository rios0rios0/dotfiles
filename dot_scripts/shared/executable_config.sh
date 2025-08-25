#!/bin/bash
#
# Shared configuration for tool versions and URLs
# This file centralizes version numbers and download URLs for consistency
#

# Tool versions - update these when new versions are available
readonly GO_VERSION="1.24.1"
readonly GO_VERSION_ANDROID="1.24.5"
readonly TERRAGRUNT_VERSION="0.76.6"
readonly TERRAFORM_VERSION="1.12.2"
readonly NVM_VERSION="0.40.2"
readonly PYTHON_VERSION="3.13.2"
readonly PYTHON_VERSION_ANDROID="3.13:latest"
readonly ONEPASSWORD_VERSION="2.31.1"
readonly KUBECTL_VERSION="v1.32"

# Base URLs
readonly HASHICORP_GPG_URL="https://apt.releases.hashicorp.com/gpg"
readonly HASHICORP_REPO_BASE="https://apt.releases.hashicorp.com"
readonly KUBERNETES_GPG_URL="https://pkgs.k8s.io/core:/stable:/${KUBECTL_VERSION}/deb/Release.key"
readonly KUBERNETES_REPO_BASE="https://pkgs.k8s.io/core:/stable:/${KUBECTL_VERSION}/deb/"

# GitHub release URLs
readonly GVM_INSTALLER_URL="https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer"
readonly OHMYZSH_INSTALLER_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
readonly SDKMAN_INSTALLER_URL="https://get.sdkman.io"
readonly NVM_INSTALLER_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh"
readonly PYENV_INSTALLER_URL="https://pyenv.run"
readonly KREW_RELEASES_URL="https://github.com/kubernetes-sigs/krew/releases/latest/download"

# Tool-specific URLs with version substitution
get_terragrunt_url() {
    local arch="$1"
    echo "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_${arch}"
}

get_terraform_url() {
    local arch="$1"
    echo "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip"
}

get_onepassword_url() {
    local arch="$1"
    echo "https://cache.agilebits.com/dist/1P/op2/pkg/v${ONEPASSWORD_VERSION}/op_linux_${arch}_v${ONEPASSWORD_VERSION}.zip"
}

# Architecture detection
get_architecture() {
    local arch
    arch="$(uname -m)"
    
    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l|armhf)
            echo "arm"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# Platform-specific paths
if is_android 2>/dev/null; then
    readonly LOCAL_BIN_PATH="/data/data/com.termux/files/usr/bin"
    readonly HOME_PATH="$HOME"
else
    readonly LOCAL_BIN_PATH="/usr/local/bin"
    readonly HOME_PATH="$HOME"
fi

# Common install paths
readonly GVM_PATH="$HOME_PATH/.gvm"
readonly NVM_PATH="$HOME_PATH/.nvm"
readonly PYENV_PATH="$HOME_PATH/.pyenv"
readonly SDKMAN_PATH="$HOME_PATH/.sdkman"
readonly OHMYZSH_PATH="$HOME_PATH/.oh-my-zsh"
readonly AZURE_PATH="$HOME_PATH/.azure"

# Export configuration functions
export -f get_terragrunt_url get_terraform_url get_onepassword_url get_architecture