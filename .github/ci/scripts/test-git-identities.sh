#!/bin/bash
set -euo pipefail

# Tests the git identity of each workspace: .chezmoitemplates/lib-git-identities.tmpl, the includeIf
# blocks dot_gitconfig.tmpl renders from it, and the write-git-identities scripts that write
# ~/.config/git/identities/<alias>, all against a mock 1Password serving a device note of its own.
# Covers which ssh: entries become identities (a bad alias, a second item with the same alias, a
# missing field and a line break are skipped), how a ws: field becomes a gitdir condition ($HOME,
# ${HOME} and ~ as ~, one trailing slash, a relative path skipped, a workspace named after no
# identity ignored), the order that lets a workspace inside another win, the platforms that get the
# includes (Linux and Android, not Windows), the writers in a sandbox home (quoting that git reads
# back, an apply that changes nothing saying nothing, a file edited by hand put back, an identity
# taken off the note deleted, a file without the marker kept, the Android script in step with the
# Linux one), and real commits: every repository commits as its workspace's identity, the default
# one outside them, a worktree as its main repository, and a repository's own config still wins.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
LINUX_WRITER="$REPO_ROOT/.chezmoiscripts/run_after_linux-003-write-git-identities.sh.tmpl"
ANDROID_WRITER="$REPO_ROOT/.chezmoiscripts/run_after_android-002-write-git-identities.sh.tmpl"
MARKER="# Written by chezmoi from this device's 1Password note; edits here are overwritten."
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-git-identities] testing the git identity of each workspace..." >&2

pass() { echo "[test-git-identities] PASS: $1" >&2; }
fail() { echo "[test-git-identities] FAIL: $1" >&2; EXIT_CODE=1; }

if ! command -v chezmoi >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "[test-git-identities] FAIL: chezmoi and jq must be on PATH" >&2
    exit 1
fi

# --- A mock 1Password ---------------------------------------------------------------------------

# `op item get <name>` answers with $MOCK_ITEMS/<name>.json, and fails like op for any other name,
# so a template that asks for an item the note does not list fails the render. POSIX sh, because
# chezmoi executes it directly.
cat >"$TMP/op" <<'EOF'
#!/bin/sh
while [ "${1:-}" = "--session" ]; do shift 2; done
case "$1 ${2:-}" in
    "item get") shift 2 ;;
    "account list") echo '[{"shorthand":"my","url":"https://my.1password.com","email":"test@example.com","user_uuid":"test-user-uuid","account_uuid":"test-account-uuid"}]'; exit 0 ;;
    "signin"*) echo "mock-session-token"; exit 0 ;;
    *) echo '{}'; exit 0 ;;
esac
name=""
while [ $# -gt 0 ]; do
    case "$1" in
        --format|--vault|--account) shift; [ $# -gt 0 ] && shift ;;
        *) [ -z "$name" ] && name="$1"; shift ;;
    esac
done
if [ ! -f "$MOCK_ITEMS/$name.json" ]; then
    echo "[ERROR] \"$name\" isn't an item in any vault" >&2
    exit 1
fi
cat "$MOCK_ITEMS/$name.json"
EOF
chmod +x "$TMP/op"

# ssh_item <dir> <title> <alias> <username> <email> <public key>: an SSH Key item. An empty field
# is left out, as 1Password leaves out a field that has no value.
ssh_item() {
    jq -n --arg a "$3" --arg u "$4" --arg e "$5" --arg k "$6" '{fields: ([
        {label: "ssh alias", value: $a}, {label: "ssh username", value: $u},
        {label: "ssh email", value: $e}, {label: "public key", value: $k},
        {label: "private key", value: "fixture-key-placeholder"}, {id: "notesPlain", label: "notesPlain"}
    ] | map(select(.value != "")))}' >"$1/$2.json"
}
# device_note <dir> <notesPlain> [<ws name>=<dir>]...: the device note, with a cred: field that must
# not be taken for anything else.
device_note() {
    local dir="$1" notes="$2" ws
    shift 2
    for ws in "$@"; do printf '%s\n' "$ws"; done |
        jq -R -s --arg notes "$notes" '{fields: ([{id: "notesPlain", label: "notesPlain", value: $notes},
            {label: "cred:TOKEN", value: "fixture-token-placeholder"}] +
            (split("\n") | map(select(. != "") | capture("^(?<n>[^=]*)=(?<v>.*)$") | {label: ("ws:" + .n), value: .v})))}' \
            >"$dir/Device: testdevice.json"
}

