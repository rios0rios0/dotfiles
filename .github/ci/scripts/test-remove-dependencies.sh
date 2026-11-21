#!/bin/bash
set -euo pipefail

# Exercises .chezmoitemplates/lib-remove-dependencies.sh. This library calls
# `rm -rf` unattended on every tombstone change, so the $HOME safety rail and the
# no-op-when-clean behaviour are covered explicitly.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LIB="$REPO_ROOT/.chezmoitemplates/lib-remove-dependencies.sh"
EXIT_CODE=0
CASE_INDEX=0

echo "[test-remove-dependencies] testing dependency removal library..." >&2

if [[ ! -f "$LIB" ]]; then
    echo "[test-remove-dependencies] FAIL: library not found at $LIB" >&2
    exit 1
fi

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# Runs a test case in its own bash process with HOME redirected into the sandbox,
# so the $HOME-scoped safety rail is exercised without touching the real home.
run_case() {
    local description="$1"
    local body="$2"

    CASE_INDEX=$((CASE_INDEX + 1))
    local case_home="$SANDBOX/home-$CASE_INDEX"
    local case_script="$SANDBOX/case-$CASE_INDEX.sh"
    mkdir -p "$case_home"

    {
        echo 'set -euo pipefail'
        echo "source '$LIB'"
        echo "$body"
    } > "$case_script"

    # NVM_DIR too: `npm_global` reads every Node.js under it, and the developer's own is exported.
    local output
    if output=$(HOME="$case_home" NVM_DIR="$case_home/.nvm" bash "$case_script" 2>&1); then
        echo "[test-remove-dependencies] PASS: $description" >&2
    else
        echo "[test-remove-dependencies] FAIL: $description" >&2
        [[ -n "$output" ]] && echo "$output" >&2
        EXIT_CODE=1
    fi
}

run_case "removes a path inside \$HOME" "$(cat <<'CASE'
# given
mkdir -p "$HOME/.doomed"
touch "$HOME/.doomed/config.json"

# when
apply_tombstones "path:$HOME/.doomed" >/dev/null 2>&1

# then
[[ ! -e "$HOME/.doomed" ]]
CASE
)"

run_case "refuses to remove a path outside \$HOME" "$(cat <<'CASE'
# given
outside=$(mktemp -d)
trap 'rm -rf "$outside"' EXIT
touch "$outside/precious.txt"

# when
output=$(apply_tombstones "path:$outside" 2>&1)

# then
[[ -e "$outside/precious.txt" ]]
grep -q 'refusing to remove' <<<"$output"
CASE
)"

run_case "refuses to remove a bare \$HOME" "$(cat <<'CASE'
# given
touch "$HOME/precious.txt"

# when
apply_tombstones "path:$HOME" >/dev/null 2>&1

# then
[[ -e "$HOME/precious.txt" ]]
CASE
)"

run_case "refuses a path that escapes \$HOME via a '..' component" "$(cat <<'CASE'
# given
mkdir -p "$HOME/sub"
touch "$HOME/precious.txt"

# when: satisfies the "$HOME/" prefix check but climbs back out
output=$(apply_tombstones "path:$HOME/sub/../precious.txt" 2>&1)

# then
[[ -e "$HOME/precious.txt" ]]
grep -q 'component' <<<"$output"
CASE
)"

run_case "still removes a legitimate path whose name merely contains dots" "$(cat <<'CASE'
# given
mkdir -p "$HOME/foo..bar"

# when
apply_tombstones "path:$HOME/foo..bar" >/dev/null 2>&1

# then
[[ ! -e "$HOME/foo..bar" ]]
CASE
)"

run_case "reports a failed removal instead of counting it as removed" "$(cat <<'CASE'
# given: a stub npm that reports the package installed but fails to uninstall it
npm() {
    [[ "$1" == "uninstall" ]] && return 1
    return 0
}

# when
output=$(apply_tombstones "npm_global:@example/stuck" 2>&1)

# then
grep -q 'failed to remove' <<<"$output"
! grep -q 'leftover dependency entries' <<<"$output"
CASE
)"

run_case "removes an npm package from every Node.js NVM installed, each with its own npm" "$(cat <<'CASE'
# given: an active npm that does not see the package, and two Node versions whose trees hold it,
# each with a node that runs its npm by deleting the package from --prefix
npm() { return 1; }
for version in v24.0.0 v26.0.0; do
    tree="$NVM_DIR/versions/node/$version"
    mkdir -p "$tree/bin" "$tree/lib/node_modules/@example/tool" "$tree/lib/node_modules/npm/bin"
    : > "$tree/lib/node_modules/npm/bin/npm-cli.js"
    cat > "$tree/bin/node" <<'NODE'
#!/bin/bash
# node <npm-cli.js> uninstall -g --prefix <tree> <package>
[[ "$2" == uninstall ]] && rm -rf "$5/lib/node_modules/$6"
NODE
    chmod +x "$tree/bin/node"
done

# when
output=$(apply_tombstones "npm_global:@example/tool" 2>&1)

# then
[[ ! -e "$NVM_DIR/versions/node/v24.0.0/lib/node_modules/@example/tool" ]]
[[ ! -e "$NVM_DIR/versions/node/v26.0.0/lib/node_modules/@example/tool" ]]
grep -q 'removing npm global package: @example/tool from Node.js v24.0.0' <<<"$output"
grep -q 'removing npm global package: @example/tool from Node.js v26.0.0' <<<"$output"
! grep -q 'failed to remove' <<<"$output"
CASE
)"

run_case "reports an npm package a Node.js tree still holds after its uninstall" "$(cat <<'CASE'
# given: a Node version whose npm exits 0 without removing anything
npm() { return 1; }
tree="$NVM_DIR/versions/node/v24.0.0"
mkdir -p "$tree/bin" "$tree/lib/node_modules/@example/stuck" "$tree/lib/node_modules/npm/bin"
: > "$tree/lib/node_modules/npm/bin/npm-cli.js"
printf '#!/bin/bash\nexit 0\n' > "$tree/bin/node"
chmod +x "$tree/bin/node"

# when
output=$(apply_tombstones "npm_global:@example/stuck" 2>&1)

# then
[[ -e "$tree/lib/node_modules/@example/stuck" ]]
grep -q 'failed to remove' <<<"$output"
CASE
)"

run_case "stays silent when every target is already absent" "$(cat <<'CASE'
# given
absent="$HOME/.never-existed"

# when
output=$(apply_tombstones "path:$absent" 2>&1)

# then
[[ -z "$output" ]]
CASE
)"

run_case "warns on an unknown strategy without skipping later tombstones" "$(cat <<'CASE'
# given
mkdir -p "$HOME/.doomed"

# when
output=$(apply_tombstones "bogus_strategy:whatever" "path:$HOME/.doomed" 2>&1)

# then
grep -q 'unknown removal strategy' <<<"$output"
[[ ! -e "$HOME/.doomed" ]]
CASE
)"

run_case "no-ops when the underlying package manager is unavailable" "$(cat <<'CASE'
# given
export PATH="$HOME/empty-path"

# when
output=$(apply_tombstones "npm_global:@example/absent" "pipx:absent" 2>&1)

# then
[[ -z "$output" ]]
CASE
)"

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-remove-dependencies] all dependency removal tests passed" >&2
fi

exit $EXIT_CODE
