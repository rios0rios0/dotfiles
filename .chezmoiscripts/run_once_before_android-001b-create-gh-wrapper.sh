#!/data/data/com.termux/files/usr/bin/bash

# This script creates the 'gh' wrapper before any templates are rendered.
# Uses termux-etc-seccomp to redirect /etc/resolv.conf (for Go DNS) and
# suppress SIGSYS from Android's seccomp (for faccessat2 in os/exec.LookPath).
# Environment variables (GH_TOKEN, etc.) are inherited naturally.

set -e

echo "[gh-wrapper] creating gh in ~/.local/bin..." >&2

cat > "$HOME/.local/bin/gh" << 'GH_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# Wraps GitHub CLI through termux-etc-seccomp for /etc/ path redirection
# and SIGSYS suppression. GitHub tokens are inherited from the environment.

# Go's user.Current() in GOOS=linux static binaries requires $USER when
# /etc/passwd is missing (Android).
export USER="${USER:-$(id -un)}"

exec termux-etc-seccomp ~/.local/bin/gh_linux_arm64 "$@"
GH_EOF

# Make gh executable
chmod +x "$HOME/.local/bin/gh"

echo "[gh-wrapper] gh wrapper created successfully" >&2
