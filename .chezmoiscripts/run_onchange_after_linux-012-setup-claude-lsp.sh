#!/bin/bash

# Gives Claude Code code intelligence on Linux. Its LSP tool -- definitions, references, hover,
# symbols, call hierarchy, and the type errors it reports after each edit -- does nothing until a
# plugin names a language server and that server is on PATH, so this installs both halves: the
# servers, pinned, and the official plugins that start them, at user scope. Enabling a plugin in
# settings.json does not install it, which is why this runs `claude plugin install`.
#
# `run_onchange_`, so it reaches machines that predate it and runs again whenever a pin moves.
# Every step is idempotent, and a failed one fails the apply, so the next apply retries it.
#
# See "Claude Code Language Servers" in CLAUDE.md.

set -euo pipefail

prefix="claude-lsp"

# Bumping a pin is an edit to this file, which is also what makes the next apply install it.
gopls_version="v0.23.0"
typescript_language_server_version="6.0.2"
# typescript-language-server drives tsserver, and TypeScript 7 -- the native port, `latest` since
# July 2026 -- ships none, so the fallback for a project without its own typescript stays on 6.x.
typescript_version="6.0.3"
pyright_version="1.1.414"

# Each plugin, and the function that installs the server it starts.
plugins=(
    "gopls-lsp install_gopls"
    "typescript-lsp install_typescript_language_server"
    "pyright-lsp install_pyright"
)

# The marketplace Anthropic publishes these plugins in, under the ids aifiles' settings.json and
# earlier project-scope installs already use, so no machine runs two copies of one server. A fresh
# profile knows only the built-in directory, hence the `marketplace add`.
marketplace="claude-plugins-official"
marketplace_repo="anthropics/claude-plugins-official"

# ~/.zshenv puts GVM's newest Go and NVM's default Node on PATH, but the first `chezmoi init
# --apply` runs this from bash, where neither was loaded. `npm` may already resolve to a system
# install or Windows' npm through WSL PATH interop, so select NVM's default whenever it exists.
if ! command -v go >/dev/null 2>&1; then
    go_bin="$(printf '%s\n' "$HOME"/.gvm/gos/go*/bin | sort -V | tail -n 1)"
    if [[ -x "$go_bin/go" ]]; then
        PATH="$go_bin:$PATH"
    fi
fi
nvm_script="${NVM_DIR:-$HOME/.nvm}/nvm.sh"
if [[ -s "$nvm_script" ]]; then
    # nvm.sh neither survives `set -u` nor promises `set -e`
    set +eu
    # shellcheck source=/dev/null
    nvm_status=0
    source "$nvm_script"
    nvm use default >/dev/null 2>&1 || nvm_status=$?
    set -eu
    if (( nvm_status != 0 )); then
        echo "[$prefix] ERROR: could not select NVM's default Node.js; refusing to install with another npm" >&2
        exit 1
    fi
fi

# No server lives in a per-version toolchain tree, because ~/.zshenv puts only one version on PATH:
# gopls goes to ~/.local/bin rather than GVM's newest pkgset, and the npm servers to a prefix of
# their own rather than NVM's default Node, reached through links in ~/.local/bin. A plain
# `npm install -g` left both in v24's tree when NVM's default moved to v26 on alien-a51
# (2026-11-02), and nothing ran this script again. Both packages are plain JavaScript, so
# whichever Node is on PATH runs them, and typescript-language-server falls back to the
# `typescript` installed beside it here, which it finds with `require.resolve` from its own path.
npm_prefix="$HOME/.local/share/claude-lsp"

install_gopls() {
    GOBIN="$HOME/.local/bin" go install "golang.org/x/tools/gopls@$gopls_version" || return 1
    [[ -x "$HOME/.local/bin/gopls" ]]
}

# link_server <name>: points ~/.local/bin/<name> at the prefix's copy, with a line when it pointed
# anywhere else, and succeeds only when the link reaches an executable server. Only the servers
# are linked, so the prefix's `tsc` and `pyright` never shadow a Node's own on PATH.
link_server() {
    local target="$npm_prefix/bin/$1" link="$HOME/.local/bin/$1"
    [[ -x "$target" ]] || return 1
    if [[ -e "$link" || -L "$link" ]] && [[ "$(readlink -f "$link" 2>/dev/null)" != "$(readlink -f "$target")" ]]; then
        echo "[$prefix] $link pointed at $(readlink -f "$link" 2>/dev/null || echo '<dangling>'); repointing it at $target" >&2
    fi
    ln -sfn "$target" "$link"
    [[ -x "$link" ]]
}

# NVM's default npm runs the installs, selected above. None of these packages has an install
# script to run.
install_typescript_language_server() {
    npm install -g --prefix "$npm_prefix" --ignore-scripts \
        "typescript-language-server@$typescript_language_server_version" "typescript@$typescript_version" || return 1
    link_server typescript-language-server
}

install_pyright() {
    npm install -g --prefix "$npm_prefix" --ignore-scripts "pyright@$pyright_version" || return 1
    link_server pyright-langserver
}

mkdir -p "$HOME/.local/bin"

failed=()
ready=()
for entry in "${plugins[@]}"; do
    plugin="${entry%% *}"
    if "${entry#* }"; then
        ready+=("$plugin")
    else
        echo "[$prefix] ERROR: could not install the language server $plugin starts; leaving the plugin out" >&2
        failed+=("$plugin")
    fi
done

# A CLAUDE_CONFIG_DIR inherited from a session in another profile would put the plugins in
# that profile instead of the regular one.
unset CLAUDE_CONFIG_DIR

claude="$(command -v claude || true)"
if [[ -z "$claude" && -x "$HOME/.local/bin/claude" ]]; then
    claude="$HOME/.local/bin/claude"
fi

if [[ -z "$claude" ]]; then
    echo "[$prefix] ERROR: claude is not installed, so no plugin was" >&2
    failed+=("${ready[@]}")
elif ! "$claude" plugin marketplace add "$marketplace_repo" </dev/null; then
    echo "[$prefix] ERROR: could not add the $marketplace marketplace" >&2
    failed+=("${ready[@]}")
else
    # No -y, and no terminal: none of these plugins runs a command to install, and one that
    # started to should stop here for a person instead of running unattended.
    for plugin in "${ready[@]}"; do
        if ! "$claude" plugin install "$plugin@$marketplace" --scope user </dev/null; then
            failed+=("$plugin")
        fi
    done
fi

if (( ${#failed[@]} > 0 )); then
    echo "[$prefix] ERROR: not set up: ${failed[*]}; the next apply retries" >&2
    exit 1
fi

echo "[$prefix] gopls $gopls_version, typescript-language-server $typescript_language_server_version and pyright $pyright_version with their plugins; restart Claude Code to load them" >&2
