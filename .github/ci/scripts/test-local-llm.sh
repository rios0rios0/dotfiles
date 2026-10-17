#!/bin/bash
set -euo pipefail

# Tests the local model server: the settings every consumer reads, the Ollama unit and claude-omni,
# which must agree on one context window, and the installer's render gate plus a stubbed end-to-end
# run of it. claude-omni itself, its GPU guards and claude-omni-task are covered by test-claude-omni.sh.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CI_DIR="$REPO_ROOT/.github/ci"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# The end-to-end installer run below uses stubs that record into $TMP at run time, under an
# environment built from scratch, so the variable must survive into them.
export TMP

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

# --- installer, end to end ----------------------------------------------------------------------
#
# The installer is run for real against stubs: the release directory passes its digest gate, the
# server answers, and journalctl serves the start-up log the GPU check reads. What matters here is
# that the check loads no model -- no /api/generate, no /api/ps -- that it reads this start's
# lines through the invocation id, that a log whose only backend is the CPU fails the run, that a
# log with no discovery line at all fails it too, and that free VRAM smaller than the model warns.

mkdir -p "$TMP/systemd" "$TMP/runbin"
# Two poll loops bound the run (server readiness and GPU discovery); shorten both for the test.
render gpu "$INSTALLER" | sed -e "s|/run/systemd/system|$TMP/systemd|g" -e 's|seq 1 30|seq 1 3|g' > "$TMP/installer.sh"
bash -n "$TMP/installer.sh" || fail "the rendered installer is not a valid script"
checksum="$(sed -n 's/^checksum="\(.*\)"/\1/p' "$TMP/installer.sh")"
llm_model="$(PATH="$TMP/bin-gpu" chezmoi execute-template --config "$TMP/chezmoi.yaml" \
    '{{ (includeTemplate "lib-local-llm.tmpl" . | fromJson).model }}')"

RUNHOME="$TMP/run-home"
release_dir="$RUNHOME/.local/share/ollama/0.40.3"
mkdir -p "$release_dir/bin" "$RUNHOME/.local/bin"
# The managed `ollama` behind the symlink: `show <model>` says the model is pulled.
cat > "$release_dir/bin/ollama" <<EOF
#!/bin/bash
echo "\$*" >> "$TMP/ollama.args"
[[ "\$1" == show ]] && exit 0
exit 1
EOF
chmod +x "$release_dir/bin/ollama"
echo "$checksum" > "$release_dir/.archive-sha256"
(cd "$release_dir" && find . -type f ! -name .files.sha256 -print0 | sort -z | xargs -0 sha256sum > .files.sha256)

cat > "$TMP/runbin/nvidia-smi" <<'STUB'
#!/bin/bash
echo "NVIDIA Test GPU, 24576 MiB"
STUB
cat > "$TMP/runbin/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$TMP/systemctl.args"
case "$*" in
    *InvocationID*) echo "fake-invocation" ;;
    is-active*) exit 1 ;;
esac
STUB
cat > "$TMP/runbin/journalctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$TMP/journalctl.args"
cat "$TMP/journal.log" 2>/dev/null || true
STUB
cat > "$TMP/runbin/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$TMP/curl.args"
url=""
for arg in "$@"; do
    case "$arg" in
        http*) url="$arg" ;;
    esac
done
case "$url" in
    */api/version) echo '{"version":"0.0.0-test"}' ;;
    */api/tags) cat "$TMP/tags.json" ;;
    *) exit 22 ;;
esac
STUB
chmod +x "$TMP/runbin/"*

run_installer() {
    local rc=0
    : > "$TMP/curl.args"
    : > "$TMP/ollama.args"
    : > "$TMP/journalctl.args"
    (cd "$TMP" && HOME="$RUNHOME" PATH="$TMP/runbin:/usr/bin:/bin" bash "$TMP/installer.sh") > "$TMP/installer.out" 2>&1 || rc=$?
    echo "$rc" > "$TMP/installer.rc"
}

