#!/bin/bash
set -euo pipefail

# Tests tailscale-up against a stubbed tailscale, systemctl and sudo: the pass every interactive
# zsh runs, which must never wait or ask for a password, and the direct call, which logs in, sets
# the two preferences and shares the local model's server. Also checks that the installer runs
# again when what the machine shares changes, and that zsh runs the quiet pass.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CI_DIR="$REPO_ROOT/.github/ci"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-tailscale] testing the tailnet setup..." >&2

pass() { echo "[test-tailscale] PASS: $1" >&2; }
fail() { echo "[test-tailscale] FAIL: $1" >&2; EXIT_CODE=1; }

chmod +x "$CI_DIR/fixtures/mock-op.sh"
cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
onePassword:
  command: "$CI_DIR/fixtures/mock-op.sh"
data:
  deviceName: "testdevice"
EOF

# Whether this machine shares its Ollama depends on nvidia-smi being on PATH, so each render runs
# with a PATH holding only chezmoi, plus a fake driver for a machine with a GPU.
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

HELPER="$REPO_ROOT/dot_local/bin/executable_tailscale-up.tmpl"
INSTALLER="$REPO_ROOT/.chezmoiscripts/run_onchange_after_linux-010-setup-tailscale.sh.tmpl"
render gpu "$HELPER" > "$TMP/tailscale-up-gpu"
render nogpu "$HELPER" > "$TMP/tailscale-up-nogpu"
chmod +x "$TMP/tailscale-up-gpu" "$TMP/tailscale-up-nogpu"

# Stubs. tailscale reports the state in ts-state (and no daemon while ts-down exists), records
# every call, and logs in on `up`; `set` and `serve --bg` are refused until sudo, or a login
# through sudo, made this user the operator. sudo records itself and runs the command as that
# operator. systemctl answers from ts-enabled and ts-failed, and starts the daemon.
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/tailscale" <<EOF
#!/bin/bash
echo "\${TS_VIA_SUDO:+sudo }tailscale \$*" | tee -a "$TMP/all-calls" >> "$TMP/calls"
operator() { [[ -n "\${TS_VIA_SUDO:-}" || -e "$TMP/ts-operator" ]]; }
case "\$1" in
    status) [[ -e "$TMP/ts-down" ]] && exit 1; printf '{"BackendState":"%s"}\n' "\$(cat "$TMP/ts-state")" ;;
    up) [[ -n "\${TS_VIA_SUDO:-}" && "\$*" == *--operator=* ]] && touch "$TMP/ts-operator"
        operator || exit 1
        echo Running > "$TMP/ts-state" ;;
    set) operator ;;
    serve) [[ "\$2" == "status" ]] && { cat "$TMP/ts-serve.json" 2>/dev/null || echo '{}'; exit 0; }
        operator ;;
    ip) echo 100.64.0.5 ;;
esac
EOF
cat > "$STUBS/sudo" <<EOF
#!/bin/bash
TS_VIA_SUDO=1 exec "\$@"
EOF
cat > "$STUBS/systemctl" <<EOF
#!/bin/bash
echo "\${TS_VIA_SUDO:+sudo }systemctl \$*" | tee -a "$TMP/all-calls" >> "$TMP/calls"
case "\$1" in
    is-enabled) [[ -e "$TMP/ts-enabled" ]] ;;
    is-failed) [[ -e "$TMP/ts-failed" ]] ;;
    enable) rm -f "$TMP/ts-down" ;;
