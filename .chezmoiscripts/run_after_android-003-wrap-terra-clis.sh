#!/data/data/com.termux/files/usr/bin/bash

# Wraps `terragrunt` and `terraform` in ~/.local/bin so every caller (shell,
# terra's exec.Command, scripts) routes through termux-etc-seccomp for /etc/
# path redirection and SIGSYS (faccessat2) suppression on Android/Termux.
#
# Shell aliases like `terragruntw` don't help here because Go's
# exec.Command bypasses shell aliasing, which is how `terra` launches
# terragrunt under the hood.
#
# This is a `run_after_` (not `run_once_after_`) script so it re-applies on
# every `chezmoi apply`. `terra update` periodically refreshes these binaries
# and would otherwise clobber the wrapper script.

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

is_wrapper() {
    [ -f "$1" ] && grep -q 'termux-etc-seccomp' "$1" 2>/dev/null
}

wrap_go_cli() {
    name="$1"
    target="$BIN_DIR/$name"
    raw="$BIN_DIR/${name}_raw"

    # Nothing to wrap if the CLI hasn't been installed yet.
    if [ ! -e "$target" ] && [ ! -e "$raw" ]; then
        return 0
    fi

    # Already wrapped: idempotent no-op.
    if is_wrapper "$target"; then
        return 0
    fi

    # If $target is a real binary (first install, or `terra update` clobbered
    # the previous wrapper), promote it to ${name}_raw so the new wrapper can
    # exec it.
    if [ -f "$target" ]; then
        mv -f "$target" "$raw"
    fi

    if [ ! -x "$raw" ]; then
        echo "[${name}-wrapper] WARN: ${raw} missing or not executable; skipping wrap" >&2
        return 0
    fi

    echo "[${name}-wrapper] creating ${name} in ~/.local/bin..." >&2

    cat > "$target" <<WRAPPER_EOF
#!/data/data/com.termux/files/usr/bin/bash

# Wraps ${name} through termux-etc-seccomp for /etc/ path redirection and
# SIGSYS (faccessat2) suppression on Android/Termux.

export PATH="/data/data/com.termux/files/usr/bin\${PATH:+:\$PATH}"
export USER="\${USER:-\$(id -un)}"

RAW_BIN="\${HOME}/.local/bin/${name}_raw"

if ! command -v termux-etc-seccomp >/dev/null 2>&1; then
  echo "[${name}-wrapper] ERROR: termux-etc-seccomp is not installed or not in PATH." >&2
  echo "[${name}-wrapper] Re-run 'chezmoi apply' to install Android dependencies, then try again." >&2
  exit 1
fi

if [ ! -x "\$RAW_BIN" ]; then
  echo "[${name}-wrapper] ERROR: \$RAW_BIN is missing or not executable." >&2
  echo "[${name}-wrapper] Re-run 'chezmoi apply' so terra can reinstall ${name}." >&2
  exit 1
fi

exec termux-etc-seccomp "\$RAW_BIN" "\$@"
WRAPPER_EOF

    chmod +x "$target"

    echo "[${name}-wrapper] ${name} wrapper created successfully" >&2
}

wrap_go_cli terragrunt
wrap_go_cli terraform
