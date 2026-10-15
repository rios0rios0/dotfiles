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

# omni_gpu_windows [override JSON]: the window claude-omni declares for GPU models, once from
# gpuWindow and once from every GPU entry of its model list, space-separated
omni_gpu_windows() {
    local override="${1:-}"
    PATH="$TMP/bin-gpu" chezmoi execute-template --config "$TMP/chezmoi.yaml" \
        ${override:+--override-data "$override"} \
        '{{ $omni := includeTemplate "lib-omniroute.tmpl" . | fromJson }}{{ $omni.gpuWindow }} {{ range $omni.models }}{{ if hasKey . "gpu" }}{{ .window }} {{ end }}{{ end }}'
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
