#!/bin/bash
#
# Refactored Linux dependencies installation script
# Uses shared patterns and DRY principles
#

set -euo pipefail

# Include shared utility functions inline
command_exists() { command -v "$1" >/dev/null 2>&1; }
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"; }
log_error() { echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >&2; }
execute_command() { 
    local description="$1"; shift
    log "Executing: $description"
    if "$@"; then log "Success: $description"; else log_error "Failed: $description"; return 1; fi
}
is_tool_installed() { 
    local tool="$1" path="$2"
    [ -n "$path" ] && [ -f "$path" ] && { log "$tool already installed at $path"; return 0; }
    command_exists "$tool" && { log "$tool already available"; return 0; }
    return 1
}

# Configuration constants
readonly GO_VERSION="1.24.1"
readonly TERRAGRUNT_VERSION="0.76.6"
readonly NVM_VERSION="0.40.2"
readonly PYTHON_VERSION="3.13.2"

# Package definitions
readonly REQUIREMENTS=(
    "git" "curl" "zip" "unzip" "age" "gpg" "gpg-agent" "eza" "sqlite3"
    "bsdmainutils" "binutils" "bison" "gcc" "make"
)
readonly HARDWARE=("htop" "screenfetch")
readonly UTILITIES=(
    "jq" "bat" "silversearcher-ag" "inotify-tools" "dos2unix" "expect" "aria2c" "file"
)

# Install packages function
install_packages() {
    local description="$1"; shift
    local packages=("$@")
    log "Installing $description: ${packages[*]}"
    execute_command "Install $description" sudo apt install --no-install-recommends --yes "${packages[@]}"
}

# Installer functions with idempotency
install_oh_my_zsh() {
    [ -d "$HOME/.oh-my-zsh" ] && { log "Oh My Zsh already installed"; return 0; }
    execute_command "Install Oh My Zsh" \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

install_gvm() {
    command_exists go && { log "Go already available"; return 0; }
    [ -d "$HOME/.gvm" ] && { log "GVM already installed"; return 0; }
    [ -d "$HOME/.gvm" ] && execute_command "Remove existing GVM" rm -rf "$HOME/.gvm"
    execute_command "Install GVM" \
        bash -c "curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer | bash"
    [ -f "$HOME/.gvm/scripts/gvm" ] && {
        source "$HOME/.gvm/scripts/gvm"
        execute_command "Install Go $GO_VERSION" gvm install "$GO_VERSION" -B
        execute_command "Use Go $GO_VERSION" gvm use "$GO_VERSION" --default
    }
}

install_kubectl() {
    command_exists kubectl && { log "kubectl already installed"; return 0; }
    execute_command "Create apt keyrings directory" sudo mkdir -p -m 755 /etc/apt/keyrings
    execute_command "Add Kubernetes GPG key" \
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    execute_command "Set GPG key permissions" sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    execute_command "Add Kubernetes repository" \
        echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    execute_command "Update package list" sudo apt update
    install_packages "kubectl" "kubectl"
}

install_krew() {
    command_exists kubectl-krew && { log "krew already installed"; return 0; }
    local tmpdir; tmpdir="$(mktemp -d)"
    (
        cd "$tmpdir" || exit 1
        local os arch krew_file
        os="$(uname | tr '[:upper:]' '[:lower:]')"
        arch="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64$/arm64/')"
        krew_file="krew-${os}_${arch}"
        curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${krew_file}.tar.gz" &&
        tar zxf "${krew_file}.tar.gz" &&
        ./"${krew_file}" install krew
    ) && {
        kubectl krew install ctx
        kubectl krew install ns
    }
    rm -rf "$tmpdir"
}

install_terraform() {
    command_exists terraform && { log "Terraform already installed"; return 0; }
    execute_command "Add HashiCorp GPG key" \
        wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    execute_command "Add HashiCorp repository" \
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com bullseye main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    execute_command "Update package list" sudo apt update
    install_packages "Terraform" "terraform"
}

install_terragrunt() {
    command_exists terragrunt && { log "Terragrunt already installed"; return 0; }
    local arch; arch="$(uname -m | sed 's/x86_64/amd64/')"
    local url="https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_${arch}"
    local tmpfile; tmpfile="$(mktemp)"
    curl -fsSL "$url" -o "$tmpfile" &&
    execute_command "Install Terragrunt" sudo mv "$tmpfile" /usr/local/bin/terragrunt &&
    execute_command "Make Terragrunt executable" sudo chmod +x /usr/local/bin/terragrunt
}

install_sdkman() {
    [ -d "$HOME/.sdkman" ] && { log "SDKMan already installed"; return 0; }
    execute_command "Install SDKMan" curl -s "https://get.sdkman.io" | bash
    [ -f "$HOME/.sdkman/bin/sdkman-init.sh" ] && {
        source "$HOME/.sdkman/bin/sdkman-init.sh"
        execute_command "Install Java" sdk install java
        execute_command "Install Gradle" sdk install gradle
    }
}

install_nvm() {
    command_exists npm && { 
        execute_command "Install corepack" npm install -g corepack
        execute_command "Enable corepack" corepack enable
        return 0
    }
    [ -d "$HOME/.nvm" ] && { log "NVM already installed"; return 0; }
    execute_command "Install NVM" curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
    [ -f "$HOME/.nvm/nvm.sh" ] && {
        source "$HOME/.nvm/nvm.sh"
        execute_command "Install Node LTS" nvm install --lts
        execute_command "Install corepack" npm install -g corepack
        execute_command "Enable corepack" corepack enable
    }
}

install_pyenv() {
    command_exists pip && { log "Python/pip already available"; return 0; }
    [ -d "$HOME/.pyenv" ] && { log "pyenv already installed"; return 0; }
    [ -d "$HOME/.pyenv" ] && execute_command "Remove existing pyenv" rm -rf "$HOME/.pyenv"
    
    # Install build dependencies
    install_packages "pyenv build dependencies" \
        "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" "libreadline-dev" \
        "libsqlite3-dev" "libncursesw5-dev" "xz-utils" "tk-dev" "libxml2-dev" \
        "libxmlsec1-dev" "libffi-dev" "liblzma-dev"
    
    execute_command "Install pyenv" curl -fsSL https://pyenv.run | bash
    [ -d "$HOME/.pyenv" ] && {
        export PATH="$PATH:$HOME/.pyenv/bin"
        execute_command "Install Python $PYTHON_VERSION" pyenv install "$PYTHON_VERSION"
        execute_command "Set Python global" pyenv global "$PYTHON_VERSION"
        execute_command "Upgrade pip" pip install --upgrade pip
    }
}

install_azure_cli() {
    command_exists pip || { log_error "pip required for Azure CLI"; return 1; }
    [ -d "$HOME/.azure" ] && { log "Azure CLI already installed"; return 0; }
    execute_command "Install Azure CLI" pip install azure-cli
}

# Main installation function
main() {
    log "Starting Linux dependencies installation..."
    
    # Update package list
    execute_command "Update package list" sudo apt update
    
    # Install system packages
    install_packages "requirements" "${REQUIREMENTS[@]}"
    install_packages "hardware monitoring" "${HARDWARE[@]}"
    install_packages "utilities" "${UTILITIES[@]}"
    
    # Install development tools
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
    
    log "Linux dependencies installation completed successfully!"
}

# Run main function
main "$@"