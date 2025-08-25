#!/bin/bash
#
# Shared utility functions for dotfiles installation scripts
# This file provides common functions used across Linux and Android installation scripts
#

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Log messages with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*"
}

# Log error messages
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >&2
}

# Log warning messages
log_warn() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $*" >&2
}

# Check if directory exists, create if not
ensure_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        log "Creating directory: $dir"
        mkdir -p "$dir"
    fi
}

# Check if tool is already installed by checking path
is_tool_installed() {
    local tool_name="$1"
    local install_path="$2"
    
    if [ -n "$install_path" ] && [ -f "$install_path" ]; then
        log "$tool_name is already installed at $install_path"
        return 0
    elif command_exists "$tool_name"; then
        log "$tool_name is already available in PATH"
        return 0
    fi
    return 1
}

# Download file with retry logic
download_file() {
    local url="$1"
    local output="$2"
    local retries=3
    
    for i in $(seq 1 $retries); do
        log "Downloading $url (attempt $i/$retries)"
        if curl -fsSL "$url" -o "$output"; then
            log "Successfully downloaded $output"
            return 0
        else
            log_warn "Download failed, attempt $i/$retries"
            sleep 2
        fi
    done
    
    log_error "Failed to download $url after $retries attempts"
    return 1
}

# Execute command with error handling
execute_command() {
    local description="$1"
    shift
    
    log "Executing: $description"
    if "$@"; then
        log "Successfully completed: $description"
        return 0
    else
        log_error "Failed to execute: $description"
        return 1
    fi
}

# Check if running on Android/Termux
is_android() {
    [ -n "$ANDROID_ROOT" ] || [ -d "/data/data/com.termux" ]
}

# Check if running on Linux (non-Android)
is_linux() {
    [ "$(uname)" = "Linux" ] && ! is_android
}

# Get package manager command based on platform
get_package_manager() {
    if is_android; then
        echo "apt"
    elif is_linux; then
        echo "sudo apt"
    else
        log_error "Unsupported platform"
        return 1
    fi
}

# Install packages using appropriate package manager
install_packages() {
    local description="$1"
    shift
    local packages=("$@")
    
    local pkg_manager
    pkg_manager=$(get_package_manager) || return 1
    
    log "Installing $description: ${packages[*]}"
    execute_command "Install $description" $pkg_manager install --no-install-recommends --yes "${packages[@]}"
}

# Export all functions for use in other scripts
export -f command_exists log log_error log_warn ensure_directory is_tool_installed
export -f download_file execute_command is_android is_linux get_package_manager install_packages