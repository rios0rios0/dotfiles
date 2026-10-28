#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CI_DIR="$REPO_ROOT/.github/ci"
MOCK_OP="$CI_DIR/fixtures/mock-op.sh"
EXIT_CODE=0

echo "[test-template-render] testing template rendering with mock 1Password..." >&2

chmod +x "$MOCK_OP"

# Create a temporary chezmoi config that uses the mock op. It names this checkout as the source,
# so templates read its .chezmoidata and .chezmoitemplates rather than whatever the default source
# directory holds, or nothing at all on CI.
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
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
    ["dot_config/git/allowed_signers.tmpl"]=""
    ["dot_ssh/authorized_keys.tmpl"]=""
    ["dot_age_recipients.tmpl"]="^age1"
    ["dot_wakatime.cfg.tmpl"]="api_key"
)

for tmpl in "${!TEMPLATE_CHECKS[@]}"; do
    file="$REPO_ROOT/$tmpl"
    if [[ ! -f "$file" ]]; then
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
    if [[ -n "$check" ]] && ! echo "$output" | grep -qE "$check"; then
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
if [[ -f "$ssh_config_file" ]]; then
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
if [[ -f "$docker_tmpl" ]]; then
    err_file="$TMPDIR/err-docker"
    if output=$(chezmoi execute-template --config="$TMPDIR/chezmoi.yaml" < "$docker_tmpl" 2>"$err_file"); then
        if [[ -n "$output" ]] && ! echo "$output" | jq empty 2>/dev/null; then
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

# Parse the complete shell template for both supported platforms.
for platform in linux android; do
    rendered="$TMPDIR/zshrc-$platform.zsh"
    if ! chezmoi execute-template --config="$TMPDIR/chezmoi.yaml" \
        --override-data "{\"chezmoi\":{\"os\":\"$platform\"}}" \
        < "$REPO_ROOT/dot_zshrc.tmpl" > "$rendered" || ! zsh -n "$rendered"; then
        echo "[test-template-render] FAIL: $platform zshrc rendering/syntax" >&2
        EXIT_CODE=1
    else
        echo "[test-template-render] PASS: $platform zshrc rendering and syntax" >&2
    fi
done

# The Windows key scripts emit one PowerShell block per ssh:/pem: entry on the
# device note, and the fixture has two of each, so the boundary between blocks is
# exercised. A `-}}` that eats the newline there glues the next block's comment
# onto `Set-Content ... -Force`, which PowerShell reads as a parameter `Force#`.
for script in run_after_windows-001-create-ssh-public-keys.ps1.tmpl run_after_windows-002-create-ssh-pems.ps1.tmpl; do
    # given the device note with two entries of each type
    # when
    if ! output=$(chezmoi execute-template --config="$TMPDIR/chezmoi.yaml" \
        --override-data '{"chezmoi": {"os": "windows"}}' \
        < "$REPO_ROOT/.chezmoiscripts/$script" 2>/dev/null); then
        echo "[test-template-render] FAIL: $script (execution failed)" >&2
        EXIT_CODE=1
        continue
    fi

    # then: one Set-Content per entry, each ending its line, no comment glued to code
    set_contents=$(grep -c '^Set-Content ' <<<"$output" || true)
    unterminated=$(grep '^Set-Content ' <<<"$output" | grep -cv -- '-Force$' || true)
    glued=$(grep -cE '[^[:space:]]#' <<<"$output" || true)
    if [[ "$set_contents" = "2" ]] && [[ "$unterminated" = "0" ]] && [[ "$glued" = "0" ]]; then
        echo "[test-template-render] PASS: $script keeps each entry's block on its own lines" >&2
    else
        echo "[test-template-render] FAIL: $script ($set_contents Set-Content lines, $unterminated not ending in -Force, $glued comments glued to code)" >&2
        EXIT_CODE=1
    fi
done

# The config guard must render to nothing for a current config -- chezmoi then
# never runs it -- and stop a config generated before a data key existed, pointing
# at `chezmoi init`.
guard="$REPO_ROOT/.chezmoiscripts/run_before_000-verify-chezmoi-config.tmpl"

# given the test config, which has every data key
# when
if output=$(chezmoi execute-template --config="$TMPDIR/chezmoi.yaml" < "$guard" 2>&1) &&
    # then
    [[ -z "${output//[[:space:]]/}" ]]; then
    echo "[test-template-render] PASS: config guard renders to nothing for a current config" >&2
else
    echo "[test-template-render] FAIL: config guard is not silent for a current config: $output" >&2
    EXIT_CODE=1
fi

# given a config generated before data.deviceName existed
printf 'onePassword:\n  command: "%s"\n' "$MOCK_OP" > "$TMPDIR/stale.yaml"
# when
if output=$(chezmoi execute-template --config="$TMPDIR/stale.yaml" < "$guard" 2>&1); then
    echo "[test-template-render] FAIL: config guard let a config without deviceName through" >&2
    EXIT_CODE=1
