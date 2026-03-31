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

GOLANGCI_LINT_BIN="${HOME}/.local/bin/golangci-lint_linux_arm64"

# Ensure termux-etc-seccomp is available before exec.
if ! command -v termux-etc-seccomp >/dev/null 2>&1; then
  echo "[golangci-lint-wrapper] ERROR: termux-etc-seccomp is not installed or not in PATH." >&2
  echo "[golangci-lint-wrapper] Re-run 'chezmoi apply' to install Android dependencies, then try again." >&2
  exit 1
fi

# Ensure the underlying golangci-lint binary exists and is executable.
if [ ! -x "${GOLANGCI_LINT_BIN}" ]; then
  echo "[golangci-lint-wrapper] ERROR: ${GOLANGCI_LINT_BIN} is missing or not executable." >&2
  echo "[golangci-lint-wrapper] Re-run 'chezmoi apply' so Android golangci-lint dependencies are installed." >&2
  exit 1
fi

exec termux-etc-seccomp "${GOLANGCI_LINT_BIN}" "$@"
GOLANGCI_EOF

chmod +x "$HOME/.local/bin/golangci-lint"

echo "[golangci-lint-wrapper] golangci-lint wrapper created successfully" >&2
