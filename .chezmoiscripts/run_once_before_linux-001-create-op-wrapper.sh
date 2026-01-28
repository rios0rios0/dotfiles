#!/bin/bash

# This script creates the 'op' wrapper before any templates are rendered.
# This is necessary because templates (like dot_gitconfig.tmpl) use the onepassword function
# which requires the 'op' command to be available in PATH.
# Since files are applied in alphabetical order, .gitconfig would be rendered before
# .local/bin/op is created, causing the initialization to fail.

set -e

echo "Creating op wrapper in ~/.local/bin..."

# Create the .local/bin directory if it doesn't exist
mkdir -p "$HOME/.local/bin"

# Linux/WSL version - calls op.exe
cat > "$HOME/.local/bin/op" << 'EOF'
#!/bin/bash

# this variable transports the environment variables to the op executable on Windows
# see more details on how to use it at: https://devblogs.microsoft.com/commandline/share-environment-vars-between-wsl-and-windows/
# see also at: https://github.com/1Password/terraform-provider-onepassword/blob/main/internal/onepassword/cli/op.go#L249
export WSLENV=OP_FORMAT:OP_INTEGRATION_NAME:OP_INTEGRATION_ID:OP_INTEGRATION_BUILDNUMBER

op.exe "$@"
EOF

# Make the script executable
chmod +x "$HOME/.local/bin/op"

echo "op wrapper created successfully"
