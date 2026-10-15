#!/bin/bash
set -euo pipefail

# Tests run_onchange_after_linux-012-setup-claude-lsp.sh against stubbed go, npm and claude, in an
# environment with nothing else of the developer's: that each plugin comes after the server it
# starts, that the servers are the pinned ones, that a server which failed keeps its plugin out and
# fails the run, that the plugins land in the regular profile, and that go and npm are found when
# the first apply runs the script from a bash that never loaded GVM or NVM.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$REPO_ROOT/.chezmoiscripts/run_onchange_after_linux-012-setup-claude-lsp.sh"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-claude-lsp] testing the language servers and their plugins..." >&2

pass() { echo "[test-claude-lsp] PASS: $1" >&2; }
fail() { echo "[test-claude-lsp] FAIL: $1" >&2; EXIT_CODE=1; }

# Writes the stubs into $1. Each records its call in $CALLS; npm fails when its arguments contain
# $FAIL_NPM, and claude records the CLAUDE_CONFIG_DIR it was started with.
write_stubs() {
    mkdir -p "$1"
    cat > "$1/go" <<'EOF'
#!/bin/bash
echo "go $* GOBIN=${GOBIN:-}" >> "$CALLS"
EOF
    cat > "$1/npm" <<'EOF'
#!/bin/bash
echo "npm $*" >> "$CALLS"
if [[ -n "${FAIL_NPM:-}" && "$*" == *"$FAIL_NPM"* ]]; then
    exit 1
fi
EOF
    cat > "$1/claude" <<'EOF'
#!/bin/bash
echo "claude $* CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-}" >> "$CALLS"
EOF
    chmod +x "$1/go" "$1/npm" "$1/claude"
}

# The only programs on PATH besides the stubs: a runner's own go or npm in /usr/bin would
# otherwise answer for a stub that a case removed, and download for real.
TOOLS="$TMP/tools"
mkdir -p "$TOOLS"
for tool in bash sort tail mkdir; do
    ln -s "$(command -v "$tool")" "$TOOLS/$tool"
done

# run_case <name> [VAR=value...]: runs the script with HOME and the call log under $TMP/<name>, the
# stubs first on PATH, and only the given variables. Leaves the status in $STATUS and stderr in
# $TMP/<name>/stderr.
run_case() {
    local name="$1"
    shift
    local dir="$TMP/$name"
    mkdir -p "$dir/home"
    : > "$dir/calls"
    STATUS=0
    env -i HOME="$dir/home" CALLS="$dir/calls" PATH="${CASE_PATH:-$TMP/stubs}:$TOOLS" "$@" \
        bash "$SCRIPT" > /dev/null 2> "$dir/stderr" || STATUS=$?
}

# line_of <name> <fixed string>: the number of the first call that contains the string, or 0.
line_of() {
    local found
    found="$(grep -n -F -m 1 -- "$2" "$TMP/$1/calls" | cut -d: -f1)"
    echo "${found:-0}"
}

write_stubs "$TMP/stubs"

# given every install succeeding

# when
run_case all

# then
calls="$TMP/all/calls"
if [[ "$STATUS" -eq 0 ]]; then
    pass "a run where everything installs succeeds"
else
    fail "a run where everything installs exited $STATUS: $(cat "$TMP/all/stderr")"
fi
if grep -q -F "go install golang.org/x/tools/gopls@v0.23.0 GOBIN=$TMP/all/home/.local/bin" "$calls"; then
    pass "gopls is the pinned version, installed into ~/.local/bin"
else
    fail "gopls was not installed pinned into ~/.local/bin: $(grep '^go ' "$calls")"
fi
if grep -q -F "npm install -g --ignore-scripts typescript-language-server@6.0.2 typescript@6.0.3" "$calls" &&
    grep -q -F "npm install -g --ignore-scripts pyright@1.1.414" "$calls"; then
    pass "the npm servers are pinned, TypeScript on 6.x, with no install scripts run"
else
    fail "the npm servers were not installed as pinned: $(grep '^npm ' "$calls")"
fi
marketplace=$(line_of all "claude plugin marketplace add anthropics/claude-plugins-official")
ordered=true
for pair in "gopls-lsp:go install" "typescript-lsp:typescript-language-server@" "pyright-lsp:pyright@"; do
    plugin_line=$(line_of all "claude plugin install ${pair%%:*}@claude-plugins-official --scope user")
    server_line=$(line_of all "${pair#*:}")
    if [[ "$plugin_line" -eq 0 || "$server_line" -eq 0 || "$server_line" -gt "$plugin_line" ||
        "$marketplace" -eq 0 || "$marketplace" -gt "$plugin_line" ]]; then
        ordered=false
    fi
