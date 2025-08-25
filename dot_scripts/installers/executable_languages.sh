#!/bin/bash
#
# Additional installer functions for development tools
# Language managers and other utilities
#

# Source shared utilities and config
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/../shared/executable_utils.sh"
source "$SCRIPT_DIR/../shared/executable_config.sh"

# Install SDKMan (Java/Gradle manager)
install_sdkman() {
    log "Installing SDKMan..."
    
    if [ -d "$SDKMAN_PATH" ]; then
        log "SDKMan is already installed"
        return 0
    fi
    
    execute_command "Install SDKMan" \
        curl -s "$SDKMAN_INSTALLER_URL" | bash
    
    if [ -f "$SDKMAN_PATH/bin/sdkman-init.sh" ]; then
        source "$SDKMAN_PATH/bin/sdkman-init.sh"
        execute_command "Install Java" sdk install java
        execute_command "Install Gradle" sdk install gradle
    fi
}

# Install NVM (Node Version Manager)
install_nvm() {
    log "Installing NVM..."
    
    # Check if Node is already available (might be from package manager)
    if command_exists npm; then
        log "Node/npm is already available, configuring corepack..."
        execute_command "Install corepack globally" npm install -g corepack
        execute_command "Enable corepack" corepack enable
        return 0
    fi
    
    if [ -d "$NVM_PATH" ]; then
        log "NVM is already installed"
        return 0
    fi
    
    execute_command "Install NVM" \
        curl -o- "$NVM_INSTALLER_URL" | bash
    
    if [ -f "$NVM_PATH/nvm.sh" ]; then
        # For Android, unset PREFIX to avoid conflicts
        if is_android; then
            unset PREFIX
        fi
        
        source "$NVM_PATH/nvm.sh"
        execute_command "Install Node LTS" nvm install --lts
        
        if is_android; then
            execute_command "Update npm" npm install -g npm@latest
        fi
        
        execute_command "Install corepack globally" npm install -g corepack
        execute_command "Enable corepack" corepack enable
    fi
}

# Install pyenv (Python Version Manager)
install_pyenv() {
    log "Installing pyenv..."
    
    # Check if Python/pip is already available (might be from package manager)
    if command_exists pip; then
        log "Python/pip is already available, skipping pyenv installation"
        return 0
    fi
    
    if [ -d "$PYENV_PATH" ]; then
        log "pyenv is already installed"
        return 0
    fi
    
    # Remove any existing installation
    if [ -d "$PYENV_PATH" ]; then
        execute_command "Remove existing pyenv" rm -rf "$PYENV_PATH"
    fi
    
    execute_command "Install pyenv" \
        curl -fsSL "$PYENV_INSTALLER_URL" | bash
    
    if [ -d "$PYENV_PATH" ]; then
        export PATH="$PATH:$PYENV_PATH/bin"
        
        local python_version
        if is_android; then
            python_version="$PYTHON_VERSION_ANDROID"
        else
            python_version="$PYTHON_VERSION"
            # Install build dependencies for Linux
            install_pyenv_dependencies_linux
        fi
        
        execute_command "Install Python $python_version" pyenv install "$python_version"
        execute_command "Set Python $python_version as global" pyenv global "$python_version"
        execute_command "Upgrade pip" pip install --upgrade pip
    fi
}

install_pyenv_dependencies_linux() {
    log "Installing pyenv build dependencies..."
    install_packages "pyenv build dependencies" \
        "build-essential" "libssl-dev" "zlib1g-dev" "libbz2-dev" \
        "libreadline-dev" "libsqlite3-dev" "curl" "git" \
        "libncursesw5-dev" "xz-utils" "tk-dev" "libxml2-dev" \
        "libxmlsec1-dev" "libffi-dev" "liblzma-dev"
}

# Install Azure CLI
install_azure_cli() {
    log "Installing Azure CLI..."
    
    if [ -d "$AZURE_PATH" ]; then
        log "Azure CLI is already installed"
        return 0
    fi
    
    # Check if pip is available
    if ! command_exists pip; then
        log_error "pip is required for Azure CLI installation. Install Python/pip first."
        return 1
    fi
    
    execute_command "Install Azure CLI" pip install azure-cli
}