esac
EOF
printf '#!/bin/sh\nexit 0\n' > "$STUBS/sleep"
chmod +x "$STUBS"/*

# reset <state> [down] [enabled] [failed] [operator] [shared]
reset() {
    rm -f "$TMP/calls" "$TMP/ts-down" "$TMP/ts-enabled" "$TMP/ts-failed" "$TMP/ts-operator" "$TMP/ts-serve.json"
    touch "$TMP/calls"
    echo "$1" > "$TMP/ts-state"
    shift
    local flag
    for flag in "$@"; do
        case "$flag" in
            down) touch "$TMP/ts-down" ;;
            enabled) touch "$TMP/ts-enabled" ;;
            failed) touch "$TMP/ts-failed" ;;
            operator) touch "$TMP/ts-operator" ;;
            shared) echo '{"TCP":{"11434":{"TCPForward":"127.0.0.1:11434"}}}' > "$TMP/ts-serve.json" ;;
        esac
    done
}

# helper <gpu|nogpu> [args]: stderr and stdout together
helper() {
    local gpu="$1"
    shift
    PATH="$STUBS:/usr/bin:/bin" USER=tester "$TMP/tailscale-up-$gpu" "$@" 2>&1
}

# --- the pass every interactive zsh runs ---------------------------------------------------------

# given a node on the tailnet
reset Running operator
# when
output="$(helper gpu --no-login)" && status=0 || status=$?
# then
[[ "$status" -eq 0 && -z "$output" ]] && ! grep -q ' up\| set\|serve --bg' "$TMP/calls" &&
    pass "a new shell says nothing while the node is on the tailnet" ||
    fail "a running node: status=$status output=$output calls=$(tr '\n' ';' < "$TMP/calls")"

# given a node switched off with `tailscale down`
reset Stopped operator
# when
output="$(helper gpu --no-login)" && status=0 || status=$?
# then: a bare `tailscale up`, which only switches a logged-in node back on
[[ "$status" -eq 0 && -z "$output" ]] && grep -qx 'tailscale up' "$TMP/calls" &&
    pass "a new shell brings a stopped node back up with a bare tailscale up" ||
    fail "a stopped node: status=$status output=$output calls=$(tr '\n' ';' < "$TMP/calls")"

# given a machine that is not logged in
reset NeedsLogin
# when
output="$(helper gpu --no-login)" && status=0 || status=$?
# then: a hint, and nothing that would wait for a browser
[[ "$status" -eq 0 && "$output" == *"run 'tailscale-up' to log in"* ]] && ! grep -q ' up' "$TMP/calls" &&
    pass "a new shell points at tailscale-up while the machine is logged out, without waiting" ||
    fail "a logged-out node: status=$status output=$output calls=$(tr '\n' ';' < "$TMP/calls")"

# given a machine waiting for the admin's approval
reset NeedsMachineAuth
# when
output="$(helper gpu --no-login)" && status=0 || status=$?
# then
[[ "$status" -eq 0 && "$output" == *"admin/machines"* ]] &&
    pass "a new shell says where to approve a machine" ||
    fail "a node awaiting approval: status=$status output=$output"

# given a daemon still starting with the machine
reset NoState down enabled
# when
output="$(helper gpu --no-login)" && status=0 || status=$?
# then: the first terminal of a WSL boot can get there before tailscaled answers
[[ "$status" -eq 0 && -z "$output" ]] &&
    pass "a new shell says nothing while an enabled tailscaled is still starting" ||
    fail "a starting daemon: status=$status output=$output"

# given a daemon that failed
reset NoState down enabled failed
# when
output="$(helper gpu --no-login)" && status=0 || status=$?
# then
[[ "$status" -eq 0 && "$output" == *"tailscaled is not running"* ]] &&
    pass "a new shell reports a tailscaled that failed" ||
    fail "a failed daemon: status=$status output=$output"

# given no tailscale at all
reset Running
# when
output="$(PATH="$TMP/bin-nogpu:/usr/bin:/bin" "$TMP/tailscale-up-gpu" --no-login 2>&1)" && status=0 || status=$?
# then
[[ "$status" -eq 0 && "$output" == *"not installed"* ]] &&
    pass "a new shell reports a missing tailscale and goes on" ||
    fail "no tailscale: status=$status output=$output"

# then, across every case above: the shell's pass never asked for a password
if grep -q '^sudo' "$TMP/all-calls"; then
    fail "the shell's pass ran sudo: $(grep '^sudo' "$TMP/all-calls" | tr '\n' ';')"
else
    pass "the shell's pass never runs sudo"
fi

# --- asked for directly ----------------------------------------------------------------------------

# given a fresh install on a machine with a GPU
reset NeedsLogin
# when
output="$(helper gpu)" && status=0 || status=$?
# then: logged in through sudo with both preferences, which makes this user the operator, and the
# local model's server shared on the tailnet
expected="sudo tailscale up --operator=tester --accept-dns=false"
if [[ "$status" -eq 0 && "$output" == *"this waits until you have"* && "$output" == *"on the tailnet as 100.64.0.5"* ]] &&
    grep -qx -- "$expected" "$TMP/calls" &&
    grep -qx -- 'tailscale set --operator=tester --accept-dns=false' "$TMP/calls" &&
    grep -qx -- 'tailscale serve --bg --tcp=11434 tcp://127.0.0.1:11434' "$TMP/calls"; then
    pass "tailscale-up logs in with both preferences and shares the model's server"
else
    fail "a fresh login: status=$status output=$output calls=$(tr '\n' ';' < "$TMP/calls")"
fi

# given a node already on the tailnet and already sharing
reset Running operator shared
# when
output="$(helper gpu)" && status=0 || status=$?
# then: nothing to log in and nothing to share again
[[ "$status" -eq 0 ]] && ! grep -q ' up\|serve --bg' "$TMP/calls" &&
    pass "tailscale-up leaves a node that is up and sharing as it is" ||
    fail "an up-to-date node: status=$status calls=$(tr '\n' ';' < "$TMP/calls")"

# given a machine without a GPU
reset NeedsLogin
# when
output="$(helper nogpu)" && status=0 || status=$?
# then
[[ "$status" -eq 0 ]] && ! grep -q 'serve' "$TMP/calls" &&
    pass "a machine without the local model shares nothing" ||
    fail "a machine without a GPU: status=$status calls=$(tr '\n' ';' < "$TMP/calls")"

# given tailscaled switched off
reset NeedsLogin down
# when
output="$(helper gpu)" && status=0 || status=$?
# then
[[ "$status" -eq 0 ]] && grep -qx 'sudo systemctl enable --now tailscaled' "$TMP/calls" &&
    pass "tailscale-up starts a tailscaled that is off" ||
    fail "a daemon that is off: status=$status output=$output calls=$(tr '\n' ';' < "$TMP/calls")"

# --- installer and shell -------------------------------------------------------------------------

# given a machine that starts or stops sharing a GPU
gpu_hash="$(render gpu "$INSTALLER" | grep -o 'tailscale-up [0-9a-f]\{64\}')"
nogpu_hash="$(render nogpu "$INSTALLER" | grep -o 'tailscale-up [0-9a-f]\{64\}')"
# then: the installer's own content changes, so it runs again
[[ -n "$gpu_hash" && "$gpu_hash" != "$nogpu_hash" ]] &&
    pass "the installer runs again when what this machine shares changes" ||
    fail "the installer does not track tailscale-up: '$gpu_hash' / '$nogpu_hash'"

# then: zsh runs the quiet pass in interactive shells on Linux, and not at all on Android
linux_zshrc="$(render gpu "$REPO_ROOT/dot_zshrc.tmpl" '{"chezmoi":{"os":"linux"}}')"
android_zshrc="$(render gpu "$REPO_ROOT/dot_zshrc.tmpl" '{"chezmoi":{"os":"android"}}')"
if grep -A2 -F 'if [[ -o interactive ]] && command -v tailscale-up' <<<"$linux_zshrc" | grep -q 'tailscale-up --no-login' &&
    ! grep -q 'tailscale-up' <<<"$android_zshrc"; then
    pass "interactive zsh on Linux joins the tailnet with the quiet pass"
else
    fail "zshrc does not run tailscale-up --no-login as expected"
fi

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-tailscale] all tailnet tests passed" >&2
fi

exit $EXIT_CODE
