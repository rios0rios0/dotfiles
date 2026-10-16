#!/bin/bash
set -euo pipefail

# Tests the OpenCode V2 global configuration: that the template renders to valid JSONC on
# both platforms, that the provider points at the OmniRoute data file with the key as an
# {env:...} reference, that the MCP servers carry the V2 field names, and that the dotfiles
# reference names the chezmoi source. No OpenCode, OmniRoute or network is needed: chezmoi
# renders the template with a mock config, and jq reads the result.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CI_DIR="$REPO_ROOT/.github/ci"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-opencode] testing the OpenCode V2 global configuration..." >&2

pass() { echo "[test-opencode] PASS: $1" >&2; }
fail() { echo "[test-opencode] FAIL: $1" >&2; EXIT_CODE=1; }

# .chezmoidata is read from the source directory, so every render points chezmoi at this
# checkout; the template reads no 1Password field.
chmod +x "$CI_DIR/fixtures/mock-op.sh" 2>/dev/null || true
cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
onePassword:
  command: "$CI_DIR/fixtures/mock-op.sh"
data:
  deviceName: "testdevice"
EOF

TEMPLATE="$REPO_ROOT/dot_config/opencode/opencode.json.tmpl"

# render <os>: the configuration as that platform receives it, with JSONC comments stripped
# (they are for editors; jq cannot read them).
render() {
    chezmoi execute-template --config "$TMP/chezmoi.yaml" --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" < "$TEMPLATE" |
        awk 'BEGIN { in_comment = 0 }
             {
               line = $0; out = ""
               while (length(line) > 0) {
                 if (in_comment) { i = index(line, "*/"); if (i == 0) line = ""; else { line = substr(line, i + 2); in_comment = 0 } }
                 else { i = index(line, "/*"); if (i == 0) { out = out line; line = "" } else { out = out substr(line, 1, i - 1); line = substr(line, i + 2); in_comment = 1 } }
               }
               print out
             }'
}

render linux > "$TMP/linux.json"
render darwin > "$TMP/darwin.json"

# given the template, rendered for each platform
# when jq parses the result
# then both are valid JSON(C), so no comment or brace escapes the stripper
if jq -e . "$TMP/linux.json" >/dev/null 2>&1 && jq -e . "$TMP/darwin.json" >/dev/null 2>&1; then
    pass "the template renders to valid JSONC on Linux and macOS"
else
    fail "the rendered configuration is not valid JSON"
fi

# given the rendered configuration
# when shell-style placeholders are searched for
# then none remain: OpenCode substitutes {env:...} when it loads the file, and it expands
# ${...} only inside a provider's settings.baseURL, where a key would stay literal
if ! grep -Fq '${' "$TMP/linux.json" "$TMP/darwin.json"; then
    pass "no shell-style placeholders remain"
else
    fail "a \${...} placeholder remains: $(grep -Fn '${' "$TMP/linux.json" | head -2)"
fi

# given the provider entry
# when it is read
# then the base URL is the one .chezmoidata/omniroute.yaml names, with /v1, and the key is
# an env reference, never a literal
base_url="$(chezmoi execute-template --config "$TMP/chezmoi.yaml" '{{ .omniroute.baseUrl }}')"
if [[ "$(jq -r '.providers.omniroute.settings.baseURL' "$TMP/linux.json")" == "$base_url/v1" &&
    "$(jq -r '.providers.omniroute.settings.apiKey' "$TMP/linux.json")" == '{env:OMNIROUTE_API_KEY}' ]]; then
    pass "the provider reads the data file's baseUrl and keeps the key out of the repository"
else
    fail "unexpected provider: $(jq -c '.providers' "$TMP/linux.json")"
fi

# given the default model and agent
# when they are read
# then the model is the auto combo the gateway serves, under OmniRoute
if [[ "$(jq -r '.model' "$TMP/linux.json")" == "omniroute/auto/coding" &&
    "$(jq -r '.default_agent' "$TMP/linux.json")" == "build" ]]; then
    pass "the default model is omniroute/auto/coding on the build agent"