# Install 1Password CLI
install_1password_cli() {
    log "Installing 1Password CLI..."
    
    if command_exists op; then
        log "1Password CLI is already installed"
        return 0
    fi
    
    local arch
    arch="$(get_architecture)"
    
    if is_android; then
        install_1password_cli_android "$arch"
    else
        install_1password_cli_linux "$arch"
    fi
}

install_1password_cli_linux() {
    local arch="$1"
    local url
    url="$(get_onepassword_url "$arch")"
    
    local tmpdir
    tmpdir="$(mktemp -d)"
    
    (
        cd "$tmpdir" || exit 1
        download_file "$url" "op.zip" &&
        execute_command "Extract 1Password CLI" unzip -d op op.zip &&
        execute_command "Install 1Password CLI" sudo mv op/op "$LOCAL_BIN_PATH/" &&
        execute_command "Make 1Password CLI executable" sudo chmod +x "$LOCAL_BIN_PATH/op"
    )
    
    rm -rf "$tmpdir"
}

install_1password_cli_android() {
    local arch="$1"
    local url
    url="$(get_onepassword_url "$arch")"
    
    execute_command "Install 1Password CLI in proot" \
        proot-distro login alpine -- bash -c "
            if [ ! -f '/usr/bin/op' ]; then
                wget '$url' -O op.zip &&
                unzip -d op op.zip &&
                mv op/op /usr/bin/ &&
                rm -rf op.zip op &&
                chmod +x /usr/bin/op
            else
                echo '1Password CLI is already installed'
            fi
        "
}

# Install custom terra tool (Android only)
install_terra() {
    if ! is_android; then
        log "Terra tool is only available for Android"
        return 0
    fi
    
    log "Installing terra tool..."
    
    local terra_bin="/usr/bin/terra"
    
    # Check if already installed in proot
    if proot-distro login alpine -- bash -c "[ -f '$terra_bin' ]" 2>/dev/null; then
        log "Terra is already installed"
        return 0
    fi
    
    local source_path="$HOME/Development/github.com/rios0rios0/terra"
    
    if [ ! -d "$source_path" ]; then
        ensure_directory "$(dirname "$source_path")"
        execute_command "Clone terra repository" \
            git clone https://github.com/rios0rios0/terra.git "$source_path"
    fi
    
    (
        cd "$source_path" || exit 1
        export PATH="$PATH:$HOME/go/bin"
        execute_command "Build terra" make build
        execute_command "Copy terra to proot" \
            proot-distro copy bin/terra alpine:/usr/bin
    )
}

# Configure DNS for Android
configure_dns_android() {
    if ! is_android; then
        return 0
    fi
    
    log "Configuring DNS for Android..."
    
    local rcfile="/data/data/com.termux/files/usr/etc/resolv.conf"
    
    execute_command "Configure DNS servers" bash -c "
        echo 'nameserver 8.8.8.8' > '$rcfile'
        echo 'nameserver 8.8.4.4' >> '$rcfile'
        echo 'nameserver 1.1.1.1' >> '$rcfile'
    "
}

# Configure NeoVim with AstroVim
configure_neovim() {
    if ! is_android; then
        return 0
    fi
    
    log "Configuring NeoVim with AstroVim..."
    
    local nvim_path="$HOME/.config/nvim"
    
    if [ -d "$nvim_path" ]; then
        log "NeoVim is already configured"
        return 0
    fi
    
    ensure_directory "$(dirname "$nvim_path")"
    execute_command "Clone AstroVim template" \
        git clone --depth 1 https://github.com/AstroNvim/template "$nvim_path"
    
    execute_command "Remove template git history" \
        rm -rf "$nvim_path/.git"
    
    log "NeoVim configured. Run 'nvim' to complete setup."
}

# Install wrapper (proot-distro alpine) for Android
install_wrapper() {
    if ! is_android; then
        return 0
    fi
    
    log "Installing proot wrapper (Alpine)..."
    execute_command "Install Alpine proot distribution" \
        proot-distro install alpine
}

# Export all installer functions
export -f install_sdkman install_nvm install_pyenv install_pyenv_dependencies_linux
export -f install_azure_cli install_1password_cli install_1password_cli_linux install_1password_cli_android
export -f install_terra configure_dns_android configure_neovim install_wrapper