#!/bin/bash
set -euo pipefail

# Tests the hook that fills ~/.claude and ~/.config/opencode from aifiles after every apply:
# run_after_linux-014-sync-aifiles.sh.tmpl and run_after_android-008-sync-aifiles.sh.tmpl, whose
# body is .chezmoitemplates/lib-aifiles-sync.sh. Both are rendered with a throwaway identity in place
# of aifiles' key. `aisync` is a stub that records every call and acts out `init` and `pull`, and the
# remote is a local bare repository, so the clone, its checks and `git ls-remote` run for real while
# nothing reaches GitHub or 1Password. Covers the first sync (the backup, aifiles winning, the
# replaced files named), the steady state, the unchanged no-op, every failure only warning, the
# version floor on both platforms, the key on both platforms, the SSH command, and that nothing
# ever pushes.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0
# What every forced pull logs: the sync keeps aifiles' side whenever both sides changed.
PULLED='pull --force --prefer remote$'

pass() { echo "[test-aifiles-sync] PASS: $1" >&2; }
fail() { echo "[test-aifiles-sync] FAIL: $1" >&2; EXIT_CODE=1; }

echo "[test-aifiles-sync] testing the aisync hook..." >&2

for tool in age-keygen chezmoi git jq tar sha256sum timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[test-aifiles-sync] SKIP: needs $tool" >&2
        exit 0
    fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

age-keygen -o "$TMP/aifiles.id" 2>/dev/null
age-keygen -o "$TMP/other.id" 2>/dev/null
RECIPIENT="$(age-keygen -y "$TMP/aifiles.id")"
SECRET_LINE="$(grep '^AGE-SECRET-KEY-1' "$TMP/aifiles.id")"

# git reads only this file, never the machine's own config (signing, hooks), here and in the hook,
# which finds WSL's ssh.exe there.
printf '[core]\n\tsshCommand = ssh.exe\n' >"$TMP/gitconfig"
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1

# The remote: a bare repository whose path ends like aifiles' URL, with a tracked config.yaml and
# both branches the hook asks `ls-remote` about.
REMOTE="$TMP/remote/rios0rios0/aifiles.git"
git init -q --bare "$REMOTE"
git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
git init -q "$TMP/work"
echo "sources: []" >"$TMP/work/config.yaml"
printf '.aisync/*\n' >"$TMP/work/.gitignore"
git -C "$TMP/work" add config.yaml .gitignore
git -C "$TMP/work" -c user.name=t -c user.email=t@t commit -q -m init
git -C "$TMP/work" push -q "$REMOTE" HEAD:refs/heads/main HEAD:refs/heads/transcripts
advance_remote() {
    echo "# $RANDOM" >>"$TMP/work/config.yaml"
    git -C "$TMP/work" -c user.name=t -c user.email=t@t commit -q -am more
    git -C "$TMP/work" push -q "$REMOTE" HEAD:refs/heads/main
}

# aisync stub: logs each call (and the SSH command it was given), reports $AISYNC_VERSION_FILE's
# version, and acts out the commands the hook runs. init clones the bare remote and rewrites
# config.yaml as the real one does; pull writes aisync's manifest and conversation state, takes
# aifiles' settings.json on --prefer remote, and prints the real summary lines.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/aisync" <<'STUB'
#!/bin/bash
echo "$*" >>"$AISYNC_LOG"
echo "${GIT_SSH_COMMAND:-}" >>"$AISYNC_SSH_LOG"
repo="$HOME/.config/aisync/repo"
args=()
while (($#)); do
    case "$1" in
        --use-system-git) shift ;;
        --repo) repo="$2"; shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
