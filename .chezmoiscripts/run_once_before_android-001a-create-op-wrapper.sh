#!/data/data/com.termux/files/usr/bin/bash

# This script creates the 'op' wrapper before any templates are rendered.
# This is necessary because templates (like dot_gitconfig.tmpl) use the onepassword function
# which requires the 'op' command to be available in PATH.
# Uses termux-etc-seccomp to handle /etc/ path redirection and SIGSYS suppression.

set -e

echo "[op-wrapper] creating op in ~/.local/bin..." >&2

cat > "$HOME/.local/bin/op" << 'OP_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# Wraps the 1Password CLI through termux-etc-seccomp for /etc/ path redirection
# and SIGSYS suppression. Environment variables (OP_SESSION_*) are inherited
# naturally since we run in the same Termux environment (no proot boundary).

# Go's user.Current() in GOOS=linux static binaries reads /etc/passwd (missing on
# Android) then falls back to $USER. Without $USER, op can't resolve the current
# user and rejects directory ownership checks.
export USER="${USER:-$(id -un)}"

# check if the user is already signed in by running 'op whoami'
# if it fails, check if accounts are configured and trigger the signin flow
if ! termux-etc-seccomp ~/.local/bin/op_linux_arm64 whoami &>/dev/null; then
    # check if any accounts are configured (only when not signed in)
    accounts_json=$(termux-etc-seccomp ~/.local/bin/op_linux_arm64 account list --format=json 2>/dev/null || echo "[]")

    # check if accounts array is empty
    if [ "$accounts_json" = "[]" ] || [ -z "$accounts_json" ]; then
        echo "[op-wrapper] no accounts configured, adding account..." >&2
        termux-etc-seccomp ~/.local/bin/op_linux_arm64 account add --address my.1password.com --shorthand my
        add_exit_code=$?
        if [ $add_exit_code -ne 0 ]; then
            echo "[op-wrapper] ERROR: account add failed with exit code $add_exit_code" >&2
            exit 1
        fi
    fi
fi

exec termux-etc-seccomp ~/.local/bin/op_linux_arm64 "$@"
OP_EOF

# Make op executable
chmod +x "$HOME/.local/bin/op"

echo "[op-wrapper] op wrapper created successfully" >&2
