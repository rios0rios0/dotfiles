#!/bin/bash
set -euo pipefail

# Tests run_onchange_after_linux-012-setup-claude-lsp.sh against stubbed go, npm and claude, in an
# environment with nothing else of the developer's: that each plugin comes after an available
# server, that the servers are pinned, that failed or missing binaries keep their plugins out and
# fail the run, that NVM's default wins over another npm on PATH, and that go and npm are found on
# the first apply from a bash that never loaded GVM or NVM.

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
if [[ -n "${FAIL_GO:-}" ]]; then
    exit 1
fi
if [[ "${SKIP_GOPLS_BINARY:-}" != 1 ]]; then
    mkdir -p "$GOBIN"
    : > "$GOBIN/gopls"
    chmod +x "$GOBIN/gopls"
fi
EOF
    cat > "$1/npm" <<'EOF'
#!/bin/bash
echo "${NPM_LOG_PREFIX:-npm} $*" >> "$CALLS"
if [[ -n "${FAIL_NPM:-}" && "$*" == *"$FAIL_NPM"* ]]; then
    exit 1
fi
if [[ "${SKIP_NPM_BINARIES:-}" == 1 ]]; then
    exit 0
fi
mkdir -p "$NPM_GLOBAL_BIN"
if [[ "$*" == *typescript-language-server@* ]]; then
    : > "$NPM_GLOBAL_BIN/typescript-language-server"
    chmod +x "$NPM_GLOBAL_BIN/typescript-language-server"
fi
if [[ "$*" == *pyright@* ]]; then
    : > "$NPM_GLOBAL_BIN/pyright-langserver"
    chmod +x "$NPM_GLOBAL_BIN/pyright-langserver"
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
for tool in bash sort tail mkdir chmod; do
    ln -s "$(command -v "$tool")" "$TOOLS/$tool"
done

# run_case <name> [VAR=value...]: runs the script with HOME and the call log under $TMP/<name>, the
# stubs first on PATH, and only the given variables. Leaves the status in $STATUS and stderr in
# $TMP/<name>/stderr.
run_case() {
    local name="$1"
    shift
    local dir="$TMP/$name"
    mkdir -p "$dir/home" "$dir/npm-global-bin"
    : > "$dir/calls"
    STATUS=0
    env -i HOME="$dir/home" CALLS="$dir/calls" NPM_GLOBAL_BIN="$dir/npm-global-bin" \
        PATH="$dir/home/.local/bin:$dir/npm-global-bin:${CASE_PATH:-$TMP/stubs}:$TOOLS" "$@" \
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

# given npm exits successfully without exposing either language server

# when
run_case npm-unresolved SKIP_NPM_BINARIES=1

# then
calls="$TMP/npm-unresolved/calls"
if [[ "$STATUS" -ne 0 ]] &&
    grep -q -F "claude plugin install gopls-lsp@claude-plugins-official" "$calls" &&
    ! grep -q -F "claude plugin install typescript-lsp" "$calls" &&
    ! grep -q -F "claude plugin install pyright-lsp" "$calls" &&
    grep -q -F "not set up: typescript-lsp pyright-lsp" "$TMP/npm-unresolved/stderr"; then
    pass "npm success without reachable servers keeps both plugins out and fails the run"
else
    fail "missing npm server binaries did not keep their plugins out or fail the run (status $STATUS): $(cat "$calls")"
fi

# given go install exits successfully without exposing gopls

# when
run_case gopls-unresolved SKIP_GOPLS_BINARY=1

# then
calls="$TMP/gopls-unresolved/calls"
if [[ "$STATUS" -ne 0 ]] &&
    ! grep -q -F "claude plugin install gopls-lsp" "$calls" &&
    grep -q -F "claude plugin install typescript-lsp@claude-plugins-official" "$calls" &&
    grep -q -F "claude plugin install pyright-lsp@claude-plugins-official" "$calls" &&
    grep -q -F "not set up: gopls-lsp" "$TMP/gopls-unresolved/stderr"; then
    pass "go install success without gopls keeps its plugin out and fails the run"
else
    fail "a missing gopls binary did not keep its plugin out or fail the run (status $STATUS): $(cat "$calls")"
fi

# given a working NVM default and an unrelated npm earlier on PATH
mkdir -p "$TMP/foreign-npm" "$TMP/nvm-selected/home/.nvm/versions/node/v24.21.0/bin"
write_stubs "$TMP/nvm-selected/home/.nvm/versions/node/v24.21.0/bin"
rm "$TMP/nvm-selected/home/.nvm/versions/node/v24.21.0/bin/go" \
    "$TMP/nvm-selected/home/.nvm/versions/node/v24.21.0/bin/claude"
cat > "$TMP/foreign-npm/npm" <<'EOF'
#!/bin/bash
echo "foreign npm $*" >> "$CALLS"
EOF
chmod +x "$TMP/foreign-npm/npm"
cat > "$TMP/nvm-selected/home/.nvm/nvm.sh" <<'EOF'
: "$NVM_UNSET_PROBE"
nvm() {
    [[ "$1" == "use" && "$2" == "default" ]] || return 1
    echo "nvm use default" >> "$CALLS"
    export NPM_LOG_PREFIX="nvm npm"
    NPM_GLOBAL_BIN="$NVM_DIR/versions/node/v24.21.0/bin"
    export NPM_GLOBAL_BIN
    export PATH="$NPM_GLOBAL_BIN:$PATH"
}
EOF

# when
CASE_PATH="$TMP/foreign-npm:$TMP/stubs" run_case nvm-selected NVM_DIR="$TMP/nvm-selected/home/.nvm"

# then
calls="$TMP/nvm-selected/calls"
if [[ "$STATUS" -eq 0 ]] && grep -q '^nvm use default$' "$calls" &&
    grep -q '^nvm npm install -g' "$calls" && ! grep -q '^foreign npm ' "$calls"; then
    pass "NVM's default wins when an unrelated npm already resolves on PATH"
else
    fail "the unrelated npm was used instead of NVM's default (status $STATUS): $(cat "$calls")"
fi

# given NVM cannot select its default while another npm is available
mkdir -p "$TMP/nvm-failure/home/.nvm"
cat > "$TMP/nvm-failure/home/.nvm/nvm.sh" <<'EOF'
nvm() {
    echo "nvm use default" >> "$CALLS"
    return 1
}
EOF

# when
CASE_PATH="$TMP/foreign-npm:$TMP/stubs" run_case nvm-failure NVM_DIR="$TMP/nvm-failure/home/.nvm"

# then
calls="$TMP/nvm-failure/calls"
if [[ "$STATUS" -ne 0 ]] && grep -q '^nvm use default$' "$calls" &&
    ! grep -q '^foreign npm ' "$calls" &&
    grep -q -F "ERROR: could not select NVM's default Node.js" "$TMP/nvm-failure/stderr"; then
    pass "a failed NVM default selection stops before using another npm"
else
    fail "a failed NVM default selection did not stop the run (status $STATUS): $(cat "$calls")"
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
    if [[ "$1" == "use" && "$2" == "default" ]]; then
        NPM_GLOBAL_BIN="$HOME/.nvm/versions/node/v24.21.0/bin"
        export NPM_GLOBAL_BIN
        PATH="$NPM_GLOBAL_BIN:$PATH"
    fi
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