done
if $ordered; then
    pass "each plugin is installed at user scope after its server and the marketplace"
else
    fail "a plugin was missing or came before its server or the marketplace: $(cat "$calls")"
fi
if grep -q -E '^claude .* (-y|--yes)( |$)' "$calls"; then
    fail "a plugin install accepted marketplace commands unattended (-y)"
else
    pass "no plugin install accepts a marketplace command unattended"
fi

# given a CLAUDE_CONFIG_DIR inherited from a claude-local session

# when
run_case profile CLAUDE_CONFIG_DIR="$TMP/profile/claude-local"

# then
if [[ "$(grep -c '^claude ' "$TMP/profile/calls")" -eq 4 ]] &&
    ! grep -q -F "CLAUDE_CONFIG_DIR=$TMP/profile/claude-local" "$TMP/profile/calls"; then
    pass "the plugins land in the regular profile, not an inherited CLAUDE_CONFIG_DIR"
else
    fail "claude ran with the inherited CLAUDE_CONFIG_DIR: $(grep '^claude ' "$TMP/profile/calls")"
fi

# given pyright failing to install

# when
run_case pyright FAIL_NPM=pyright@

# then
calls="$TMP/pyright/calls"
if [[ "$STATUS" -ne 0 ]] &&
    grep -q -F "claude plugin install gopls-lsp@claude-plugins-official" "$calls" &&
    grep -q -F "claude plugin install typescript-lsp@claude-plugins-official" "$calls" &&
    ! grep -q -F "claude plugin install pyright-lsp" "$calls" &&
    grep -q -F "not set up: pyright-lsp" "$TMP/pyright/stderr"; then
    pass "a server that failed keeps its plugin out, the others still install, and the run fails"
else
    fail "a failed server did not keep its plugin out or fail the run (status $STATUS): $(cat "$calls")"
fi

# given no claude anywhere
mkdir -p "$TMP/noclaude-stubs"
write_stubs "$TMP/noclaude-stubs"
rm "$TMP/noclaude-stubs/claude"

# when
CASE_PATH="$TMP/noclaude-stubs" run_case noclaude

# then
if [[ "$STATUS" -ne 0 ]] && grep -q '^npm ' "$TMP/noclaude/calls" && ! grep -q '^claude ' "$TMP/noclaude/calls"; then
    pass "without claude the servers still install and the run fails, so the next apply retries"
else
    fail "a run without claude did not fail after installing the servers (status $STATUS)"
fi

# given the first apply's bash, with Go only under GVM and npm only behind nvm.sh
mkdir -p "$TMP/bare-stubs" "$TMP/firstrun/home/.gvm/gos/go1.9.7/bin" "$TMP/firstrun/home/.gvm/gos/go1.27.2/bin" \
    "$TMP/firstrun/home/.nvm/versions/node/v24.21.0/bin"
write_stubs "$TMP/bare-stubs"
mv "$TMP/bare-stubs/go" "$TMP/firstrun/home/.gvm/gos/go1.27.2/bin/go"
printf '#!/bin/bash\necho "stale go" >> "$CALLS"\n' > "$TMP/firstrun/home/.gvm/gos/go1.9.7/bin/go"
chmod +x "$TMP/firstrun/home/.gvm/gos/go1.9.7/bin/go"
mv "$TMP/bare-stubs/npm" "$TMP/firstrun/home/.nvm/versions/node/v24.21.0/bin/npm"
cat > "$TMP/firstrun/home/.nvm/nvm.sh" <<'EOF'
# Like the real nvm.sh, this reads a variable nobody set, which `set -u` would abort on.
: "$NVM_UNSET_PROBE"
nvm() {
    [[ "$1" == "use" && "$2" == "default" ]] && PATH="$HOME/.nvm/versions/node/v24.21.0/bin:$PATH"
}
EOF

# when
CASE_PATH="$TMP/bare-stubs" run_case firstrun

# then
if [[ "$STATUS" -eq 0 ]] && grep -q '^go install' "$TMP/firstrun/calls" && grep -q '^npm install' "$TMP/firstrun/calls" &&
    ! grep -q '^stale go' "$TMP/firstrun/calls"; then
    pass "the first apply finds the newest GVM Go and NVM's default npm"
else
    fail "the first apply did not find GVM's newest Go and NVM's npm (status $STATUS): $(cat "$TMP/firstrun/stderr")"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-claude-lsp] all language server tests passed" >&2
fi

exit $EXIT_CODE