else
    fail "unexpected defaults: $(jq -c '{model, default_agent}' "$TMP/linux.json")"
fi

# given the Linux render
# when chrome-devtools is read
# then it carries the V2 environment field with the update check off, and no env key, which
# V2 would ignore without a diagnostic
if [[ "$(jq -r '.mcp.servers["chrome-devtools"].environment.CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS' "$TMP/linux.json")" == "1" &&
    "$(jq -r '.mcp.servers["chrome-devtools"] | has("env")' "$TMP/linux.json")" == "false" ]]; then
    pass "chrome-devtools uses the V2 environment field, not env"
else
    fail "unexpected chrome-devtools entry: $(jq -c '.mcp.servers["chrome-devtools"]' "$TMP/linux.json")"
fi

# given either platform
# when every MCP server is checked
# then none carries an env key
if [[ "$(jq -r '[.mcp.servers[] | has("env")] | any' "$TMP/linux.json")" == "false" &&
    "$(jq -r '[.mcp.servers[] | has("env")] | any' "$TMP/darwin.json")" == "false" ]]; then
    pass "no MCP server carries the ignored env field"
else
    fail "an MCP server carries env"
fi

# given the context7 server
# when its header is read
# then the bearer is an env reference
if [[ "$(jq -r '.mcp.servers.context7.headers.Authorization' "$TMP/linux.json")" == 'Bearer {env:CONTEXT7_API_KEY}' ]]; then
    pass "context7's bearer comes from {env:CONTEXT7_API_KEY}"
else
    fail "unexpected context7 header: $(jq -r '.mcp.servers.context7.headers.Authorization' "$TMP/linux.json")"
fi

# given the macOS render
# when the servers are read
# then Chrome DevTools is absent: it drives the Linux-installed Google Chrome
if [[ "$(jq -r '.mcp.servers | has("chrome-devtools")' "$TMP/darwin.json")" == "false" &&
    "$(jq -r '.mcp.servers | keys | join(",")' "$TMP/darwin.json")" == "context7" ]]; then
    pass "chrome-devtools is Linux only"
else
    fail "unexpected macOS servers: $(jq -c '.mcp.servers | keys' "$TMP/darwin.json")"
fi

# given the dotfiles reference
# when it is read
# then it is the absolute chezmoi source, not a path relative to the config directory
ref="$(jq -r '.references.dotfiles.path' "$TMP/linux.json")"
if [[ "$ref" == "$REPO_ROOT" && "$ref" == /* ]]; then
    pass "the dotfiles reference names the chezmoi source absolutely"
else
    fail "unexpected reference path: $ref"
fi

# given the instructions list
# when it is read
# then AGENTS.md and the project's CLAUDE.md are both fed to sessions
if [[ "$(jq -r '.instructions | join(",")' "$TMP/linux.json")" == "AGENTS.md,CLAUDE.md" ]]; then
    pass "AGENTS.md and CLAUDE.md reach sessions"
else
    fail "unexpected instructions: $(jq -c '.instructions' "$TMP/linux.json")"
fi

# given the permission rules
# when they are read
# then every effect is one of the V2 literals, and the shell, read, edit and websearch
# allowances mirror the Claude Code side
if [[ "$(jq -r '[.permissions[].effect] | unique | join(",")' "$TMP/linux.json")" == "allow" &&
    "$(jq -r '[.permissions[] | select(.action == "shell" and .resource == "git *")] | length' "$TMP/linux.json")" == "1" &&
    "$(jq -r '[.permissions[] | select(.action == "websearch" and .effect == "allow")] | length' "$TMP/linux.json")" == "1" ]]; then
    pass "the permission rules are V2 entries with allow effects"
else
    fail "unexpected permissions: $(jq -c '.permissions' "$TMP/linux.json")"
fi

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-opencode] all OpenCode configuration tests passed" >&2
fi

exit $EXIT_CODE
