#!/bin/bash
set -euo pipefail

# Exercises the NVM block of dot_zshenv.tmpl, which decides which Node version
# every shell on the machine gets.
#
# The property under test is agreement with NVM itself. The dependency installer
# runs the real `nvm`, and `npm install -g` writes into whichever version that
# leaves active -- so when this block picks a different one, every npm-installed
# CLI (`codex`, `sentry`, Claude Code) is installed correctly and still missing
# from PATH, with nothing anywhere reporting an error. The case that produced
# that in practice is first below: a machine holding both an LTS and a newer
# Current release, where "newest installed" and "what `default` points at" differ.
#
# Cases run under zsh, the shell that sources this file in production.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ZSHENV_TMPL="$REPO_ROOT/dot_zshenv.tmpl"
EXIT_CODE=0
CASE_INDEX=0

echo "[test-nvm-resolution] testing NVM version resolution in dot_zshenv.tmpl..." >&2

if ! command -v zsh >/dev/null 2>&1; then
    echo "[test-nvm-resolution] FAIL: zsh not installed" >&2
    exit 1
fi

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# The NVM block runs before the platform conditionals, so it carries no Go
# template directives and can be run standalone the way zsh runs it on every
# shell start. Both checks below fail loudly if the block is renamed or moved
# under a conditional, rather than silently testing nothing.
awk '/^# NVM - Node.js version manager/ { found = 1 }
     found && /^\{\{- if ne \.chezmoi\.os "android" \}\}/ { exit }
     found' "$ZSHENV_TMPL" > "$SANDBOX/nvm.zsh"

if ! grep -q 'nvmRoot/alias/default' "$SANDBOX/nvm.zsh"; then
    echo "[test-nvm-resolution] FAIL: no NVM alias block found in dot_zshenv.tmpl" >&2
    exit 1
fi
if grep -q '{{' "$SANDBOX/nvm.zsh"; then
    echo "[test-nvm-resolution] FAIL: the NVM block in dot_zshenv.tmpl now contains template directives" >&2
    exit 1
fi

# Builds a fake NVM root: `make_nvm <case-home> <version>...`
make_nvm() {
    local home="$1"
    shift
    local version
    mkdir -p "$home/.nvm/alias"
    for version in "$@"; do
        mkdir -p "$home/.nvm/versions/node/$version/bin"
    done
}

# Writes an alias file, creating the `lts/` subdirectory NVM uses for the
# codename aliases: `set_alias <case-home> <name> <value>`
set_alias() {
    local home="$1"
    local name="$2"
    local value="$3"
    mkdir -p "$(dirname "$home/.nvm/alias/$name")"
    printf '%s\n' "$value" > "$home/.nvm/alias/$name"
}

# Sources the block in a bare zsh with HOME redirected into the sandbox and
# prints the Node bin directory it prepended, or nothing when it left PATH alone.
resolve() {
    local home="$1"
    HOME="$home" PATH=/usr/bin:/bin zsh -fc "
        source '$SANDBOX/nvm.zsh'
        case \"\${PATH%%:*}\" in
            '$home'/*) print -r -- \"\${PATH%%:*}\" ;;
        esac
    " | sed "s|^$home/.nvm/versions/node/||; s|/bin$||"
}

run_case() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    if [ "$actual" = "$expected" ]; then
        echo "[test-nvm-resolution] PASS: $description" >&2
    else
        echo "[test-nvm-resolution] FAIL: $description" >&2
        echo "  expected: '$expected'" >&2
        echo "  actual:   '$actual'" >&2
        EXIT_CODE=1
    fi
}

# Returns through the global $HOME_DIR rather than stdout: a command
# substitution would run the counter in a subshell, so every case would be
# handed the same directory and inherit the previous case's installed versions.
new_home() {
    CASE_INDEX=$((CASE_INDEX + 1))
    HOME_DIR="$SANDBOX/home-$CASE_INDEX"
}

# given an LTS and a newer non-LTS Current release, with `default` on the LTS chain
new_home
make_nvm "$HOME_DIR" v24.21.0 v26.7.0
set_alias "$HOME_DIR" default 'lts/*'
set_alias "$HOME_DIR" 'lts/*' 'lts/krypton'
set_alias "$HOME_DIR" 'lts/krypton' v24.21.0
# when / then the chain wins over the higher version number
run_case "follows the lts/* alias chain past a newer Current release" \
    "v24.21.0" "$(resolve "$HOME_DIR")"

# given a `default` alias holding a bare version number
new_home
make_nvm "$HOME_DIR" v20.18.3 v24.21.0
set_alias "$HOME_DIR" default 20.18.3
# when / then the `v` prefix is supplied and the newer version is not chosen
run_case "resolves a default alias written as a bare version number" \
    "v20.18.3" "$(resolve "$HOME_DIR")"

# given a chain ending on a version that is no longer installed
new_home
make_nvm "$HOME_DIR" v24.21.0
set_alias "$HOME_DIR" default 'lts/*'
set_alias "$HOME_DIR" 'lts/*' 'lts/krypton'
set_alias "$HOME_DIR" 'lts/krypton' v22.0.0
# when / then the shell still gets a Node rather than none
run_case "falls back to the newest installed version when the alias target is gone" \
    "v24.21.0" "$(resolve "$HOME_DIR")"

# given `nvm alias default system`, which means "use the system Node"
new_home
make_nvm "$HOME_DIR" v24.21.0
set_alias "$HOME_DIR" default system
# when / then PATH is left alone instead of falling back to an NVM version
run_case "leaves PATH alone when the default alias is 'system'" \
    "" "$(resolve "$HOME_DIR")"

# given two aliases pointing at each other, which NVM allows
new_home
make_nvm "$HOME_DIR" v24.21.0
set_alias "$HOME_DIR" default alpha
set_alias "$HOME_DIR" alpha beta
set_alias "$HOME_DIR" beta alpha
# when / then the hop budget breaks the loop and the fallback applies
run_case "does not hang on an alias cycle" \
    "v24.21.0" "$(resolve "$HOME_DIR")"

# given an NVM root with no alias at all
new_home
make_nvm "$HOME_DIR" v24.21.0 v26.7.0
# when / then the newest installed version is used
run_case "uses the newest installed version when no default alias exists" \
    "v26.7.0" "$(resolve "$HOME_DIR")"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-nvm-resolution] all cases passed" >&2
fi

exit $EXIT_CODE
