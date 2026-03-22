# shellcheck shell=bash
# Shared dependency-installation library included by platform-specific wrappers.
# Included via: {{ template "lib-install-deps.sh" }}

# =========================================================================================================
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# https://ohmyz.sh/#install
install_oh_my_zsh() {
    omzPath="$HOME/.oh-my-zsh"

    if [ ! -d "$omzPath" ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        echo "Oh My ZSH is already installed."
    fi
}

# https://sdkman.io/install/
install_sdkman() {
    sdkPath="$HOME/.sdkman"

    if [ ! -d "$sdkPath" ]; then
        curl -s "https://get.sdkman.io" | bash

        export SDKMAN_DIR="$sdkPath"
        # shellcheck source=/dev/null
        [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
        sdk install java
        sdk install gradle
    else
        echo "SDKMan is already installed."
    fi
}

# https://github.com/nvm-sh/nvm?tab=readme-ov-file#install--update-script
install_nvm() {
    if command_exists npm; then
        echo "Node detected, means it was previously installed or native package installed..."

        npm install -g corepack
        corepack enable
        return
    fi

    nvmPath="$HOME/.nvm"

    if [ ! -d "$nvmPath" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash

        unset PREFIX
        export NVM_DIR="$nvmPath"
        # shellcheck source=/dev/null
        [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
        nvm install --lts

        npm install -g npm@latest
        npm install -g corepack
        corepack enable
    else
        echo "NVM is already installed."
    fi
}

# https://github.com/google-gemini/gemini-cli
install_gemini_cli() {
    npm install -g @google/gemini-cli
}

# https://github.com/anthropics/claude-code
install_claude_cli() {
    npm install -g @anthropic-ai/claude-code
}
# =========================================================================================================
