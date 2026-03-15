#!/data/data/com.termux/files/usr/bin/bash

# This script creates the generic proot 'wrapper' executable before any templates are rendered.
# This is necessary because tool-specific wrappers (op, gh) depend on this generic wrapper,
# and they must exist before chezmoi applies files (since templates use 1Password via 'op').

set -e

echo "[wrapper] creating proot wrapper in ~/.local/bin..." >&2

# Create the .local/bin directory if it doesn't exist
mkdir -p "$HOME/.local/bin"

# Create directories that will be mounted by proot
# These must exist before proot tries to bind them
mkdir -p "$HOME/.config/op"
mkdir -p "$HOME/.azure"
mkdir -p "$HOME/.local/share"

# Create the wrapper script that tool-specific wrappers depend on
cat > "$HOME/.local/bin/wrapper" << 'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# All host-installed binaries are visible inside a proot session via binds, but they have different needs,
# that's why each bind below, describe different needs of each binary which is being executed.

export PROOTNOCALL_VERIFY=1
export PROOT_LINK2SYMLINK=1
export PROOT_VERBOSE=-1

# Parse --env flags from arguments (tool wrappers pass their env vars this way)
env_flags=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env)
            env_flags+=(--env "$2")
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

workspace="/root/workspace"
proot-distro login alpine --no-arch-warning \
    "${env_flags[@]}" \
    --bind $HOME/.local/bin:/root/.local/bin \
    --bind $HOME/.config/op:/root/.config/op \
    --bind $HOME/.azure:/root/.azure \
    --bind $HOME/.local/share:/root/.local/share \
    --bind $(pwd):$workspace \
    --work-dir $workspace -- "$@"
WRAPPER_EOF

# Make wrapper executable
chmod +x "$HOME/.local/bin/wrapper"

echo "[wrapper] proot wrapper created successfully" >&2
