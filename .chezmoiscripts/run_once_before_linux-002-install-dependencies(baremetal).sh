#!/bin/bash

# This script installs GUI/desktop applications that are only useful on baremetal Linux.
# It must NOT run on WSL or Android.

# Exit if running inside WSL
if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
    echo "WSL detected, skipping baremetal dependencies installation."
    exit 0
fi

# Detect the distribution
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    DISTRO="$ID"
else
    echo "Cannot detect distribution (/etc/os-release not found). Aborting."
    exit 1
fi

if [[ "$DISTRO" != "debian" && "$DISTRO" != "ubuntu" ]]; then
    echo "Unsupported distribution: $DISTRO. Only Debian and Ubuntu are supported."
    exit 1
fi

echo "Detected distribution: $DISTRO"

# update the package list (once, upfront)
sudo apt update

# =========================================================================================================
# Desktop Applications (apt)
desktop_apps=(
    "barrier"       # software KVM switch (https://github.com/debauchee/barrier)
    "bleachbit"     # system cleaner and privacy manager
    "gimp"          # GNU Image Manipulation Program
    "octave"        # GNU Octave numerical computation language (https://octave.org/)
    "scrcpy"        # Android screen mirroring tool (https://github.com/Genymobile/scrcpy)
    "unetbootin"    # bootable USB creator (https://github.com/unetbootin/unetbootin)
    "vlc"           # multimedia player
    "pdftk"         # PDF toolkit for merging, splitting, and manipulating PDF files
)
sudo apt install --no-install-recommends --yes "${desktop_apps[@]}"
# =========================================================================================================

# =========================================================================================================
# Download helper: follows redirects but refuses any hop that leaves HTTPS, so a hijacked
# redirect cannot downgrade the transfer to plain HTTP.
download_https_only() {
    curl -fsSL --proto '=https' --proto-redir '=https' "$@"
}
# =========================================================================================================

# =========================================================================================================
# Genymotion - Android emulator (https://www.genymotion.com/product-desktop/download/)
install_genymotion() {
    if [[ -d /opt/genymotion ]]; then
        echo "[configure-deps] Genymotion is already installed, skipping" >&2
        return
    fi

    echo "Installing Genymotion..."
    local temp_dir
    temp_dir="$(mktemp -d)"

    download_https_only -o "$temp_dir/genymotion.bin" "https://dl.genymotion.com/releases/genymotion-3.8.0/genymotion-3.8.0-linux_x64.bin"
    chmod +x "$temp_dir/genymotion.bin"
    sudo "$temp_dir/genymotion.bin" -d /opt/genymotion -- -y
    sudo ln -sf /opt/genymotion/genymotion /usr/local/bin/genymotion
    rm -rf "$temp_dir"
}

# Reactotron - React/React Native debugging tool (https://github.com/infinitered/reactotron)
install_reactotron() {
    if dpkg -l reactotron-app &>/dev/null; then
        echo "[configure-deps] Reactotron is already installed, skipping" >&2
        return
    fi

    echo "Installing Reactotron..."
    local temp_dir
    temp_dir="$(mktemp -d)"

    local latest_tag
    latest_tag="$(download_https_only "https://api.github.com/repos/infinitered/reactotron/releases/latest" | jq -r '.tag_name')"
    # The tag format is "reactotron-app@X.Y.Z", extract the version number
    local version
    version="${latest_tag##*@}"

    download_https_only -o "$temp_dir/reactotron.deb" "https://github.com/infinitered/reactotron/releases/download/${latest_tag}/reactotron-app_${version}_amd64.deb"
    sudo dpkg -i "$temp_dir/reactotron.deb" || sudo apt install --fix-broken --yes
    rm -rf "$temp_dir"
}

# R-Linux 5 - data recovery tool (https://www.r-studio.com/free-linux-recovery/)
install_rlinux() {
    if dpkg -l rlinux &>/dev/null; then
        echo "[configure-deps] R-Linux is already installed, skipping" >&2
        return
    fi

    echo "Installing R-Linux 5..."
    local temp_dir
    temp_dir="$(mktemp -d)"

    download_https_only -o "$temp_dir/rlinux.deb" "https://www.r-studio.com/downloads/RLinux_amd64.deb"
    sudo dpkg -i "$temp_dir/rlinux.deb" || sudo apt install --fix-broken --yes
    rm -rf "$temp_dir"
}

# Slack - team communication (https://slack.com/downloads/linux)
install_slack() {
    if dpkg -l slack-desktop &>/dev/null; then
        echo "[configure-deps] Slack is already installed, skipping" >&2
        return
    fi

    echo "Installing Slack..."
    local temp_dir
    temp_dir="$(mktemp -d)"

    # Download the latest Slack .deb package
    download_https_only -o "$temp_dir/slack.deb" "https://packagemanager.rstudio.com/client/#/repos/2/packages/slack-desktop" 2>/dev/null \
        || download_https_only -o "$temp_dir/slack.deb" "https://downloads.slack-edge.com/desktop-releases/linux/x64/4.42.2/slack-desktop-4.42.2-amd64.deb"
    sudo dpkg -i "$temp_dir/slack.deb" || sudo apt install --fix-broken --yes
    rm -rf "$temp_dir"
}

# VirtualBox (https://www.virtualbox.org/wiki/Linux_Downloads)
install_virtualbox() {
    if dpkg -l virtualbox-7.1 &>/dev/null; then
        echo "[configure-deps] VirtualBox is already installed, skipping" >&2
        return
    fi

    echo "Installing VirtualBox..."

    # Add Oracle VirtualBox repository key
    download_https_only https://www.virtualbox.org/download/oracle_vbox_2016.asc | sudo gpg --yes --dearmor -o /usr/share/keyrings/oracle-virtualbox-2016.gpg

    local codename
    codename="$(lsb_release -cs)"

    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian $codename contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list

    sudo apt update
    sudo apt install --no-install-recommends --yes virtualbox-7.1
}

install_genymotion
install_reactotron
install_rlinux
install_slack
install_virtualbox
# =========================================================================================================
