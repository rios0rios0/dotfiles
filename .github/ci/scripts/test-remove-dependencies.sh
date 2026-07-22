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

if [ ! -f "$LIB" ]; then
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

    local output
    if output=$(HOME="$case_home" bash "$case_script" 2>&1); then
        echo "[test-remove-dependencies] PASS: $description" >&2
    else
        echo "[test-remove-dependencies] FAIL: $description" >&2
        [ -n "$output" ] && echo "$output" >&2
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

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-remove-dependencies] all dependency removal tests passed" >&2
fi

exit $EXIT_CODE