case "${args[0]}" in
    version) echo "aisync $(cat "$AISYNC_VERSION_FILE")" ;;
    self-update)
        [[ "${AISYNC_UPDATE_FAIL:-}" == 1 ]] && exit 1
        echo "${AISYNC_UPDATE_TO:-1.6.0}" >"$AISYNC_VERSION_FILE"
        ;;
    init)
        if [[ "${AISYNC_INIT_FAIL:-}" == 1 ]]; then
            mkdir -p "$repo/.git" && exit 1
        fi
        git clone -q "$AISYNC_REMOTE" "$repo" || exit 1
        echo "tools: {}" >>"$repo/config.yaml"
        mkdir -p "$repo/.aisync" && echo '{}' >"$repo/.aisync/state.json"
        ;;
    pull)
        code="${AISYNC_PULL_EXIT:-0}"
        ((code)) && exit "$code"
        # like aisync, a tool whose directory does not exist is skipped
        if [[ -d "$HOME/.claude" ]]; then
            if [[ " ${args[*]} " == *" --prefer remote "* ]]; then
                echo '{"from": "aifiles"}' >"$HOME/.claude/settings.json"
            fi
            mkdir -p "$HOME/.claude/rules" && echo "from aifiles" >"$HOME/.claude/rules/new.md"
            echo '{}' >"$HOME/.claude/.aisync-manifest.json"
        fi
        mkdir -p "$repo/.aisync" && echo '{}' >"$repo/.aisync/transcripts-base.json"
        conflicts=""
        [[ "${AISYNC_CONFLICTS:-}" == 1 ]] && conflicts=", 1 conflict(s) skipped"
        echo "Personal files: 0 sent to the repo, 2 received, 0 deleted here, 0 deleted in the repo$conflicts."
        echo "Conversations: 0 sent, 3 received, 0 deleted here, 0 deleted in the snapshot, 0 expired."
        echo "Pull complete."
        ;;
    *) exit 64 ;;
esac
STUB
chmod +x "$TMP/bin/aisync"

# op stub for chezmoi's own 1Password calls while rendering the Android script; `read` serves
# $OP_SERVE, aifiles' identity unless a case says otherwise.
cat >"$TMP/bin/op" <<'STUB'
#!/bin/sh
while [ "${1:-}" = "--session" ]; do shift 2; done
case "$1" in
    account) echo '[{"shorthand":"my","url":"https://my.1password.com","email":"t@example.com","user_uuid":"u","account_uuid":"a"}]' ;;
    signin) echo "token" ;;
    read) cat "$OP_SERVE" ;;
    *) echo '{}' ;;
esac
STUB
chmod +x "$TMP/bin/op"

printf 'sourceDir: "%s"\nonePassword:\n  command: "%s"\n' "$REPO_ROOT" "$TMP/bin/op" >"$TMP/chezmoi.yaml"
OVERRIDE="$(jq -nc --arg r "$RECIPIENT" \
    '{ageKeys: {aisync: {recipient: $r, privateKey: "op://Private/test-aisync/private key"}}}')"

# render <platform> <output>: the platform's script, with the sandbox as HOME, so the Android
# template looks for the key where the cases put it.
render() {
    local platform="$1" output="$2"
    local template="$REPO_ROOT/.chezmoiscripts/run_after_linux-014-sync-aifiles.sh.tmpl"
    [[ "$platform" == android ]] && template="$REPO_ROOT/.chezmoiscripts/run_after_android-008-sync-aifiles.sh.tmpl"
    HOME="$TMP/home" OP_SERVE="${OP_SERVE:-$TMP/aifiles.id}" PATH="$TMP/bin:$PATH" \
        chezmoi execute-template --config "$TMP/chezmoi.yaml" --override-data "$OVERRIDE" <"$template" >"$output"
    bash -n "$output" || fail "the rendered $platform script is not valid bash"
}

export AISYNC_LOG="$TMP/aisync.log" AISYNC_SSH_LOG="$TMP/ssh.log" AISYNC_VERSION_FILE="$TMP/version"
export AISYNC_REMOTE="$REMOTE"

