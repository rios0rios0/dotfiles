#!/bin/bash
set -euo pipefail

# Tests claude-omni, Claude Code through OmniRoute: how it sizes each model's window, what it hands
# Claude Code, the GPU guards it keeps from claude-local and claude-remote, the /model lineup when
# it outgrows a command-line argument, the audited runs of claude-omni-task, and the capacity hint
# in the zsh wrapper. curl, claude, systemctl and tailscale are stubs, so no OmniRoute, GPU or
# network is needed.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CI_DIR="$REPO_ROOT/.github/ci"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-claude-omni] testing claude-omni and claude-omni-task..." >&2

pass() { echo "[test-claude-omni] PASS: $1" >&2; }
fail() { echo "[test-claude-omni] FAIL: $1" >&2; EXIT_CODE=1; }

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

render() {
    chezmoi execute-template --config "$TMP/chezmoi.yaml" < "$1"
}

WRAPPER="$REPO_ROOT/dot_local/bin/executable_claude-omni.tmpl"
TASK="$REPO_ROOT/dot_local/bin/executable_claude-omni-task.tmpl"
UNIT="$REPO_ROOT/dot_config/systemd/user/ollama.service.tmpl"

# Whether systemd runs is read from /run/systemd/system, so the wrapper is rendered with that path
# pointing at a directory that exists, and once more at one that does not: the host running this
# suite never decides a result.
mkdir -p "$TMP/systemd"
render "$WRAPPER" | sed "s|/run/systemd/system|$TMP/systemd|g" > "$TMP/claude-omni"
render "$WRAPPER" | sed "s|/run/systemd/system|$TMP/no-systemd|g" > "$TMP/claude-omni-nosystemd"
chmod +x "$TMP/claude-omni" "$TMP/claude-omni-nosystemd"

window="$(render "$UNIT" | sed -n 's/^Environment=OLLAMA_CONTEXT_LENGTH=//p')"
gpu_model="$(chezmoi execute-template --config "$TMP/chezmoi.yaml" '{{ (includeTemplate "lib-local-llm.tmpl" . | fromJson).model }}')"

# The catalog OmniRoute serves, as its /v1/models shapes it: every chat model carries the stable
# `root` a label comes from; the GPU models -- last in the catalog, as in OmniRoute's own -- and
# the NIM model carry its 128000 fallback and no max_input_tokens; real windows elsewhere; an auto
# combo advertising the largest window in its pool; one model too small for most sessions; and two
# the lineup leaves out, an image model and one OmniRoute says cannot call tools.
jq -n --arg gpu "$gpu_model" '{data: [
    {id: "nvidia/z-ai/glm-5.3", root: "z-ai/glm-5.3", context_length: 128000, max_input_tokens: null},
    {id: "openrouter/moonshotai/kimi-k2.7-code", root: "moonshotai/kimi-k2.7-code", context_length: 262144, max_input_tokens: 262144, max_output_tokens: 235929},
    {id: "openrouter/z-ai/glm-5.3", root: "z-ai/glm-5.3", context_length: 1048576, max_input_tokens: 1048576, max_output_tokens: 131072},
    {id: "openrouter/poolside/laguna-s-2.1:free", root: "poolside/laguna-s-2.1:free", context_length: 262144, max_input_tokens: 262144},
    {id: "auto/coding", root: "auto/coding", context_length: 2000000, max_input_tokens: 2000000, max_output_tokens: 1800000},
    {id: "openrouter/some/small", root: "some/small", context_length: 32768, max_input_tokens: 32768},
    {id: "openrouter/some/specialty", root: "some/specialty", context_length: 200000, max_input_tokens: 200000, capabilities: {tool_calling: false}},
    {id: "openrouter/some/image", root: "some/image", type: "image"},
    {id: "ollama-laptop/\($gpu)", root: $gpu, context_length: 128000, max_input_tokens: null, capabilities: {tool_calling: true}},
    {id: "ollama-desktop/\($gpu)", root: $gpu, context_length: 128000, max_input_tokens: null}]}' > "$TMP/catalog.json"

# Stubs. curl serves the catalog (recording the headers it was handed on stdin and its argument
# list), answers this machine's Ollama once it is up and the tailnet's for the addresses in
# remote-answering, loads any model, and reports remote-ps.json as the server's running models.
# claude records its arguments and environment; systemctl starting the unit brings the local
# server up unless told it never will; tailscale answers from files; sleep is instant.
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/curl" <<EOF
#!/bin/bash
url="" out="" fmt=""
args=("\$@")
for ((i = 0; i < \${#args[@]}; i++)); do
    case "\${args[i]}" in
        -o) out="\${args[i+1]}" ;;
        -w) fmt="\${args[i+1]}" ;;
        http*) url="\${args[i]}" ;;
    esac
done
printf '%s\n' "\$@" >> "$TMP/curl.argv"
host="\${url#http://}"
host="\${host%%[:/]*}"
case "\$url" in
    */v1/models*)
        cat > "$TMP/curl.stdin"
        [[ -e "$TMP/omniroute-down" ]] && exit 7
        if [[ -e "$TMP/omniroute-refuses" ]]; then
            echo '{"error":{"message":"Invalid API key"}}' > "\$out"
            printf 401
            exit 0
        fi
        cp "$TMP/catalog.json" "\$out"
        printf 200
        ;;
    http://127.0.0.1:11434/api/version) [[ -e "$TMP/local-up" ]] ;;
    */api/version) grep -qxF "\$host" "$TMP/remote-answering" ;;
    */api/generate) echo "\$host" >> "$TMP/remote-loaded"; echo '{"done":true}' ;;
    */api/ps) cat "$TMP/remote-ps.json" ;;
    *) exit 7 ;;
