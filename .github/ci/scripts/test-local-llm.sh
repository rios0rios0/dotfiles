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

# --- claude-remote -----------------------------------------------------------------------------

render gpu "$REPO_ROOT/dot_local/bin/executable_claude-remote.tmpl" > "$TMP/claude-remote"
chmod +x "$TMP/claude-remote"
window="$(jq -r '.contextTokens' <<<"$(settings gpu)")"

# Stubs: tailscale answers from files each case writes; curl answers /api/version only for the
# addresses listed in remote-answering, loads any model, and reports remote-ps.json as the server's
# running models; claude-local records what it was handed.
REMOTE_STUBS="$TMP/remote-stubs"
mkdir -p "$REMOTE_STUBS"
cat > "$REMOTE_STUBS/tailscale" <<EOF
#!/bin/bash
[[ "\$1 \$2" == "status --json" ]] && exec cat "$TMP/remote-status.json"
[[ "\$1 \$2" == "ip -4" ]] && { awk -v name="\$3" '\$1 == name { print \$2; found = 1 } END { exit !found }' "$TMP/remote-ips"; exit; }
exit 1
EOF
cat > "$REMOTE_STUBS/curl" <<EOF
#!/bin/bash
url=""
for arg in "\$@"; do [[ "\$arg" == http* ]] && url="\$arg"; done
host="\${url#http://}"
host="\${host%%:*}"
[[ "\$url" == */api/version ]] && { grep -qxF "\$host" "$TMP/remote-answering"; exit; }
[[ "\$url" == */api/generate ]] && { echo "\$host" >> "$TMP/remote-loaded"; echo '{"done":true}'; exit; }
[[ "\$url" == */api/ps ]] && exec cat "$TMP/remote-ps.json"
exit 7
EOF
cat > "$REMOTE_STUBS/claude-local" <<EOF
#!/bin/bash
echo "OLLAMA_HOST=\$OLLAMA_HOST" > "$TMP/remote.handed"
printf '<%s>\n' "\$@" >> "$TMP/remote.handed"
EOF
chmod +x "$REMOTE_STUBS"/*

# remote_case <backend state> <answering addresses...>: a tailnet of three peers -- laptop and
# desktop online, an offline server that would answer -- and a model held entirely in VRAM
remote_case() {
    local state="$1"
    shift
    rm -f "$TMP/remote.handed" "$TMP/remote-loaded"
    jq -n --arg state "$state" '{BackendState: $state, Peer: {
        a: {HostName: "phone", Online: true, TailscaleIPs: ["100.64.0.2", "fd7a::2"]},
        b: {HostName: "old-server", Online: false, TailscaleIPs: ["100.64.0.9"]},
        c: {HostName: "desktop", Online: true, TailscaleIPs: ["fd7a::3", "100.64.0.3"]}}}' > "$TMP/remote-status.json"
    printf '%s\n' "$@" > "$TMP/remote-answering"
    printf 'desktop 100.64.0.3\n' > "$TMP/remote-ips"
    jq -n --arg model "$model" --argjson ctx "$window" \
        '{models: [{name: $model, model: $model, context_length: $ctx, size: 100, size_vram: 100}]}' > "$TMP/remote-ps.json"
}

run_remote() {
    env -u CLAUDE_REMOTE_HOST -u CLAUDE_LOCAL_MODEL PATH="$REMOTE_STUBS:/usr/bin:/bin" "$@"
}

# given a tailnet where the first online peer has no server and the offline one would answer
remote_case Running 100.64.0.9 100.64.0.3
# when
output="$(run_remote "$TMP/claude-remote" -p "two words" 2>&1)" || true
# then: the online server is chosen, warmed, and claude-local is handed it with the arguments intact
if [[ "$(head -1 "$TMP/remote.handed" 2>/dev/null)" == "OLLAMA_HOST=http://100.64.0.3:11434" &&
    "$(tail -2 "$TMP/remote.handed" | tr '\n' '|')" == "<-p>|<two words>|" &&
    "$(cat "$TMP/remote-loaded")" == "100.64.0.3" && "$output" == *"using desktop (100.64.0.3)"* ]]; then
    pass "claude-remote finds the online server on the tailnet and hands it to claude-local"
else
    fail "claude-remote picked the wrong server: $output / $(tr '\n' ' ' < "$TMP/remote.handed" 2>/dev/null)"
fi

# given no machine that answers
remote_case Running
# when
if output="$(run_remote "$TMP/claude-remote" -p hi 2>&1)"; then status=0; else status=$?; fi
# then
if [[ "$status" -ne 0 && "$output" == *"no machine on the tailnet shares Ollama"* && ! -e "$TMP/remote.handed" ]]; then
    pass "claude-remote stops when no machine shares a server"
else
    fail "claude-remote without a server: status=$status output=$output"
fi

# given a server whose window differs from the one claude-local declares
remote_case Running 100.64.0.3
jq '.models[0].context_length = 32768' "$TMP/remote-ps.json" > "$TMP/remote-ps.tmp" && mv "$TMP/remote-ps.tmp" "$TMP/remote-ps.json"
# when
if output="$(run_remote "$TMP/claude-remote" -p hi 2>&1)"; then status=0; else status=$?; fi
# then: a window mismatch truncates silently, so it stops the launch
if [[ "$status" -ne 0 && "$output" == *"32768-token window"* && "$output" == *"chezmoi update"* && ! -e "$TMP/remote.handed" ]]; then
    pass "claude-remote refuses a server whose context window differs"
else
    fail "claude-remote with a mismatched window: status=$status output=$output"
fi

# given a server whose GPU holds only part of the model
remote_case Running 100.64.0.3
jq '.models[0].size_vram = 40' "$TMP/remote-ps.json" > "$TMP/remote-ps.tmp" && mv "$TMP/remote-ps.tmp" "$TMP/remote-ps.json"
# when
output="$(run_remote "$TMP/claude-remote" -p hi 2>&1)" || true
# then
if [[ "$output" == *"WARN: 60% of $model runs on the CPU of desktop"* && -e "$TMP/remote.handed" ]]; then
    pass "claude-remote warns when the server runs part of the model on its CPU, and goes on"
else
    fail "claude-remote with partial GPU placement: $output"
fi

# given a server named by the caller
remote_case Running 100.64.0.3
# when
output="$(run_remote env CLAUDE_REMOTE_HOST=desktop "$TMP/claude-remote" -p hi 2>&1)" || true
# then: the tailnet name resolves without MagicDNS
if [[ "$(head -1 "$TMP/remote.handed" 2>/dev/null)" == "OLLAMA_HOST=http://100.64.0.3:11434" ]]; then
    pass "CLAUDE_REMOTE_HOST picks a tailnet machine by name"
else
    fail "CLAUDE_REMOTE_HOST ignored: $output"
fi

# given a machine that is not logged in to the tailnet
remote_case NeedsLogin 100.64.0.3
# when
if output="$(run_remote "$TMP/claude-remote" -p hi 2>&1)"; then status=0; else status=$?; fi
# then
if [[ "$status" -ne 0 && "$output" == *"run 'tailscale-up'"* && ! -e "$TMP/remote.handed" ]]; then
    pass "claude-remote points at tailscale-up when this machine is off the tailnet"
else
    fail "claude-remote off the tailnet: status=$status output=$output"
fi

# --- claude-local-task -------------------------------------------------------------------------

TASK="$REPO_ROOT/dot_local/bin/executable_claude-local-task"
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
for launcher in claude-local claude-remote; do
    cat > "$TASK_STUBS/$launcher" <<EOF
#!/bin/bash
cat > "$TMP/task-brief.seen"
printf '<%s>\n' "\$@" > "$TMP/task-launcher.args"
echo "$launcher" > "$TMP/task-launcher.name"
echo "changed by the run" >> a.txt
echo "added by the run" > new.txt
rm -f gone.txt
cat "$TMP/task-stream.jsonl"
EOF
done
chmod +x "$TASK_STUBS"/*
printf 'Add a feature.\n' > "$TMP/task-brief.md"

# A repository with work of the caller's own: an uncommitted edit and a staged new file.
task_repo() {
    rm -rf "$TMP/task-repo" "$TMP/task-config"
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
    (cd "$TMP/task-repo" && env CLAUDE_LOCAL_CONFIG_DIR="$TMP/task-config" PATH="$TASK_STUBS:/usr/bin:/bin" bash "$TASK" "$@")
}

# given a repository with the caller's own work in progress
task_repo
index_before="$(sha256sum < "$TMP/task-repo/.git/index")"
tree_before="$(tree_state)"
# when
if output="$(run_task "$TMP/task-brief.md" 2>&1)"; then status=0; else status=$?; fi
# then: every action is listed with its result, a write outside the repository flagged
if [[ "$status" -eq 0 && "$output" == *"1. Bash: go test ./... -> ok"* &&
    "$output" == *"2. Write: [outside the repository] /elsewhere/notes.txt (2 lines) -> ok"* &&
    "$output" == *"3. Bash: git push -> error: Exit code 128"* && "$output" == *"final message:"*"Done, tests pass."* ]]; then
    pass "claude-local-task lists every action with its result"
else
    fail "unexpected action list (status $status): $output"
fi
# then: the change is the run's alone -- the caller's edit and staged file are not in it
if [[ "$(sed -n '/^change:/,/^diff:/p' <<<"$output" | grep -E '^  [AMD]' | tr '\t' ' ' | tr '\n' '|')" == "  M a.txt|  D gone.txt|  A new.txt|" ]]; then
    pass "claude-local-task attributes only the run's own change to it"
else
    fail "unexpected change: $(sed -n '/^change:/,/^undo:/p' <<<"$output")"
fi
# then: the caller's index is untouched, and the undo command restores the tree as it was
undo="$(sed -n 's/^undo: //p' <<<"$output")"
if [[ "$(sha256sum < "$TMP/task-repo/.git/index")" == "$index_before" ]] && (cd "$TMP/task-repo" && eval "$undo") &&
    [[ "$(tree_state)" == "$tree_before" ]]; then
    pass "claude-local-task leaves the caller's index alone, and its undo restores the tree"
else
    fail "the index changed or the undo did not restore the tree: $undo"
fi
# then: the launcher got the brief on stdin and an unattended run, and the full audit was saved
audit="$(sed -n 's/^\[claude-local-task\] full audit: //p' <<<"$output")"
if cmp -s "$TMP/task-brief.md" "$TMP/task-brief.seen" &&
    grep -qx -- '<--dangerously-skip-permissions>' "$TMP/task-launcher.args" &&
    grep -qx -- '<stream-json>' "$TMP/task-launcher.args" &&
    [[ -f "$audit" ]] && grep -q '^## Actions' "$audit" && grep -q 'fatal: no remote' "$audit"; then
    pass "claude-local-task runs the brief unattended and saves the full audit"
else
    fail "unexpected launcher call or audit: $(tr '\n' ' ' < "$TMP/task-launcher.args") / $audit"
fi

# given --remote
task_repo
# when
run_task --remote "$TMP/task-brief.md" >/dev/null 2>&1 || true
# then
[[ "$(cat "$TMP/task-launcher.name")" == "claude-remote" ]] &&
    pass "claude-local-task --remote runs the model through claude-remote" ||
    fail "claude-local-task --remote used $(cat "$TMP/task-launcher.name")"

# given a launcher that fails before the model runs
task_repo
printf '#!/bin/bash\necho "Error: no server" >&2\nexit 1\n' > "$TMP/task-stubs-failing"
mkdir -p "$TMP/task-stubs-fail"
cp "$TMP/task-stubs-failing" "$TMP/task-stubs-fail/claude-local"
chmod +x "$TMP/task-stubs-fail/claude-local"
# when
if output="$(cd "$TMP/task-repo" && env CLAUDE_LOCAL_CONFIG_DIR="$TMP/task-config" PATH="$TMP/task-stubs-fail:/usr/bin:/bin" bash "$TASK" "$TMP/task-brief.md" 2>&1)"; then status=0; else status=$?; fi
# then
if [[ "$status" -ne 0 && "$output" == *"did not run (exit 1): Error: no server"* && "$output" == *"change: none"* ]]; then
    pass "claude-local-task reports a run that never started, and fails"
else
    fail "claude-local-task with a failing launcher: status=$status output=$output"
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
