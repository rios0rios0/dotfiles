#!/bin/bash
set -euo pipefail

# Tests tailscale-up in both of its renders. On bare metal, against a stubbed tailscale, systemctl
# and sudo: the pass every interactive zsh runs, which must never wait or ask for a password, and
# the direct call, which logs in, sets the two preferences and shares what .chezmoidata says this
# machine shares -- the local model's server, the ocode web UI and, on the one device that runs it,
# the Atuin sync server. On WSL, against a stub of
# Windows' client: nothing waits, nothing runs as root, and both are shared through Windows to
# `localhost`, moving a share an older revision left on a literal address. Also checks that the web
# UI's port is the one the fork's service derives from the channel the build stamps, the wrapper
# that gives WSL Windows' CLI, that the installer runs again when what the machine shares changes
# and installs nothing on WSL, that WSL removes the Linux client an older revision installed, and
# that only bare metal's zsh runs the quiet pass.

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

# render <gpu|nogpu> <metal|wsl|android> <source file> [noshare]. The OS and the kernel are set for
# every render, so the host running the suite -- WSL on a developer's machine, bare metal on CI --
# decides nothing. `noshare` switches the ocode web UI share off, as a device can in
# .chezmoidata/opencode.yaml; chezmoi merges --override-data into that file's data key by key.
render() {
    local os="linux" osrelease="6.11.0-generic" share=true
    case "$2" in
        wsl) osrelease="6.18.33.2-microsoft-standard-WSL2" ;;
        android) os="android" ;;
    esac
    [[ "${4:-}" != noshare ]] || share=false
    PATH="$TMP/bin-$1" chezmoi execute-template --config "$TMP/chezmoi.yaml" \
        --override-data "{\"opencode\":{\"shareOnTailnet\":$share},\"chezmoi\":{\"os\":\"$os\",\"kernel\":{\"osrelease\":\"$osrelease\",\"ostype\":\"Linux\",\"version\":\"#1 SMP\"}}}" \
        < "$3"
}

# The ocode web UI's port, as .chezmoidata/opencode.yaml declares it for this device.
PORT="$(chezmoi execute-template --config "$TMP/chezmoi.yaml" '{{ (includeTemplate "lib-opencode.tmpl" . | fromJson).webPort }}')"
# The Atuin sync server's port, as .chezmoidata/atuin.yaml declares it.
ATUIN_PORT="$(chezmoi execute-template --config "$TMP/chezmoi.yaml" '{{ (includeTemplate "lib-atuin.tmpl" . | fromJson).port }}')"

# render_atuin_server <metal|wsl>: tailscale-up on the device .chezmoidata/atuin.yaml names as the
# Atuin server, with no GPU and the web UI share off, so the Atuin share is all it shares.
render_atuin_server() {
    local osrelease="6.11.0-generic"
    [[ "$1" != wsl ]] || osrelease="6.18.33.2-microsoft-standard-WSL2"
    PATH="$TMP/bin-nogpu" chezmoi execute-template --config "$TMP/chezmoi.yaml" \
        --override-data "{\"atuin\":{\"serverDevice\":\"testdevice\"},\"opencode\":{\"shareOnTailnet\":false},\"chezmoi\":{\"os\":\"linux\",\"kernel\":{\"osrelease\":\"$osrelease\",\"ostype\":\"Linux\",\"version\":\"#1 SMP\"}}}" \
        < "$HELPER"
}

HELPER="$REPO_ROOT/dot_local/bin/executable_tailscale-up.tmpl"
INSTALLER="$REPO_ROOT/.chezmoiscripts/run_onchange_after_linux-010-setup-tailscale.sh.tmpl"
REMOVER="$REPO_ROOT/.chezmoiscripts/run_onchange_after_linux-006-remove-dependencies.sh.tmpl"
WRAPPER="$REPO_ROOT/dot_local/bin/executable_tailscale"
for gpu in gpu nogpu; do
    for kind in metal wsl; do
        render "$gpu" "$kind" "$HELPER" > "$TMP/tailscale-up-$kind-$gpu"
        render "$gpu" "$kind" "$HELPER" noshare > "$TMP/tailscale-up-$kind-$gpu-noshare"
        chmod +x "$TMP/tailscale-up-$kind-$gpu" "$TMP/tailscale-up-$kind-$gpu-noshare"
    done
