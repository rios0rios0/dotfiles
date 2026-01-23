#!/bin/bash
#
# Version Manager Utilities
# Reusable functions for detecting and switching language versions
# Supports: Go (gvm), Node (nvm), Python (pyenv)
#

# Generic function to detect version from a file and use the appropriate version manager
# Usage: _vm_detect_and_use <language> <version_file> <extract_func> <list_cmd> <install_cmd> <use_cmd> [version_prefix]
#
# Parameters:
#   language       - Language name for messages (e.g., "Go", "Node", "Python")
#   version_file   - Path to the file containing version info (e.g., "go.mod", ".nvmrc")
#   extract_func   - Function name to extract version from the file
#   list_cmd       - Command to list installed versions
#   install_cmd    - Command to install a version (version appended)
#   use_cmd        - Command to use/switch to a version (version appended)
#   version_prefix - Optional prefix to add to version (e.g., "go" for "go1.21")
_vm_detect_and_use() {
    local language="$1"
    local version_file="$2"
    local extract_func="$3"
    local list_cmd="$4"
    local install_cmd="$5"
    local use_cmd="$6"
    local version_prefix="${7:-}"

    # Only run in interactive shells
    [[ ! -o interactive ]] && return 0

    # Check if the version file exists
    [[ ! -f "$version_file" ]] && return 0

    # Extract version using the provided function
    local version
    version=$("$extract_func" "$version_file")
    [[ -z "$version" ]] && return 0

    # Add prefix if provided
    local full_version="${version_prefix}${version}"

    # Check if version is already installed
    if ! eval "$list_cmd" 2>/dev/null | grep -q "$full_version"; then
        echo "Installing $language version $full_version..."
        eval "$install_cmd $full_version" 2>/dev/null || {
            echo "Warning: Failed to install $language $full_version"
            return 1
        }
    fi

    # Use the detected version (suppress errors)
    eval "$use_cmd $full_version" 2>/dev/null || true
}

# Extract Go version from go.mod
_vm_extract_go_version() {
    local file="$1"
    grep -E '^go [0-9]+\.[0-9]+' "$file" 2>/dev/null | awk '{print $2}'
}

# Extract Node version from .nvmrc
_vm_extract_node_version_nvmrc() {
    local file="$1"
    tr -d '\r\n' < "$file"
}

# Extract Python version from pyproject.toml
# Supports multiple formats:
#   - requires-python = ">=3.10" or "~=3.10" or "==3.10"
#   - python = "^3.10" or ">=3.10" (Poetry style)
#   - python_requires = ">=3.10"
_vm_extract_python_version() {
    local file="$1"
    local version=""

    # Try to extract from requires-python (PEP 621 / PDM / Hatch)
    version=$(grep -E '^\s*requires-python\s*=' "$file" 2>/dev/null | \
        sed -E 's/.*["'\'']([><=~^!]*)?([0-9]+\.[0-9]+(\.[0-9]+)?).*["'\''].*/\2/' | head -1)

    # If not found, try poetry style [tool.poetry.dependencies] python = "^3.10"
    if [[ -z "$version" ]]; then
        version=$(grep -E '^\s*python\s*=\s*["'\'']' "$file" 2>/dev/null | \
            sed -E 's/.*["'\'']([><=~^!]*)?([0-9]+\.[0-9]+(\.[0-9]+)?).*["'\''].*/\2/' | head -1)
    fi

    # If not found, try python_requires (older setuptools style in pyproject.toml)
    if [[ -z "$version" ]]; then
        version=$(grep -E '^\s*python_requires\s*=' "$file" 2>/dev/null | \
            sed -E 's/.*["'\'']([><=~^!]*)?([0-9]+\.[0-9]+(\.[0-9]+)?).*["'\''].*/\2/' | head -1)
    fi

    echo "$version"
}

# Wrapper function for Go version detection
_vm_use_go() {
    local go_mod="${1:-$(pwd)/go.mod}"
    command -v gvm &>/dev/null || return 0

    _vm_detect_and_use "Go" "$go_mod" \
        "_vm_extract_go_version" \
        "gvm list" \
        "gvm install -B" \
        "gvm use" \
        "go"
}

# Wrapper function for Node version detection from .nvmrc
_vm_use_node() {
    local nvmrc="${1:-$(pwd)/.nvmrc}"
    command -v nvm &>/dev/null || return 0

    if [[ -f "$nvmrc" ]]; then
        _vm_detect_and_use "Node" "$nvmrc" \
            "_vm_extract_node_version_nvmrc" \
            "nvm ls" \
            "nvm install" \
            "nvm use"
    elif [[ -f "$(pwd)/package.json" ]]; then
        # If no .nvmrc but package.json exists, try to use current/default node
        nvm use 2>/dev/null || true
    fi
}

# Wrapper function for Python version detection
_vm_use_python() {
    local pyproject="${1:-$(pwd)/pyproject.toml}"
    command -v pyenv &>/dev/null || return 0

    _vm_detect_and_use "Python" "$pyproject" \
        "_vm_extract_python_version" \
        "pyenv versions" \
        "pyenv install" \
        "pyenv local"
}

# Clean up stale pyenv shim locks (fixes rehash lock issues)
_vm_cleanup_pyenv_locks() {
    local shims_dir="${PYENV_ROOT:-$HOME/.pyenv}/shims"
    local lock_file="$shims_dir/.pyenv-shim"

    # Remove stale lock file if it exists and is older than 60 seconds
    if [[ -f "$lock_file" ]]; then
        local file_age
        if [[ "$(uname)" == "Darwin" ]]; then
            file_age=$(( $(date +%s) - $(stat -f %m "$lock_file" 2>/dev/null || echo 0) ))
        else
            file_age=$(( $(date +%s) - $(stat -c %Y "$lock_file" 2>/dev/null || echo 0) ))
        fi

        if (( file_age > 60 )); then
            rm -f "$lock_file" 2>/dev/null
        fi
    fi
}

# Safe pyenv wrapper that handles noclobber issues
# The "cannot overwrite existing file" error during rehash is caused by noclobber shell option
# This wrapper temporarily disables noclobber for all pyenv operations
pyenv() {
    # Temporarily disable noclobber if it's set (fixes rehash lock issues)
    local noclobber_was_set=false
    if [[ -o noclobber ]]; then
        noclobber_was_set=true
        set +o noclobber
    fi

    # Clean up any stale locks before running pyenv
    _vm_cleanup_pyenv_locks

    # Run the actual pyenv command
    command pyenv "$@"
    local exit_code=$?

    # Restore noclobber if it was set
    if [[ "$noclobber_was_set" == "true" ]]; then
        set -o noclobber
    fi

    return $exit_code
}
