#!/data/data/com.termux/files/usr/bin/bash

# This script creates the 'op' and 'wrapper' executables before any templates are rendered.
# This is necessary because templates (like dot_gitconfig.tmpl) use the onepassword function
# which requires the 'op' command to be available in PATH.
# Since files are applied in alphabetical order, .gitconfig would be rendered before
# .local/bin/op is created, causing the initialization to fail.

set -e

echo "Creating wrapper and op in ~/.local/bin..."

# Create the .local/bin directory if it doesn't exist
mkdir -p "$HOME/.local/bin"

# First, create the wrapper script that op depends on
cat > "$HOME/.local/bin/wrapper" << 'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# All host-installed binaries are visible inside a proot session via binds, but they have different needs,
# that's why each bind below, describe different needs of each binary which is being executed.

export PROOTNOCALL_VERIFY=1
export PROOT_LINK2SYMLINK=1
export PROOT_VERBOSE=0

workspace="/root/workspace"
proot-distro login alpine \
    --bind $HOME/.local/bin:/root/.local/bin \
    --bind $HOME/.config/op:/root/.config/op \
    --bind $HOME/.azure:/root/.azure \
    --bind $(pwd):$workspace \
    --work-dir $workspace -- "$@"
WRAPPER_EOF

# Make wrapper executable
chmod +x "$HOME/.local/bin/wrapper"

# Now create the op wrapper that uses wrapper
cat > "$HOME/.local/bin/op" << 'OP_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# this can't be an alias/function, because it needs to be sourced from different shells and contexts (eg. Chezmoi)
wrapper op_linux_arm64 "$@"
OP_EOF

# Make op executable
chmod +x "$HOME/.local/bin/op"

echo "wrapper and op created successfully"