done
for kind in metal wsl; do
    render_atuin_server "$kind" > "$TMP/tailscale-up-$kind-atuin"
    chmod +x "$TMP/tailscale-up-$kind-atuin"
done

# A tool directory without any tailscale, for the runs that must not find one: a developer's
# machine can have a real one in /usr/bin.
mkdir -p "$TMP/tools" "$TMP/home"
for tool in cat head jq tee timeout; do
    ln -s "$(command -v "$tool")" "$TMP/tools/$tool"
done

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

# Windows' client as WSL reaches it, through the wrapper: no operator and no sudo. It answers from
# the same ts-state, has no service while win-down exists and no CLI while win-missing exists, and
# a bare `up` switches it back on. systemctl reports a Linux tailscaled while linux-tailscaled
# exists. Every call, sudo included, goes to wsl-all-calls as well.
WSL_STUBS="$TMP/wsl-stubs"
mkdir -p "$WSL_STUBS"
cat > "$WSL_STUBS/tailscale" <<EOF
#!/bin/bash
[[ -e "$TMP/win-missing" ]] && exit 127
echo "tailscale \$*" | tee -a "$TMP/wsl-all-calls" >> "$TMP/calls"
case "\$1" in
    version) echo 1.104.1 ;;
    status) [[ -e "$TMP/win-down" ]] && exit 1; printf '{"BackendState":"%s"}\n' "\$(cat "$TMP/ts-state")" ;;
    up) [[ \$# -eq 1 ]] || exit 1; echo Running > "$TMP/ts-state" ;;
    serve) [[ "\$2" == "status" ]] && { cat "$TMP/ts-serve.json" 2>/dev/null || echo '{}'; exit 0; }
        true ;;
    ip) echo 100.64.0.7 ;;
