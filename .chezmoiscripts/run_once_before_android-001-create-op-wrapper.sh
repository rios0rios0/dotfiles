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

# Create directories that will be mounted by proot
# These must exist before proot tries to bind them
mkdir -p "$HOME/.config/op"
mkdir -p "$HOME/.azure"

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

# check if the user is already signed in by running 'op whoami'
# if it fails, check if accounts are configured and trigger the signin flow
if ! ~/.local/bin/wrapper ~/.local/bin/op_linux_arm64 whoami &>/dev/null; then
    # check if any accounts are configured (only when not signed in)
    # using --format=json to get reliable output that can be parsed
    accounts_json=$(~/.local/bin/wrapper ~/.local/bin/op_linux_arm64 account list --format=json 2>/dev/null || echo "[]")
    
    # check if accounts array is empty
    if [ "$accounts_json" = "[]" ] || [ -z "$accounts_json" ]; then
        echo "1Password: No accounts configured. Adding account..."
        ~/.local/bin/wrapper ~/.local/bin/op_linux_arm64 account add --address my.1password.com --shorthand my
        add_exit_code=$?
        if [ $add_exit_code -ne 0 ]; then
            echo "1Password: Account add failed with exit code $add_exit_code" >&2
            exit 1
        fi
    fi

    echo "1Password: Not signed in. Initiating signin..."
    signin_output=$(~/.local/bin/wrapper ~/.local/bin/op_linux_arm64 signin --account my 2>&1)
    signin_exit_code=$?
    if [ $signin_exit_code -ne 0 ]; then
        echo "1Password: Signin failed with exit code $signin_exit_code" >&2
        echo "$signin_output" >&2
        exit 1
    fi
    eval "$signin_output"
fi

~/.local/bin/wrapper ~/.local/bin/op_linux_arm64 "$@"
OP_EOF

# Make op executable
chmod +x "$HOME/.local/bin/op"

echo "wrapper and op created successfully"
