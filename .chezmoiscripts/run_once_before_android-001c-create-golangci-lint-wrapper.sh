#!/data/data/com.termux/files/usr/bin/bash

# This script creates the 'golangci-lint' wrapper before dependencies are installed.
# Uses termux-etc-seccomp to redirect /etc/ paths and suppress SIGSYS from Android's
# seccomp policy for the statically-compiled linux/arm64 golangci-lint binary.

set -e

echo "[golangci-lint-wrapper] creating golangci-lint in ~/.local/bin..." >&2

cat > "$HOME/.local/bin/golangci-lint" << 'GOLANGCI_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# Wraps golangci-lint through termux-etc-seccomp for /etc/ path redirection
# and SIGSYS suppression on Android/Termux.

# Ensure Termux bin is in PATH so golangci-lint can find 'go' and other tools.
export PATH="/data/data/com.termux/files/usr/bin${PATH:+:$PATH}"

# Go's user.Current() in GOOS=linux static binaries requires $USER when
# /etc/passwd is missing (Android).
export USER="${USER:-$(id -un)}"

exec termux-etc-seccomp ~/.local/bin/golangci-lint_linux_arm64 "$@"
GOLANGCI_EOF

chmod +x "$HOME/.local/bin/golangci-lint"

echo "[golangci-lint-wrapper] golangci-lint wrapper created successfully" >&2
