#!/bin/bash
set -euo pipefail

# Exercises the runtime 1Password loaders in dot_scripts/ together with the cache
# block of dot_zshenv.tmpl.
#
# The property under test is removal: a credential deleted from the vault has to
# leave the shell, not just the cache. Because the value is already exported it
# outlives the cache in the shell that loaded it and in every shell forked from
# that one, so both the reload path and the .zshenv path are covered. The mirror
# image matters just as much — a 1Password outage produces the same "not in the
# response" shape as a deletion and must never unset anything.
#
# Cases run under zsh, the shell that sources these files in production.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/dot_scripts"
ZSHENV_TMPL="$REPO_ROOT/dot_zshenv.tmpl"
EXIT_CODE=0
CASE_INDEX=0

echo "[test-shell-credentials] testing 1Password credential loading and removal..." >&2

if ! command -v zsh >/dev/null 2>&1; then
    echo "[test-shell-credentials] FAIL: zsh not installed" >&2
    exit 1
fi

for script in linux-engineering-op-loader.sh linux-engineering-shell-credentials.sh linux-engineering-workspace-aliases.sh; do
    if [ ! -f "$SCRIPTS_DIR/$script" ]; then
        echo "[test-shell-credentials] FAIL: script not found at $SCRIPTS_DIR/$script" >&2
        exit 1
    fi
done

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# Stands in for the 1Password CLI: emits a device note whose cred:/ws: fields come
# from $FAKE_CREDS and $FAKE_WS ("NAME=VALUE", space separated). $FAKE_OP_FAIL
# makes every call fail, standing in for a locked or unreachable vault.
cat > "$SANDBOX/op" <<'MOCK_OP'
#!/bin/bash
if [ -n "${FAKE_OP_FAIL:-}" ]; then
    echo "[mock-op] 1Password is unreachable" >&2
    exit 1
fi
case "$1" in
    whoami) exit 0 ;;
    signin) echo 'export MOCK_OP_SESSION=1' ;;
    item)
        fields=""
        for entry in ${FAKE_CREDS:-}; do
            fields="$fields{\"label\":\"cred:${entry%%=*}\",\"value\":\"${entry#*=}\"},"
        done
        for entry in ${FAKE_WS:-}; do
            fields="$fields{\"label\":\"ws:${entry%%=*}\",\"value\":\"${entry#*=}\"},"
        done
        printf '{"fields":[%s{"label":"notesPlain","value":""}]}\n' "$fields"
        ;;
esac
MOCK_OP
chmod +x "$SANDBOX/op"

# The cache block is the tail of dot_zshenv.tmpl and carries no Go template
# directives, so it can be run standalone the way zsh runs it on every shell start.
# Both checks below fail loudly if the block is renamed or moved under a
# conditional, rather than silently testing nothing.
awk '/^###### Cached 1Password Credentials/ { found = 1 } found' "$ZSHENV_TMPL" > "$SANDBOX/zshenv-cache.zsh"

if ! grep -q '_op_prune_removed' "$SANDBOX/zshenv-cache.zsh"; then
    echo "[test-shell-credentials] FAIL: no cache-prune block found in dot_zshenv.tmpl" >&2
    exit 1
fi
if grep -q '{{' "$SANDBOX/zshenv-cache.zsh"; then
    echo "[test-shell-credentials] FAIL: cache block in dot_zshenv.tmpl now contains template directives" >&2
    exit 1
fi

# Runs a test case as its own zsh process with HOME redirected into the sandbox.
# `set -e` is deliberately not used: the loaders read variables that are unset on
# a first run, and zsh's errexit would abort on the first such test. Cases assert
# through `_fail` instead, which reports what broke.
run_case() {
    local description="$1"
    local body="$2"

    CASE_INDEX=$((CASE_INDEX + 1))
    local case_home="$SANDBOX/home-$CASE_INDEX"
    local case_script="$SANDBOX/case-$CASE_INDEX.zsh"

    mkdir -p "$case_home/.scripts" "$case_home/.cache" "$case_home/bin"
    cp "$SCRIPTS_DIR"/linux-engineering-op-loader.sh \
        "$SCRIPTS_DIR"/linux-engineering-shell-credentials.sh \
        "$SCRIPTS_DIR"/linux-engineering-workspace-aliases.sh \
        "$case_home/.scripts/"
    cp "$SANDBOX/op" "$case_home/bin/op"
    cp "$SANDBOX/zshenv-cache.zsh" "$case_home/zshenv-cache.zsh"

    {
        echo 'export PATH="$HOME/bin:$PATH"'
        echo 'export CHEZMOI_DEVICE="test-device"'
        echo '_fail() { print -r -- "ASSERT FAILED: $1" >&2; exit 1; }'
        echo "$body"
        # only `_fail` decides the outcome, never the exit status a case happens to trail with
        echo 'exit 0'
    } > "$case_script"

    local output
    if output=$(HOME="$case_home" zsh -f "$case_script" 2>&1); then
        echo "[test-shell-credentials] PASS: $description" >&2
    else
        echo "[test-shell-credentials] FAIL: $description" >&2
        [ -n "$output" ] && echo "$output" >&2
        EXIT_CODE=1
    fi
}

