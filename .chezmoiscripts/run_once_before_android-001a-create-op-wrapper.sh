#!/data/data/com.termux/files/usr/bin/bash

# This script creates the 'op' wrapper before any templates are rendered.
# This is necessary because templates (like dot_gitconfig.tmpl) use the onepassword function
# which requires the 'op' command to be available in PATH.
# Depends on the generic wrapper created by run_once_before_android-001-create-wrapper.sh.

set -e

echo "[op-wrapper] creating op in ~/.local/bin..." >&2

cat > "$HOME/.local/bin/op" << 'OP_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# this can't be an alias/function, because it needs to be sourced from different shells and contexts (eg. Chezmoi)

# forward any OP_SESSION_* tokens from host to proot (set by 'op signin')
env_flags=()
for _var in $(compgen -v OP_SESSION_ 2>/dev/null); do
  env_flags+=(--env "${_var}=${!_var}")
done

# build the wrapper call with env flags (if any)
wrapper_cmd=(~/.local/bin/wrapper)
if [[ ${#env_flags[@]} -gt 0 ]]; then
    wrapper_cmd+=("${env_flags[@]}" --)
fi

# check if the user is already signed in by running 'op whoami'
# if it fails, check if accounts are configured and trigger the signin flow
if ! "${wrapper_cmd[@]}" ~/.local/bin/op_linux_arm64 whoami &>/dev/null; then
    # check if any accounts are configured (only when not signed in)
    # using --format=json to get reliable output that can be parsed
    accounts_json=$("${wrapper_cmd[@]}" ~/.local/bin/op_linux_arm64 account list --format=json 2>/dev/null || echo "[]")

    # check if accounts array is empty
    if [ "$accounts_json" = "[]" ] || [ -z "$accounts_json" ]; then
        echo "[op-wrapper] no accounts configured, adding account..." >&2
        "${wrapper_cmd[@]}" ~/.local/bin/op_linux_arm64 account add --address my.1password.com --shorthand my
        add_exit_code=$?
        if [ $add_exit_code -ne 0 ]; then
            echo "[op-wrapper] ERROR: account add failed with exit code $add_exit_code" >&2
            exit 1
        fi
    fi
fi

"${wrapper_cmd[@]}" ~/.local/bin/op_linux_arm64 "$@"
OP_EOF

# Make op executable
chmod +x "$HOME/.local/bin/op"

echo "[op-wrapper] op wrapper created successfully" >&2
