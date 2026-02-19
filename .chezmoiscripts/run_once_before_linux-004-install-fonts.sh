#!/bin/bash

# This script installs MesloLGS NF, Meslo Nerd Font, and FiraCode Nerd Font
# on Linux (baremetal/WSL) and Android (Termux).
# The same fonts are installed on Windows via run_once_before_windows-003-install-fonts.ps1.

set -euo pipefail

NERD_FONTS_BASE_URL="https://github.com/ryanoasis/nerd-fonts/releases/download"
MESLO_BASE_URL="https://raw.githubusercontent.com/romkatv/powerlevel10k-media/master"
MESLO_LGS_FILES=(
    "MesloLGS%20NF%20Regular.ttf"
    "MesloLGS%20NF%20Bold.ttf"
    "MesloLGS%20NF%20Italic.ttf"
    "MesloLGS%20NF%20Bold%20Italic.ttf"
)

# =========================================================================================================
# Resolve the latest Nerd Fonts release tag (https://github.com/ryanoasis/nerd-fonts)
resolve_nerd_fonts_version() {
    curl -fsSL "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" | jq -r '.tag_name'
}

# Install a Nerd Font zip by name (e.g. "FiraCode", "Meslo")
install_nerd_font_zip() {
    local NAME="$1"
    local VERSION="$2"
    local FONT_DIR="$3"
    mkdir -p "$FONT_DIR"

    echo "Installing $NAME Nerd Font ($VERSION)..."
    local TEMP_DIR
    TEMP_DIR="$(mktemp -d)"

    curl -fsSL -o "$TEMP_DIR/$NAME.zip" "$NERD_FONTS_BASE_URL/$VERSION/$NAME.zip"
    unzip -o "$TEMP_DIR/$NAME.zip" "*.ttf" -d "$TEMP_DIR/$NAME"
    find "$TEMP_DIR/$NAME" -name "*.ttf" -exec cp {} "$FONT_DIR/" \;
    rm -rf "$TEMP_DIR"
}

# MesloLGS NF - Nerd Font for Powerlevel10k (https://github.com/romkatv/powerlevel10k#fonts)
install_meslo_lgs_nf() {
    echo "Installing MesloLGS NF fonts..."
    local FONT_DIR="$1"
    mkdir -p "$FONT_DIR"

    for file in "${MESLO_LGS_FILES[@]}"; do
        curl -fsSL -o "$FONT_DIR/$(printf '%b' "${file//%/\\x}")" "$MESLO_BASE_URL/$file"
    done
}
# =========================================================================================================

# =========================================================================================================
if [ "$(uname -o 2>/dev/null)" = "Android" ]; then
    FONT_BASE="$HOME/.local/share/fonts"
else
    FONT_BASE="$HOME/.fonts"
fi

NERD_FONTS_VERSION="$(resolve_nerd_fonts_version)"

install_nerd_font_zip "FiraCode" "$NERD_FONTS_VERSION" "$FONT_BASE/FiraCode"
install_nerd_font_zip "Meslo"    "$NERD_FONTS_VERSION" "$FONT_BASE/Meslo"
install_meslo_lgs_nf "$FONT_BASE/MesloLGS NF"

# Rebuild and clean the fonts cache (not available on Android/Termux)
if [ "$(uname -o 2>/dev/null)" != "Android" ]; then
    fc-cache -f -v
fi
# =========================================================================================================
