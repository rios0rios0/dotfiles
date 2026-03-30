#!/data/data/com.termux/files/usr/bin/bash

# This script creates the generic 'wrapper' executable before any templates are rendered.
# This is necessary because tool-specific wrappers (op, gh) depend on this generic wrapper,
# and they must exist before chezmoi applies files (since templates use 1Password via 'op').
#
# The wrapper uses termux-etc-seccomp (built in the 002-install-dependencies script) to
# redirect /etc/ paths and suppress SIGSYS from Android's seccomp policy.

set -e

echo "[wrapper] creating termux-etc-seccomp wrapper in ~/.local/bin..." >&2

# Create the .local/bin directory if it doesn't exist
mkdir -p "$HOME/.local/bin"

# Create directories used by wrapped tools
mkdir -p "$HOME/.config/op"
mkdir -p "$HOME/.azure"
mkdir -p "$HOME/.local/share"

# Create the wrapper script that tool-specific wrappers depend on
cat > "$HOME/.local/bin/wrapper" << 'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# Runs a command under termux-etc-seccomp, which:
#   1. Redirects /etc/ paths (resolv.conf, hosts, SSL certs) to $PREFIX/etc/
#   2. Suppresses SIGSYS from Android's seccomp for blocked syscalls (e.g., faccessat2)
# This replaces the previous proot-distro Alpine wrapper, running natively in Termux.

exec termux-etc-seccomp "$@"
WRAPPER_EOF

# Make wrapper executable
chmod +x "$HOME/.local/bin/wrapper"

echo "[wrapper] termux-etc-seccomp wrapper created successfully" >&2
