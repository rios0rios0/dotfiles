#!/bin/bash
set -euo pipefail

# Guards the order linux-engineering-detect-kube-config-files.sh gives KUBECONFIG: kubectl takes the
# default context from the first file that sets one, and `kubectl config use-context` writes into
# that file. ~/.kube/config must come first and the extra files must follow sorted by name, never in
# the order `find` returns, which changes whenever a tool rewrites a file. Each case sources the
# loader under a throwaway HOME, in bash and, when it is installed, in zsh (the shell that sources
# it on a workstation).

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LOADER="$REPO_ROOT/dot_scripts/linux-engineering-detect-kube-config-files.sh"
EXIT_CODE=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "[test-kube-config-order] testing the kubeconfig merge order..." >&2

pass() { echo "[test-kube-config-order] PASS: $1" >&2; }
fail() { echo "[test-kube-config-order] FAIL: $1" >&2; EXIT_CODE=1; }

# loaded <shell> <home>: the KUBECONFIG the loader builds under that HOME.
loaded() {
    HOME="$2" "$1" -c 'source "$0" 2>/dev/null; printf "%s" "$KUBECONFIG"' "$LOADER"
}

# new_home <name> <file>...: a HOME whose ~/.kube/config-files holds the files, created in the
# order given so that a creation-order bug would show.
new_home() {
    local home="$WORK/$1"
    shift
    mkdir -p "$home/.kube/config-files"
    local file
    for file in "$@"; do
        printf 'apiVersion: v1\nkind: Config\n' > "$home/.kube/config-files/$file"
    done
    printf '%s' "$home"
}

SHELLS=(bash)
if command -v zsh >/dev/null 2>&1; then
    SHELLS+=(zsh)
fi

for shell in "${SHELLS[@]}"; do
    forward="$(new_home "$shell-forward" "a.yml" "b.yaml" "c.yaml")"
    backward="$(new_home "$shell-backward" "c.yaml" "b.yaml" "a.yml")"
    printf 'apiVersion: v1\nkind: Config\n' > "$forward/.kube/config"
    printf 'apiVersion: v1\nkind: Config\n' > "$backward/.kube/config"

    want="$forward/.kube/config:$forward/.kube/config-files/a.yml:$forward/.kube/config-files/b.yaml:$forward/.kube/config-files/c.yaml"
    got="$(loaded "$shell" "$forward")"
    if [[ "$got" == "$want" ]]; then
        pass "$shell: ~/.kube/config first, then the extra files sorted by name"
    else
        fail "$shell: expected '$want', got '$got'"
    fi

    got_backward="$(loaded "$shell" "$backward")"
    if [[ "${got_backward//$backward/HOME}" == "${got//$forward/HOME}" ]]; then
        pass "$shell: the order does not depend on the order the files were created in"
    else
        fail "$shell: creation order changed the result: '$got_backward'"
    fi

    bare="$(new_home "$shell-bare" "z.yaml" "m.yaml")"
    got="$(loaded "$shell" "$bare")"
    if [[ "$got" == "$bare/.kube/config-files/m.yaml:$bare/.kube/config-files/z.yaml" ]]; then
        pass "$shell: without ~/.kube/config the first sorted file comes first"
    else
        fail "$shell: without ~/.kube/config, got '$got'"
    fi

    mixed="$(new_home "$shell-mixed" "with space.yaml" "notes.txt")"
    mkdir -p "$mixed/.kube/config-files/folder.yaml"
    got="$(loaded "$shell" "$mixed")"
    if [[ "$got" == "$mixed/.kube/config-files/with space.yaml" ]]; then
        pass "$shell: a name with a space stays whole; other files and *.yaml folders stay out"
    else
        fail "$shell: expected only 'with space.yaml', got '$got'"
    fi
done

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-kube-config-order] all kubeconfig order tests passed" >&2
fi
exit $EXIT_CODE