# The device note the end-to-end checks run against: four identities, the first being the default
# one, with a workspace for three of them, one inside another, and one for no identity at all.
CLEAN="$TMP/clean"
mkdir -p "$CLEAN"
ssh_item "$CLEAN" "Default Key" default "Default Person" default@example.com "ssh-ed25519 AAAAdefault"
ssh_item "$CLEAN" "Personal Key" personal "Person Al" personal@example.com "ssh-ed25519 AAAApersonal"
ssh_item "$CLEAN" "Work Key" work "Work Person" work@example.org "ssh-rsa AAAAwork"
ssh_item "$CLEAN" "Client Key" client "Client Person" client@example.net "ssh-ed25519 AAAAclient"
device_note "$CLEAN" $'ssh:Default Key\nssh:Personal Key\nssh:Work Key\nssh:Client Key' \
    'personal=$HOME/Development/' \
    'client=~/Development/dev.azure.com/SomeOrg/client-project' \
    'work=${HOME}/Development/dev.azure.com/SomeOrg//' \
    'notes=$HOME/notes/'

# The device note that tries every way an entry can be unusable: a name git must read back with its
# quote and backslash, an alias that is a path, a second item with an alias already taken, an item
# missing its email, a line break in a field, and a workspace that is a relative path.
BAD="$TMP/bad"
mkdir -p "$BAD"
ssh_item "$BAD" "Default Key" default "Default Person" default@example.com "ssh-ed25519 AAAAdefault"
ssh_item "$BAD" "Work Key" work "Work \"Q\" O'Brien \\ backslash" work@example.org "ssh-rsa AAAAwork"
ssh_item "$BAD" "Path Key" "../evil" "Evil" evil@example.com "ssh-ed25519 AAAAevil"
ssh_item "$BAD" "Second Work Key" work "Second" second@example.org "ssh-ed25519 AAAAsecond"
ssh_item "$BAD" "Emailless Key" emailless "Emailless" "" "ssh-ed25519 AAAAemailless"
ssh_item "$BAD" "Broken Key" broken $'Broken\nLine' broken@example.org "ssh-ed25519 AAAAbroken"
device_note "$BAD" $'ssh:Default Key\nssh:Work Key\nssh:Path Key\nssh:Second Work Key\nssh:Emailless Key\nssh:Broken Key' \
    'work=$HOME/Development/dev.azure.com/SomeOrg/' \
    'default=relative/path' \
    'emailless=$HOME/emailless/'

# A device note without a single ssh: entry.
NONE="$TMP/none"
mkdir -p "$NONE"
device_note "$NONE" "" 'work=$HOME/Development/dev.azure.com/SomeOrg/'

printf 'sourceDir: "%s"\nonePassword:\n  command: "%s"\ndata:\n  deviceName: "testdevice"\n' \
    "$REPO_ROOT" "$TMP/op" >"$TMP/chezmoi.yaml"

