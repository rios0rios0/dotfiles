#!/bin/bash
set -euo pipefail

# Tests Docker's zsh completion in dot_zshrc.tmpl. Docker Desktop's WSL integration links its own
# `_docker` into /usr/share/zsh/vendor-completions, pointing at a mount that exists only while Docker
# Desktop runs, and compinit opens every completion file when it builds its dump: a new machine's
# first shell printed `compinit:533: no such file or directory` for that link whenever Docker Desktop
# was not up yet. The rendered .zshrc therefore installs docker/cli's `_docker` as a zinit completion,
# never sourced, before Oh My Zsh runs compinit and whatever docker answers; Termux gets none.
#
# compinit itself is then run in a bare zsh against a dangling `_docker`: alone, it fails as that first
# shell did; behind a `_docker` in an earlier fpath directory, where zinit puts its completions, it is
# never opened.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-docker-completion] testing Docker's zsh completion in dot_zshrc.tmpl..." >&2

pass() { echo "[test-docker-completion] PASS: $1" >&2; }
fail() { echo "[test-docker-completion] FAIL: $1" >&2; EXIT_CODE=1; }

for tool in chezmoi zsh; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[test-docker-completion] FAIL: $tool not installed" >&2
        exit 1
    fi
done

URL='https://github.com/docker/cli/blob/master/contrib/completion/zsh/_docker'
SNIPPET="zinit snippet \"$URL\""
ICE='zinit ice as"completion"'
OMZ='source $ZSH/oh-my-zsh.sh'

# dot_zshrc.tmpl reads nothing but .chezmoi and, on Termux, deviceName, so a config of its own keeps
# the host's out of the render
cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
data:
  deviceName: "testdevice"
EOF

render() {
    chezmoi execute-template --config "$TMP/chezmoi.yaml" \
        --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" < "$REPO_ROOT/dot_zshrc.tmpl"
}

if ! linux_zshrc="$(render linux)" || ! android_zshrc="$(render android)"; then
    fail "dot_zshrc.tmpl does not render"
    exit 1
fi

# The snippet: once, as a whole line of its own, so no `command -v docker` guard can sit around it
# (the zshrc indents every block it guards)
mentions="$(grep -c -F "$URL" <<<"$linux_zshrc" || true)"
if [[ "$mentions" -eq 1 ]] && grep -q -x -F "$SNIPPET" <<<"$linux_zshrc"; then
    pass "linux: the snippet is loaded once, unguarded"
else
    fail "linux: expected the one line '$SNIPPET', found: $(grep -n -F "$URL" <<<"$linux_zshrc" || echo none)"
fi

snippet_line="$(grep -n -F "$URL" <<<"$linux_zshrc" | cut -d: -f1 | head -1 || true)"
if [[ -z "$snippet_line" ]]; then
    fail "linux: the rendered .zshrc does not load Docker's completion"
else
    # Its ice, on the line right before it: a bare `zinit snippet` sources the file, which ends by
    # calling `_docker` outside the completion system
    ice="$(sed -n "$((snippet_line - 1))p" <<<"$linux_zshrc")"
    if [[ "$ice" == "$ICE" ]]; then
        pass "linux: the snippet is installed as a completion, never sourced"
    else
        fail "linux: the line before the snippet is '$ice', not '$ICE'"
    fi

    omz_line="$(grep -n -x -F "$OMZ" <<<"$linux_zshrc" | cut -d: -f1 | head -1 || true)"
    if [[ -n "$omz_line" ]] && (( snippet_line < omz_line )); then
        pass "linux: the completion is in place before Oh My Zsh runs compinit"
    else
        fail "linux: the snippet (line $snippet_line) has to come before '$OMZ' (line ${omz_line:-missing})"
    fi
fi

if grep -q '_docker' <<<"$android_zshrc"; then
    fail "android: the rendered .zshrc loads Docker's completion: $(grep -n '_docker' <<<"$android_zshrc" | head -3)"
else
    pass "android: no Docker completion"
fi

# compinit against Docker Desktop's link while Docker Desktop is stopped. Each run gets a dump of its
# own, so each builds one from scratch, as a first shell does; -u keeps the runner's umask from
# getting these directories set aside as insecure.
mkdir -p "$TMP/vendor-completions" "$TMP/zinit-completions"
ln -s "$TMP/docker-desktop-stopped/_docker" "$TMP/vendor-completions/_docker"
printf '#compdef docker dockerd\n' > "$TMP/snippet-_docker"
ln -s "$TMP/snippet-_docker" "$TMP/zinit-completions/_docker"
COMPINIT='fpath=("$@" $fpath); autoload -Uz compinit; compinit -u -d "$DUMP"; print -r -- "docker=$_comps[docker]"'

out="$(DUMP="$TMP/dump-alone" zsh -fc "$COMPINIT" zsh "$TMP/vendor-completions" 2>&1 || true)"
if grep -qF "no such file or directory: $TMP/vendor-completions/_docker" <<<"$out" &&
    grep -qx 'docker=' <<<"$out"; then
    pass "compinit: a dangling _docker on its own fails to open, as on a new machine's first shell"
else
    fail "compinit: a dangling _docker on its own should fail to open and leave docker unbound: $out"
fi

out="$(DUMP="$TMP/dump-behind" zsh -fc "$COMPINIT" zsh "$TMP/zinit-completions" "$TMP/vendor-completions" 2>&1 || true)"
if [[ "$out" == "docker=_docker" ]]; then
    pass "compinit: a dangling _docker behind zinit's copy is never opened, and docker is bound"
else
    fail "compinit: with zinit's _docker first, expected only 'docker=_docker': $out"
fi

exit "$EXIT_CODE"
