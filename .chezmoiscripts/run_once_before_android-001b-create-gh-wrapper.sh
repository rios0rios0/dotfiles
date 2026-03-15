#!/data/data/com.termux/files/usr/bin/bash

# This script creates the 'gh' wrapper before any templates are rendered.
# gh needs proot-distro (Alpine) because Go's built-in DNS resolver
# reads /etc/resolv.conf, which doesn't exist in Termux (it's at $PREFIX/etc/resolv.conf).
# Without proot, gh fails DNS lookups and reports "token is invalid".
# Depends on the generic wrapper created by run_once_before_android-001-create-wrapper.sh.

set -e

echo "[gh-wrapper] creating gh in ~/.local/bin..." >&2

cat > "$HOME/.local/bin/gh" << 'GH_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# forward GitHub tokens so gh CLI authenticates inside proot
env_flags=()
for _var in GH_TOKEN GITHUB_PERSONAL_ACCESS_TOKEN GITHUB_TOKEN; do
  [[ -n "${!_var}" ]] && env_flags+=(--env "${_var}=${!_var}")
done

# build the wrapper call with env flags (if any)
wrapper_cmd=(~/.local/bin/wrapper)
if [[ ${#env_flags[@]} -gt 0 ]]; then
    wrapper_cmd+=("${env_flags[@]}" --)
fi

exec "${wrapper_cmd[@]}" ~/.local/bin/gh_linux_arm64 "$@"
GH_EOF

# Make gh executable
chmod +x "$HOME/.local/bin/gh"

echo "[gh-wrapper] gh wrapper created successfully" >&2