# chezmoi's data for each platform, with the home folder the rendered files point into. The kernel
# is a literal, so the host that runs this suite never decides which branch renders.
SANDBOX="$TMP/home"
declare -A DATA=(
    [wsl]='{"chezmoi":{"os":"linux","homeDir":"'"$SANDBOX"'","kernel":{"osrelease":"6.18.33.2-microsoft-standard-WSL2","ostype":"Linux","version":"#1 SMP"}}}'
    [metal]='{"chezmoi":{"os":"linux","homeDir":"'"$SANDBOX"'","kernel":{"osrelease":"6.11.0-generic","ostype":"Linux","version":"#1 SMP"}}}'
    [android]='{"chezmoi":{"os":"android","homeDir":"'"$SANDBOX"'","kernel":{"osrelease":"5.15.0-android13","ostype":"Linux","version":"#1 SMP"}}}'
    [windows]='{"chezmoi":{"os":"windows"}}'
)

# render <items> <platform> [<template file>]: the file, or the library's JSON, as chezmoi renders
# it from that device note; chezmoi's warnings go to $TMP/warnings.
render() {
    local items="$1" platform="$2" file="${3:-}"
    if [[ -n "$file" ]]; then
        MOCK_ITEMS="$items" chezmoi execute-template --config "$TMP/chezmoi.yaml" \
            --override-data "${DATA[$platform]}" <"$file" 2>"$TMP/warnings"
    else
        MOCK_ITEMS="$items" chezmoi execute-template --config "$TMP/chezmoi.yaml" \
            --override-data "${DATA[$platform]}" '{{ includeTemplate "lib-git-identities.tmpl" . }}' 2>"$TMP/warnings"
    fi
}

# --- The library ----------------------------------------------------------------------------------

# given the note with every kind of unusable entry
# when
if ! lib="$(render "$BAD" wsl)"; then
    fail "the library does not render: $(cat "$TMP/warnings")"
    lib='{"identities":[],"workspaces":[]}'
fi

# then
[[ "$(jq -r '[.identities[].alias] | join(" ")' <<<"$lib")" == "default work" ]] ||
    fail "the identities must be 'default work', not '$(jq -r '[.identities[].alias] | join(" ")' <<<"$lib")'"
for skipped in '"Path Key": its ssh alias "../evil" is not a plain file name' \
    '"Second Work Key": "Work Key" already has the ssh alias "work"' \
    '"Emailless Key": it needs an ssh username, an ssh email and a public key' \
    '"Broken Key": a line break in its name or fields' \
    'the workspace "default": "relative/path" is neither under ~ nor absolute'; do
    grep -qF -- "[git-identities] WARN: skipped $skipped" "$TMP/warnings" || fail "no warning that it skipped $skipped"
done
[[ "$(jq -c '.workspaces' <<<"$lib")" == '[{"alias":"work","dir":"~/Development/dev.azure.com/SomeOrg/"}]' ]] ||
    fail "only the work workspace may remain, not $(jq -c '.workspaces' <<<"$lib")"
pass "the library skips, with a warning each, an alias that is a path, a taken alias, a missing field, a line break and a relative workspace"

# given the clean note
# when
lib="$(render "$CLEAN" wsl)" || fail "the library does not render the clean note: $(cat "$TMP/warnings")"

# then: ${HOME}, $HOME and ~ all become ~, with one trailing slash, shallowest first; the notes
# workspace, named after no identity, is not there, and nothing was worth a warning
expected='[{"alias":"personal","dir":"~/Development/"},{"alias":"work","dir":"~/Development/dev.azure.com/SomeOrg/"},{"alias":"client","dir":"~/Development/dev.azure.com/SomeOrg/client-project/"}]'
[[ "$(jq -c '.workspaces' <<<"$lib")" == "$expected" ]] ||
    fail "the workspaces must be $expected, not $(jq -c '.workspaces' <<<"$lib")"
if grep -q 'git-identities' "$TMP/warnings"; then
    fail "the clean note must render without a warning: $(grep 'git-identities' "$TMP/warnings")"
fi
pass "the library turns each workspace into a gitdir pattern, shallowest first, and ignores one named after no identity"

# --- The includes in ~/.gitconfig ---------------------------------------------------------------

includes='[includeIf "gitdir:~/Development/"]
    path = ~/.config/git/identities/personal