# reset: a machine that never synced, holding a few local files in aisync's scope (and two that
# are not), aifiles' key, and aisync 1.6.0.
reset() {
    rm -rf "${TMP:?}/home" "$TMP/tmp"
    mkdir -p "$TMP/home/.claude/skills/sentry-cli" "$TMP/home/.claude/skills/synced/x" \
        "$TMP/home/.claude/projects/-p/memory" "$TMP/home/.config/opencode" "$TMP/home/.config/aisync" \
        "$TMP/tmp"
    echo '{"local": true}' >"$TMP/home/.claude/settings.json"
    echo "local skill" >"$TMP/home/.claude/skills/sentry-cli/SKILL.md"
    echo "downloaded" >"$TMP/home/.claude/skills/synced/x/SKILL.md"
    echo "local memory" >"$TMP/home/.claude/projects/-p/memory/MEMORY.md"
    echo '{}' >"$TMP/home/.config/opencode/opencode.json"
    cp "$TMP/aifiles.id" "$TMP/home/.config/aisync/key.txt"
    echo "1.6.0" >"$AISYNC_VERSION_FILE"
    : >"$AISYNC_LOG"
    : >"$AISYNC_SSH_LOG"
}

# run <script>: the rendered hook against the sandbox. PATH is the stubs and the system's own
# directories only, so the real aisync in ~/.local/bin can never answer.
run() {
    local script="$1" rc=0
    HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" TMPDIR="$TMP/tmp" bash "$script" >"$TMP/out" 2>&1 || rc=$?
    echo "$rc"
}
pulls() { grep -c '^--use-system-git --repo .* pull' "$AISYNC_LOG" || true; }
repo="$TMP/home/.config/aisync/repo"
marker="$TMP/home/.cache/aifiles-sync/synced-refs"

render linux "$TMP/linux.sh"

# given a machine that never synced
reset
# when / then: aifiles is cloned through the personal key's alias with system git, config.yaml is
# put back after init rewrote it, and the first pull lets aifiles win
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 && -d "$repo/.git" && -z "$(git -C "$repo" status --porcelain)" ]] &&
    grep -q '^--use-system-git --repo .*/repo\.[^ ]* init --remote-url git@github.com-mine:rios0rios0/aifiles\.git$' "$AISYNC_LOG" &&
    grep -q "$PULLED" "$AISYNC_LOG" && grep -q 'in sync with aifiles' "$TMP/out"; then
    pass "a first apply clones aifiles and pulls with --prefer remote, leaving the clone clean"
else
    fail "first sync: rc=$rc, $(cat "$TMP/out"), calls: $(cat "$AISYNC_LOG")"
