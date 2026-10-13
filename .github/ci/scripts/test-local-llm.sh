#!/bin/bash
set -euo pipefail

# Tests the local model behind claude-local: the settings every consumer reads, the unit and the
# launcher that must agree on one context window, the installer's render gate, the launcher's
# behaviour against stubbed tools, and the capacity hint in the zsh wrapper.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CI_DIR="$REPO_ROOT/.github/ci"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-local-llm] testing the local model setup..." >&2

pass() { echo "[test-local-llm] PASS: $1" >&2; }
fail() { echo "[test-local-llm] FAIL: $1" >&2; EXIT_CODE=1; }

# .chezmoidata and .chezmoitemplates are read from the source directory, so every render points
# chezmoi at this checkout; the mock 1Password keeps dot_zshrc.tmpl renderable.
chmod +x "$CI_DIR/fixtures/mock-op.sh"
cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
onePassword:
  command: "$CI_DIR/fixtures/mock-op.sh"
data:
  deviceName: "testdevice"
EOF

# The settings are gated on nvidia-smi being on PATH, so each render runs with a PATH holding only
# chezmoi -- plus a fake nvidia-smi for a machine with a GPU -- and the host's own driver, present
# on a developer's WSL box and absent on a CI runner, never decides a result.
CHEZMOI="$(command -v chezmoi)"
mkdir -p "$TMP/bin-gpu" "$TMP/bin-nogpu"
ln -s "$CHEZMOI" "$TMP/bin-gpu/chezmoi"
ln -s "$CHEZMOI" "$TMP/bin-nogpu/chezmoi"
printf '#!/bin/sh\necho "NVIDIA Test GPU, 24576 MiB"\n' > "$TMP/bin-gpu/nvidia-smi"
chmod +x "$TMP/bin-gpu/nvidia-smi"

# render <gpu|nogpu> <source file> [override JSON]
render() {
    local override="${3:-}"
    PATH="$TMP/bin-$1" chezmoi execute-template --config "$TMP/chezmoi.yaml" \
        ${override:+--override-data "$override"} < "$2"
}

settings() {
    local override="${2:-}"
    PATH="$TMP/bin-$1" chezmoi execute-template --config "$TMP/chezmoi.yaml" \
        ${override:+--override-data "$override"} '{{ includeTemplate "lib-local-llm.tmpl" . }}'
}

UNIT="$REPO_ROOT/dot_config/systemd/user/ollama.service.tmpl"
LAUNCHER="$REPO_ROOT/dot_local/bin/executable_claude-local.tmpl"
INSTALLER="$REPO_ROOT/.chezmoiscripts/run_onchange_after_linux-009-setup-ollama.sh.tmpl"

# --- settings -------------------------------------------------------------------------------

# given a GPU and the defaults
# when
json="$(settings gpu)"
# then
if [[ "$(jq -r '.enabled' <<<"$json")" == "true" && "$(jq -r '.model' <<<"$json")" != "" &&
    "$(jq -r '.contextTokens' <<<"$json")" =~ ^[0-9]+$ ]]; then
    pass "settings are enabled with a model and a numeric window when a GPU is present"
else
    fail "settings with a GPU: $json"
fi

# given no GPU
# when
json="$(settings nogpu)"
# then
[[ "$(jq -r '.enabled' <<<"$json")" == "false" ]] && pass "settings are disabled without a GPU" ||
    fail "settings without a GPU: $json"

# given a GPU, but this device switched off. sprig's merge drops false as empty, which once let
# the default `true` win, so this guards the key-by-key overlay.
# when
json="$(settings gpu '{"localLLM":{"devices":{"testdevice":{"enabled":false}}}}')"
# then
[[ "$(jq -r '.enabled' <<<"$json")" == "false" ]] && pass "a device can switch the local model off" ||
    fail "device opt-out ignored: $json"