# then
elif grep -q 'run `chezmoi init`' <<<"$output"; then
    echo "[test-template-render] PASS: config guard stops a config without deviceName and names chezmoi init" >&2
else
    echo "[test-template-render] FAIL: config guard failed without pointing at chezmoi init: $output" >&2
    EXIT_CODE=1
fi

# Commit signing, per platform: the program git signs and verifies with, and the allowed-signers
# file it verifies against. WSL signs with Linux's ssh-keygen through the SSH agent bridge rather
# than a Windows path that depends on how 1Password was installed; Linux reads the copy in
# ~/.config/git, since .ssh is not deployed there; Windows takes the op-ssh-sign.exe on PATH (the
# Microsoft Store build's alias) before falling back to Program Files. Each render gets its own
# PATH -- the signer's directory, plus /usr/bin and /bin for the mock op -- so a WSL host, whose PATH
# reaches Windows' own WindowsApps through /mnt/c, decides nothing.
CHEZMOI="$(command -v chezmoi)"
home="$("$CHEZMOI" execute-template --config="$TMPDIR/chezmoi.yaml" '{{ .chezmoi.homeDir }}')"
mkdir -p "$TMPDIR/no-signer" "$TMPDIR/signer"
printf '#!/bin/sh\nexit 0\n' > "$TMPDIR/signer/op-ssh-sign.exe"
chmod +x "$TMPDIR/signer/op-ssh-sign.exe"
# signing <label> <PATH> <override data> <program> <allowed-signers file, as a glob>
signing() {
    local label="$1" path_dir="$2" override="$3" want_program="$4" want_allowed="$5"
    local rendered program allowed
    rendered="$(PATH="$path_dir:/usr/bin:/bin" "$CHEZMOI" execute-template --config="$TMPDIR/chezmoi.yaml" --override-data "$override" \
        < "$REPO_ROOT/dot_gitconfig.tmpl" 2>/dev/null)" || {
        echo "[test-template-render] FAIL: $label gitconfig does not render" >&2
        EXIT_CODE=1
        return
    }
    program="$(sed -n 's/^    program = "\(.*\)"$/\1/p' <<<"$rendered")"
    allowed="$(sed -n 's/^    allowedSignersFile = "\(.*\)"$/\1/p' <<<"$rendered")"
    # shellcheck disable=SC2053 # the expected file is a glob on purpose
    if [[ "$program" == "$want_program" && "$allowed" == $want_allowed ]]; then
        echo "[test-template-render] PASS: $label signs with $want_program and verifies against $allowed" >&2
    else
        echo "[test-template-render] FAIL: $label signs with '$program' and verifies against '$allowed'" >&2
        EXIT_CODE=1
    fi
}
wsl_kernel='"kernel":{"osrelease":"6.18.33.2-microsoft-standard-WSL2","ostype":"Linux","version":"#1 SMP"}'
metal_kernel='"kernel":{"osrelease":"6.11.0-generic","ostype":"Linux","version":"#1 SMP"}'
signing "WSL" "$TMPDIR/no-signer" "{\"chezmoi\":{\"os\":\"linux\",$wsl_kernel}}" \
    "ssh-keygen" "$home/.config/git/allowed_signers"
signing "bare-metal Linux" "$TMPDIR/no-signer" "{\"chezmoi\":{\"os\":\"linux\",$metal_kernel}}" \
    "op-ssh-sign" "$home/.config/git/allowed_signers"
signing "Android" "$TMPDIR/no-signer" '{"chezmoi":{"os":"android"}}' \
    "ssh-keygen" "$home/.ssh/allowed_signers"
signing "Windows with op-ssh-sign.exe on PATH" "$TMPDIR/signer" '{"chezmoi":{"os":"windows"}}' \
    "$TMPDIR/signer/op-ssh-sign.exe" 'C:/Users/*/.ssh/allowed_signers'
signing "Windows without it" "$TMPDIR/no-signer" '{"chezmoi":{"os":"windows"}}' \
    "C:/Program Files/1Password/app/8/op-ssh-sign.exe" 'C:/Users/*/.ssh/allowed_signers'

# The Linux allowed-signers file and the .ssh one render from the same fragment.
if cmp -s <("$CHEZMOI" execute-template --config="$TMPDIR/chezmoi.yaml" < "$REPO_ROOT/dot_ssh/allowed_signers.tmpl" 2>/dev/null) \
    <("$CHEZMOI" execute-template --config="$TMPDIR/chezmoi.yaml" < "$REPO_ROOT/dot_config/git/allowed_signers.tmpl" 2>/dev/null); then
    echo "[test-template-render] PASS: the Linux allowed-signers file matches the .ssh one" >&2
else
    echo "[test-template-render] FAIL: the Linux allowed-signers file differs from the .ssh one" >&2
    EXIT_CODE=1
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-template-render] all template rendering tests passed" >&2
fi

exit $EXIT_CODE
