#!/bin/bash
set -euo pipefail

# Tests the Sentry CLI setup scripts and .chezmoitemplates/lib-sentry-cli.sh, which they share. An
# older CLI must be raised to the version `sentry-ds` needs before the setup runs, and a CLI that
# stays older must fail the script, so that chezmoi re-runs it on the next apply: on such a CLI,
# `sentry-ds` silently runs on the personal login. Both scripts are rendered and run against a stub
# `sentry` on a PATH that holds nothing else, so no CLI, npm or network is needed.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LIB="$REPO_ROOT/.chezmoitemplates/lib-sentry-cli.sh"
EXIT_CODE=0
CASE_INDEX=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-sentry-setup] testing the Sentry CLI setup scripts and lib-sentry-cli.sh..." >&2

pass() { echo "[test-sentry-setup] PASS: $1" >&2; }
fail() { echo "[test-sentry-setup] FAIL: $1" >&2; EXIT_CODE=1; }

check() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$description"
    else
        fail "$description"
        echo "  expected: '$expected'" >&2
        echo "  actual:   '$actual'" >&2
    fi
}

if ! command -v chezmoi >/dev/null 2>&1; then
    echo "[test-sentry-setup] FAIL: chezmoi not installed" >&2
    exit 1
fi
BASH_BIN="$(type -P bash)"

# --- the version comparison ----------------------------------------------------------------------

at_least() {
    bash -c 'source "$1"; sentry_cli_version_at_least "$2" "$3" && echo yes || echo no' _ "$LIB" "$1" "$2"
}
check "the floor itself is enough" "yes" "$(at_least 0.47.0 0.47.0)"
check "a newer patch is enough" "yes" "$(at_least 0.47.1 0.47.0)"
check "an older minor is not" "no" "$(at_least 0.46.9 0.47.0)"
check "an older patch is not" "no" "$(at_least 0.47.0 0.47.1)"
check "parts compare as numbers, not as text" "yes" "$(at_least 0.100.0 0.47.0)"
check "a newer major is enough whatever its minor" "yes" "$(at_least 1.0.0 0.47.0)"

# --- the setup scripts ---------------------------------------------------------------------------

# A Sentry CLI whose version lives in $STUB/version, missing when it reports none. `cli upgrade`
# writes $UPGRADE_TO there, or fails when UPGRADE_FAILS is set. Every call goes to $STUB/calls.
# Builtins only: the scripts run with nothing else on PATH.
mkdir -p "$TMP/bin" "$TMP/empty"
cat > "$TMP/bin/sentry" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB/calls"
if [[ "$1" == --version ]]; then
    [[ -s "$STUB/version" ]] || exit 1
    echo "$(< "$STUB/version")"
elif [[ "$1 $2" == "cli upgrade" ]]; then
    [[ -z "${UPGRADE_FAILS:-}" ]] || exit 1
    [[ -z "${UPGRADE_TO:-}" ]] || echo "$UPGRADE_TO" > "$STUB/version"
fi
exit 0
EOF
chmod +x "$TMP/bin/sentry"

cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
data:
  deviceName: "testdevice"
EOF

# Starts a case with the stub reporting a version, or none for "": `new_case <version>`. Returns
# through the globals $CASE_STUB and $CASE_HOME rather than stdout, since a command substitution
# would run the counter in a subshell and hand every case the same directory.
new_case() {
    CASE_INDEX=$((CASE_INDEX + 1))
    CASE_STUB="$TMP/case-$CASE_INDEX"
    CASE_HOME="$CASE_STUB/home"
    mkdir -p "$CASE_HOME"
    : > "$CASE_STUB/calls"
    [[ -z "$1" ]] || echo "$1" > "$CASE_STUB/version"
}

# Runs a rendered setup script in the current case: `run_case <script> <path-dir> [VAR=value...]`.
# Leaves the status in $STATUS, stderr in $TMP/err, and the stub's calls joined by `|` in $CALLS.
run_case() {
    local script="$1" path_dir="$2"
    shift 2
    STATUS=0
    env -u NVM_DIR -u XDG_CONFIG_HOME HOME="$CASE_HOME" PATH="$path_dir" STUB="$CASE_STUB" "$@" \
        "$BASH_BIN" "$script" > /dev/null 2> "$TMP/err" || STATUS=$?
    CALLS="$(tr '\n' '|' < "$CASE_STUB/calls")"
}