esac
EOF
cat > "$STUBS/claude" <<EOF
#!/bin/bash
printf '<%s>\n' "\$@" > "$TMP/claude.args"
env | grep -E '^(ANTHROPIC_|CLAUDE_|DISABLE_)' | sort > "$TMP/claude.env"
printf '%s' "\${ANTHROPIC_CUSTOM_HEADERS:-}" > "$TMP/claude.headers"
EOF
cat > "$STUBS/systemctl" <<EOF
#!/bin/bash
echo "\$*" >> "$TMP/systemctl.args"
[[ -e "$TMP/local-never-up" ]] || touch "$TMP/local-up"
EOF
cat > "$STUBS/tailscale" <<EOF
#!/bin/bash
[[ "\$1 \$2" == "status --json" ]] && exec cat "$TMP/tailnet.json"
[[ "\$1 \$2" == "ip -4" ]] && { awk -v name="\$3" '\$1 == name { print \$2; found = 1 } END { exit !found }' "$TMP/tailnet-ips"; exit; }
exit 1
EOF
printf '#!/bin/sh\nexit 0\n' > "$STUBS/sleep"
chmod +x "$STUBS"/*

# reset: a fresh profile, OmniRoute up, this machine's server up, and a tailnet whose desktop
# answers and holds the model at this machine's window, entirely in VRAM
reset() {
    rm -rf "${TMP:?}/profile" "${TMP:?}/home"
    rm -f "$TMP"/claude.args "$TMP"/claude.env "$TMP"/claude.headers "$TMP"/systemctl.args "$TMP"/curl.argv "$TMP"/curl.stdin \
        "$TMP"/omniroute-down "$TMP"/omniroute-refuses "$TMP"/local-never-up "$TMP"/remote-loaded
    mkdir -p "$TMP/home"
    touch "$TMP/local-up"
    jq -n '{BackendState: "Running", Peer: {
        a: {HostName: "phone", Online: true, TailscaleIPs: ["100.64.0.2"]},
        b: {HostName: "desktop", Online: true, TailscaleIPs: ["fd7a::3", "100.64.0.3"]}}}' > "$TMP/tailnet.json"
    printf '100.64.0.3\n' > "$TMP/remote-answering"
    printf 'desktop 100.64.0.3\n' > "$TMP/tailnet-ips"
    jq -n --arg model "$gpu_model" --argjson ctx "$window" \
        '{models: [{name: $model, model: $model, context_length: $ctx, size: 100, size_vram: 100}]}' > "$TMP/remote-ps.json"
}

# run_omni <wrapper> [arguments...]: no terminal, so no picker; the caller's ANTHROPIC_API_KEY
# and an unrelated variable stand in for a shell's environment
run_omni() {
    env -i HOME="$TMP/home" PATH="$STUBS:/usr/bin:/bin" OMNIROUTE_API_KEY="fixture-token-placeholder" \
        CLAUDE_OMNI_CONFIG_DIR="$TMP/profile" ANTHROPIC_API_KEY="fixture-console-key-placeholder" "$@" </dev/null
}

envvar() {
    sed -n "s/^$1=//p" "$TMP/claude.env"
}

# The settings reach Claude Code as a file in the profile, so the --settings value is a path; the
# inline form is still read straight from the argument.
settings_arg() {
    local arg
    arg="$(awk 'prev == "<--settings>" { sub(/^</, ""); sub(/>$/, ""); print; exit } { prev = $0 }' "$TMP/claude.args")"
    if [[ -f "$arg" ]]; then cat "$arg"; else printf '%s' "$arg"; fi
}

# --- windows -------------------------------------------------------------------------------------

# given a GPU model, which OmniRoute advertises at its 128000 fallback
reset
# when
run_omni "$TMP/claude-omni" -m "ollama-laptop/$gpu_model" -p hi 2>/dev/null
# then: the window is the one the Ollama unit allocates -- one value, rendered twice
if [[ -n "$window" && "$(envvar CLAUDE_CODE_MAX_CONTEXT_TOKENS)" == "$window" &&
    "$(envvar CLAUDE_OMNI_WINDOW)" == "$window" && "$(envvar CLAUDE_CODE_MAX_OUTPUT_TOKENS)" == "8192" ]]; then
    pass "a GPU model gets the window the Ollama unit allocates ($window), not OmniRoute's fallback"
else
    fail "GPU window: unit '$window', claude got '$(envvar CLAUDE_CODE_MAX_CONTEXT_TOKENS)', output '$(envvar CLAUDE_CODE_MAX_OUTPUT_TOKENS)'"
fi

# given a cloud model whose window OmniRoute knows
reset
# when
run_omni "$TMP/claude-omni" -m openrouter/moonshotai/kimi-k2.7-code -p hi 2>/dev/null
# then: its window, and a reply reservation of a 32000 ceiling rather than an eighth of 262144
if [[ "$(envvar CLAUDE_CODE_MAX_CONTEXT_TOKENS)" == "262144" && "$(envvar CLAUDE_CODE_MAX_OUTPUT_TOKENS)" == "32000" ]]; then
    pass "a cloud model gets OmniRoute's window and a capped reply reservation"
else
    fail "cloud window: $(envvar CLAUDE_CODE_MAX_CONTEXT_TOKENS) / $(envvar CLAUDE_CODE_MAX_OUTPUT_TOKENS)"
fi

# given a model OmniRoute reports only its fallback for
reset
# when
output="$(run_omni "$TMP/claude-omni" -m nvidia/z-ai/glm-5.3 -p hi 2>&1)"
# then: the fallback is used, and said to be one
if [[ "$(envvar CLAUDE_CODE_MAX_CONTEXT_TOKENS)" == "128000" && "$output" == *"WARN: OmniRoute knows no window for nvidia/z-ai/glm-5.3"* ]]; then
    pass "a fallback window is used with a warning that it is one"
else
    fail "fallback window: $(envvar CLAUDE_CODE_MAX_CONTEXT_TOKENS) / $output"
fi

# given an auto combo, which advertises the largest window in its pool
reset
# when
run_omni "$TMP/claude-omni" -m auto/coding -p hi 2>/dev/null
# then
[[ "$(envvar CLAUDE_CODE_MAX_CONTEXT_TOKENS)" == "200000" ]] && pass "an auto combo compacts at autoWindow, not at its pool's largest window" ||
    fail "auto window: $(envvar CLAUDE_CODE_MAX_CONTEXT_TOKENS)"

# given a model OmniRoute does not serve
reset
# when
if output="$(run_omni "$TMP/claude-omni" -m openrouter/missing/model -p hi 2>&1)"; then status=0; else status=$?; fi
# then
if [[ "$status" -ne 0 && "$output" == *"OmniRoute does not serve openrouter/missing/model"* && ! -e "$TMP/claude.args" ]]; then
    pass "claude-omni refuses a model OmniRoute does not serve"
else
    fail "unserved model: status=$status output=$output"
fi

# --- what Claude Code is handed -----------------------------------------------------------------

# given a GPU session started with arguments for Claude Code, -m among them
reset
# when
run_omni "$TMP/claude-omni" -c -m "ollama-laptop/$gpu_model" -p "two words" "" "*.go" 2>/dev/null
# then: every tier is pinned to the model, the 1M variants are off, the cache-keeping list is set,
# the key reaches Claude Code only as its token, and the caller's console key is gone
if [[ "$(envvar ANTHROPIC_BASE_URL)" == "http://127.0.0.1:20128" &&
    "$(envvar ANTHROPIC_AUTH_TOKEN)" == "fixture-token-placeholder" && -z "$(envvar ANTHROPIC_API_KEY)" &&
    "$(envvar ANTHROPIC_MODEL)" == "ollama-laptop/$gpu_model" &&
    "$(envvar ANTHROPIC_DEFAULT_OPUS_MODEL)" == "ollama-laptop/$gpu_model" &&
    "$(envvar ANTHROPIC_DEFAULT_SONNET_MODEL)" == "ollama-laptop/$gpu_model" &&
    "$(envvar ANTHROPIC_DEFAULT_HAIKU_MODEL)" == "ollama-laptop/$gpu_model" &&
    "$(envvar ANTHROPIC_DEFAULT_FABLE_MODEL)" == "ollama-laptop/$gpu_model" &&
    "$(envvar CLAUDE_CODE_SUBAGENT_MODEL)" == "ollama-laptop/$gpu_model" &&
    "$(envvar CLAUDE_CODE_DISABLE_1M_CONTEXT)" == "1" && "$(envvar CLAUDE_CODE_ATTRIBUTION_HEADER)" == "0" &&
    "$(envvar CLAUDE_CODE_TOTAL_TOKENS_REMINDER)" == "off" && "$(envvar CLAUDE_CODE_AUTO_MODE_SERVER)" == "0" &&
    "$(envvar DISABLE_ERROR_REPORTING)" == "1" && "$(envvar DISABLE_FEEDBACK_COMMAND)" == "1" &&
    "$(envvar CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY)" == "1" && "$(envvar CLAUDE_CONFIG_DIR)" == "$TMP/profile" &&
    "$(envvar CLAUDE_OMNI_MODEL)" == "ollama-laptop/$gpu_model" ]]; then
    pass "claude-omni pins every tier, turns the 1M variants off and keeps the prompt cacheable"
else
    fail "unexpected environment: $(tr '\n' ' ' < "$TMP/claude.env")"
fi
# then: both OmniRoute headers are set, one per line
if [[ "$(cat "$TMP/claude.headers")" == $'x-omniroute-compression: off\nx-omniroute-no-memory: true' ]]; then
    pass "the prompt reaches the provider uncompressed and without injected memory"
else
    fail "unexpected custom headers: $(cat "$TMP/claude.headers")"
fi
# then: the key went to curl on stdin, never on its command line
if grep -qx 'Authorization: Bearer fixture-token-placeholder' "$TMP/curl.stdin" &&
    ! grep -q 'fixture-token-placeholder' "$TMP/curl.argv"; then
    pass "the API key reaches curl on stdin only"
else
    fail "the key was on curl's command line, or never reached it"
fi
# then: -m is taken out wherever it stands, the lean tool list is closed off by --settings, and the
# caller's arguments follow intact
if [[ "$(head -5 "$TMP/claude.args" | tr '\n' '|')" == "<--model>|<ollama-laptop/$gpu_model>|<--tools>|<Bash,Read,Edit,Write,Glob,Grep>|<--settings>|" &&
    "$(tail -5 "$TMP/claude.args" | tr '\n' '|')" == "<-c>|<-p>|<two words>|<>|<*.go>|" ]]; then
    pass "claude-omni hands Claude Code its arguments intact, after the lean tool list"
else
    fail "unexpected claude arguments: $(tr '\n' ' ' < "$TMP/claude.args")"
fi
# then: the lean profile keeps exactly the listed global rules
excludes="$(settings_arg | jq -r '.claudeMdExcludes[0]')"
[[ "$excludes" == "$HOME/.claude/rules/!(code-style|git-flow|testing).md" ]] &&
    pass "a small window gets the lean profile, which keeps only the listed global rules" ||
    fail "unexpected claudeMdExcludes: $excludes"

# given a model with a window past the lean threshold
reset
# when
run_omni "$TMP/claude-omni" -m openrouter/moonshotai/kimi-k2.7-code -p hi 2>/dev/null
# then: every tool and every rule
if ! grep -qx '<--tools>' "$TMP/claude.args" && [[ "$(settings_arg | jq 'has("claudeMdExcludes")')" == "false" ]]; then
    pass "a large window gets every tool and every rule"
else
    fail "a large window got the lean profile: $(tr '\n' ' ' < "$TMP/claude.args")"
fi

# --- the /model lineup -----------------------------------------------------------------------------

# given a session on a GPU model
reset
# when
run_omni "$TMP/claude-omni" -m "ollama-desktop/$gpu_model" -p hi 2>/dev/null
lineup="$(settings_arg | jq -c '.modelPicker')"
# then: the models OmniRoute lists that can call tools, the GPUs' own model leading, each option
# labelled from its `root` and carrying its window, replacing the built-ins
if [[ "$(jq -r '.replaceBuiltInOptions' <<<"$lineup")" == "true" &&
    "$(jq -r '[.options[].model] | join(" ")' <<<"$lineup")" == "ollama-laptop/$gpu_model ollama-desktop/$gpu_model nvidia/z-ai/glm-5.3 openrouter/moonshotai/kimi-k2.7-code openrouter/z-ai/glm-5.3 openrouter/poolside/laguna-s-2.1:free auto/coding" &&
    "$(jq -r '[.options[].model] | index("openrouter/some/specialty") == null' <<<"$lineup")" == "true" &&
    "$(jq -r '.options[] | select(.model == "nvidia/z-ai/glm-5.3") | "\(.label) \(.description)"' <<<"$lineup")" == "z-ai/glm-5.3 128K? context · nvidia" &&
    "$(jq -r ".options[] | select(.model == \"ollama-desktop/$gpu_model\") | .label" <<<"$lineup")" == "$gpu_model · desktop GPU" ]]; then
    pass "/model offers the served models, each labelled with its window"
else
    fail "unexpected lineup: $lineup"
fi

# given a session on a 1M-token model
reset
# when
run_omni "$TMP/claude-omni" -m openrouter/z-ai/glm-5.3 -p hi 2>/dev/null
# then: no model with a smaller window, which would overflow before the session compacts
models="$(settings_arg | jq -r '[.modelPicker.options[].model] | join(" ")')"
[[ "$models" == "openrouter/z-ai/glm-5.3" ]] && pass "/model leaves out the models whose window is smaller than the session's" ||
    fail "a smaller window was offered: $models"

# given a session started without -m and without a terminal
reset
mkdir -p "$TMP/profile"
echo '{"model":"openrouter/poolside/laguna-s-2.1:free"}' > "$TMP/profile/settings.json"
# when
run_omni "$TMP/claude-omni" -p hi 2>/dev/null
# then: the choice the profile saved last, rather than a prompt
[[ "$(envvar ANTHROPIC_MODEL)" == "openrouter/poolside/laguna-s-2.1:free" ]] &&
    pass "without a terminal, claude-omni starts on the model the profile saved last" ||
    fail "saved choice ignored: $(envvar ANTHROPIC_MODEL)"

# given the same, with no saved choice
reset
# when
run_omni "$TMP/claude-omni" -p hi 2>/dev/null
# then: the first served model in the lineup
[[ "$(envvar ANTHROPIC_MODEL)" == "ollama-laptop/$gpu_model" ]] &&
    pass "without a saved choice, claude-omni starts on the first served model" ||
    fail "unexpected default: $(envvar ANTHROPIC_MODEL)"

# given a terminal, and an answer of 3 at the prompt
reset
# when
answer_file="$TMP/answer"
printf '3\n' > "$answer_file"
script -qec "env -i HOME='$TMP/home' PATH='$STUBS:/usr/bin:/bin' OMNIROUTE_API_KEY=fixture-token-placeholder CLAUDE_OMNI_CONFIG_DIR='$TMP/profile' '$TMP/claude-omni' < /dev/tty" /dev/null < "$answer_file" >/dev/null 2>&1 || true
# then
[[ "$(envvar ANTHROPIC_MODEL 2>/dev/null)" == "nvidia/z-ai/glm-5.3" ]] && pass "the picker starts the model whose number was typed" ||
    fail "the picker chose '$(envvar ANTHROPIC_MODEL 2>/dev/null)'"

# given a session, for the status line's sake
reset
# when
run_omni "$TMP/claude-omni" -m "ollama-desktop/$gpu_model" -p hi 2>/dev/null
# then: every served chat model's window is on file, a GPU's at the server's and an auto combo's
# at autoWindow, and no image model
table="$TMP/profile/omniroute-windows.tsv"
if grep -qxF "ollama-desktop/$gpu_model	$window" "$table" && grep -qxF "openrouter/some/small	32768" "$table" &&
    grep -qxF "auto/coding	200000" "$table" && ! grep -q '^openrouter/some/image' "$table"; then
    pass "the window of every served chat model is written for the status line"
else
    fail "unexpected windows table: $(tr '\n' ' ' < "$table")"
fi

# --- a lineup too large for a command line ---------------------------------------------------------

# The real catalog holds more than a thousand chat models, and the resolved lineup and the settings
# built from it both pass MAX_ARG_STRLEN (32 pages): an exec given one argument that long fails with
# "Argument list too long" before anything runs. The launcher therefore hands jq the lineup on stdin
# and Claude Code a settings file named on its command line, and a catalog this size must launch
# like any other.

# given a catalog whose lineup and settings pass the argument limit
reset
cp "$TMP/catalog.json" "$TMP/catalog.saved"
jq '.data += [range(1; 1501) | {id: "openrouter/bulk/provider-\(.)/filler-model", root: "bulk/provider-\(.)/filler-model", context_length: 128000, max_input_tokens: 128000}]' \
    "$TMP/catalog.saved" > "$TMP/catalog.json"
# the fixture is only a fixture if its lineup really crosses the limit, or this test proves nothing
arg_limit=$(( 32 * $(getconf PAGESIZE) ))
config="$(chezmoi execute-template --config "$TMP/chezmoi.yaml" '{{ includeTemplate "lib-omniroute.tmpl" . | fromJson | toJson }}')"
resolve_jq="$(sed -n "/^resolve_jq='/,/^'$/p" "$TMP/claude-omni" | sed '1d;$d')"
lineup_size="$(jq -c --argjson cfg "$config" --arg want "" --slurpfile catalog "$TMP/catalog.json" -n "$resolve_jq" | wc -c)"
(( lineup_size > arg_limit )) ||
    fail "the bulk fixture's lineup ($lineup_size bytes) no longer crosses MAX_ARG_STRLEN ($arg_limit)"

# when
if output="$(run_omni "$TMP/claude-omni" -m openrouter/some/small -p hi 2>&1)"; then status=0; else status=$?; fi
# then: the session starts, the settings arrive as a file past the limit, and the windows table
# holds the whole catalog
settings_path="$(awk 'prev == "<--settings>" { sub(/^</, ""); sub(/>$/, ""); print; exit } { prev = $0 }' "$TMP/claude.args")"
settings_size=0
[[ -f "$settings_path" ]] && settings_size="$(wc -c < "$settings_path")"
if [[ "$status" -eq 0 && "$settings_size" -gt "$arg_limit" ]] &&
    [[ "$(settings_arg | jq -r '.modelPicker.replaceBuiltInOptions')" == "true" ]] &&
    awk -F '\t' '$1 == "openrouter/bulk/provider-1/filler-model" && $2 == 128000 { found = 1 } END { exit !found }' "$TMP/profile/omniroute-windows.tsv" &&
    awk -F '\t' '$1 == "openrouter/some/small" && $2 == 32768 { found = 1 } END { exit !found }' "$TMP/profile/omniroute-windows.tsv"; then
    pass "a lineup and settings past an argument's limit launch like any other"
else
    fail "large lineup: status=$status settings=$settings_size output=$output"
fi

mv -f "$TMP/catalog.saved" "$TMP/catalog.json"

# --- the GPU guards -------------------------------------------------------------------------------

# given this machine's server, stopped
reset
rm -f "$TMP/local-up"
# when
run_omni "$TMP/claude-omni" -m "ollama-laptop/$gpu_model" -p hi 2>/dev/null
# then
if grep -qx -- '--user start ollama.service' "$TMP/systemctl.args" && [[ -s "$TMP/claude.args" ]]; then
    pass "claude-omni starts this machine's Ollama unit on demand"
else
    fail "claude-omni did not start a stopped local server and go on"
fi

# given this machine's server, which never comes up
reset
rm -f "$TMP/local-up"
touch "$TMP/local-never-up"
# when
if output="$(run_omni "$TMP/claude-omni" -m "ollama-laptop/$gpu_model" -p hi 2>&1)"; then status=0; else status=$?; fi
# then
if [[ "$status" -ne 0 && "$output" == *"no Ollama server answers on this machine"* && "$output" == *"systemctl --user status ollama"* &&
    ! -e "$TMP/claude.args" ]]; then
    pass "claude-omni stops when this machine's server does not answer"
else
    fail "local server down: status=$status output=$output"
fi

# given the same, on a machine where systemd is not running
reset
rm -f "$TMP/local-up"
touch "$TMP/local-never-up"
# when
if output="$(run_omni "$TMP/claude-omni-nosystemd" -m "ollama-laptop/$gpu_model" -p hi 2>&1)"; then status=0; else status=$?; fi
# then: it says what is missing, rather than pointing at a systemctl that fails the same way
if [[ "$status" -ne 0 && "$output" == *"systemd, which runs it, is not running"* && "$output" != *"systemctl --user status"* ]]; then
    pass "claude-omni says systemd is not running instead of pointing at systemctl"
else
    fail "no systemd: status=$status output=$output"
fi

# given a model on another machine's GPU
reset
# when
output="$(run_omni "$TMP/claude-omni" -m "ollama-desktop/$gpu_model" -p hi 2>&1)"
# then: the online machine that answers is found, the model loaded there, and the session goes on
if [[ "$output" == *"using desktop (100.64.0.3)"* && "$(cat "$TMP/remote-loaded")" == "100.64.0.3" && -s "$TMP/claude.args" ]]; then
    pass "claude-omni finds the tailnet machine serving the GPU and loads the model there"
else
    fail "tailnet GPU: $output"
fi

# given that machine serving a window other than this one declares
reset
jq '.models[0].context_length = 32768' "$TMP/remote-ps.json" > "$TMP/remote-ps.tmp" && mv "$TMP/remote-ps.tmp" "$TMP/remote-ps.json"
# when
if output="$(run_omni "$TMP/claude-omni" -m "ollama-desktop/$gpu_model" -p hi 2>&1)"; then status=0; else status=$?; fi
# then: a window mismatch truncates silently, so it stops the launch
if [[ "$status" -ne 0 && "$output" == *"32768-token window"* && "$output" == *"chezmoi update"* && ! -e "$TMP/claude.args" ]]; then
    pass "claude-omni refuses a tailnet GPU whose window differs"
else
    fail "mismatched window: status=$status output=$output"
fi

# given that machine's GPU holding only part of the model
reset
jq '.models[0].size_vram = 40' "$TMP/remote-ps.json" > "$TMP/remote-ps.tmp" && mv "$TMP/remote-ps.tmp" "$TMP/remote-ps.json"
# when
output="$(run_omni "$TMP/claude-omni" -m "ollama-desktop/$gpu_model" -p hi 2>&1)"
# then
if [[ "$output" == *"WARN: 60% of $gpu_model runs on the CPU of desktop"* && -s "$TMP/claude.args" ]]; then
    pass "claude-omni warns when part of the model runs on the other machine's CPU, and goes on"
else
    fail "partial GPU placement: $output"
fi

# given a tailnet machine named by the caller
reset
# when
output="$(run_omni env CLAUDE_OMNI_GPU_HOST=desktop "$TMP/claude-omni" -m "ollama-desktop/$gpu_model" -p hi 2>&1)"
# then: the name resolves without MagicDNS
[[ "$output" == *"using desktop (100.64.0.3)"* ]] && pass "CLAUDE_OMNI_GPU_HOST picks a tailnet machine by name" ||
    fail "CLAUDE_OMNI_GPU_HOST ignored: $output"

# given no machine on the tailnet that answers
reset
: > "$TMP/remote-answering"
# when
if output="$(run_omni "$TMP/claude-omni" -m "ollama-desktop/$gpu_model" -p hi 2>&1)"; then status=0; else status=$?; fi
# then
if [[ "$status" -ne 0 && "$output" == *"no machine on the tailnet shares Ollama"* && ! -e "$TMP/claude.args" ]]; then
    pass "claude-omni stops when no tailnet machine shares its GPU"
else
    fail "no tailnet GPU: status=$status output=$output"
fi

# --- the gateway ----------------------------------------------------------------------------------

# given no key
reset
# when
if output="$(env -i HOME="$TMP/home" PATH="$STUBS:/usr/bin:/bin" CLAUDE_OMNI_CONFIG_DIR="$TMP/profile" "$TMP/claude-omni" -p hi 2>&1 </dev/null)"; then status=0; else status=$?; fi
# then
if [[ "$status" -ne 0 && "$output" == *"cred:OMNIROUTE_API_KEY"* && ! -e "$TMP/claude.args" ]]; then
    pass "claude-omni names the 1Password field when the key is missing"
else
    fail "no key: status=$status output=$output"
fi

# given OmniRoute not answering
reset
touch "$TMP/omniroute-down"
# when
if output="$(run_omni "$TMP/claude-omni" -p hi 2>&1)"; then status=0; else status=$?; fi
# then
if [[ "$status" -ne 0 && "$output" == *"OmniRoute does not answer"* && "$output" == *"Docker Desktop"* && ! -e "$TMP/claude.args" ]]; then
    pass "claude-omni points at Docker Desktop when OmniRoute does not answer"
else
    fail "OmniRoute down: status=$status output=$output"
fi

# given OmniRoute refusing the key
reset
touch "$TMP/omniroute-refuses"
# when
if output="$(run_omni "$TMP/claude-omni" -p hi 2>&1)"; then status=0; else status=$?; fi
# then
if [[ "$status" -ne 0 && "$output" == *"refused OMNIROUTE_API_KEY (HTTP 401)"* && ! -e "$TMP/claude.args" ]]; then
    pass "claude-omni says OmniRoute refused the key"
else
    fail "refused key: status=$status output=$output"
fi

# given --list --json
reset
# when
listing="$(run_omni "$TMP/claude-omni" --list --json 2>/dev/null)"
# then: every model of the lineup, with its window, where its window comes from, what OmniRoute
# says it can do, and the label built from its root -- the tool-less and image models left out
if [[ "$(jq -r ".[] | select(.id == \"ollama-desktop/$gpu_model\") | \"\(.window) \(.source) \(.gpu) \(.machine) \(.served)\"" <<<"$listing")" == "$window server ollama-desktop tailnet true" &&
    "$(jq -r '.[] | select(.id == "nvidia/z-ai/glm-5.3") | "\(.window) \(.source) \(.label)"' <<<"$listing")" == "128000 fallback z-ai/glm-5.3" &&
    "$(jq -c '[.[] | select(.id == "openrouter/some/specialty" or .id == "openrouter/some/image")] | length' <<<"$listing")" == "0" &&
    ! -e "$TMP/claude.args" ]]; then
    pass "--list --json reports each model's window, its source and whether OmniRoute serves it"
else
    fail "unexpected listing: $listing"
fi

# given a GPU whose model the catalog no longer carries
reset
cp "$TMP/catalog.json" "$TMP/catalog.saved"
jq 'del(.data[] | select(.id | startswith("ollama-desktop/")))' "$TMP/catalog.json" > "$TMP/catalog.tmp" && mv "$TMP/catalog.tmp" "$TMP/catalog.json"
# when
output="$(run_omni "$TMP/claude-omni" --list 2>&1)"
listing="$(run_omni "$TMP/claude-omni" --list --json 2>/dev/null)"
mv "$TMP/catalog.saved" "$TMP/catalog.json"
# then: it stays in the list, marked unserved and explained, so a GPU that fell out of the
# catalog is visible instead of silently absent
if [[ "$output" == *"GPU models marked - are configured"* &&
    "$(jq -r '.[] | select(.id == "ollama-desktop/'"$gpu_model"'") | "\(.served) \(.window) \(.source)"' <<<"$listing")" == "false $window server" ]]; then
    pass "a GPU model OmniRoute no longer serves is still listed, marked unserved and explained"
else
    fail "unserved GPU: $listing"
fi

# given --list --all
reset
# when
listing="$(run_omni "$TMP/claude-omni" --list --all --json 2>/dev/null)"
# then: the wider catalog, including the chat model the lineup left out for not calling tools
if [[ "$(jq -r '[.[] | select(.id == "openrouter/some/specialty")] | length' <<<"$listing")" == "1" &&
    "$(jq -r '[.[] | select(.id == "openrouter/some/image")] | length' <<<"$listing")" == "0" ]]; then
    pass "--list --all shows the chat models the lineup filters out"
else
    fail "unexpected --all listing: $listing"
fi

# --- claude-omni-task -----------------------------------------------------------------------------

render "$TASK" > "$TMP/claude-omni-task"
chmod +x "$TMP/claude-omni-task"
TASK_STUBS="$TMP/task-stubs"
mkdir -p "$TASK_STUBS"

# A run that edits, adds and deletes a file, writes outside the repository, and reports through
# the events Claude Code streams: one command that succeeds, one that fails, then the result.
cat > "$TMP/task-stream.jsonl" <<'EOF'
{"type":"system","subtype":"init","session_id":"0123abcd-0000-4000-8000-000000000000"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"go test ./..."}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok  example.com/calc"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Write","input":{"file_path":"/elsewhere/notes.txt","content":"a\nb"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":"File created"}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t3","name":"Bash","input":{"command":"git push"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t3","is_error":true,"content":"Exit code 128\nfatal: no remote"}]}}
{"type":"result","subtype":"success","is_error":false,"num_turns":4,"result":"Done, tests pass.","session_id":"0123abcd-0000-4000-8000-000000000000"}
{"type":"assistant","message":{"content":[{"type":"tool_use"
EOF
# claude-omni: --check fails for the GPUs listed in check-fail; a run records what it was handed
# and does its work in the working tree
cat > "$TASK_STUBS/claude-omni" <<EOF
#!/bin/bash
if [[ "\$1" == "--check" ]]; then
    if grep -qxF "\$3" "$TMP/check-fail" 2>/dev/null; then
        echo "[claude-omni] ERROR: no Ollama server answers on this machine" >&2
        exit 1
    fi
    echo "[claude-omni] \$3: 65536-token window (server)" >&2
    exit 0
fi
cat > "$TMP/task-brief.seen"
printf '<%s>\n' "\$@" > "$TMP/task-launcher.args"
env | grep -c '^CLAUDE_EFFORT=' > "$TMP/task-effort.count" || true
echo "changed by the run" >> a.txt
echo "added by the run" > new.txt
rm -f gone.txt
cat "$TMP/task-stream.jsonl"
EOF
chmod +x "$TASK_STUBS"/*
printf 'Add a feature.\n' > "$TMP/task-brief.md"

# A repository with work of the caller's own: an uncommitted edit and a staged new file.
task_repo() {
    rm -rf "$TMP/task-repo" "$TMP/task-config" "$TMP/check-fail" "$TMP/task-launcher.args"
    git init -q "$TMP/task-repo"
    printf 'one\n' > "$TMP/task-repo/a.txt"
    printf 'doomed\n' > "$TMP/task-repo/gone.txt"
    git -C "$TMP/task-repo" add -A
    git -C "$TMP/task-repo" -c core.hooksPath=/dev/null -c user.email=test@example.com -c user.name=test commit -qm init
    printf "the caller's edit\n" >> "$TMP/task-repo/a.txt"
    printf 'staged\n' > "$TMP/task-repo/staged.txt"
    git -C "$TMP/task-repo" add staged.txt
}

# The working tree's files and contents, which is what an undo must restore (tar would also
# compare modification times).
tree_state() {
    (cd "$TMP/task-repo" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort |
        while read -r file; do printf '%s %s\n' "$file" "$(sha256sum < "$file")"; done)
}

run_task() {
    (cd "$TMP/task-repo" && env CLAUDE_OMNI_CONFIG_DIR="$TMP/task-config" CLAUDE_EFFORT=max \
        PATH="$TASK_STUBS:/usr/bin:/bin" bash "$TMP/claude-omni-task" "$@")
}

# given a repository with the caller's own work in progress, and both GPUs free
task_repo
index_before="$(sha256sum < "$TMP/task-repo/.git/index")"
tree_before="$(tree_state)"
# when
if output="$(run_task "$TMP/task-brief.md" 2>&1)"; then status=0; else status=$?; fi
# then: every action is listed with its result, a write outside the repository flagged
if [[ "$status" -eq 0 && "$output" == *"1. Bash: go test ./... -> ok"* &&
    "$output" == *"2. Write: [outside the repository] /elsewhere/notes.txt (2 lines) -> ok"* &&
    "$output" == *"3. Bash: git push -> error: Exit code 128"* && "$output" == *"final message:"*"Done, tests pass."* ]]; then
    pass "claude-omni-task lists every action with its result"
else
    fail "unexpected action list (status $status): $output"
fi
# then: the change is the run's alone -- the caller's edit and staged file are not in it
if [[ "$(sed -n '/^change:/,/^diff:/p' <<<"$output" | grep -E '^  [AMD]' | tr '\t' ' ' | tr '\n' '|')" == "  M a.txt|  D gone.txt|  A new.txt|" ]]; then
    pass "claude-omni-task attributes only the run's own change to it"
else
    fail "unexpected change: $(sed -n '/^change:/,/^undo:/p' <<<"$output")"
fi
# then: the caller's index is untouched, and the undo command restores the tree as it was
undo="$(sed -n 's/^undo: //p' <<<"$output")"
if [[ "$(sha256sum < "$TMP/task-repo/.git/index")" == "$index_before" ]] && (cd "$TMP/task-repo" && eval "$undo") &&
    [[ "$(tree_state)" == "$tree_before" ]]; then
    pass "claude-omni-task leaves the caller's index alone, and its undo restores the tree"
else
    fail "the index changed or the undo did not restore the tree: $undo"
fi
# then: the first GPU took the run, unattended, without the caller's effort, and the audit says so
audit="$(sed -n 's/^\[claude-omni-task\] full audit: //p' <<<"$output")"
if cmp -s "$TMP/task-brief.md" "$TMP/task-brief.seen" &&
    [[ "$(head -2 "$TMP/task-launcher.args" | tr '\n' '|')" == "<-m>|<ollama-laptop/$gpu_model>|" ]] &&
    grep -qx -- '<--dangerously-skip-permissions>' "$TMP/task-launcher.args" &&
    grep -qx -- '<stream-json>' "$TMP/task-launcher.args" && [[ "$(cat "$TMP/task-effort.count")" == "0" ]] &&
    [[ -f "$audit" ]] && grep -q '^## Actions' "$audit" && grep -q 'fatal: no remote' "$audit" &&
    grep -q "^- model: \`ollama-laptop/$gpu_model\`, on the GPU behind ollama-laptop" "$audit"; then
    pass "claude-omni-task runs the brief unattended on the first GPU and saves the full audit"
else
    fail "unexpected launcher call or audit: $(tr '\n' ' ' < "$TMP/task-launcher.args") / $audit"
fi

# given the first GPU not serving
task_repo
printf 'ollama-laptop/%s\n' "$gpu_model" > "$TMP/check-fail"
# when
output="$(run_task "$TMP/task-brief.md" 2>&1)" || true
# then: the run moves to the next GPU, and the audit says why
if [[ "$(sed -n '2p' "$TMP/task-launcher.args")" == "<ollama-desktop/$gpu_model>" &&
    "$output" == *"skipped ollama-laptop: no Ollama server answers on this machine"* ]]; then
    pass "claude-omni-task moves to the next GPU when the first is not serving"
else
    fail "GPU fallback: $(tr '\n' ' ' < "$TMP/task-launcher.args" 2>/dev/null) / $output"
fi

# given the first GPU busy with another run
task_repo
mkdir -p "$TMP/task-config/locks"
flock "$TMP/task-config/locks/ollama-laptop.lock" sleep 30 &
holder=$!
for _ in $(seq 1 50); do
    flock -n "$TMP/task-config/locks/ollama-laptop.lock" true 2>/dev/null || break
    /usr/bin/sleep 0.1
done
# when
output="$(run_task "$TMP/task-brief.md" 2>&1)" || true
kill "$holder" 2>/dev/null || true
wait "$holder" 2>/dev/null || true
# then
if [[ "$(sed -n '2p' "$TMP/task-launcher.args")" == "<ollama-desktop/$gpu_model>" && "$output" == *"ollama-laptop is running another task"* ]]; then
    pass "claude-omni-task leaves a GPU another run holds and takes the next one"
else
    fail "GPU lock: $(tr '\n' ' ' < "$TMP/task-launcher.args" 2>/dev/null) / $output"
fi

# given a cloud model named by the caller
task_repo
# when
output="$(run_task -m openrouter/z-ai/glm-5.3 "$TMP/task-brief.md" 2>&1)" || true
# then: it runs there, and the audit says the provider received what the model read
if [[ "$(sed -n '2p' "$TMP/task-launcher.args")" == "<openrouter/z-ai/glm-5.3>" &&
    "$output" == *"model: openrouter/z-ai/glm-5.3, on openrouter, a cloud provider that receives every file the model reads"* ]]; then
    pass "claude-omni-task runs a cloud model only when named, and says where the files went"
else
    fail "cloud model: $output"
fi

# given a launcher that fails before the model runs
task_repo
mkdir -p "$TMP/task-stubs-fail"
cat > "$TMP/task-stubs-fail/claude-omni" <<'EOF'
#!/bin/bash
[[ "$1" == "--check" ]] && exit 0
echo "Error: no server" >&2
exit 1
EOF
chmod +x "$TMP/task-stubs-fail/claude-omni"
# when
if output="$(cd "$TMP/task-repo" && env CLAUDE_OMNI_CONFIG_DIR="$TMP/task-config" PATH="$TMP/task-stubs-fail:/usr/bin:/bin" bash "$TMP/claude-omni-task" "$TMP/task-brief.md" 2>&1)"; then status=0; else status=$?; fi
# then
if [[ "$status" -ne 0 && "$output" == *"did not run (exit 1): Error: no server"* && "$output" == *"change: none"* ]]; then
    pass "claude-omni-task reports a run that never started, and fails"
else
    fail "claude-omni-task with a failing launcher: status=$status output=$output"
fi

# --- capacity hint in the zsh wrapper ----------------------------------------------------------

chezmoi execute-template --config "$TMP/chezmoi.yaml" --override-data '{"chezmoi":{"os":"linux"}}' \
    < "$REPO_ROOT/dot_zshrc.tmpl" > "$TMP/zshrc.zsh"
awk '/^_claude_ensure_account\(\) \{/ { capture=1 } capture { print } capture && /^\}/ { exit }' \
    "$TMP/zshrc.zsh" > "$TMP/guard.zsh"

HINT_BIN="$TMP/hint-bin"
mkdir -p "$HINT_BIN"
cat > "$HINT_BIN/ccswitch" <<'EOF'
#!/bin/sh
[ "$1" = "capacity" ] && exit "${CAPACITY_EXIT:-0}"
exit 0
EOF
printf '#!/bin/sh\nexit 0\n' > "$HINT_BIN/claude-omni"
chmod +x "$HINT_BIN"/*

# hint <exit status of `ccswitch capacity`> <PATH>: the guard's stderr
# shellcheck disable=SC2069 # stderr is what is captured; stdout is dropped
hint() {
    CAPACITY_EXIT="$1" PATH="$2" zsh -f -c 'source "$1"; _claude_ensure_account' guard "$TMP/guard.zsh" 2>&1 >/dev/null
}

[[ "$(hint 3 "$HINT_BIN:/usr/bin:/bin")" == *"claude-omni"* ]] &&
    pass "the wrapper points at claude-omni when no account has capacity (exit 3)" ||
    fail "no hint for exit 3"
[[ -z "$(hint 0 "$HINT_BIN:/usr/bin:/bin")" && -z "$(hint 1 "$HINT_BIN:/usr/bin:/bin")" ]] &&
    pass "the wrapper stays silent for capacity, failures and older ccswitch (exit 0 and 1)" ||
    fail "a hint was printed without exit 3"
mkdir -p "$TMP/hint-bin-noomni"
cp "$HINT_BIN/ccswitch" "$TMP/hint-bin-noomni/"
[[ -z "$(hint 3 "$TMP/hint-bin-noomni:/usr/bin:/bin")" ]] &&
    pass "the wrapper says nothing where claude-omni is not installed" ||
    fail "a hint pointed at a claude-omni that is not installed"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-claude-omni] all claude-omni tests passed" >&2
fi

exit $EXIT_CODE
