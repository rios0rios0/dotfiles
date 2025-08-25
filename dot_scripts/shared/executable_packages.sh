#!/bin/bash
#
# Package definitions for different platforms
# This file defines package arrays for Linux and Android
#

# Common requirements for both platforms
declare -a COMMON_REQUIREMENTS=(
    "git"
    "curl"
    "zip"
    "unzip"
    "age"
    "jq"
    "bat"
    "file"
)

# Linux-specific requirements
declare -a LINUX_REQUIREMENTS=(
    "${COMMON_REQUIREMENTS[@]}"
    "gpg"
    "gpg-agent"
    "eza"
    "sqlite3"
    "bsdmainutils"
    "binutils"
    "bison"
    "gcc"
    "make"
)

# Android/Termux-specific requirements  
declare -a ANDROID_REQUIREMENTS=(
    "${COMMON_REQUIREMENTS[@]}"
    "eza"
    "sqlite"
    "vim"
    "neovim"
    "binutils-is-llvm"
    "bison"
    "make"
    "wget"
    "zsh"
    "ncurses-utils"
    "proot"
    "proot-distro"
)

# Common hardware monitoring tools
declare -a HARDWARE_PACKAGES=(
    "htop"
    "screenfetch"
)

# Common utilities
declare -a COMMON_UTILITIES=(
    "silversearcher-ag"
    "inotify-tools"
    "dos2unix"
    "expect"
)

# Linux-specific utilities
declare -a LINUX_UTILITIES=(
    "${COMMON_UTILITIES[@]}"
    "aria2c"
)

# Android-specific utilities
declare -a ANDROID_UTILITIES=(
    "${COMMON_UTILITIES[@]}"
    "which"
    "mlocate"
    "openssh"
)

# Android-specific language packages
declare -a ANDROID_LANGUAGES=(
    "golang"
    "rust"
    "nodejs"
    "python"
    "python-pip"
)

# Get requirements packages for current platform
get_requirements_packages() {
    if is_android 2>/dev/null; then
        printf '%s\n' "${ANDROID_REQUIREMENTS[@]}"
    else
        printf '%s\n' "${LINUX_REQUIREMENTS[@]}"
    fi
}

# Get utilities packages for current platform
get_utilities_packages() {
    if is_android 2>/dev/null; then
        printf '%s\n' "${ANDROID_UTILITIES[@]}"
    else
        printf '%s\n' "${LINUX_UTILITIES[@]}"
    fi
}

# Get hardware packages (same for both platforms)
get_hardware_packages() {
    printf '%s\n' "${HARDWARE_PACKAGES[@]}"
}

# Get language packages (Android only)
get_language_packages() {
    if is_android 2>/dev/null; then
        printf '%s\n' "${ANDROID_LANGUAGES[@]}"
    fi
}

# Install all package categories
install_all_packages() {
    local pkg_manager
    pkg_manager=$(get_package_manager) || return 1
    
    # Update package list first
    execute_command "Update package list" $pkg_manager update
    
    # Install requirements
    local requirements
    mapfile -t requirements < <(get_requirements_packages)
    if [ ${#requirements[@]} -gt 0 ]; then
        install_packages "requirements" "${requirements[@]}"
    fi
    
    # Install hardware tools
    local hardware
    mapfile -t hardware < <(get_hardware_packages)
    if [ ${#hardware[@]} -gt 0 ]; then
        install_packages "hardware monitoring" "${hardware[@]}"
    fi
    
    # Install utilities
    local utilities
    mapfile -t utilities < <(get_utilities_packages)
    if [ ${#utilities[@]} -gt 0 ]; then
        install_packages "utilities" "${utilities[@]}"
    fi
    
    # Install languages (Android only)
    if is_android; then
        local languages
        mapfile -t languages < <(get_language_packages)
        if [ ${#languages[@]} -gt 0 ]; then
            install_packages "programming languages" "${languages[@]}"
        fi
        
        # Android-specific setup
        execute_command "Setup Termux storage" termux-setup-storage
    fi
}

# Export package functions
export -f get_requirements_packages get_utilities_packages get_hardware_packages
export -f get_language_packages install_all_packages