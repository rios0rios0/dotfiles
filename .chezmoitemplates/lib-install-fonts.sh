# shellcheck shell=bash
# Shared font-installation library included by platform-specific wrappers.

NERD_FONTS_BASE_URL="https://github.com/ryanoasis/nerd-fonts/releases/download"
MESLO_BASE_URL="https://raw.githubusercontent.com/romkatv/powerlevel10k-media/master"
MESLO_LGS_FILES=(
    "MesloLGS%20NF%20Regular.ttf"
    "MesloLGS%20NF%20Bold.ttf"
    "MesloLGS%20NF%20Italic.ttf"
    "MesloLGS%20NF%20Bold%20Italic.ttf"
)

# Download helper: follows redirects but refuses any hop that leaves HTTPS, so a hijacked
# redirect cannot downgrade the transfer to plain HTTP.
download_https_only() {
    curl -fsSL --proto '=https' --proto-redir '=https' "$@"
}

# =========================================================================================================
# Resolve the latest Nerd Fonts release tag (https://github.com/ryanoasis/nerd-fonts)
resolve_nerd_fonts_version() {
    download_https_only "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" | jq -r '.tag_name'
}

# Install a Nerd Font zip by name (e.g. "FiraCode", "Meslo")
install_nerd_font_zip() {
    local name="$1"
    local version="$2"
    local font_dir="$3"
    mkdir -p "$font_dir"

    echo "[fonts] installing $name Nerd Font ($version)..." >&2
    local temp_dir
    temp_dir="$(mktemp -d)"

    download_https_only -o "$temp_dir/$name.zip" "$NERD_FONTS_BASE_URL/$version/$name.zip"
    unzip -o "$temp_dir/$name.zip" "*.ttf" -d "$temp_dir/$name"
    find "$temp_dir/$name" -name "*.ttf" -exec cp {} "$font_dir/" \;
    rm -rf "$temp_dir"
}

# MesloLGS NF - Nerd Font for Powerlevel10k (https://github.com/romkatv/powerlevel10k#fonts)
install_meslo_lgs_nf() {
    echo "[fonts] installing MesloLGS NF fonts..." >&2
    local font_dir="$1"
    mkdir -p "$font_dir"

    for file in "${MESLO_LGS_FILES[@]}"; do
        download_https_only -o "$font_dir/$(printf '%b' "${file//%/\\x}")" "$MESLO_BASE_URL/$file"
    done
}

# Main entry point – call with the target font base directory.
install_fonts() {
    local font_base="$1"

    local nerd_fonts_version
    nerd_fonts_version="$(resolve_nerd_fonts_version)"

    install_nerd_font_zip "FiraCode" "$nerd_fonts_version" "$font_base/FiraCode"
    install_nerd_font_zip "Meslo"    "$nerd_fonts_version" "$font_base/Meslo"
    install_meslo_lgs_nf "$font_base/MesloLGS NF"
}
# =========================================================================================================
