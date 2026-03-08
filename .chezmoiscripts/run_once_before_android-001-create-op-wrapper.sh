#!/data/data/com.termux/files/usr/bin/bash

# This script creates the 'op' and 'wrapper' executables before any templates are rendered.
# This is necessary because templates (like dot_gitconfig.tmpl) use the onepassword function
# which requires the 'op' command to be available in PATH.
# Since files are applied in alphabetical order, .gitconfig would be rendered before
# .local/bin/op is created, causing the initialization to fail.

set -e

echo "[op-wrapper] creating wrapper and op in ~/.local/bin..." >&2

# Create the .local/bin directory if it doesn't exist
mkdir -p "$HOME/.local/bin"

# Create directories that will be mounted by proot
# These must exist before proot tries to bind them
mkdir -p "$HOME/.config/op"
mkdir -p "$HOME/.azure"

# First, create the wrapper script that op depends on
cat > "$HOME/.local/bin/wrapper" << 'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# forward any OP_SESSION_* tokens from host to proot (set by 'op signin')
env_flags=()
for _var in $(compgen -v OP_SESSION_ 2>/dev/null); do
  env_flags+=(--env "${_var}=${!_var}")
done

proot-distro login alpine --no-arch-warning \
    "${env_flags[@]}" \
    --bind $HOME/.local/bin:/root/.local/bin \
    --bind $HOME/.config/op:/root/.config/op \
    --bind $HOME/.azure:/root/.azure \
    --bind $(pwd):/root/workspace \
    --work-dir /root/workspace -- "$@"
WRAPPER_EOF

# Make wrapper executable
chmod +x "$HOME/.local/bin/wrapper"

# Now create the op wrapper that uses wrapper.
# No redundant 'op whoami' check — the op-loader handles auth flow.
cat > "$HOME/.local/bin/op" << 'OP_EOF'
#!/data/data/com.termux/files/usr/bin/bash
~/.local/bin/wrapper ~/.local/bin/op_linux_arm64 "$@"
OP_EOF

# Make op executable
chmod +x "$HOME/.local/bin/op"

echo "[op-wrapper] wrapper and op created successfully" >&2
