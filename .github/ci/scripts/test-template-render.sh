#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CI_DIR="$REPO_ROOT/.github/ci"
MOCK_OP="$CI_DIR/fixtures/mock-op.sh"
EXIT_CODE=0

echo "[test-template-render] testing template rendering with mock 1Password..." >&2

chmod +x "$MOCK_OP"

# Create a temporary chezmoi config that uses the mock op
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/chezmoi.yaml" <<EOF
onePassword:
  command: "$MOCK_OP"
data:
  deviceName: "testdevice"
EOF

export CHEZMOI_CONFIG="$TMPDIR/chezmoi.yaml"

# Templates to test with format-specific validation
declare -A TEMPLATE_CHECKS=(
    ["dot_gitconfig.tmpl"]="\\[user\\]"
    ["dot_ssh/config.tmpl"]="Host"
    ["dot_ssh/allowed_signers.tmpl"]=""
    ["dot_ssh/authorized_keys.tmpl"]=""
    ["dot_age_recipients.tmpl"]=""
    ["dot_wakatime.cfg.tmpl"]="api_key"
)

for tmpl in "${!TEMPLATE_CHECKS[@]}"; do
    file="$REPO_ROOT/$tmpl"
    if [ ! -f "$file" ]; then
        echo "[test-template-render] SKIP: $tmpl (not found)" >&2
        continue
    fi

    err_file="$TMPDIR/err-$(echo "$tmpl" | tr '/' '-')"
    output=$(chezmoi execute-template --config="$TMPDIR/chezmoi.yaml" < "$file" 2>"$err_file") || {
        echo "[test-template-render] FAIL: $tmpl (template execution failed)" >&2
        cat "$err_file" >&2 || true
        EXIT_CODE=1
        continue
    }

    # Format-specific validation
    check="${TEMPLATE_CHECKS[$tmpl]}"
    if [ -n "$check" ] && ! echo "$output" | grep -qE "$check"; then
        echo "[test-template-render] FAIL: $tmpl (expected pattern '$check' not found in output)" >&2
        EXIT_CODE=1
        continue
    fi

    echo "[test-template-render] PASS: $tmpl" >&2
done

# Extra regression checks for dot_ssh/config.tmpl — ensure gist aliases and the
# port-443 SSH endpoint targets stay in the rendered output (CI runs on Linux,
# so the github/gist/gitlab/bitbucket blocks render with ProxyCommand pointing
# at ssh.github.com:443 / altssh.gitlab.com:443 / altssh.bitbucket.org:443).
ssh_config_file="$REPO_ROOT/dot_ssh/config.tmpl"
if [ -f "$ssh_config_file" ]; then
    err_file="$TMPDIR/err-ssh-config-extra"
    if ssh_output=$(chezmoi execute-template --config="$TMPDIR/chezmoi.yaml" < "$ssh_config_file" 2>"$err_file"); then
        for pattern in \
            "Host gist\.github\.com-" \
            "ssh\.github\.com 443" \
            "altssh\.gitlab\.com 443" \
            "altssh\.bitbucket\.org 443"
        do
            if ! echo "$ssh_output" | grep -qE "$pattern"; then
                echo "[test-template-render] FAIL: dot_ssh/config.tmpl (expected pattern '$pattern' not found)" >&2
                EXIT_CODE=1
            else
                echo "[test-template-render] PASS: dot_ssh/config.tmpl pattern '$pattern'" >&2
            fi
        done
    else
        echo "[test-template-render] FAIL: dot_ssh/config.tmpl (extra check execution failed)" >&2
        cat "$err_file" >&2 || true
        EXIT_CODE=1
    fi
fi

# Test docker config template (must be valid JSON)
docker_tmpl="$REPO_ROOT/dot_docker/config.json.tmpl"
if [ -f "$docker_tmpl" ]; then
    err_file="$TMPDIR/err-docker"
    if output=$(chezmoi execute-template --config="$TMPDIR/chezmoi.yaml" < "$docker_tmpl" 2>"$err_file"); then
        if [ -n "$output" ] && ! echo "$output" | jq empty 2>/dev/null; then
            echo "[test-template-render] FAIL: dot_docker/config.json.tmpl (invalid JSON output)" >&2
            EXIT_CODE=1
        else
            echo "[test-template-render] PASS: dot_docker/config.json.tmpl" >&2
        fi
    else
        echo "[test-template-render] FAIL: dot_docker/config.json.tmpl (execution failed)" >&2
        cat "$err_file" >&2 || true
        EXIT_CODE=1
    fi
fi

# Parse the complete shell template for both supported platforms, then exercise
# only the shortcut block so tests never load plugins or start account monitors.
mkdir -p "$TMPDIR/codex-bin"
cat > "$TMPDIR/codex-bin/codex" <<'EOF'
#!/bin/sh
printf '<%s>\n' "$@"
EOF
chmod +x "$TMPDIR/codex-bin/codex"
cat > "$TMPDIR/expected-codex-args" <<'EOF'
<--dangerously-bypass-approvals-and-sandbox>
<resume>
<two words>
<>
<*.go>
EOF

for platform in linux android; do
    rendered="$TMPDIR/zshrc-$platform.zsh"
    if ! chezmoi execute-template --config="$TMPDIR/chezmoi.yaml" \
        --override-data "{\"chezmoi\":{\"os\":\"$platform\"}}" \
        < "$REPO_ROOT/dot_zshrc.tmpl" > "$rendered" || ! zsh -n "$rendered"; then
        echo "[test-template-render] FAIL: $platform zshrc rendering/syntax" >&2
        EXIT_CODE=1
        continue
    fi
    awk '/^###### Codex CLI / { capture=1; next }
         capture && /^###### / { exit }
         capture { print }' "$rendered" > "$TMPDIR/codex-shortcut.zsh"
    # An inherited alias must be replaced; repeated sourcing must be harmless.
    # A shell function named codex must not intercept the executable on PATH.
    if ! PATH="$TMPDIR/codex-bin:$PATH" zsh -f -c '
        alias codexx="false"
        source "$1"
        source "$1"
        codex() { return 97; }
        codexx resume "two words" "" "*.go"
    ' test "$TMPDIR/codex-shortcut.zsh" > "$TMPDIR/actual-codex-args" || \
        ! diff -u "$TMPDIR/expected-codex-args" "$TMPDIR/actual-codex-args"; then
        echo "[test-template-render] FAIL: $platform codexx behavior" >&2
        EXIT_CODE=1
    else
        echo "[test-template-render] PASS: $platform zshrc syntax and codexx behavior" >&2
    fi
done

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-template-render] all template rendering tests passed" >&2
fi

exit $EXIT_CODE
