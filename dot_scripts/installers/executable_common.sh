#!/bin/bash
#
# Shared installer functions for common development tools
# These functions work across Linux and Android platforms
#

# Source shared utilities and config
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/../shared/executable_utils.sh"
source "$SCRIPT_DIR/../shared/executable_config.sh"

# Install Oh My Zsh
install_oh_my_zsh() {
    log "Installing Oh My Zsh..."
    
    if [ -d "$OHMYZSH_PATH" ]; then
        log "Oh My Zsh is already installed"
        return 0
    fi
    
    execute_command "Install Oh My Zsh" \
        sh -c "$(curl -fsSL $OHMYZSH_INSTALLER_URL)"
}

# Install GVM (Go Version Manager)
install_gvm() {
    log "Installing GVM (Go Version Manager)..."
    
    # Check if Go is already available (might be from package manager)
    if command_exists go; then
        log "Go is already available, skipping GVM installation"
        return 0
    fi
    
    if [ -d "$GVM_PATH" ]; then
        log "GVM is already installed"
        return 0
    fi
    
    # Remove any existing installation
    if [ -d "$GVM_PATH" ]; then
        execute_command "Remove existing GVM" rm -rf "$GVM_PATH"
    fi
    
    # Install GVM
    execute_command "Download and install GVM" \
        bash -c "curl -s -S -L $GVM_INSTALLER_URL | bash"
    
    # Install Go version
    local go_version
    if is_android; then
        go_version="$GO_VERSION_ANDROID"
    else
        go_version="$GO_VERSION"
    fi
    
    if [ -f "$GVM_PATH/scripts/gvm" ]; then
        source "$GVM_PATH/scripts/gvm"
        execute_command "Install Go $go_version" gvm install "$go_version" -B
        execute_command "Set Go $go_version as default" gvm use "$go_version" --default
    fi
}

# Install kubectl
install_kubectl() {
    log "Installing kubectl..."
    
    # Skip on Android as it's typically installed via proot
    if is_android; then
        log "Skipping kubectl on Android (use proot installation)"
        return 0
    fi
    
    if command_exists kubectl; then
        log "kubectl is already installed"
        return 0
    fi
    
    # Add Kubernetes apt repository
    execute_command "Create apt keyrings directory" \
        sudo mkdir -p -m 755 /etc/apt/keyrings
    
    execute_command "Add Kubernetes GPG key" \
        curl -fsSL "$KUBERNETES_GPG_URL" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    
    execute_command "Set GPG key permissions" \
        sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    
    execute_command "Add Kubernetes repository" \
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] $KUBERNETES_REPO_BASE /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    
    execute_command "Set repository permissions" \
        sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
    
    execute_command "Update package list" sudo apt update
    
    install_packages "kubectl" "kubectl"
}

# Install krew (kubectl plugin manager)
install_krew() {
    log "Installing krew..."
    
    # Skip on Android
    if is_android; then
        log "Skipping krew on Android"
        return 0
    fi
    
    if command_exists kubectl-krew; then
        log "krew is already installed"
        return 0
    fi
    
    local tmpdir
    tmpdir="$(mktemp -d)"
    
    (
        cd "$tmpdir" || exit 1
        
        local os arch krew_file
        os="$(uname | tr '[:upper:]' '[:lower:]')"
        arch="$(get_architecture)"
        krew_file="krew-${os}_${arch}"
        
        download_file "$KREW_RELEASES_URL/${krew_file}.tar.gz" "${krew_file}.tar.gz" &&
        execute_command "Extract krew" tar zxf "${krew_file}.tar.gz" &&
        execute_command "Install krew" ./"${krew_file}" install krew
    )
    
    # Install useful krew plugins
    if command_exists kubectl-krew; then
        execute_command "Install krew ctx plugin" kubectl krew install ctx
        execute_command "Install krew ns plugin" kubectl krew install ns
    fi
    
    rm -rf "$tmpdir"
}

# Install Terraform
install_terraform() {
    log "Installing Terraform..."
    
    if command_exists terraform; then
        log "Terraform is already installed"
        return 0
    fi
    
    if is_android; then
        # Install in proot for Android
        install_terraform_android
    else
        # Install via apt repository for Linux
        install_terraform_linux
    fi
}

install_terraform_linux() {
    execute_command "Add HashiCorp GPG key" \
        wget -O - "$HASHICORP_GPG_URL" | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    
    execute_command "Add HashiCorp repository" \
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] $HASHICORP_REPO_BASE bullseye main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    
    execute_command "Update package list" sudo apt update
    install_packages "Terraform" "terraform"
}

install_terraform_android() {
    local arch terraform_bin
    arch="$(get_architecture)"
    terraform_bin="/usr/bin/terraform"
    
    execute_command "Install Terraform in proot" \
        proot-distro login alpine -- bash -c "
            if [ ! -f '$terraform_bin' ]; then
                wget '$(get_terraform_url "$arch")' -O terraform.zip &&
                unzip terraform.zip -d /usr/bin &&
                chmod +x '$terraform_bin' &&
                rm terraform.zip
            else
                echo 'Terraform is already installed'
            fi
        "
}

# Install Terragrunt
install_terragrunt() {
    log "Installing Terragrunt..."
    
    if command_exists terragrunt; then
        log "Terragrunt is already installed"
        return 0
    fi
    
    local arch
    arch="$(get_architecture)"
    
    if is_android; then
        install_terragrunt_android "$arch"
    else
        install_terragrunt_linux "$arch"
    fi
}

install_terragrunt_linux() {
    local arch="$1"
    local url
    url="$(get_terragrunt_url "$arch")"
    
    local tmpfile
    tmpfile="$(mktemp)"
    
    download_file "$url" "$tmpfile" &&
    execute_command "Install Terragrunt" sudo mv "$tmpfile" "$LOCAL_BIN_PATH/terragrunt" &&
    execute_command "Make Terragrunt executable" sudo chmod +x "$LOCAL_BIN_PATH/terragrunt"
}

install_terragrunt_android() {
    local arch="$1"
    local url
    url="$(get_terragrunt_url "$arch")"
    
    execute_command "Install Terragrunt in proot" \
        proot-distro login alpine -- bash -c "
            if [ ! -f '/usr/bin/terragrunt' ]; then
                curl -LO '$url' &&
                mv 'terragrunt_linux_$arch' '/usr/bin/terragrunt' &&
                chmod +x '/usr/bin/terragrunt'
            else
                echo 'Terragrunt is already installed'
            fi
        "
}

# Export all installer functions
export -f install_oh_my_zsh install_gvm install_kubectl install_krew
export -f install_terraform install_terraform_linux install_terraform_android
export -f install_terragrunt install_terragrunt_linux install_terragrunt_android