# given an override for this device and one for another
# when
json="$(settings gpu '{"localLLM":{"devices":{"testdevice":{"contextTokens":32768},"other":{"contextTokens":8192}}}}')"
# then
[[ "$(jq -r '.contextTokens' <<<"$json")" == "32768" ]] && pass "this device's override applies, another's does not" ||
    fail "device override: $json"

# given a config that predates deviceName. .chezmoiignore includes the settings and is rendered
# before run_before_000-verify-chezmoi-config can report the stale config, so they must render
# with the defaults rather than abort the apply with a template error.
printf 'sourceDir: "%s"\n' "$REPO_ROOT" > "$TMP/stale.yaml"
# when
if json="$(PATH="$TMP/bin-gpu" chezmoi execute-template --config "$TMP/stale.yaml" \
    '{{ includeTemplate "lib-local-llm.tmpl" . }}' 2>&1)" && [[ "$(jq -r '.enabled' <<<"$json")" == "true" ]]; then
    pass "settings render with the defaults when the config has no deviceName"
else
    fail "settings without deviceName: $json"
fi

# --- one window, two consumers ---------------------------------------------------------------

for override in "" '{"localLLM":{"devices":{"testdevice":{"contextTokens":32768}}}}'; do
    # given the same settings
    # when
    server="$(render gpu "$UNIT" "$override" | sed -n 's/^Environment=OLLAMA_CONTEXT_LENGTH=//p')"
    client="$(render gpu "$LAUNCHER" "$override" | sed -n 's/^export CLAUDE_CODE_MAX_CONTEXT_TOKENS=//p')"
    # then
    if [[ -n "$server" && "$server" == "$client" ]]; then
        pass "the unit and claude-local agree on a ${server}-token window"
    else
        fail "the unit serves '$server' tokens but claude-local declares '$client'"
    fi
done

# --- installer ---------------------------------------------------------------------------------

# given a GPU
# when
script="$(render gpu "$INSTALLER")"
# then
if [[ "$(head -1 <<<"$script")" == "#!/bin/bash" ]] && bash -n <<<"$script"; then
    pass "the installer renders to a valid bash script on a GPU machine"
else
    fail "the installer did not render to a valid script with a GPU"
fi

# given no GPU
# when
script="$(render nogpu "$INSTALLER")"
# then: chezmoi never runs a script that renders to whitespace
[[ -z "${script//[[:space:]]/}" ]] && pass "the installer renders to nothing without a GPU" ||
    fail "the installer rendered content without a GPU"

# given two context windows
# when
digest_a="$(render gpu "$INSTALLER" | sed -n 's/^#   unit //p')"
digest_b="$(render gpu "$INSTALLER" '{"localLLM":{"contextTokens":32768}}' | sed -n 's/^#   unit //p')"
# then: a changed unit changes the script, which is what makes run_onchange_ restart the server
if [[ -n "$digest_a" && "$digest_a" != "$digest_b" ]]; then
    pass "a change to the unit changes the installer, so it re-runs"
else
    fail "the installer's unit digest did not follow the unit ('$digest_a' vs '$digest_b')"
fi

# --- launcher ----------------------------------------------------------------------------------

render gpu "$LAUNCHER" > "$TMP/claude-local"
chmod +x "$TMP/claude-local"

