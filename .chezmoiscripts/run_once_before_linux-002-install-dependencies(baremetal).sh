#!/bin/bash

# This script installs GUI/desktop applications that are only useful on baremetal Linux.
# It must NOT run on WSL or Android.

# Exit if running inside WSL
if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
    echo "WSL detected, skipping baremetal dependencies installation."
    exit 0
fi

# Detect the distribution
if [ -f /etc/os-release ]; then
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

# update the package list
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
# Genymotion - Android emulator (https://www.genymotion.com/product-desktop/download/)
install_genymotion() {
    echo "Installing Genymotion..."
    local TEMP_DIR
    TEMP_DIR="$(mktemp -d)"

    curl -fsSL -o "$TEMP_DIR/genymotion.bin" "https://dl.genymotion.com/releases/genymotion-3.8.0/genymotion-3.8.0-linux_x64.bin"
    chmod +x "$TEMP_DIR/genymotion.bin"
    sudo "$TEMP_DIR/genymotion.bin" -d /opt/genymotion -- -y
    sudo ln -sf /opt/genymotion/genymotion /usr/local/bin/genymotion
    rm -rf "$TEMP_DIR"
}

# Reactotron - React/React Native debugging tool (https://github.com/infinitered/reactotron)
install_reactotron() {
    echo "Installing Reactotron..."
    local TEMP_DIR
    TEMP_DIR="$(mktemp -d)"

    local LATEST_TAG
    LATEST_TAG="$(curl -fsSL "https://api.github.com/repos/infinitered/reactotron/releases/latest" | jq -r '.tag_name')"
    # The tag format is "reactotron-app@X.Y.Z", extract the version number
    local VERSION
    VERSION="${LATEST_TAG##*@}"

    curl -fsSL -o "$TEMP_DIR/reactotron.deb" "https://github.com/infinitered/reactotron/releases/download/${LATEST_TAG}/reactotron-app_${VERSION}_amd64.deb"
    sudo dpkg -i "$TEMP_DIR/reactotron.deb" || sudo apt install --fix-broken --yes
    rm -rf "$TEMP_DIR"
}

# R-Linux 5 - data recovery tool (https://www.r-studio.com/free-linux-recovery/)
install_rlinux() {
    echo "Installing R-Linux 5..."
    local TEMP_DIR
    TEMP_DIR="$(mktemp -d)"

    curl -fsSL -o "$TEMP_DIR/rlinux.deb" "https://www.r-studio.com/downloads/RLinux_amd64.deb"
    sudo dpkg -i "$TEMP_DIR/rlinux.deb" || sudo apt install --fix-broken --yes
    rm -rf "$TEMP_DIR"
}

# Slack - team communication (https://slack.com/downloads/linux)
install_slack() {
    echo "Installing Slack..."
    local TEMP_DIR
    TEMP_DIR="$(mktemp -d)"

    # Download the latest Slack .deb package
    curl -fsSL -o "$TEMP_DIR/slack.deb" "https://packagemanager.rstudio.com/client/#/repos/2/packages/slack-desktop" 2>/dev/null \
        || curl -fsSL -o "$TEMP_DIR/slack.deb" "https://downloads.slack-edge.com/desktop-releases/linux/x64/4.42.2/slack-desktop-4.42.2-amd64.deb"
    sudo dpkg -i "$TEMP_DIR/slack.deb" || sudo apt install --fix-broken --yes
    rm -rf "$TEMP_DIR"
}

# VirtualBox (https://www.virtualbox.org/wiki/Linux_Downloads)
install_virtualbox() {
    echo "Installing VirtualBox..."

    # Add Oracle VirtualBox repository key
    curl -fsSL https://www.virtualbox.org/download/oracle_vbox_2016.asc | sudo gpg --yes --dearmor -o /usr/share/keyrings/oracle-virtualbox-2016.gpg

    local CODENAME
    CODENAME="$(lsb_release -cs)"

    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/oracle-virtualbox-2016.gpg] https://download.virtualbox.org/virtualbox/debian $CODENAME contrib" | sudo tee /etc/apt/sources.list.d/virtualbox.list

    sudo apt update
    sudo apt install --no-install-recommends --yes virtualbox-7.1
}

install_genymotion
install_reactotron
install_rlinux
install_slack
install_virtualbox
# =========================================================================================================