fi
backup="$(find "$TMP/tmp" -name before.tar.gz)"
if [[ -n "$backup" && "$(stat -c '%a' "$backup")" == 600 && "$(stat -c '%a' "${backup%/*}")" == 700 ]] &&
    tar -tzf "$backup" | grep -qx '.claude/settings.json' && tar -tzf "$backup" | grep -qx '.claude/skills/sentry-cli/SKILL.md' &&
    tar -tzf "$backup" | grep -qx '.claude/projects/-p/memory/MEMORY.md' &&
    ! tar -tzf "$backup" | grep -q 'synced\|opencode.json'; then
    pass "the first sync backs up what it may replace to a private directory in \$TMPDIR, and nothing else"
else
    fail "first-sync backup: ${backup:-none}, $(tar -tzf "$backup" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q "replaced 1 local file(s), kept in $backup: .claude/settings.json$" "$TMP/out" &&
    [[ "$(tar -xzOf "$backup" .claude/settings.json)" == '{"local": true}' ]]; then
    pass "the files aifiles replaced are named, and the backup holds their old content"
else
    fail "replaced files: $(cat "$TMP/out")"
fi
if [[ -d "$TMP/home/.claude/projects" && -f "$marker" && ! -e "$TMP/home/.cache/aifiles-sync/first-sync" ]] &&
    [[ "$(stat -c '%a' "$TMP/home/.cache/aifiles-sync")" == 700 && "$(stat -c '%a' "$TMP/home/.cache/aifiles-sync/last-pull.log")" == 600 ]]; then
    pass "a finished first sync leaves its marker and a private log"
else
    fail "after the first sync: $(ls -la "$TMP/home/.cache/aifiles-sync" 2>&1)"
fi
if grep -qx 'ssh.exe -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new' "$AISYNC_SSH_LOG"; then
    pass "SSH goes through the git config's sshCommand, and can ask nothing"
else
    fail "SSH command: $(sort -u "$AISYNC_SSH_LOG")"
fi

# given the same machine, and an aifiles that has not moved
# when / then: one ls-remote, no pull
before="$(pulls)"
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 && "$(pulls)" == "$before" ]] && grep -q 'unchanged since the last sync' "$TMP/out"; then
    pass "an unchanged aifiles costs no pull"
else
    fail "unchanged: rc=$rc, $(cat "$TMP/out")"
fi

# given an aifiles that moved
advance_remote
echo '{"local": "edited"}' >"$TMP/home/.claude/settings.json"
# when / then: a plain pull, which settles nothing for the local side and backs nothing up
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 ]] && tail -1 "$AISYNC_LOG" | grep -q 'pull --force$' &&
    [[ "$(find "$TMP/tmp" -name before.tar.gz | wc -l)" == 1 && "$(cat "$TMP/home/.claude/settings.json")" == '{"local": "edited"}' ]]; then
    pass "after the first sync, a pull never prefers a side and backs nothing up"
else
    fail "steady state: rc=$rc, last call: $(tail -1 "$AISYNC_LOG")"
fi

# given an aifiles that moved, and a change on both sides
advance_remote
# when / then: a warning that repeats, because no marker is written
rc="$(AISYNC_CONFLICTS=1 run "$TMP/linux.sh")"
state="$(cat "$marker")"
rc2="$(AISYNC_CONFLICTS=1 run "$TMP/linux.sh")"
if [[ "$rc" == 0 && "$rc2" == 0 && "$(cat "$marker")" == "$state" ]] && grep -q "WARN: .*run 'aisync sync' in a terminal" "$TMP/out" &&
    [[ "$(grep -c 'pull --force$' "$AISYNC_LOG")" -ge 3 ]]; then
    pass "skipped conflicts warn on every apply until settled"
else
    fail "conflicts: rc=$rc/$rc2, $(cat "$TMP/out")"
fi

# given a pull that fails, and one that times out
# when / then: each only warns, and the next apply tries again
rc="$(AISYNC_PULL_EXIT=1 run "$TMP/linux.sh")"
if [[ "$rc" == 0 ]] && grep -q 'WARN: aisync pull exited 1' "$TMP/out"; then
    pass "a failed pull only warns"
else
    fail "failed pull: rc=$rc, $(cat "$TMP/out")"
fi
rc="$(AISYNC_PULL_EXIT=124 run "$TMP/linux.sh")"
if [[ "$rc" == 0 ]] && grep -q 'WARN: aisync pull timed out' "$TMP/out"; then
    pass "a pull that times out only warns"
else
    fail "timed-out pull: rc=$rc, $(cat "$TMP/out")"
fi

# given an aifiles that cannot be reached
git -C "$repo" remote set-url origin "$TMP/gone/rios0rios0/aifiles.git"
# when / then: a warning, and no pull
before="$(pulls)"
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 && "$(pulls)" == "$before" ]] && grep -q 'WARN: aifiles is unreachable' "$TMP/out"; then
    pass "an unreachable aifiles only warns"
else
    fail "unreachable: rc=$rc, $(cat "$TMP/out")"
fi

# given a clone of something else
git -C "$repo" remote set-url origin "$TMP/remote/someone/else.git"
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 ]] && grep -q 'WARN: .* is no clone of rios0rios0/aifiles' "$TMP/out"; then
    pass "a foreign clone is left alone"
else
    fail "foreign clone: rc=$rc, $(cat "$TMP/out")"
fi

# given a first sync that a failed pull interrupted
reset
rc="$(AISYNC_PULL_EXIT=1 run "$TMP/linux.sh")"
# when / then: the next apply is still a first sync, even though aisync wrote its manifest
echo '{}' >"$TMP/home/.claude/.aisync-manifest.json"
rc2="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 && "$rc2" == 0 ]] && tail -1 "$AISYNC_LOG" | grep -q "$PULLED"; then
    pass "an interrupted first sync is finished as a first sync"
else
    fail "interrupted first sync: rc=$rc/$rc2, last call: $(tail -1 "$AISYNC_LOG")"
fi

# given a machine with nothing local in scope
reset
rm -rf "$TMP/home/.claude/settings.json" "$TMP/home/.claude/skills/sentry-cli" "$TMP/home/.claude/projects"
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 && -z "$(find "$TMP/tmp" -name before.tar.gz)" ]] && grep -q 'nothing local overlaps aifiles' "$TMP/out"; then
    pass "a first sync with nothing local backs nothing up"
else
    fail "nothing local: rc=$rc, $(cat "$TMP/out")"
fi

# given SKIP_AIFILES_SYNC=1
reset
rc="$(SKIP_AIFILES_SYNC=1 run "$TMP/linux.sh")"
if [[ "$rc" == 0 && ! -s "$AISYNC_LOG" ]] && grep -q 'skipped: SKIP_AIFILES_SYNC=1' "$TMP/out"; then
    pass "SKIP_AIFILES_SYNC=1 skips the hook"
else
    fail "skip: rc=$rc, $(cat "$AISYNC_LOG")"
fi

# given no aisync, then aisync only in ~/.local/bin
reset
mv "$TMP/bin/aisync" "$TMP/aisync"
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 ]] && grep -q 'WARN: aisync is not installed' "$TMP/out"; then
    pass "a machine without aisync only warns"
else
    fail "no aisync: rc=$rc, $(cat "$TMP/out")"
fi
mkdir -p "$TMP/home/.local/bin"
cp "$TMP/aisync" "$TMP/home/.local/bin/aisync"
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 ]] && grep -q "$PULLED" "$AISYNC_LOG"; then
    pass "aisync is found in ~/.local/bin when PATH lacks it"
else
    fail "~/.local/bin aisync: rc=$rc, $(cat "$TMP/out")"
fi
mv "$TMP/aisync" "$TMP/bin/aisync"

# given an aisync older than the minimum
reset
echo "1.5.13" >"$AISYNC_VERSION_FILE"
# when / then: Linux upgrades it and goes on; a failed upgrade stops before any clone
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 ]] && grep -q '^self-update --force$' "$AISYNC_LOG" && grep -q "$PULLED" "$AISYNC_LOG"; then
    pass "an older aisync is upgraded on Linux before the sync"
else
    fail "upgrade: rc=$rc, $(cat "$TMP/out")"
fi
reset
echo "1.5.13" >"$AISYNC_VERSION_FILE"
rc="$(AISYNC_UPDATE_FAIL=1 run "$TMP/linux.sh")"
if [[ "$rc" == 0 && ! -e "$repo" ]] && grep -q 'WARN: aisync is still 1.5.13' "$TMP/out"; then
    pass "an aisync that cannot be upgraded syncs nothing, and only warns"
else
    fail "failed upgrade: rc=$rc, $(cat "$TMP/out")"
fi
reset
echo "dev" >"$AISYNC_VERSION_FILE"
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 ]] && ! grep -q 'self-update' "$AISYNC_LOG" && grep -q "$PULLED" "$AISYNC_LOG"; then
    pass "a development build is left alone"
else
    fail "dev build: rc=$rc, $(cat "$TMP/out")"
fi

# given no key, another key, and a key without age-keygen's comment
reset
rm "$TMP/home/.config/aisync/key.txt"
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 && ! -e "$repo" ]] && grep -q 'WARN: there is no aisync age key' "$TMP/out"; then
    pass "no key: nothing is cloned, and the hook only warns"
else
    fail "no key: rc=$rc, $(cat "$TMP/out")"
fi
reset
cp "$TMP/other.id" "$TMP/home/.config/aisync/key.txt"
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 && ! -e "$repo" ]] && cmp -s "$TMP/other.id" "$TMP/home/.config/aisync/key.txt" &&
    grep -q 'WARN: .* holds another key' "$TMP/out"; then
    pass "another key is reported and kept"
else
    fail "other key: rc=$rc, $(cat "$TMP/out")"
fi
reset
grep '^AGE-SECRET-KEY-1' "$TMP/aifiles.id" >"$TMP/home/.config/aisync/key.txt"
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 ]] && grep -q 'in sync with aifiles' "$TMP/out"; then
    pass "a key without age-keygen's comment is recognised"
else
    fail "bare key: rc=$rc, $(cat "$TMP/out")"
fi

# given a clone that fails, and a directory in the clone's place
reset
rc="$(AISYNC_INIT_FAIL=1 run "$TMP/linux.sh")"
if [[ "$rc" == 0 && ! -e "$repo" && -z "$(find "$TMP/home/.config/aisync" -name 'repo.*')" ]] &&
    grep -q 'WARN: could not clone git@github.com-mine:rios0rios0/aifiles.git' "$TMP/out"; then
    pass "a failed clone leaves nothing behind, and only warns"
else
    fail "failed clone: rc=$rc, $(ls -a "$TMP/home/.config/aisync"), $(cat "$TMP/out")"
fi
reset
mkdir -p "$repo" && echo "mine" >"$repo/notes"
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 && "$(cat "$repo/notes")" == mine ]] && ! grep -q ' init ' "$AISYNC_LOG" &&
    grep -q 'WARN: .* exists but is no checkout' "$TMP/out"; then
    pass "a directory in the clone's place is left alone"
else
    fail "occupied repo path: rc=$rc, $(cat "$TMP/out")"
fi

# given something nothing in the hook expects to fail: ~/.cache is a file
reset
rm -rf "$TMP/home/.cache" && : >"$TMP/home/.cache"
# when / then: the sync stops there, and the apply still goes on
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 && ! -e "$repo" ]] && grep -q 'WARN: the sync stopped unexpectedly' "$TMP/out"; then
    pass "an unexpected failure stops the sync and only warns"
else
    fail "unexpected failure: rc=$rc, $(cat "$TMP/out")"
fi

# given no ~/.claude at all
reset
rm -rf "$TMP/home/.claude"
rc="$(run "$TMP/linux.sh")"
if [[ "$rc" == 0 && ! -e "$TMP/home/.claude" ]]; then
    pass "~/.claude/projects is created only inside an existing ~/.claude"
else
    fail "no ~/.claude: rc=$rc, $(ls -a "$TMP/home")"
fi

# given Android, where the key comes through chezmoi's template and the minimum is higher
reset
rm "$TMP/home/.config/aisync/key.txt"
render android "$TMP/android.sh"
if grep -qxF "$SECRET_LINE" "$TMP/android.sh"; then
    pass "Android renders the identity into the hook when the device has no key"
else
    fail "Android render without a key carries no identity"
fi
echo "1.7.0" >"$AISYNC_VERSION_FILE"
rc="$(run "$TMP/android.sh")"
if [[ "$rc" == 0 ]] && cmp -s "$TMP/aifiles.id" "$TMP/home/.config/aisync/key.txt" &&
    [[ "$(stat -c '%a' "$TMP/home/.config/aisync/key.txt")" == 600 && "$(stat -c '%a' "$TMP/home/.config/aisync")" == 700 ]] &&
    grep -q 'in sync with aifiles' "$TMP/out"; then
    pass "Android writes the rendered key, 0600 in a 0700 directory, and syncs"
else
    fail "Android key: rc=$rc, $(cat "$TMP/out")"
fi
render android "$TMP/android-with-key.sh"
if ! grep -q '^AGE-SECRET-KEY-1' "$TMP/android-with-key.sh"; then
    pass "Android renders no identity once the key is in place"
else
    fail "Android render with a key still carries an identity"
fi
reset
rm "$TMP/home/.config/aisync/key.txt"
OP_SERVE="$TMP/other.id" render android "$TMP/android-other.sh"
echo "1.7.0" >"$AISYNC_VERSION_FILE"
rc="$(run "$TMP/android-other.sh")"
if [[ "$rc" == 0 && ! -e "$TMP/home/.config/aisync/key.txt" && ! -e "$repo" ]] &&
    [[ -z "$(find "$TMP/home/.config/aisync" -name 'key.txt.*')" ]] && grep -q 'WARN: 1Password returned no age identity' "$TMP/out"; then
    pass "Android refuses an identity for another recipient"
else
    fail "Android wrong identity: rc=$rc, $(cat "$TMP/out")"
fi
reset
echo "1.6.0" >"$AISYNC_VERSION_FILE"
rc="$(run "$TMP/android-with-key.sh")"
if [[ "$rc" == 0 && ! -e "$repo" ]] && ! grep -q 'self-update' "$AISYNC_LOG" &&
    grep -q "WARN: aisync 1.6.0 is older than the 1.7.0 .* rebuild it: (cd ~/Development/github.com/rios0rios0/aisync" "$TMP/out"; then
    pass "Android reports an older aisync with the rebuild command, and never self-updates"
else
    fail "Android floor: rc=$rc, $(cat "$TMP/out")"
fi

# across every run above: the hook only ever ran version, self-update, init and pull
if ! awk '{ for (i = 1; i <= NF; i++) if ($i !~ /^-/ && $(i-1) != "--repo") { print $i; next } }' "$AISYNC_LOG" |
    grep -qvxE 'version|self-update|init|pull'; then
    pass "nothing but version, self-update, init and pull is ever run: no push, sync or source"
else
    fail "unexpected aisync commands: $(cat "$AISYNC_LOG")"
fi

# aisync owns the AI content in ~/.claude and ~/.config/opencode, so chezmoi must manage nothing
# there that aisync syncs, and delete nothing aisync writes -- except the two global instruction
# files whose job moved to the home guide chezmoi writes as ~/AGENTS.md (#283).
claude_entries="$(find "$REPO_ROOT/dot_claude" -mindepth 1 -printf '%f\n' | sort | tr '\n' ' ')"
opencode_entries="$(find "$REPO_ROOT/dot_config/opencode" -mindepth 1 -printf '%f\n' | sort | tr '\n' ' ')"
removed_entries="$(grep -E '^\.(claude|config/opencode)(/|$)' "$REPO_ROOT/.chezmoiremove" | sort | tr '\n' ' ' || true)"
if [[ "$claude_entries" == "executable_statusline-command.sh modify_dot_claude.json modify_settings.json " &&
    "$opencode_entries" == "cli.json opencode.json.tmpl " &&
    "$removed_entries" == ".claude/CLAUDE.md .config/opencode/AGENTS.md " ]]; then
    pass "chezmoi manages only settings.json's merge, the status line and OpenCode's two configs there, and deletes only the two global instruction files"
else
    fail "chezmoi's entries in aisync's directories: dot_claude: $claude_entries; dot_config/opencode: $opencode_entries; .chezmoiremove: $removed_entries"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-aifiles-sync] all aisync hook tests passed" >&2
fi
exit "$EXIT_CODE"