# Both at once, for the cases that need nothing in between: `run_setup <script> <path-dir> <version>
# [VAR=value...]`
run_setup() {
    new_case "$3"
    run_case "$1" "$2" "${@:4}"
}

for platform in linux-007 android-006; do
    script="$TMP/$platform.sh"
    if ! chezmoi execute-template --config "$TMP/chezmoi.yaml" \
        < "$REPO_ROOT/.chezmoiscripts/run_onchange_after_$platform-setup-sentry-cli.sh.tmpl" > "$script"; then
        fail "$platform: the setup script does not render"
        continue
    fi

    # given a CLI at the floor
    # when / then it is not upgraded, and the setup runs
    run_setup "$script" "$TMP/bin" 0.47.0
    check "$platform: leaves a CLI at the floor alone and runs the setup" \
        "0 --version|cli setup --no-modify-path|" "$STATUS $CALLS"

    # given an older CLI whose upgrade succeeds
    # when / then it is upgraded first, checked again, and the setup runs
    run_setup "$script" "$TMP/bin" 0.46.0 UPGRADE_TO=0.47.2
    check "$platform: upgrades an older CLI before the setup" \
        "0 --version|cli upgrade|--version|cli setup --no-modify-path| yes" \
        "$STATUS $CALLS $(grep -q 'upgraded the Sentry CLI to 0.47.2' "$TMP/err" && echo yes || echo no)"

    # given an older CLI whose upgrade fails
    # when / then the script fails before the setup, so chezmoi runs it again on the next apply
    run_setup "$script" "$TMP/bin" 0.46.0 UPGRADE_FAILS=1
    check "$platform: fails when the upgrade fails" \
        "1 --version|cli upgrade| yes" \
        "$STATUS $CALLS $(grep -q 'ERROR: sentry cli upgrade failed' "$TMP/err" && echo yes || echo no)"

    # given an upgrade that succeeds without changing the CLI on PATH, as when a standalone binary
    # sits ahead of the one that was upgraded
    # when / then the script still fails, naming the version it found
    run_setup "$script" "$TMP/bin" 0.46.0 UPGRADE_TO=0.46.0
    check "$platform: fails when the CLI on PATH is still older after the upgrade" \
        "1 --version|cli upgrade|--version| yes" \
        "$STATUS $CALLS $(grep -q 'still 0.46.0 after sentry cli upgrade' "$TMP/err" && echo yes || echo no)"

    # given a CLI that reports no version
    # when / then it is treated as older and upgraded
    run_setup "$script" "$TMP/bin" "" UPGRADE_TO=0.47.0
    check "$platform: upgrades a CLI that reports no version" \
        "0 --version|cli upgrade|--version|cli setup --no-modify-path|" "$STATUS $CALLS"

    # given no CLI at all
    # when / then the setup is skipped with a warning and the apply goes on
    run_setup "$script" "$TMP/empty" 0.46.0
    check "$platform: skips with a warning when no CLI is installed" \
        "0  yes" "$STATUS $CALLS $(grep -q 'WARN: sentry is not installed' "$TMP/err" && echo yes || echo no)"
done

# given the CLI only under NVM's Node versions, as in the bash that starts the first apply on Linux
new_case 0.46.0
mkdir -p "$CASE_HOME/.nvm/versions/node/v24.0.0/bin"
ln -s "$TMP/bin/sentry" "$CASE_HOME/.nvm/versions/node/v24.0.0/bin/sentry"
# when the Linux script runs
run_case "$TMP/linux-007.sh" "$TMP/empty" UPGRADE_TO=0.47.0
# then it finds the CLI there and holds it at the floor too
check "linux-007: finds the CLI under NVM and upgrades it there" \
    "0 --version|cli upgrade|--version|cli setup --no-modify-path|" "$STATUS $CALLS"

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-sentry-setup] all cases passed" >&2
fi

exit $EXIT_CODE