[includeIf "gitdir:~/Development/dev.azure.com/SomeOrg/"]
    path = ~/.config/git/identities/work
[includeIf "gitdir:~/Development/dev.azure.com/SomeOrg/client-project/"]
    path = ~/.config/git/identities/client'
for platform in wsl metal android; do
    # given the clean note
    # when
    if ! render "$CLEAN" "$platform" "$REPO_ROOT/dot_gitconfig.tmpl" >"$TMP/gitconfig-$platform"; then
        fail "$platform: the gitconfig does not render: $(cat "$TMP/warnings")"
        continue
    fi

    # then: the includes, in order, after [user] and before ~/.gitconfig.local
    [[ "$(grep -A1 '^\[includeIf "gitdir:' "$TMP/gitconfig-$platform" | grep -v '^--$')" == "$includes" ]] ||
        fail "$platform: the includes must be, in this order: $includes"
    user="$(grep -n '^\[user\]$' "$TMP/gitconfig-$platform" | cut -d: -f1)"
    first="$(grep -n '^\[includeIf ' "$TMP/gitconfig-$platform" | head -n 1 | cut -d: -f1)"
    local_include="$(grep -n '^    path = ~/.gitconfig.local$' "$TMP/gitconfig-$platform" | cut -d: -f1)"
    ((${user:-0} > 0 && ${first:-0} > user && ${local_include:-0} > first)) ||
        fail "$platform: the includes must come after [user] and before ~/.gitconfig.local"
done
pass "Linux and Android include each workspace's identity, after [user] and before ~/.gitconfig.local"

# given the clean note on Windows, which gets no identity files
# when
if render "$CLEAN" windows "$REPO_ROOT/dot_gitconfig.tmpl" >"$TMP/gitconfig-windows"; then
    # then
    if grep -q 'includeIf' "$TMP/gitconfig-windows" || ! grep -q '^    path = ~/.gitconfig.local$' "$TMP/gitconfig-windows"; then
        fail "windows: the gitconfig must include ~/.gitconfig.local and no identity"
    else
        pass "Windows includes no identity, and still ~/.gitconfig.local"
    fi
else
    fail "windows: the gitconfig does not render: $(cat "$TMP/warnings")"
fi

# given a note without a single ssh: entry
# when
if render "$NONE" wsl "$REPO_ROOT/dot_gitconfig.tmpl" >"$TMP/gitconfig-none"; then
    # then
    if grep -q 'includeIf' "$TMP/gitconfig-none"; then
        fail "a note without identities must render no include"
    else
        pass "a note without identities renders no include"
    fi
else
    fail "the gitconfig does not render a note without identities: $(cat "$TMP/warnings")"
fi

# --- The writers ----------------------------------------------------------------------------------

# run_writer <platform> <items> <home>: renders the platform's writer from the note and runs it
# under bash with <home> as the home folder; its messages go to $TMP/writer.log.
run_writer() {
    local platform="$1" items="$2" home="$3" writer="$LINUX_WRITER"
    [[ "$platform" == "android" ]] && writer="$ANDROID_WRITER"
    render "$items" "$platform" "$writer" >"$TMP/writer-$platform.sh" || {
        echo "the $platform writer does not render: $(cat "$TMP/warnings")" >"$TMP/writer.log"
        return 1
    }
    HOME="$home" bash "$TMP/writer-$platform.sh" 2>"$TMP/writer.log"
}

for platform in wsl android; do
    home="$TMP/writer-home-$platform"
    dir="$home/.config/git/identities"
    mkdir -p "$home"

    # given a home folder without identities
    # when
    if ! run_writer "$platform" "$BAD" "$home"; then
        fail "$platform: the writer failed: $(cat "$TMP/writer.log")"
        continue
    fi

    # then: one file per usable identity, each starting with the marker, read back as written
    # shellcheck disable=SC2012 # the names are plain words the library allows
    [[ "$(command ls "$dir" | tr '\n' ' ')" == "default work " ]] ||
        fail "$platform: the identities written must be 'default work', not '$(command ls "$dir" | tr '\n' ' ')'"
    [[ "$(head -n 1 "$dir/work")" == "$MARKER" ]] || fail "$platform: an identity must start with the marker"
    [[ "$(git config --file "$dir/work" user.name)" == "Work \"Q\" O'Brien \\ backslash" ]] ||
        fail "$platform: git must read the name back with its quote and backslash, not '$(git config --file "$dir/work" user.name)'"
    [[ "$(git config --file "$dir/work" user.email) $(git config --file "$dir/work" user.signingkey) $(git config --file "$dir/work" gpg.format)" == \
        "work@example.org ssh-rsa AAAAwork ssh" ]] || fail "$platform: the work identity must carry its email, key and the ssh format"
    pass "$platform: the writer writes each usable identity, which git reads back as written"

    # given the same note again
    before="$(cksum "$dir"/*)"
    # when
    run_writer "$platform" "$BAD" "$home" || fail "$platform: the second run failed: $(cat "$TMP/writer.log")"
    # then
    if [[ -s "$TMP/writer.log" || "$(cksum "$dir"/*)" != "$before" ]]; then
        fail "$platform: an apply with nothing to change must write nothing and say nothing: $(cat "$TMP/writer.log")"
    else
        pass "$platform: an apply with nothing to change writes nothing and says nothing"
    fi

    # given an identity edited by hand, one this writer wrote for a key the note no longer has, and
    # one somebody wrote without the marker
    printf '%s\n[user]\n    email = edited@example.com\n' "$MARKER" >"$dir/work"
    printf '%s\n[user]\n    email = stale@example.com\n' "$MARKER" >"$dir/stale"
    printf '[user]\n    email = own@example.com\n' >"$dir/own"
    # when
    run_writer "$platform" "$BAD" "$home" || fail "$platform: the third run failed: $(cat "$TMP/writer.log")"
    # then
    [[ "$(git config --file "$dir/work" user.email)" == "work@example.org" ]] || fail "$platform: the edited identity must be put back"
    [[ ! -e "$dir/stale" ]] || fail "$platform: the identity the note no longer has must be deleted"
    [[ -f "$dir/own" ]] || fail "$platform: a file without the marker must be kept"
    grep -qF '[git-identities] wrote the identity "work"' "$TMP/writer.log" &&
        grep -qF '[git-identities] removed the identity "stale"' "$TMP/writer.log" ||
        fail "$platform: the writer must say what it rewrote and removed: $(cat "$TMP/writer.log")"
    pass "$platform: the writer puts back an edited identity, deletes its own stale one and keeps somebody else's"

    # given a note without identities
    # when
    run_writer "$platform" "$NONE" "$home" || fail "$platform: the run without identities failed: $(cat "$TMP/writer.log")"
    # then
    # shellcheck disable=SC2012 # the names are plain words the library allows
    [[ "$(command ls "$dir" | tr '\n' ' ')" == "own " ]] ||
        fail "$platform: a note without identities must leave only somebody else's file, not '$(command ls "$dir" | tr '\n' ' ')'"
    pass "$platform: a note without identities deletes every identity the writer wrote"
done

# The Android writer runs the Linux one's body: rendered from the same note, the two differ above
# `set -euo pipefail` alone.
if render "$CLEAN" wsl "$LINUX_WRITER" >"$TMP/body-linux" && render "$CLEAN" android "$ANDROID_WRITER" >"$TMP/body-android" &&
    grep -q "^write_git_identity 'client' <<'GIT_IDENTITY'$" "$TMP/body-linux" &&
    cmp -s <(sed -n '/^set -euo pipefail$/,$p' "$TMP/body-linux") <(sed -n '/^set -euo pipefail$/,$p' "$TMP/body-android"); then
    pass "the Android writer runs the same body as the Linux one"
else
    fail "the Android writer must run the same body as the Linux one"
fi

# --- Real commits ---------------------------------------------------------------------------------

# given the clean note's ~/.gitconfig and identities in a sandbox home, and no identity from the
# environment or the host's own config
mkdir -p "$SANDBOX"
cp "$TMP/gitconfig-wsl" "$SANDBOX/.gitconfig"
run_writer wsl "$CLEAN" "$SANDBOX" || fail "the writer failed on the clean note: $(cat "$TMP/writer.log")"
mkdir -p "$TMP/no-hooks"
unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL EMAIL
git_in_sandbox() {
    HOME="$SANDBOX" GIT_CONFIG_NOSYSTEM=1 git -c core.hooksPath="$TMP/no-hooks" -c commit.gpgsign=false \
        -c init.defaultBranch=main "$@"
}
# author_of <repository>: who an empty commit in it is authored by, and the key it would be signed
# with, creating the repository first when there is none.
author_of() {
    local repo="$1"
    [[ -e "$repo/.git" ]] || { mkdir -p "$repo" && git_in_sandbox init -q "$repo"; }
    git_in_sandbox -C "$repo" commit -q --allow-empty -m "test" &&
        echo "$(git_in_sandbox -C "$repo" log -1 --format='%an <%ae>') $(git_in_sandbox -C "$repo" config user.signingkey)"
}
declare -A AUTHOR=(
    ["elsewhere/repo"]="Default Person <default@example.com> ssh-ed25519 AAAAdefault"
    ["notes/repo"]="Default Person <default@example.com> ssh-ed25519 AAAAdefault"
    ["Development/github.com/someone/repo"]="Person Al <personal@example.com> ssh-ed25519 AAAApersonal"
    ["Development/dev.azure.com/SomeOrgX/repo"]="Person Al <personal@example.com> ssh-ed25519 AAAApersonal"
    ["Development/dev.azure.com/SomeOrg/project/repo"]="Work Person <work@example.org> ssh-rsa AAAAwork"
    ["Development/dev.azure.com/SomeOrg/client-project/repo"]="Client Person <client@example.net> ssh-ed25519 AAAAclient"
)

# when / then: outside every workspace the default identity, in a workspace named after no identity
# too; in a workspace its identity, the deepest one when one sits inside another, and never a
# workspace whose name merely starts the same way
for repo in "${!AUTHOR[@]}"; do
    got="$(author_of "$SANDBOX/$repo" 2>&1)" || true
    [[ "$got" == "${AUTHOR[$repo]}" ]] || fail "~/$repo must commit as '${AUTHOR[$repo]}', not '$got'"
done
pass "every repository commits as its workspace's identity, the deepest workspace's, and the default identity outside them"

# given a worktree of a work repository, placed outside every workspace
work="$SANDBOX/Development/dev.azure.com/SomeOrg/project/repo"
git_in_sandbox -C "$work" worktree add -q "$SANDBOX/elsewhere/worktree" 2>/dev/null ||
    fail "could not add a worktree to $work"
# when / then: its git directory is inside the work repository's, so it commits as work
got="$(author_of "$SANDBOX/elsewhere/worktree" 2>&1)" || true
[[ "$got" == "${AUTHOR["Development/dev.azure.com/SomeOrg/project/repo"]}" ]] ||
    fail "a worktree of a work repository must commit as work, not '$got'"
pass "a worktree commits as its main repository's workspace, wherever it is placed"

# given a work repository with an email of its own
git_in_sandbox -C "$work" config user.email own@example.org
# when / then
got="$(author_of "$work" 2>&1)" || true
[[ "$got" == "Work Person <own@example.org> ssh-rsa AAAAwork" ]] ||
    fail "a repository's own config must win over its workspace's identity, not '$got'"
pass "a repository's own config still wins over its workspace's identity"

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-git-identities] all git identity tests passed" >&2
fi
exit "$EXIT_CODE"