esac
EOF
cat > "$WSL_STUBS/systemctl" <<EOF
#!/bin/bash
echo "systemctl \$*" | tee -a "$TMP/wsl-all-calls" >> "$TMP/calls"
[[ "\$1" == "is-active" && -e "$TMP/linux-tailscaled" ]]
EOF
cat > "$WSL_STUBS/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" | tee -a "$TMP/wsl-all-calls" >> "$TMP/calls"
exit 1
EOF
chmod +x "$WSL_STUBS"/*

# reset <state> [down] [enabled] [failed] [operator] [shared=<forward target>]
#       [ocode=<forward target>] [atuin=<forward target>] [win-down] [win-missing] [linux-tailscaled]
reset() {
    rm -f "$TMP/calls" "$TMP/ts-down" "$TMP/ts-enabled" "$TMP/ts-failed" "$TMP/ts-operator" "$TMP/ts-serve.json" \
        "$TMP/win-down" "$TMP/win-missing" "$TMP/linux-tailscaled"
    touch "$TMP/calls"
    echo "$1" > "$TMP/ts-state"
    shift
    local flag serve='{}'
    for flag in "$@"; do
        case "$flag" in
            down) touch "$TMP/ts-down" ;;
            enabled) touch "$TMP/ts-enabled" ;;
            failed) touch "$TMP/ts-failed" ;;
            operator) touch "$TMP/ts-operator" ;;
            shared=*) serve="$(jq -c --arg t "${flag#shared=}" '.TCP["11434"].TCPForward = $t' <<<"$serve")" ;;
            ocode=*) serve="$(jq -c --arg t "${flag#ocode=}" --arg p "$PORT" '.TCP[$p].TCPForward = $t' <<<"$serve")" ;;
            atuin=*) serve="$(jq -c --arg t "${flag#atuin=}" --arg p "$ATUIN_PORT" '.TCP[$p].TCPForward = $t' <<<"$serve")" ;;
            win-down) touch "$TMP/win-down" ;;
            win-missing) touch "$TMP/win-missing" ;;
            linux-tailscaled) touch "$TMP/linux-tailscaled" ;;
        esac
    done
    [[ "$serve" == '{}' ]] || echo "$serve" > "$TMP/ts-serve.json"
}

# helper <gpu|nogpu>[-noshare] [args]: the bare-metal render; stderr and stdout together
helper() {
    local gpu="$1"
    shift
    PATH="$STUBS:/usr/bin:/bin" USER=tester "$TMP/tailscale-up-metal-$gpu" "$@" 2>&1
}

# wsl <gpu|nogpu>[-noshare] [args]: the WSL render, with Windows' client behind the tailscale on PATH
wsl() {
    local gpu="$1"
    shift
    HOME="$TMP/home" PATH="$WSL_STUBS:$TMP/tools" "$TMP/tailscale-up-wsl-$gpu" "$@" 2>&1
}

calls() {
    tr '\n' ';' < "$TMP/calls"
}

# --- bare metal: the pass every interactive zsh runs ------------------------------------------------

# given a node on the tailnet
reset Running operator
# when
output="$(helper gpu --no-login)" && status=0 || status=$?
# then
[[ "$status" -eq 0 && -z "$output" ]] && ! grep -q ' up\| set\|serve --bg' "$TMP/calls" &&
    pass "a new shell says nothing while the node is on the tailnet" ||
    fail "a running node: status=$status output=$output calls=$(calls)"

# given a node switched off with `tailscale down`
reset Stopped operator
# when
output="$(helper gpu --no-login)" && status=0 || status=$?
# then: a bare `tailscale up`, which only switches a logged-in node back on
[[ "$status" -eq 0 && -z "$output" ]] && grep -qx 'tailscale up' "$TMP/calls" &&
    pass "a new shell brings a stopped node back up with a bare tailscale up" ||
    fail "a stopped node: status=$status output=$output calls=$(calls)"

# given a machine that is not logged in
reset NeedsLogin
# when
output="$(helper gpu --no-login)" && status=0 || status=$?
# then: a hint, and nothing that would wait for a browser
[[ "$status" -eq 0 && "$output" == *"run 'tailscale-up' to log in"* ]] && ! grep -q ' up' "$TMP/calls" &&
    pass "a new shell points at tailscale-up while the machine is logged out, without waiting" ||
    fail "a logged-out node: status=$status output=$output calls=$(calls)"

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
# then: the first terminal can get there before tailscaled answers
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
output="$(PATH="$TMP/tools" "$TMP/tailscale-up-metal-gpu" --no-login 2>&1)" && status=0 || status=$?
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

# --- bare metal: asked for directly -----------------------------------------------------------------

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
    grep -qx -- 'tailscale serve --bg --tcp=11434 tcp://127.0.0.1:11434' "$TMP/calls" &&
    grep -qx -- "tailscale serve --bg --tcp=$PORT tcp://127.0.0.1:$PORT" "$TMP/calls"; then
    pass "tailscale-up logs in with both preferences and shares the model's server and the web UI"
else
    fail "a fresh login: status=$status output=$output calls=$(calls)"
fi

# given a node already on the tailnet and already sharing both
reset Running operator shared=127.0.0.1:11434 "ocode=127.0.0.1:$PORT"
# when
output="$(helper gpu)" && status=0 || status=$?
# then: nothing to log in and nothing to share again
[[ "$status" -eq 0 ]] && ! grep -q ' up\|serve --bg' "$TMP/calls" &&
    pass "tailscale-up leaves a node that is up and sharing as it is" ||
    fail "an up-to-date node: status=$status calls=$(calls)"

# given a machine without a GPU
reset NeedsLogin
# when
output="$(helper nogpu)" && status=0 || status=$?
# then: the model has nothing to serve here, and the web UI still reaches the tailnet
[[ "$status" -eq 0 ]] && ! grep -q -- '--tcp=11434' "$TMP/calls" &&
    grep -qx -- "tailscale serve --bg --tcp=$PORT tcp://127.0.0.1:$PORT" "$TMP/calls" &&
    pass "a machine without the local model shares only the web UI" ||
    fail "a machine without a GPU: status=$status calls=$(calls)"

# given .chezmoidata/opencode.yaml switching the web UI share off
reset NeedsLogin
# when
output="$(helper gpu-noshare)" && status=0 || status=$?
# then: the model's server alone
[[ "$status" -eq 0 ]] && ! grep -q -- "--tcp=$PORT" "$TMP/calls" &&
    grep -qx -- 'tailscale serve --bg --tcp=11434 tcp://127.0.0.1:11434' "$TMP/calls" &&
    pass "a machine that switches the web UI share off shares only the model's server" ||
    fail "web UI share off: status=$status calls=$(calls)"

# given a machine without a GPU that switches the web UI share off as well
reset NeedsLogin
# when
output="$(helper nogpu-noshare)" && status=0 || status=$?
# then: nothing to share, so the shares are not even asked for
[[ "$status" -eq 0 ]] && ! grep -q 'serve' "$TMP/calls" &&
    pass "a machine that shares neither runs no tailscale serve at all" ||
    fail "nothing to share: status=$status calls=$(calls)"

# given tailscaled switched off
reset NeedsLogin down
# when
output="$(helper gpu)" && status=0 || status=$?
# then
[[ "$status" -eq 0 ]] && grep -qx 'sudo systemctl enable --now tailscaled' "$TMP/calls" &&
    pass "tailscale-up starts a tailscaled that is off" ||
    fail "a daemon that is off: status=$status output=$output calls=$(calls)"

# --- WSL: Windows' client -----------------------------------------------------------------------

# given Windows on the tailnet and nothing shared yet
reset Running
# when: the pass the apply runs
output="$(wsl gpu --no-login)" && status=0 || status=$?
# then: both are shared through Windows' client, to Windows' localhost, which reaches WSL's relay
# whichever loopback family it listens on
[[ "$status" -eq 0 && "$output" == *"sharing Ollama"* && "$output" == *"sharing the ocode web UI"* &&
    "$output" == *"on the tailnet as 100.64.0.7"* ]] &&
    grep -qx -- 'tailscale serve --bg --tcp=11434 tcp://localhost:11434' "$TMP/calls" &&
    grep -qx -- "tailscale serve --bg --tcp=$PORT tcp://localhost:$PORT" "$TMP/calls" && ! grep -q ' up' "$TMP/calls" &&
    pass "on WSL the apply shares the model's server and the web UI through Windows' client" ||
    fail "WSL sharing: status=$status output=$output calls=$(calls)"

# given Windows on the tailnet and already sharing both
reset Running shared=localhost:11434 "ocode=localhost:$PORT"
# when
output="$(wsl gpu)" && status=0 || status=$?
# then
[[ "$status" -eq 0 ]] && ! grep -q 'serve --bg\| up' "$TMP/calls" &&
    pass "on WSL tailscale-up leaves a share that is in place as it is" ||
    fail "WSL already sharing: status=$status calls=$(calls)"

# given the shares an older revision set on a literal address, Windows' 127.0.0.1, which reaches
# WSL's relay only while what listens behind it binds IPv4
reset Running shared=127.0.0.1:11434 "ocode=127.0.0.1:$PORT"
# when: the pass the apply runs, which the installer repeats whenever tailscale-up changes
output="$(wsl gpu --no-login)" && status=0 || status=$?
# then: both are moved to localhost
[[ "$status" -eq 0 && "$output" == *"sharing Ollama"* && "$output" == *"sharing the ocode web UI"* ]] &&
    grep -qx -- 'tailscale serve --bg --tcp=11434 tcp://localhost:11434' "$TMP/calls" &&
    grep -qx -- "tailscale serve --bg --tcp=$PORT tcp://localhost:$PORT" "$TMP/calls" &&
    pass "on WSL the apply moves shares an older revision left on 127.0.0.1 to localhost" ||
    fail "WSL shares on 127.0.0.1: status=$status output=$output calls=$(calls)"

# given Windows not logged in
reset NeedsLogin
# when: asked for directly
output="$(wsl gpu)" && status=0 || status=$?
# then: the login is the Windows app's, so nothing here waits for it or shares anything
[[ "$status" -eq 1 && "$output" == *"log in with the Tailscale app"* ]] && ! grep -q ' up\|login\|serve' "$TMP/calls" &&
    pass "on WSL tailscale-up points a logged-out Windows at its app" ||
    fail "WSL logged out: status=$status output=$output calls=$(calls)"

# given Windows not logged in
reset NeedsLogin
# when: the pass the apply runs
output="$(wsl gpu --no-login)" && status=0 || status=$?
# then: a hint, and the apply goes on
[[ "$status" -eq 0 && "$output" == *"log in with the Tailscale app"* ]] && ! grep -q 'serve' "$TMP/calls" &&
    pass "on WSL the apply only hints while Windows is logged out" ||
    fail "WSL logged out, apply: status=$status output=$output calls=$(calls)"

# given Windows' client switched off in its app
reset Stopped
# when: asked for directly
output="$(wsl gpu)" && status=0 || status=$?
# then: a bare `tailscale up` switches it back on, and both are shared
[[ "$status" -eq 0 ]] && grep -qx 'tailscale up' "$TMP/calls" &&
    grep -qx -- 'tailscale serve --bg --tcp=11434 tcp://localhost:11434' "$TMP/calls" &&
    grep -qx -- "tailscale serve --bg --tcp=$PORT tcp://localhost:$PORT" "$TMP/calls" &&
    pass "on WSL tailscale-up switches Windows' client back on" ||
    fail "WSL switched off: status=$status output=$output calls=$(calls)"

# given Windows' client switched off in its app
reset Stopped
# when: the pass the apply runs
output="$(wsl gpu --no-login)" && status=0 || status=$?
# then: someone switched it off, so the apply leaves it off
[[ "$status" -eq 0 && "$output" == *"switched off"* ]] && ! grep -q ' up\|serve' "$TMP/calls" &&
    pass "on WSL the apply leaves a client someone switched off as it is" ||
    fail "WSL switched off, apply: status=$status output=$output calls=$(calls)"

# given Windows' Tailscale service not running
reset NoState win-down
# when
output="$(wsl gpu)" && status=0 || status=$?
# then
[[ "$status" -eq 1 && "$output" == *"not running on Windows"* ]] &&
    pass "on WSL tailscale-up reports a Windows service that is not running" ||
    fail "WSL service down: status=$status output=$output"

# given no Tailscale on Windows: the wrapper finds no tailscale.exe
reset Running win-missing
# when
output="$(wsl gpu)" && status=0 || status=$?
# then
[[ "$status" -eq 1 && "$output" == *"not installed on Windows"* ]] &&
    pass "on WSL tailscale-up reports Tailscale missing on Windows" ||
    fail "WSL without Windows' client: status=$status output=$output"

# given no wrapper at all
reset Running
# when
output="$(HOME="$TMP/home" PATH="$TMP/tools" "$TMP/tailscale-up-wsl-gpu" --no-login 2>&1)" && status=0 || status=$?
# then
[[ "$status" -eq 0 && "$output" == *"wrapper is missing"* ]] &&
    pass "on WSL the apply reports a missing wrapper and goes on" ||
    fail "WSL without the wrapper: status=$status output=$output"

# given the Linux client an older revision installed, still running
reset Running shared=localhost:11434 linux-tailscaled
# when
output="$(wsl gpu --no-login)" && status=0 || status=$?
# then
[[ "$status" -eq 0 && "$output" == *"WARN: tailscaled still runs inside WSL"*"apt-get purge"* ]] &&
    pass "on WSL tailscale-up warns about a client still running inside WSL" ||
    fail "WSL with a Linux client: status=$status output=$output"

# given a machine without a GPU
reset Running
# when
output="$(wsl nogpu)" && status=0 || status=$?
# then
[[ "$status" -eq 0 ]] && ! grep -q -- '--tcp=11434' "$TMP/calls" &&
    grep -qx -- "tailscale serve --bg --tcp=$PORT tcp://localhost:$PORT" "$TMP/calls" &&
    pass "on WSL a machine without the local model shares only the web UI" ||
    fail "WSL without a GPU: status=$status calls=$(calls)"

# given .chezmoidata/opencode.yaml switching the web UI share off
reset Running
# when
output="$(wsl gpu-noshare --no-login)" && status=0 || status=$?
# then
[[ "$status" -eq 0 ]] && ! grep -q -- "--tcp=$PORT" "$TMP/calls" &&
    grep -qx -- 'tailscale serve --bg --tcp=11434 tcp://localhost:11434' "$TMP/calls" &&
    pass "on WSL a machine that switches the web UI share off shares only the model's server" ||
    fail "WSL web UI share off: status=$status calls=$(calls)"

# given a machine without a GPU that switches the web UI share off as well
reset Running
# when
output="$(wsl nogpu-noshare --no-login)" && status=0 || status=$?
# then
[[ "$status" -eq 0 ]] && ! grep -q 'serve' "$TMP/calls" &&
    pass "on WSL a machine that shares neither runs no tailscale serve at all" ||
    fail "WSL nothing to share: status=$status calls=$(calls)"

# --- the Atuin sync server, on the one device that runs it ----------------------------------------

# given the Atuin server's device on the tailnet, sharing nothing yet
reset Running
# when: the pass the apply runs
output="$(wsl atuin --no-login)" && status=0 || status=$?
# then: its port is shared through Windows' client, to Windows' localhost, where Docker Desktop
# publishes it
[[ "$status" -eq 0 && "$output" == *"sharing the Atuin sync server"* ]] &&
    grep -qx -- "tailscale serve --bg --tcp=$ATUIN_PORT tcp://localhost:$ATUIN_PORT" "$TMP/calls" &&
    ! grep -q -- '--tcp=11434\|--tcp='"$PORT"' ' "$TMP/calls" &&
    pass "on WSL the Atuin server's device shares port $ATUIN_PORT through Windows' client" ||
    fail "WSL Atuin share: status=$status output=$output calls=$(calls)"

# given the same device already sharing it
reset Running "atuin=localhost:$ATUIN_PORT"
# when
output="$(wsl atuin)" && status=0 || status=$?
# then
[[ "$status" -eq 0 ]] && ! grep -q 'serve --bg' "$TMP/calls" &&
    pass "on WSL an Atuin share that is in place is left as it is" ||
    fail "WSL Atuin already shared: status=$status calls=$(calls)"

# given any other device, which syncs with that server rather than running one
reset Running
# when
output="$(wsl nogpu --no-login)" && status=0 || status=$?
# then
[[ "$status" -eq 0 ]] && ! grep -q -- "--tcp=$ATUIN_PORT" "$TMP/calls" &&
    pass "a device that does not run the Atuin server does not share its port" ||
    fail "Atuin shared by another device: status=$status calls=$(calls)"

# given the Atuin server's device on bare metal, with this user as the operator
reset Running operator
# when
output="$(helper atuin)" && status=0 || status=$?
# then: forwarded to the host's loopback, where Docker publishes it
[[ "$status" -eq 0 && "$output" == *"sharing the Atuin sync server"* ]] &&
    grep -qx -- "tailscale serve --bg --tcp=$ATUIN_PORT tcp://127.0.0.1:$ATUIN_PORT" "$TMP/calls" &&
    pass "on bare metal the Atuin server's device shares port $ATUIN_PORT to its loopback" ||
    fail "bare-metal Atuin share: status=$status output=$output calls=$(calls)"

# then, across every WSL case: nothing ran as root
if grep -q '^sudo\|tailscale set' "$TMP/wsl-all-calls"; then
    fail "on WSL tailscale-up ran sudo or changed a preference: $(grep '^sudo\|tailscale set' "$TMP/wsl-all-calls" | tr '\n' ';')"
else
    pass "on WSL tailscale-up never runs sudo and changes no preference"
fi

# --- WSL: the wrapper for Windows' CLI ----------------------------------------------------------

printf '#!/bin/bash\nprintf "<%%s>" "$@"\nexit 3\n' > "$TMP/tailscale.exe"
chmod +x "$TMP/tailscale.exe"
# given Windows' CLI where TAILSCALE_EXE says
# when
output="$(TAILSCALE_EXE="$TMP/tailscale.exe" bash "$WRAPPER" status --json "two words" 2>&1)" && status=0 || status=$?
# then: every argument reaches it as it was, and its exit status comes back
[[ "$status" -eq 3 && "$output" == "<status><--json><two words>" ]] &&
    pass "the wrapper hands its arguments to Windows' CLI and returns its status" ||
    fail "the wrapper: status=$status output=$output"

# given no Windows CLI
# when
output="$(TAILSCALE_EXE="$TMP/missing/tailscale.exe" bash "$WRAPPER" status 2>&1)" && status=0 || status=$?
# then
[[ "$status" -eq 127 && "$output" == *"not installed on Windows"* ]] &&
    pass "the wrapper reports Tailscale missing on Windows" ||
    fail "the wrapper without Windows' CLI: status=$status output=$output"

# --- the ocode web UI's port --------------------------------------------------------------------

# given the channel the fork build stamps, from which the fork's service derives its port: 10000
# plus the first eight hex digits of the channel's SHA-1, modulo 50000 (defaultPort in the fork's
# packages/cli/src/services/service-config.ts)
channel="$(sed -n 's/^OPENCODE_CHANNEL="\(.*\)"$/\1/p' "$REPO_ROOT/.chezmoiscripts/run_after_linux-006-build-ocode.sh")"
digits="$(printf '%s' "$channel" | sha1sum | cut -c1-8)"
derived=$((10000 + 16#$digits % 50000))
# then: the share forwards that port, so a channel renamed without moving webPort fails here
[[ -n "$channel" && "$PORT" == "$derived" ]] &&
    pass "the web UI is shared on the port the fork's service derives from its channel" ||
    fail "webPort is '$PORT', but the channel '$channel' makes the service listen on $derived"

# --- installer, removal and shell ---------------------------------------------------------------

# given a machine that starts or stops sharing a GPU, or the web UI
for kind in metal wsl; do
    gpu_hash="$(render gpu "$kind" "$INSTALLER" | grep -o 'tailscale-up [0-9a-f]\{64\}')"
    nogpu_hash="$(render nogpu "$kind" "$INSTALLER" | grep -o 'tailscale-up [0-9a-f]\{64\}')"
    noshare_hash="$(render gpu "$kind" "$INSTALLER" noshare | grep -o 'tailscale-up [0-9a-f]\{64\}')"
    # then: the installer's own content changes, so it runs again
    [[ -n "$gpu_hash" && "$gpu_hash" != "$nogpu_hash" && "$gpu_hash" != "$noshare_hash" ]] &&
        pass "the $kind installer runs again when what this machine shares changes" ||
        fail "the $kind installer does not track tailscale-up: '$gpu_hash' / '$nogpu_hash' / '$noshare_hash'"
done

# then: on WSL the installer installs nothing and runs only the apply's pass; on bare metal it
# installs tailscaled
render gpu wsl "$INSTALLER" > "$TMP/installer-wsl"
render gpu metal "$INSTALLER" > "$TMP/installer-metal"
if bash -n "$TMP/installer-wsl" && bash -n "$TMP/installer-metal" &&
    grep -qx '"$HOME/.local/bin/tailscale-up" --no-login' "$TMP/installer-wsl" &&
    ! grep -v '^\s*#' "$TMP/installer-wsl" | grep -q 'apt-get\|sudo\|systemctl' &&
    grep -q '^    install_tailscale$' "$TMP/installer-metal"; then
    pass "on WSL the installer installs nothing; on bare metal it installs tailscaled"
else
    fail "the installer renders: wsl=$(tr '\n' ';' < "$TMP/installer-wsl")"
fi

# then: WSL removes the Linux client an older revision installed, and bare metal keeps it
render nogpu wsl "$REMOVER" > "$TMP/remover-wsl"
render nogpu metal "$REMOVER" > "$TMP/remover-metal"
if bash -n "$TMP/remover-wsl" && bash -n "$TMP/remover-metal" &&
    grep -qx '    "apt:tailscale"' "$TMP/remover-wsl" && ! grep -q 'apt:tailscale' "$TMP/remover-metal"; then
    pass "WSL removes Tailscale's Linux client, bare metal keeps it"
else
    fail "the removal script does not remove the Linux client on WSL alone"
fi

# then: zsh runs the quiet pass in interactive shells on bare metal, and not at all on WSL or
# Android
metal_zshrc="$(render gpu metal "$REPO_ROOT/dot_zshrc.tmpl")"
wsl_zshrc="$(render gpu wsl "$REPO_ROOT/dot_zshrc.tmpl")"
android_zshrc="$(render gpu android "$REPO_ROOT/dot_zshrc.tmpl")"
if grep -A2 -F 'if [[ -o interactive ]] && command -v tailscale-up' <<<"$metal_zshrc" | grep -q 'tailscale-up --no-login' &&
    ! grep -q 'tailscale-up' <<<"$wsl_zshrc" && ! grep -q 'tailscale-up' <<<"$android_zshrc"; then
    pass "interactive zsh joins the tailnet with the quiet pass on bare metal only"
else
    fail "zshrc does not run tailscale-up --no-login as expected"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-tailscale] all tailnet tests passed" >&2
fi

exit $EXIT_CODE
