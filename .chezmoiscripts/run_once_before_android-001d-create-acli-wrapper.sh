#!/data/data/com.termux/files/usr/bin/bash

# This script creates the 'acli' wrapper before dependencies are installed.
# Uses termux-etc-seccomp to redirect /etc/ paths and suppress SIGSYS from Android's
# seccomp policy for the statically-compiled linux/arm64 acli (Atlassian CLI) binary.

set -e

echo "[acli-wrapper] creating acli in ~/.local/bin..." >&2

cat > "$HOME/.local/bin/acli" << 'ACLI_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# Wraps acli (Atlassian CLI) through termux-etc-seccomp for /etc/ path redirection
# and SIGSYS suppression on Android/Termux.

# Ensure Termux bin is in PATH so acli can find auxiliary tools.
export PATH="/data/data/com.termux/files/usr/bin${PATH:+:$PATH}"

# Go's user.Current() in GOOS=linux static binaries requires $USER when
# /etc/passwd is missing (Android).
export USER="${USER:-$(id -un)}"

ACLI_BIN="${HOME}/.local/bin/acli_linux_arm64"

# Ensure termux-etc-seccomp is available before exec.
if ! command -v termux-etc-seccomp >/dev/null 2>&1; then
  echo "[acli-wrapper] ERROR: termux-etc-seccomp is not installed or not in PATH." >&2
  echo "[acli-wrapper] Re-run 'chezmoi apply' to install Android dependencies, then try again." >&2
  exit 1
fi

# Ensure the underlying acli binary exists and is executable.
if [ ! -x "${ACLI_BIN}" ]; then
  echo "[acli-wrapper] ERROR: ${ACLI_BIN} is missing or not executable." >&2
  echo "[acli-wrapper] Re-run 'chezmoi apply' so Android acli dependencies are installed." >&2
  exit 1
fi

exec termux-etc-seccomp "${ACLI_BIN}" "$@"
ACLI_EOF

chmod +x "$HOME/.local/bin/acli"

echo "[acli-wrapper] acli wrapper created successfully" >&2