# Stubs: ollama records the arguments and environment it was handed; curl answers once the
# "server" is up; systemctl starting the unit brings it up unless told it never will; sleep is
# instant so the wait loop costs nothing.
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/ollama" <<EOF
#!/bin/bash
printf '<%s>\n' "\$@" > "$TMP/ollama.args"
env | grep -E '^(CLAUDE_CONFIG_DIR|CLAUDE_CODE_MAX_CONTEXT_TOKENS|CLAUDE_CODE_MAX_OUTPUT_TOKENS|OLLAMA_HOST|ANTHROPIC_[A-Z_]*)=' | sort > "$TMP/ollama.env"
EOF
cat > "$STUBS/curl" <<EOF
#!/bin/bash
[[ -e "$TMP/server-up" ]]
EOF
cat > "$STUBS/systemctl" <<EOF
#!/bin/bash
echo "\$*" >> "$TMP/systemctl.args"
[[ -e "$TMP/server-never-up" ]] || touch "$TMP/server-up"
EOF
printf '#!/bin/sh\nexit 0\n' > "$STUBS/claude"
printf '#!/bin/sh\nexit 0\n' > "$STUBS/sleep"
chmod +x "$STUBS"/*

reset_stubs() {
    rm -f "$TMP/ollama.args" "$TMP/ollama.env" "$TMP/systemctl.args" "$TMP/server-up" "$TMP/server-never-up"
}

run_launcher() {
    env -u OLLAMA_HOST -u CLAUDE_LOCAL_MODEL -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_BASE_URL \
        PATH="$STUBS:/usr/bin:/bin" "$@"
}

# given a running server
reset_stubs
touch "$TMP/server-up"
model="$(jq -r '.model' <<<"$(settings gpu)")"
# when
run_launcher "$TMP/claude-local" -p "two words" "" "*.go" 2>/dev/null
# then: the arguments reach `ollama launch` intact, the tool list closed off by --settings
cat > "$TMP/expected.args" <<EOF
<launch>
<claude>
<--model>
<$model>
<--yes>
<-->
<--tools>
<Bash,Read,Edit,Write,Glob,Grep>
<--settings>
EOF
if head -9 "$TMP/ollama.args" | diff -u "$TMP/expected.args" - >/dev/null &&
    [[ "$(tail -4 "$TMP/ollama.args" | tr '\n' '|')" == "<-p>|<two words>|<>|<*.go>|" ]]; then
    pass "claude-local hands its arguments to ollama launch intact"
else
    fail "unexpected ollama launch arguments: $(tr '\n' ' ' < "$TMP/ollama.args")"
fi

# then: the settings keep exactly the listed global rules
excludes="$(sed -n '10p' "$TMP/ollama.args" | sed 's/^<//; s/>$//' | jq -r '.claudeMdExcludes[0]')"
[[ "$excludes" == "$HOME/.claude/rules/!(code-style|git-flow|testing).md" ]] &&
    pass "the lean profile excludes every global rule but the listed ones" ||
    fail "unexpected claudeMdExcludes: $excludes"

# then: the window and the lean profile are set, and no provider variable leaks from the script --
# ollama launch scopes those to the claude process itself
if grep -qx "CLAUDE_CONFIG_DIR=$HOME/.claude-local" "$TMP/ollama.env" &&
    grep -q '^CLAUDE_CODE_MAX_CONTEXT_TOKENS=[0-9]' "$TMP/ollama.env" &&
    grep -q '^CLAUDE_CODE_MAX_OUTPUT_TOKENS=[0-9]' "$TMP/ollama.env" &&
    grep -qx 'OLLAMA_HOST=http://127.0.0.1:11434' "$TMP/ollama.env" &&
    ! grep -q '^ANTHROPIC_' "$TMP/ollama.env"; then
    pass "claude-local sets the window and the lean profile, and nothing else"
else
    fail "unexpected environment: $(tr '\n' ' ' < "$TMP/ollama.env")"
fi

# given a stopped local server
reset_stubs
# when
run_launcher "$TMP/claude-local" -p hi 2>/dev/null
# then
if grep -qx -- '--user start ollama.service' "$TMP/systemctl.args" && [[ -s "$TMP/ollama.args" ]]; then
    pass "claude-local starts the user unit on demand"
else
    fail "claude-local did not start a stopped server and go on"
fi

# given a server that never comes up
reset_stubs
touch "$TMP/server-never-up"
# when
if output="$(run_launcher "$TMP/claude-local" -p hi 2>&1)"; then status=0; else status=$?; fi
# then
if [[ "$status" -ne 0 && "$output" == *"no Ollama server answers"* && ! -e "$TMP/ollama.args" ]]; then
    pass "claude-local stops when no server answers"
else
    fail "claude-local with no server: status=$status output=$output"
fi

# given a remote server that is down
reset_stubs
# when
if run_launcher env OLLAMA_HOST=10.0.0.5:11434 "$TMP/claude-local" -p hi >/dev/null 2>&1; then status=0; else status=$?; fi
# then: the local unit is never started for a server elsewhere
if [[ "$status" -ne 0 && ! -e "$TMP/systemctl.args" ]]; then
    pass "claude-local leaves the local unit alone for a remote server"
else
    fail "claude-local with a remote server: status=$status, systemctl called: $(cat "$TMP/systemctl.args" 2>/dev/null)"
fi

# given a model chosen for one session
reset_stubs
touch "$TMP/server-up"
# when
run_launcher env CLAUDE_LOCAL_MODEL=other:7b "$TMP/claude-local" 2>/dev/null
# then
sed -n '4p' "$TMP/ollama.args" | grep -qx '<other:7b>' && pass "CLAUDE_LOCAL_MODEL picks the model for one session" ||
    fail "CLAUDE_LOCAL_MODEL ignored: $(tr '\n' ' ' < "$TMP/ollama.args")"

# given no Claude Code: ollama launch would offer to pipe an installer into bash, and --yes accepts
reset_stubs
touch "$TMP/server-up"
mkdir -p "$TMP/stubs-noclaude"
cp "$STUBS/ollama" "$STUBS/curl" "$STUBS/sleep" "$TMP/stubs-noclaude/"
# when
if env PATH="$TMP/stubs-noclaude:/usr/bin:/bin" "$TMP/claude-local" -p hi >/dev/null 2>&1; then status=0; else status=$?; fi
# then
if [[ "$status" -ne 0 && ! -e "$TMP/ollama.args" ]]; then
    pass "claude-local refuses to run ollama launch without Claude Code installed"
else
    fail "claude-local without Claude Code: status=$status"
fi

# --- capacity hint in the zsh wrapper ----------------------------------------------------------

render gpu "$REPO_ROOT/dot_zshrc.tmpl" '{"chezmoi":{"os":"linux"}}' > "$TMP/zshrc.zsh"
awk '/^_claude_ensure_account\(\) \{/ { capture=1 } capture { print } capture && /^\}/ { exit }' \
    "$TMP/zshrc.zsh" > "$TMP/guard.zsh"

HINT_BIN="$TMP/hint-bin"
mkdir -p "$HINT_BIN"
cat > "$HINT_BIN/ccswitch" <<'EOF'
#!/bin/sh
[ "$1" = "capacity" ] && exit "${CAPACITY_EXIT:-0}"
exit 0
EOF
printf '#!/bin/sh\nexit 0\n' > "$HINT_BIN/claude-local"
chmod +x "$HINT_BIN"/*

# hint <exit status of `ccswitch capacity`> <PATH>: the guard's stderr
hint() {
    CAPACITY_EXIT="$1" PATH="$2" zsh -f -c 'source "$1"; _claude_ensure_account' guard "$TMP/guard.zsh" 2>&1 >/dev/null
}

[[ "$(hint 3 "$HINT_BIN:/usr/bin:/bin")" == *"claude-local"* ]] &&
    pass "the wrapper points at claude-local when no account has capacity (exit 3)" ||
    fail "no hint for exit 3"
[[ -z "$(hint 0 "$HINT_BIN:/usr/bin:/bin")" && -z "$(hint 1 "$HINT_BIN:/usr/bin:/bin")" ]] &&
    pass "the wrapper stays silent for capacity, failures and older ccswitch (exit 0 and 1)" ||
    fail "a hint was printed without exit 3"
mkdir -p "$TMP/hint-bin-nolocal"
cp "$HINT_BIN/ccswitch" "$TMP/hint-bin-nolocal/"
[[ -z "$(hint 3 "$TMP/hint-bin-nolocal:/usr/bin:/bin")" ]] &&
    pass "the wrapper says nothing where claude-local is not installed" ||
    fail "a hint pointed at a claude-local that is not installed"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-local-llm] all local model tests passed" >&2
fi

exit $EXIT_CODE