# given a log whose backend is the GPU, and a pulled model far smaller than the free VRAM
# when
printf '%s\n' 'time=2026-01-01T00:00:02.000+00:00 level=INFO source=types.go:32 msg="inference compute" id=0 filter_id=0 library=CUDA compute=12.0 name=CUDA0 description="NVIDIA Test GPU" libdirs=ollama,cuda_v13 driver=13.4 pci_id=0000:01:00.0 type=discrete total="23.9 GiB" available="22.6 GiB"' > "$TMP/journal.log"
jq -n --arg model "$llm_model" '{models: [{name: $model, size: 17741872154}]}' > "$TMP/tags.json"
run_installer
# then
if [[ "$(cat "$TMP/installer.rc")" -eq 0 ]] &&
    grep -q 'NVIDIA Test GPU is available to the server (22.6 GiB of VRAM free)' "$TMP/installer.out" &&
    grep -q 'the model loads on the first request' "$TMP/installer.out" &&
    ! grep -q 'api/generate' "$TMP/curl.args" &&
    ! grep -q 'api/ps' "$TMP/curl.args" &&
    ! grep -q 'WARN' "$TMP/installer.out"; then
    pass "a healthy log passes without loading anything"
else
    fail "the installer on a GPU log: $(cat "$TMP/installer.rc") | $(grep -c . "$TMP/curl.args") curl calls | $(tail -3 "$TMP/installer.out" | tr '\n' ' ')"
fi

# then: the check read this start's lines, not the journal's whole history
if grep -q '_SYSTEMD_INVOCATION_ID=fake-invocation' "$TMP/journalctl.args"; then
    pass "the GPU check filters the journal by this start's invocation id"
else
    fail "the GPU check read the journal without an invocation filter: $(head -1 "$TMP/journalctl.args")"
fi

# given a GPU that is too full to hold the model
# when
printf '%s\n' 'time=2026-01-01T00:00:02.000+00:00 level=INFO source=types.go:32 msg="inference compute" id=0 filter_id=0 library=CUDA compute=12.0 name=CUDA0 description="NVIDIA Test GPU" libdirs=ollama,cuda_v13 driver=13.4 pci_id=0000:01:00.0 type=discrete total="23.9 GiB" available="10.0 GiB"' > "$TMP/journal.log"
run_installer
# then
if [[ "$(cat "$TMP/installer.rc")" -eq 0 ]] &&
    grep -q 'only 10.0 GiB of VRAM is free, less than' "$TMP/installer.out"; then
    pass "free VRAM smaller than the model warns without loading it"
else
    fail "the installer on a busy GPU: $(cat "$TMP/installer.rc") | $(tail -3 "$TMP/installer.out" | tr '\n' ' ')"
fi

# given a start-up log whose only backend is the CPU -- the damaged-CUDA failure
# when
printf '%s\n' 'time=2026-01-01T00:00:03.000+00:00 level=INFO source=types.go:50 msg="inference compute" id=cpu library=cpu compute="" name=cpu description=cpu libdirs=ollama driver="" pci_id="" type="" total="31.1 GiB" available="23.7 GiB"' > "$TMP/journal.log"
run_installer
# then: it fails the run, and does not pull a model first
if [[ "$(cat "$TMP/installer.rc")" -ne 0 ]] &&
    grep -q 'found no usable GPU' "$TMP/installer.out" &&
    ! grep -q 'pull' "$TMP/installer.out" &&
    ! grep -q . "$TMP/ollama.args"; then
    pass "a CPU-only log fails the run before the pull"
else
    fail "the installer on a CPU-only log: $(cat "$TMP/installer.rc") | $(tail -3 "$TMP/installer.out" | tr '\n' ' ')"
fi

# given a server that logs nothing about GPUs
# when
: > "$TMP/journal.log"
run_installer
# then
if [[ "$(cat "$TMP/installer.rc")" -ne 0 ]] &&
    grep -q 'logged no GPU discovery' "$TMP/installer.out"; then
    pass "a start-up log with no discovery line fails the run"
else
    fail "the installer without a discovery line: $(cat "$TMP/installer.rc") | $(tail -3 "$TMP/installer.out" | tr '\n' ' ')"
fi

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-local-llm] all local model tests passed" >&2
fi

exit $EXIT_CODE