run_case "unsets a credential deleted from 1Password when reloading" "$(cat <<'CASE'
# given
export FAKE_CREDS="KEPT=kept-value GONE=gone-value"
source "$HOME/.scripts/linux-engineering-shell-credentials.sh"
[[ "$GONE" == "gone-value" ]] || _fail "GONE was never exported"

# when
export FAKE_CREDS="KEPT=kept-value"
reload-credentials

# then
[[ -z "${GONE+set}" ]] || _fail "GONE is still set to '$GONE'"
[[ "$KEPT" == "kept-value" ]] || _fail "KEPT was lost"
if grep -q '^export GONE=' "$HOME/.cache/op-credentials.env"; then
  _fail "GONE is still cached"
fi
CASE
)"

run_case "unsets an inherited credential in a shell that only sources the caches" "$(cat <<'CASE'
# given a shell holding both credentials
export FAKE_CREDS="KEPT=kept-value GONE=gone-value"
source "$HOME/.scripts/linux-engineering-shell-credentials.sh"

# and a reload in some other terminal that dropped one of them from the cache
export FAKE_CREDS="KEPT=kept-value"
_OP_RELOAD=1 zsh -fc 'source "$HOME/.scripts/linux-engineering-shell-credentials.sh"' >/dev/null 2>&1
[[ "$GONE" == "gone-value" ]] || _fail "this shell should still hold the stale value"

# when a new terminal starts from this environment and .zshenv loads the caches
output=$(zsh -fc '
  source "$HOME/zshenv-cache.zsh"
  print -r -- "GONE=[${GONE-<unset>}] KEPT=[${KEPT-<unset>}]"
' 2>/dev/null)

# then
[[ "$output" == "GONE=[<unset>] KEPT=[kept-value]" ]] || _fail "new shell reported $output"
CASE
)"

run_case "keeps every credential when 1Password is unreachable" "$(cat <<'CASE'
# given
export FAKE_CREDS="KEPT=kept-value GONE=gone-value"
source "$HOME/.scripts/linux-engineering-shell-credentials.sh"

# when
export FAKE_OP_FAIL=1
reload-credentials

# then a failed fetch must not be read as a deletion
[[ "$GONE" == "gone-value" ]] || _fail "GONE was unset by an unreachable vault"
[[ "$KEPT" == "kept-value" ]] || _fail "KEPT was unset by an unreachable vault"
CASE
)"

run_case "unsets a credential missing from a cache written before manifests existed" "$(cat <<'CASE'
# given a cache in the pre-manifest format, as an older revision left behind
printf 'export KEPT=kept-value\nexport GONE=gone-value\n' > "$HOME/.cache/op-credentials.env"
chmod 600 "$HOME/.cache/op-credentials.env"
source "$HOME/.scripts/linux-engineering-shell-credentials.sh"
[[ "$GONE" == "gone-value" ]] || _fail "the old cache should still be loaded as-is"

# when
export FAKE_CREDS="KEPT=kept-value"
reload-credentials

# then
[[ -z "${GONE+set}" ]] || _fail "GONE is still set to '$GONE'"
[[ "$KEPT" == "kept-value" ]] || _fail "KEPT was lost"
CASE
)"

run_case "leaves variables the loader never exported alone" "$(cat <<'CASE'
# given
export MANUALLY_SET="not-from-1password"
export FAKE_CREDS="KEPT=kept-value"
source "$HOME/.scripts/linux-engineering-shell-credentials.sh"

# when
export FAKE_CREDS=""
reload-credentials

# then
[[ "$MANUALLY_SET" == "not-from-1password" ]] || _fail "an unrelated variable was unset"
[[ -z "${KEPT+set}" ]] || _fail "KEPT should have been removed"
CASE
)"

run_case "removes the alias of a workspace deleted from 1Password" "$(cat <<'CASE'
# given
export FAKE_WS="kept=/tmp/kept gone=/tmp/gone"
source "$HOME/.scripts/linux-engineering-shell-credentials.sh"
source "$HOME/.scripts/linux-engineering-workspace-aliases.sh"
alias gone >/dev/null || _fail "the alias was never created"

# when
export FAKE_WS="kept=/tmp/kept"
reload-credentials

# then
if alias gone >/dev/null; then
  _fail "the alias of a deleted workspace survived"
fi
alias kept >/dev/null || _fail "the alias of a live workspace was removed"
CASE
)"

run_case "keeps the credential cache readable only by its owner" "$(cat <<'CASE'
# given
export FAKE_CREDS="KEPT=kept-value"

# when
source "$HOME/.scripts/linux-engineering-shell-credentials.sh"

# then
mode=$(stat -c %a "$HOME/.cache/op-credentials.env")
[[ "$mode" == "600" ]] || _fail "cache mode is $mode, expected 600"
CASE
)"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-shell-credentials] all cases passed" >&2
fi

exit $EXIT_CODE
