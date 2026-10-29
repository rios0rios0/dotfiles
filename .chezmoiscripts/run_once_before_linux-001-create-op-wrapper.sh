#!/bin/bash

# This script creates the 'op' wrapper before any templates are rendered.
# This is necessary because templates (like dot_gitconfig.tmpl) use the onepassword function
# which requires the 'op' command to be available in PATH.
# Since files are applied in alphabetical order, .gitconfig would be rendered before
# .local/bin/op is created, causing the initialization to fail.
#
# The wrapper also retries the call the 1Password app turns away: it removes the pipe op connects
# to for about 0.9 s after an `op account list`, and chezmoi runs `op signin` straight after it.
# On Windows chezmoi runs op.exe itself and runs no `account list` instead. See "1Password CLI
# Retry" in AGENTS.md.

set -e

echo "[op-wrapper] creating op wrapper in ~/.local/bin..." >&2

# Create the .local/bin directory if it doesn't exist
mkdir -p "$HOME/.local/bin"

# Linux/WSL version - calls op.exe
cat > "$HOME/.local/bin/op" << 'EOF'
#!/bin/bash

# this variable transports the environment variables to the op executable on Windows
# see more details on how to use it at: https://devblogs.microsoft.com/commandline/share-environment-vars-between-wsl-and-windows/
# see also at: https://github.com/1Password/terraform-provider-onepassword/blob/main/internal/onepassword/cli/op.go#L249
export WSLENV=OP_FORMAT:OP_INTEGRATION_NAME:OP_INTEGRATION_ID:OP_INTEGRATION_BUILDNUMBER

# A person at a prompt gets op untouched: its streams stay live, and a retry is theirs to make.
if [ -t 1 ]; then
    exec op.exe "$@"
fi

# 1Password for Windows removes the pipe op connects to for about 0.9 s after every CLI call,
# and an op started in that gap exits at once with "cannot connect to 1Password app, make sure
# it is running". Programs such as chezmoi run op calls back to back, so retry exactly that
# failure, a second after it. stderr waits in a file until op is done, so that only the last
# attempt's reaches the caller.
err="$(mktemp)" || exec op.exe "$@"
trap 'rm -f "$err"' EXIT
for delay in 1 1 2 ""; do
    op.exe "$@" 2>"$err"
    rc=$?
    if [ "$rc" -eq 0 ] || [ -z "$delay" ] || ! grep -q 'cannot connect to 1Password app' "$err"; then
        break
    fi
    sleep "$delay"
done
cat "$err" >&2
exit "$rc"
EOF

# Make the script executable
chmod +x "$HOME/.local/bin/op"

echo "[op-wrapper] op wrapper created successfully" >&2
