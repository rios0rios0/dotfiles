#!/bin/bash
set -euo pipefail

# Tests the local model server: the settings every consumer reads, the Ollama unit and claude-omni,
# which must agree on one context window, and the installer's render gate. claude-omni itself, its
# GPU guards and claude-omni-task are covered by test-claude-omni.sh.

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

# omni_gpu_windows [override JSON]: the window claude-omni declares for GPU models
omni_gpu_windows() {
    local override="${1:-}"
    PATH="$TMP/bin-gpu" chezmoi execute-template --config "$TMP/chezmoi.yaml" \
        ${override:+--override-data "$override"} \
        '{{ $omni := includeTemplate "lib-omniroute.tmpl" . | fromJson }}{{ $omni.gpuWindow }}'
}

UNIT="$REPO_ROOT/dot_config/systemd/user/ollama.service.tmpl"
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

# The machines share this checkout but not their local/remote topology. The persistent deviceName
# selects the right provider map; otherwise the desktop would try to reach its own GPU via tailnet.
# The gpus map has to name exactly OmniRoute's provider prefixes: claude-omni resolves its lineup
# from the gateway's /v1/models, so a key that drifts from the dashboard drops that GPU silently.
for device in alien-a51 mxhero-z790; do
    config="$(PATH="$TMP/bin-gpu" chezmoi execute-template --config "$TMP/chezmoi.yaml" \
        --override-data "{\"deviceName\":\"$device\"}" \
        '{{ includeTemplate "lib-omniroute.tmpl" . }}')"
    if [[ "$device" == alien-a51 ]]; then local_gpu=ollama-laptop; remote_gpu=ollama-desktop; local_label='laptop GPU'; remote_label='desktop GPU'
    else local_gpu=ollama-desktop; remote_gpu=ollama-laptop; local_label='desktop GPU'; remote_label='laptop GPU'; fi
    if [[ "$(jq -r --arg gpu "$local_gpu" '.gpus[$gpu].machine + " " + .gpus[$gpu].label' <<<"$config")" == "local $local_label" &&
        "$(jq -r --arg gpu "$remote_gpu" '.gpus[$gpu].machine + " " + .gpus[$gpu].label' <<<"$config")" == "tailnet $remote_label" &&
        "$(jq -r '.gpus | keys | join(" ")' <<<"$config")" == "ollama-desktop ollama-laptop" &&
        "$(jq -r '.taskGpus | join(" ")' <<<"$config")" == "$local_gpu $remote_gpu" ]]; then
        pass "$device maps its local GPU directly and the other device through the tailnet"
    else
        fail "$device GPU routing is wrong: $(jq -c '{gpus, taskGpus}' <<<"$config")"
    fi
done

# Ollama listens on IPv4 loopback: Docker Desktop dials host.docker.internal over Windows' IPv4
# loopback, which WSL's relay answers only for an IPv4 listener (0.0.0.0 becomes a dual-stack [::]
# that Windows sees on ::1 alone, and the container's fetch fails while the server is up), and
# Tailscale Serve forwards the tailnet's port to this same localhost from Windows. The API has no
# authentication; the network cannot reach it directly.
if render gpu "$UNIT" | grep -qx 'Environment=OLLAMA_HOST=127.0.0.1:11434'; then
    pass "Ollama binds IPv4 loopback for host.docker.internal and Tailscale Serve"
else
    fail "Ollama must bind 127.0.0.1:11434 so the container and Tailscale Serve reach it"
fi

for override in "" '{"localLLM":{"devices":{"testdevice":{"contextTokens":32768}}}}'; do
    # given the same settings
    # when: the window the server allocates, and the one claude-omni declares for every GPU model
    server="$(render gpu "$UNIT" "$override" | sed -n 's/^Environment=OLLAMA_CONTEXT_LENGTH=//p')"
    client="$(omni_gpu_windows "$override")"
    # then
    if [[ -n "$server" && "$(tr ' ' '\n' <<<"$client" | grep . | sort -u)" == "$server" ]]; then
        pass "the unit and claude-omni agree on a ${server}-token window"
    else
        fail "the unit serves '$server' tokens but claude-omni declares '$client'"
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

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-local-llm] all local model tests passed" >&2
fi

exit $EXIT_CODE
