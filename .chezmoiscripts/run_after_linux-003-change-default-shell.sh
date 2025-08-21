#!/bin/bash

# Change the default shell to zsh after all dependencies are installed
# This avoids the hanging issue that occurs when the shell is changed during the bootstrap process

# Check if zsh is installed
if command -v zsh >/dev/null 2>&1; then
    # Get the current user's shell
    current_shell=$(getent passwd "$USER" | cut -d: -f7)
    zsh_path=$(which zsh)
    
    # Only change the shell if it's not already zsh
    if [ "$current_shell" != "$zsh_path" ]; then
        echo "Changing default shell from $current_shell to $zsh_path..."
        chsh -s "$zsh_path"
        echo "Default shell changed to zsh. Please log out and log back in for the change to take effect."
    else
        echo "Default shell is already set to zsh."
    fi
else
    echo "Warning: zsh is not installed. Cannot change default shell."
fi