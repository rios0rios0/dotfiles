#!/bin/bash
set -euo pipefail

# Tests the ocode fork-builder and the bun provisioning it depends on, without bun, git, the
# network or a real fork checkout: `git` and `bun` are stubs, the checkout is a fake directory
# whose `.git` holds a head, a branch and refs and whose package.json pins a bun version, the
# build fabricates the artifact the fork's build would emit, bun's GitHub releases are a local
# directory a `curl` stub serves, and `install_bun` is sourced from the shared dependency
# library against a `curl` stub that fabricates the upstream installer. Covers the checkout the
# builder obtains itself (the clone onto the fork's branch with the fork/upstream remote layout,
# the branch switch, the branch created from the fork's remote-tracking one under whichever
# remote's URL is the fork's -- `origin` in a plain clone, through an SSH host alias -- and fetched
# over the fork's HTTPS URL first when that remote never fetched it, a failed fetch, a checkout
# with no remote for the fork, a directory that is not a checkout, a failed clone), the skip without
# bun, the first build (including the fork channel and the version it must carry -- the release
# the checkout is built on, marked as the fork's build, or 2.0.0 when its CLI package names no
# release -- and the dependency install that must precede it), the no-op rebuild, the rebuild on
# a new head,
# the rebuild that restores a missing binary, the prompt for a running ocode with no answer, a
# decline and an acceptance -- none of which may skip the build -- the process started while
# the build runs, the ~/.bun/bin fallback, the bun the checkout pins (the resolved one when it is
# that version, otherwise a cached copy, or one downloaded for this machine's architecture and
# verified against the release's SHASUMS256.txt, each running the install and the build from the
# front of PATH), every fallback to the resolved bun (no network, a checksum mismatch, a binary
# that cannot start, an architecture without a build, a missing, non-release or unreadable pin),
# the failed install that fails the apply, the installed skip, the installer call (with SHELL
# empty, so bun's script cannot edit an rc file chezmoi owns), both installer failures, the
# Linux wiring and the PATH block rendered on each platform.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CI_DIR="$REPO_ROOT/.github/ci"
SCRIPT="$REPO_ROOT/.chezmoiscripts/run_after_linux-006-build-ocode.sh"
LIB="$REPO_ROOT/.chezmoitemplates/lib-install-deps.sh"
ZSHENV_TMPL="$REPO_ROOT/dot_zshenv.tmpl"
LINUX_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh.tmpl"
ANDROID_INSTALLER="$REPO_ROOT/.chezmoiscripts/run_once_before_android-002-install-dependencies.sh.tmpl"
EXIT_CODE=0
# What the fake ocode the builds install says, so a check can tell it from the one it replaced.
FAKE_OCODE="fake ocode"
# The fork's branch, which every checkout the builder touches must end on.
FORK_BRANCH="reworked"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-ocode] testing the ocode fork-builder and its bun provisioning..." >&2

pass() { echo "[test-ocode] PASS: $1" >&2; }
fail() { echo "[test-ocode] FAIL: $1" >&2; EXIT_CODE=1; }

export HOME="$TMP/home"
mkdir -p "$HOME"

# The release zips the download cases are served from are fabricated here, so zip is needed
# beside the unzip the builder itself uses.
if ! command -v zip >/dev/null 2>&1; then
    echo "[test-ocode] FAIL: zip is not on PATH, so bun's release zips cannot be fabricated" >&2
    exit 1
fi

# The bun version the fake checkout pins, and the newer one the machine's bun drifts to -- the
# pair behind the incident: bun 1.4.4 refuses a patch file that the checkout's 1.4.2 pin applies.
PIN="1.4.2"
NEWER="1.4.4"
BUN_RELEASES="https://github.com/oven-sh/bun/releases/download"
export CLONE_PIN="$PIN"
# The upstream release the fake checkout is built on, as its CLI package's `version` names it.
export CLONE_RELEASE="2.1.4"

export CHECKOUT="$HOME/Development/github.com/rios0rios0/opencode"
STUB="$TMP/stub"
BUN_STUB="$TMP/bun-stub"
RELEASE_STUB="$TMP/release-stub"
mkdir -p "$STUB" "$BUN_STUB" "$RELEASE_STUB" "$CHECKOUT/.git" "$TMP/tmpdir"

# The checkout's root package.json, with $1 as its packageManager -- the only field the builder
# reads from it.
write_manifest() { printf '{\n  "name": "opencode",\n  "packageManager": "%s"\n}\n' "$1" >"$CHECKOUT/package.json"; }
# The checkout's CLI package.json, with $1 as its version -- the release the builder stamps.
write_cli_manifest() {
    mkdir -p "$CHECKOUT/packages/cli"
    printf '{\n  "name": "@opencode/cli",\n  "version": "%s"\n}\n' "$1" >"$CHECKOUT/packages/cli/package.json"
}

# git stub: a fake checkout under .git -- HEAD holds the sha, HEAD_REF the branch, refs/ the
# branches and the remote-tracking ones, remotes/ the remote URLs -- so the clone, the branch
# switch and the remote layout are all assertable. The clone also brings the package.json a real
# one would, pinning bun $CLONE_PIN, and the CLI package's, naming release $CLONE_RELEASE. A fetch
# writes the destination of its refspec, and records the GIT_TERMINAL_PROMPT it ran with. Every
# invocation is recorded in $GIT_CALLS. CLONE_FAIL and FETCH_FAIL make the clone and the fetch fail
# the way a machine without the network does.
cat >"$STUB/git" <<'STUB'
#!/bin/bash
echo "$*" >>"${GIT_CALLS:?}"
if [ "$1" = "-C" ]; then
    dir="$2"
    shift 2
else
    dir="$PWD"
fi
sub="$1"
shift
case "$sub" in
    rev-parse)
        case "$*" in
            "HEAD") cat "$dir/.git/HEAD" ;;
            "--abbrev-ref HEAD") cat "$dir/.git/HEAD_REF" ;;
            --verify*)
                for arg in "$@"; do ref="$arg"; done
                [ -e "$dir/.git/$ref" ]
                ;;
            *) echo "stub git: unexpected rev-parse: $*" >&2; exit 1 ;;
        esac
        ;;
    log) echo "fake0123 chore: fake fork commit" ;;
    clone)
        [[ -z "${CLONE_FAIL:-}" ]] || exit 128
        remote=""; branch=""; url=""; target=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --origin) remote="$2"; shift 2 ;;
                --branch) branch="$2"; shift 2 ;;
                *) if [ -z "$url" ]; then url="$1"; else target="$1"; fi; shift ;;
            esac
        done
        mkdir -p "$target/.git" "$target/.git/remotes"
        printf '%s\n' "$branch" >"$target/.git/HEAD_REF"
        printf 'fake0001\n' >"$target/.git/HEAD"
        mkdir -p "$(dirname "$target/.git/refs/heads/$branch")" "$(dirname "$target/.git/refs/remotes/$remote/$branch")"
        : >"$target/.git/refs/heads/$branch"
        : >"$target/.git/refs/remotes/$remote/$branch"
        printf '%s\n' "$url" >"$target/.git/remotes/$remote"
        printf '{\n  "name": "opencode",\n  "packageManager": "bun@%s"\n}\n' "${CLONE_PIN:?}" >"$target/package.json"
        mkdir -p "$target/packages/cli"
        printf '{\n  "name": "@opencode/cli",\n  "version": "%s"\n}\n' "${CLONE_RELEASE:?}" >"$target/packages/cli/package.json"
        ;;
    fetch)
        echo "fetch-env GIT_TERMINAL_PROMPT=${GIT_TERMINAL_PROMPT-unset}" >>"${GIT_CALLS:?}"
        [[ -z "${FETCH_FAIL:-}" ]] || exit 128
        for arg in "$@"; do refspec="$arg"; done
        dst="${refspec#*:}"
        mkdir -p "$(dirname "$dir/.git/$dst")"
        : >"$dir/.git/$dst"
        ;;
    remote)
        case "${1:-}" in
            "") [ ! -d "$dir/.git/remotes" ] || ls "$dir/.git/remotes" ;;
            get-url)
                [ -f "$dir/.git/remotes/$2" ] || exit 2
                cat "$dir/.git/remotes/$2"
                ;;
            add)
                mkdir -p "$dir/.git/remotes"
                printf '%s\n' "$3" >"$dir/.git/remotes/$2"
                ;;
            *) echo "stub git: unexpected remote: $*" >&2; exit 1 ;;
        esac
        ;;
    checkout)
        if [ "$1" = "-b" ]; then
            branch="$2"
            mkdir -p "$(dirname "$dir/.git/refs/heads/$branch")"
            : >"$dir/.git/refs/heads/$branch"
        else
            branch="$1"
            [ -e "$dir/.git/refs/heads/$branch" ] || exit 1
        fi
        printf '%s\n' "$branch" >"$dir/.git/HEAD_REF"
        ;;
    *) echo "stub git: unexpected args: $*" >&2; exit 1 ;;
esac
STUB
export GIT_CALLS="$TMP/git-calls"
: >"$GIT_CALLS"

# bun stub, written for one version by make_bun_stub: answers `--version` with it; records every
# install and every build in $BUN_LOG as `<kind>|<its own path>|<its working directory>|<the bun
# a process it spawned would run>|<arguments>`, and each build's arguments in $BUN_CALLS and the
# build identity it was given in $BUN_ENV; fails the install with BUN_INSTALL_FAIL set; and
# fabricates the artifact under --outdir. With BUN_STUB_RACE set it also starts the installed
# binary mid-build, standing in for a person who opens ocode while the build runs -- the
# build-minutes window the installer's rename closes.
cat >"$TMP/bun-stub.in" <<'STUB'
#!/bin/bash
if [ "$1" = "--version" ]; then
    echo "@VERSION@"
    exit 0
fi
if [ "$1" = "install" ]; then
    echo "install|$0|$PWD|$(command -v bun)|$*" >>"${BUN_LOG:?}"
    exit "${BUN_INSTALL_FAIL:-0}"
fi
echo "build|$0|$PWD|$(command -v bun)|$*" >>"${BUN_LOG:?}"
echo "$*" >>"${BUN_CALLS:?}"
echo "${OPENCODE_CHANNEL:-unset}/${OPENCODE_VERSION:-unset}" >>"${BUN_ENV:?}"
if [ -n "${BUN_STUB_RACE:-}" ]; then
    # the installed binary is still the copy of bash that start_running_ocode put there
    "$HOME/.local/bin/ocode" -c 'read -r -t 300 <>"$1"' ocode "${BUN_RACE_FIFO:?}" &
    echo "$!" >"${BUN_RACE_PID:?}"
fi
for arg in "$@"; do
    case "$arg" in
        --outdir=*) out="${arg#--outdir=}" ;;
    esac
done
mkdir -p "$out/cli-linux-x64/bin"
printf '#!/bin/bash\necho fake ocode\n' >"$out/cli-linux-x64/bin/opencode"
chmod +x "$out/cli-linux-x64/bin/opencode"
STUB
make_bun_stub() {
    local path="$1" version="$2"
    mkdir -p "$(dirname "$path")"
    sed "s/@VERSION@/$version/" "$TMP/bun-stub.in" >"$path"
    chmod +x "$path"
}
make_bun_stub "$BUN_STUB/bun" "$PIN"
chmod +x "$STUB/git"

export BUN_CALLS="$TMP/bun-calls"
export BUN_ENV="$TMP/bun-env"
export BUN_LOG="$TMP/bun-log"
: >"$BUN_CALLS"
: >"$BUN_ENV"
: >"$BUN_LOG"

# curl stub for bun's GitHub releases: serves $RELEASE_ROOT/<tag>/<asset> for
# $BUN_RELEASES/<tag>/<asset> and fails any other request the way a 404 does -- or every request,
# with RELEASE_FAIL set, the way a machine without the network does. Every invocation's arguments
# go to $RELEASE_CALLS. It is on every PATH the builder runs with, so no case reaches the network.
cat >"$RELEASE_STUB/curl" <<'STUB'
#!/bin/bash
echo "$*" >>"${RELEASE_CALLS:?}"
[[ -z "${RELEASE_FAIL:-}" ]] || exit 6
out=""
url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        --proto | --proto-redir | --connect-timeout | --retry) shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
prefix="https://github.com/oven-sh/bun/releases/download/"
[[ "$url" == "$prefix"* && -f "${RELEASE_ROOT:?}/${url#"$prefix"}" ]] || exit 22
cp "$RELEASE_ROOT/${url#"$prefix"}" "$out"
STUB
# uname stub: `uname -m` answers $FAKE_UNAME_M when it is set, so a case can stand on another
# architecture; everything else is the real uname's.
cat >"$RELEASE_STUB/uname" <<'STUB'
#!/bin/bash
if [ "$*" = "-m" ] && [ -n "${FAKE_UNAME_M:-}" ]; then
    echo "$FAKE_UNAME_M"
    exit 0
fi
exec "${REAL_UNAME:?}" "$@"
STUB
chmod +x "$RELEASE_STUB/curl" "$RELEASE_STUB/uname"
REAL_UNAME="$(command -v uname)"
export REAL_UNAME
export RELEASE_ROOT="$TMP/releases"
export RELEASE_CALLS="$TMP/release-calls"
: >"$RELEASE_CALLS"

# stdin is /dev/null unless a file is given, so a case that reaches the kill prompt and answers
# nothing leaves the running ocode alone and builds anyway, instead of reading the test runner's
# terminal. TMPDIR is the test's own, so a case can check that a download left nothing in it, and
# a failing run is recorded rather than ending the test.
run_script() {
    local status=0
    (cd "$TMP" && PATH="$BUN_STUB:$RELEASE_STUB:$STUB:$PATH" TMPDIR="$TMP/tmpdir" bash "$SCRIPT" <"${1:-/dev/null}") >"$TMP/out" 2>&1 || status=$?
    echo "$status" >"$TMP/rc"
}
rc() { cat "$TMP/rc"; }
calls() { wc -l <"$BUN_CALLS"; }
installs() { grep -c '^install|' "$BUN_LOG" || true; }
# The last install or build ($1) the bun stubs recorded.
last_entry() {
    local kind="$1"
    grep "^$kind|" "$BUN_LOG" | tail -n 1 || true
}
# Whether the last install and the last build both ran with bun $1, and a `bun` that either of
# them spawned would have run $1 too.
ran_with() {
    local expected="$1" kind entry self spawned
    for kind in install build; do
        entry="$(last_entry "$kind")"
        IFS='|' read -r _ self _ spawned _ <<<"$entry"
        [[ "$self" == "$expected" ]] && [[ "$spawned" == "$expected" ]] || return 1
    done
}

# 1) No checkout: the fork is cloned onto its branch, with the fork as `fork` and sst upstream
#    as `origin`, and the build then runs -- a fresh machine ends the apply with ocode installed
#    *and* the checkout ready to edit. The build carries a release-grade version on the fork's
#    channel, because the Console's free tier refuses client versions below 1.18.0 and a bare
#    branch build's preview version falls below it.
rm -rf "$CHECKOUT"
run_script
[[ "$(rc)" -eq 0 ]] || fail "the clone must exit 0"
grep -qF "clone --origin fork --branch reworked https://github.com/rios0rios0/opencode.git $CHECKOUT" "$GIT_CALLS" ||
    fail "a missing checkout must be cloned from the fork on its branch"
[[ "$(cat "$CHECKOUT/.git/HEAD_REF")" = "$FORK_BRANCH" ]] || fail "the clone must land on the fork's branch"
[[ "$(cat "$CHECKOUT/.git/remotes/fork")" = "https://github.com/rios0rios0/opencode.git" ]] ||
    fail "the clone must keep the fork as fork"
[[ "$(cat "$CHECKOUT/.git/remotes/origin")" = "https://github.com/sst/opencode.git" ]] ||
    fail "the clone must get sst upstream as origin"
[[ -x "$HOME/.local/bin/ocode" ]] || fail "the build after the clone must install an executable ocode"
[[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake0001" ]] || fail "marker must hold the built head"
[[ "$(calls)" -eq 1 ]] || fail "the first build must invoke bun once"
identity="$(tail -n 1 "$BUN_ENV")"
[[ "${identity%%/*}" = "feat-provider-omniroute" ]] || fail "the build must carry the fork's channel: $identity"
[[ "${identity##*/}" =~ ^2\.1\.4-reworked\.[0-9]{10}$ ]] ||
    fail "the build must carry the checkout's release marked as the fork's build, <release>-reworked.<build time>: $identity"
grep -qF "stamping the build as ${identity%%/*} ${identity##*/}" "$TMP/out" || fail "the build identity must be reported: $identity"
pass "a missing checkout is cloned onto the fork's branch with the fork/upstream remotes, then built"

# 1b) The fresh clone is where the build used to die on dozens of `Could not resolve: "effect"`:
#     nothing had installed the workspace, and the build's `--skip-install` skips only its own
#     cross-platform install of two native packages. The dependencies are installed first, in the
#     checkout, from the frozen lockfile and with the lifecycle scripts on (the root postinstall
#     fixes node-pty's spawn-helper), and the build keeps `--skip-install`. The resolved bun is
#     the version the clone pins, so it runs both, first on PATH, and nothing is downloaded.
install_entry="$(last_entry install)"
[[ "$(installs)" -eq 1 ]] || fail "the first build must install the checkout's dependencies once"
[[ "$(tail -n 2 "$BUN_LOG" | cut -d'|' -f1 | paste -sd' ')" = "install build" ]] ||
    fail "the dependencies must be installed before the build: $(cat "$BUN_LOG")"
[[ "$(cut -d'|' -f3 <<<"$install_entry")" = "$CHECKOUT" ]] || fail "the install must run in the checkout: $install_entry"
[[ "$(cut -d'|' -f5 <<<"$install_entry")" = "install --frozen-lockfile" ]] ||
    fail "the install must be 'install --frozen-lockfile' alone, lifecycle scripts on: $install_entry"
grep -q -- '--skip-install' "$BUN_CALLS" || fail "the build must keep --skip-install"
ran_with "$BUN_STUB/bun" || fail "a resolved bun at the pinned version must run the install and the build: $(tail -n 2 "$BUN_LOG")"
grep -qF "is bun $PIN, the version the checkout pins" "$TMP/out" || fail "a resolved bun at the pinned version must be named as such"
[[ ! -s "$RELEASE_CALLS" ]] || fail "a resolved bun at the pinned version must not download another: $(cat "$RELEASE_CALLS")"
[[ ! -e "$HOME/.cache/ocode-bun" ]] || fail "a resolved bun at the pinned version must cache nothing"
pass "a fresh clone's dependencies are installed before the build, by the resolved bun when it is the pinned version"

# 2) A checkout left on another branch is switched to the fork's: the channel below is stamped
#    onto whatever HEAD holds, so building `main` would label a binary as the fork and carry
#    none of its code. The head is unchanged, so nothing is rebuilt.
printf 'main\n' >"$CHECKOUT/.git/HEAD_REF"
before="$(calls)"
: >"$GIT_CALLS"
run_script
[[ "$(rc)" -eq 0 ]] || fail "a branch switch must exit 0"
grep -q "checkout is on main, switching to reworked" "$TMP/out" || fail "the switch must say which branch it came from"
[[ "$(cat "$CHECKOUT/.git/HEAD_REF")" = "$FORK_BRANCH" ]] || fail "the checkout must end on the fork's branch"
[[ "$(calls)" -eq "$before" ]] || fail "an unchanged head must not rebuild after a branch switch"
pass "a checkout on another branch is switched to the fork's without rebuilding"

# 3) The branch is missing locally but the fork's remote-tracking one is there: it is created
#    from that, so a clone made by hand with another branch checked out still lands on the fork.
rm -f "$CHECKOUT/.git/refs/heads/reworked"
printf 'main\n' >"$CHECKOUT/.git/HEAD_REF"
: >"$GIT_CALLS"
run_script
[[ "$(rc)" -eq 0 ]] || fail "tracking the fork's branch must exit 0"
grep -qF "checkout -b reworked --track fork/reworked" "$GIT_CALLS" ||
    fail "a missing local branch must be created from fork/<branch>"
[[ "$(cat "$CHECKOUT/.git/HEAD_REF")" = "$FORK_BRANCH" ]] || fail "the tracked branch must be checked out"
pass "a missing local branch is created from the fork's remote-tracking one"

# Points the fake checkout at the given remotes, `<name>=<url>` each, with no local fork branch
# and no remote-tracking refs, on another branch: the state the switch above starts from.
set_remotes() {
    local spec
    rm -rf "$CHECKOUT/.git/refs/heads/reworked" "$CHECKOUT/.git/refs/remotes" "$CHECKOUT/.git/remotes"
    mkdir -p "$CHECKOUT/.git/remotes"
    for spec in "$@"; do
        printf '%s\n' "${spec#*=}" >"$CHECKOUT/.git/remotes/${spec%%=*}"
    done
    printf 'dev\n' >"$CHECKOUT/.git/HEAD_REF"
    : >"$GIT_CALLS"
}
# Gives remote $1 a remote-tracking reworked, as a fetch of the fork would.
fetched() {
    local remote="$1"
    mkdir -p "$CHECKOUT/.git/refs/remotes/$remote"
    : >"$CHECKOUT/.git/refs/remotes/$remote/$FORK_BRANCH"
}
fetches() { grep -c ' fetch --no-tags ' "$GIT_CALLS" || true; }

# 3b) A plain `git clone` of the fork, made by hand, calls the fork `origin`, here through the
#     github.com-mine SSH alias, and has no `fork` remote at all: the checkout behind this case,
#     whose apply warned that it had no reworked branch while origin/reworked was right there.
#     The branch is created from origin/reworked, and nothing is fetched.
set_remotes "origin=git@github.com-mine:rios0rios0/opencode.git"
fetched origin
run_script
[[ "$(rc)" -eq 0 ]] || fail "a plain clone of the fork must switch: $(cat "$TMP/out")"
grep -qF "checkout -b reworked --track origin/reworked" "$GIT_CALLS" ||
    fail "a plain clone's branch must be created from origin/reworked: $(cat "$GIT_CALLS")"
[[ "$(fetches)" -eq 0 ]] || fail "a fetched branch must not be fetched again"
[[ "$(cat "$CHECKOUT/.git/HEAD_REF")" = "$FORK_BRANCH" ]] || fail "a plain clone must end on the fork's branch"
pass "a plain clone, whose fork is origin, gets the branch from origin/reworked"

# 3c) The fork's other URL forms count too, under a remote of any name.
for url in "https://github.com/rios0rios0/opencode" "ssh://git@github.com/rios0rios0/opencode.git" "github.com-mine:rios0rios0/opencode"; do
    set_remotes "mirror=$url"
    fetched mirror
    run_script
    grep -qF "checkout -b reworked --track mirror/reworked" "$GIT_CALLS" ||
        fail "$url: must be recognized as the fork: $(cat "$TMP/out")"
done
pass "the fork is recognized by any of its URL forms, under any remote name"

# 3d) The fork's remote has never fetched the branch: it is fetched first, from the fork's HTTPS
#     URL rather than the remote's SSH one, whose 1Password approval nobody gives an unattended
#     apply, with git's prompts off, into that remote's namespace; then it is tracked.
set_remotes "origin=git@github.com-mine:rios0rios0/opencode.git"
run_script
[[ "$(rc)" -eq 0 ]] || fail "fetching the fork's branch must exit 0: $(cat "$TMP/out")"
grep -qF "fetch --no-tags https://github.com/rios0rios0/opencode.git +refs/heads/reworked:refs/remotes/origin/reworked" "$GIT_CALLS" ||
    fail "the branch must be fetched over the fork's HTTPS URL into origin's namespace: $(cat "$GIT_CALLS")"
grep -qxF "fetch-env GIT_TERMINAL_PROMPT=0" "$GIT_CALLS" || fail "the fetch must run with git's prompts off"
grep -qF "checkout -b reworked --track origin/reworked" "$GIT_CALLS" || fail "the fetched branch must be tracked"
[[ "$(cat "$CHECKOUT/.git/HEAD_REF")" = "$FORK_BRANCH" ]] || fail "the checkout must end on the fetched branch"
pass "a branch the fork's remote never fetched is fetched over HTTPS, then tracked"

# 4) The fetch fails -- no network, or the branch is gone: the checkout is left alone and nothing
#    is built, rather than building whatever branch it happens to be on.
set_remotes "origin=git@github.com-mine:rios0rios0/opencode.git"
rm -f "$HOME/.local/bin/ocode"
before="$(calls)"
export FETCH_FAIL=1
run_script
unset FETCH_FAIL
[[ "$(rc)" -eq 0 ]] || fail "a failed fetch must not fail the apply"
grep -qF "WARN: failed to fetch reworked from https://github.com/rios0rios0/opencode.git" "$TMP/out" ||
    fail "a failed fetch must say what failed: $(cat "$TMP/out")"
[[ "$(cat "$CHECKOUT/.git/HEAD_REF")" = "dev" ]] || fail "a failed fetch must leave the checkout on its branch"
[[ "$(calls)" -eq "$before" ]] || fail "a failed fetch must not build"
[[ ! -e "$HOME/.local/bin/ocode" ]] || fail "a failed fetch must not install a binary"
pass "a failed fetch warns and builds nothing"

# 4b) No remote points at the fork -- upstream alone, or a repository whose name only starts the
#     same: nothing is fetched or built, and the warning says how to add the remote.
set_remotes "origin=https://github.com/sst/opencode.git" "other=git@github.com-mine:rios0rios0/opencode-fork.git"
before="$(calls)"
run_script
[[ "$(rc)" -eq 0 ]] || fail "a checkout with no remote for the fork must skip"
grep -qF "has no reworked branch and no remote for https://github.com/rios0rios0/opencode.git" "$TMP/out" ||
    fail "a checkout with no remote for the fork must be reported: $(cat "$TMP/out")"
grep -qF "remote add fork https://github.com/rios0rios0/opencode.git" "$TMP/out" || fail "the warning must say how to add the remote"
[[ "$(fetches)" -eq 0 ]] || fail "a checkout with no remote for the fork must fetch nothing"
[[ "$(calls)" -eq "$before" ]] || fail "a checkout with no remote for the fork must not build"
[[ ! -e "$HOME/.local/bin/ocode" ]] || fail "a checkout with no remote for the fork must not install a binary"
pass "a checkout with no remote for the fork warns and builds nothing"

# 5) A directory that is not a checkout is not cloned into: it may hold somebody's work, and a
#    clone would either fail on it or, worse, be mistaken for done.
rm -rf "$CHECKOUT"
mkdir -p "$CHECKOUT"
before="$(wc -l <"$GIT_CALLS")"
run_script
[[ "$(rc)" -eq 0 ]] || fail "a non-checkout directory must skip"
grep -q "exists but is not a git checkout" "$TMP/out" || fail "a non-checkout directory must say why it is left alone"
[[ "$(wc -l <"$GIT_CALLS")" -eq "$before" ]] || fail "a non-checkout directory must not be cloned into"
pass "a directory that is not a checkout is left alone"

# 6) A clone that fails -- no network, for instance -- is a warning, not a failed apply: there
#    is simply nothing to build yet, and the next apply tries again.
rm -rf "$CHECKOUT"
export CLONE_FAIL=1
run_script
unset CLONE_FAIL
[[ "$(rc)" -eq 0 ]] || fail "a failed clone must not fail the apply"
grep -q "WARN: failed to clone" "$TMP/out" || fail "a failed clone must say what failed"
[[ ! -e "$HOME/.local/bin/ocode" ]] || fail "a failed clone must not install a binary"
pass "a failed clone warns and skips"

# Restore the checkout the remaining cases build from: the head test 1 built, on the fork's
# branch, with the binary that the marker now matches.
rm -rf "$CHECKOUT"
mkdir -p "$CHECKOUT/.git/refs/heads/feat" "$CHECKOUT/.git/refs/remotes/fork/feat"
printf 'fake0001\n' >"$CHECKOUT/.git/HEAD"
printf 'reworked\n' >"$CHECKOUT/.git/HEAD_REF"
: >"$CHECKOUT/.git/refs/heads/reworked"
: >"$CHECKOUT/.git/refs/remotes/fork/reworked"
write_manifest "bun@$PIN"
write_cli_manifest "$CLONE_RELEASE"
printf '#!/bin/bash\necho fake ocode\n' >"$HOME/.local/bin/ocode"
chmod +x "$HOME/.local/bin/ocode"
# 7) Unchanged head: no rebuild, and no install either -- an unchanged apply stays a no-op.
run_script
[[ "$(rc)" -eq 0 ]] || fail "unchanged apply must exit 0"
[[ "$(calls)" -eq 1 ]] || fail "unchanged head must not rebuild"
[[ "$(installs)" -eq 1 ]] || fail "unchanged head must not install the dependencies"
pass "unchanged head does not rebuild"

# 8) New head: rebuild and move the marker. The install runs again: it belongs to every build,
#    not only to a clone's.
printf 'fake4567\n' >"$CHECKOUT/.git/HEAD"
run_script
[[ "$(rc)" -eq 0 ]] || fail "rebuild must exit 0"
[[ "$(calls)" -eq 2 ]] || fail "new head must rebuild"
[[ "$(installs)" -eq 2 ]] || fail "a rebuild must install the dependencies first"
[[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake4567" ]] || fail "marker must move with the head"
pass "new head rebuilds"

# 9) Binary deleted but head unchanged: the rebuild restores it.
rm -f "$HOME/.local/bin/ocode"
run_script
[[ "$(rc)" -eq 0 ]] || fail "missing binary must rebuild"
[[ -x "$HOME/.local/bin/ocode" ]] || fail "missing binary must be reinstalled"
pass "missing binary is reinstalled"

# 10) bun off PATH but at ~/.bun/bin: the build runs anyway. This is the first apply after
#    `install_bun`, whose PATH export only reaches shells started after it. That bun is the
#    pinned version, so it installs and builds, and goes first on PATH for both.
mkdir -p "$HOME/.bun/bin"
cp "$BUN_STUB/bun" "$HOME/.bun/bin/bun"
rm -f "$HOME/.local/bin/ocode"
(cd "$TMP" && PATH="$RELEASE_STUB:$STUB:/usr/bin:/bin" bash "$SCRIPT") >"$TMP/out" 2>&1
echo $? >"$TMP/rc"
[[ "$(rc)" -eq 0 ]] || fail "the ~/.bun/bin fallback must build"
[[ "$(calls)" -eq 4 ]] || fail "the ~/.bun/bin fallback must invoke bun"
[[ -x "$HOME/.local/bin/ocode" ]] || fail "the ~/.bun/bin fallback must install the binary"
ran_with "$HOME/.bun/bin/bun" || fail "the ~/.bun/bin fallback must install and build with that bun: $(tail -n 2 "$BUN_LOG")"
pass "bun at ~/.bun/bin is used when PATH has none"

# 11) No bun anywhere: skip, and the message names both places that were looked at. The
#    restricted PATH keeps any real bun out of the picture.
rm -rf "$HOME/.bun"
(cd "$TMP" && PATH="$STUB" /bin/bash "$SCRIPT") >"$TMP/out" 2>&1
echo $? >"$TMP/rc"
[[ "$(rc)" -eq 0 ]] || fail "a machine without bun must skip"
grep -q "bun is not installed" "$TMP/out" || fail "a machine without bun must say why"
pass "a machine without bun skips"

# The library is pure bash and defines functions only, so the test shell can source it and
# call install_bun directly under the redirected HOME.
# shellcheck source=/dev/null
source "$LIB"

# curl stub: records every invocation in $CURL_CALLS and writes $CURL_BODY to the -o target,
# unless $CURL_FAIL is set, standing in for a failed download.
cat >"$STUB/curl" <<'STUB'
#!/bin/bash
echo "$*" >>"${CURL_CALLS:?}"
if [[ -n "${CURL_FAIL:-}" ]]; then
    exit 22
fi
out=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *) shift ;;
    esac
done
cp "${CURL_BODY:?}" "$out"
STUB
chmod +x "$STUB/curl"

# The fabricated upstream installer: records the SHELL it sees and its arguments, and exits
# with $INSTALLER_FAIL when set.
cat >"$TMP/bun-upstream-installer.sh" <<'FAKE'
#!/bin/bash
printf 'shell=%s\n' "${SHELL-<unset>}" >>"${INSTALLER_CALLS:?}"
printf 'args=%s\n' "$*" >>"${INSTALLER_CALLS:?}"
exit "${INSTALLER_FAIL:-0}"
FAKE

export CURL_BODY="$TMP/bun-upstream-installer.sh"
export CURL_CALLS="$TMP/curl-calls"
export INSTALLER_CALLS="$TMP/installer-calls"
: >"$CURL_CALLS"
: >"$INSTALLER_CALLS"

run_install_bun() {
    local rc=0
    (PATH="$STUB:$PATH"; cd "$TMP"; install_bun) >"$TMP/out" 2>&1 || rc=$?
    echo "$rc" >"$TMP/rc"
}
curl_calls() { wc -l <"$CURL_CALLS"; }

# 12) An existing ~/.bun/bin/bun is a skip: nothing is downloaded.
mkdir -p "$HOME/.bun/bin"
cp "$BUN_STUB/bun" "$HOME/.bun/bin/bun"
run_install_bun
[[ "$(rc)" -eq 0 ]] || fail "the installed skip must exit 0"
[[ "$(curl_calls)" -eq 0 ]] || fail "the installed skip must not download anything"
grep -q "bun is already installed, skipping" "$TMP/out" || fail "the installed skip must say why"
pass "an installed bun is skipped"

# 13) A machine without bun fetches the upstream installer and runs it with SHELL empty and no
#    arguments -- with a shell named, the installer would edit that shell's rc file, which
#    chezmoi owns and rewrites.
rm -rf "$HOME/.bun"
run_install_bun
[[ "$(rc)" -eq 0 ]] || fail "the install must exit 0"
grep -q 'https://bun.sh/install' "$CURL_CALLS" || fail "the install must fetch the bun installer"
[[ "$(sed -n '1p' "$INSTALLER_CALLS")" = "shell=" ]] || fail "the installer must run with SHELL empty: $(sed -n '1p' "$INSTALLER_CALLS")"
[[ "$(sed -n '2p' "$INSTALLER_CALLS")" = "args=" ]] || fail "the installer must be run without arguments: $(sed -n '2p' "$INSTALLER_CALLS")"
pass "the upstream installer runs with SHELL empty"

# 14) A failed download fails the install, so `verify` retries it on the next apply.
rm -rf "$HOME/.bun"
export CURL_FAIL=1
run_install_bun
unset CURL_FAIL
[[ "$(rc)" -ne 0 ]] || fail "a failed download must exit non-zero"
grep -q "failed to download the bun installer" "$TMP/out" || fail "a failed download must say what failed"
pass "a failed download fails the install"

# 15) A failed installer fails the install the same way.
rm -rf "$HOME/.bun"
export INSTALLER_FAIL=7
run_install_bun
unset INSTALLER_FAIL
[[ "$(rc)" -ne 0 ]] || fail "a failed installer must exit non-zero"
grep -q "exited with status 7" "$TMP/out" || fail "a failed installer must report its status"
pass "a failed installer fails the install"

# 16) The Linux dependency installer verifies install_bun; the Android one installs nothing.
if grep -q '^verify install_bun$' "$LINUX_INSTALLER"; then
    pass "the Linux installer verifies install_bun"
else
    fail "the Linux installer no longer verifies install_bun"
fi
if grep -q 'install_bun' "$ANDROID_INSTALLER"; then
    fail "the Android installer must not install bun"
else
    pass "the Android installer installs nothing"
fi

# 17) The ZSHENV template carries the ~/.bun/bin PATH block on Linux and macOS (the same
#     non-Android branch as flyctl) and none on Android.
chmod +x "$CI_DIR/fixtures/mock-op.sh" 2>/dev/null || true
cat >"$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
onePassword:
  command: "$CI_DIR/fixtures/mock-op.sh"
data:
  deviceName: "testdevice"
EOF

render() {
    local os="$1"
    chezmoi execute-template --config "$TMP/chezmoi.yaml" --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" <"$ZSHENV_TMPL"
}

if ! command -v chezmoi >/dev/null 2>&1; then
    fail "chezmoi is not on PATH, so dot_zshenv.tmpl cannot be rendered"
else
    if render linux | grep -qF 'export PATH="$HOME/.bun/bin:$PATH"'; then
        pass "Linux carries the ~/.bun/bin PATH block"
    else
        fail "Linux lost the ~/.bun/bin PATH block"
    fi

    if render darwin | grep -qF 'export PATH="$HOME/.bun/bin:$PATH"'; then
        pass "macOS carries the ~/.bun/bin PATH block"
    else
        fail "macOS lost the ~/.bun/bin PATH block"
    fi

    if render android | grep -q '\.bun'; then
        fail "Android must not carry the ~/.bun/bin PATH block"
    else
        pass "Android carries no ~/.bun/bin PATH block"
    fi

    # the flyctl block shares the branch and the template structure with the bun block;
    # guard that an edit to one did not break the other
    if render linux | grep -qF 'export PATH="$HOME/.fly/bin:$PATH"'; then
        pass "the flyctl PATH block still renders on Linux"
    else
        fail "the flyctl PATH block disappeared from the Linux render"
    fi
fi

# A copy of bash at ~/.local/bin/ocode stands in for a running ocode: the process executes that
# file, which is what the builder finds through /proc/<pid>/exe, and waits on a FIFO that nothing
# writes to. A copy of sleep cannot: uutils coreutils, Ubuntu's default since 25.10, is one
# multi-call binary that picks the utility from its own file name, whatever argv[0] says, so a copy
# named ocode exits at once with "coreutils: unknown program 'ocode'". $! is the running copy.
mkfifo "$TMP/never-written"
start_running_ocode() {
    cp "$BASH" "$HOME/.local/bin/ocode"
    "$HOME/.local/bin/ocode" -c 'read -r -t 300 <>"$1"' ocode "$TMP/never-written" &
}

# 18) A running ocode executes the installed binary, so the prompt appears; with nothing on stdin
#     to answer it (an unattended apply), the session is left alone and the build runs anyway --
#     the staged rename replaces the file under a running process without disturbing it.
printf 'fake7890\n' >"$CHECKOUT/.git/HEAD"
start_running_ocode
unanswered_pid=$!
before="$(calls)"
run_script
[[ "$(rc)" -eq 0 ]] || fail "an unanswered prompt must exit 0"
grep -q "ocode is running" "$TMP/out" || fail "a running ocode must be reported"
grep -q "leaving PID" "$TMP/out" || fail "an unanswered prompt must say the session is left alone"
[[ "$(calls)" -eq $((before + 1)) ]] || fail "an unanswered prompt must build anyway"
[[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake7890" ]] || fail "an unanswered prompt must move the marker"
grep -q "$FAKE_OCODE" "$HOME/.local/bin/ocode" || fail "an unanswered prompt must install the new binary"
kill -0 "$unanswered_pid" 2>/dev/null || fail "the running ocode must survive the build"
kill "$unanswered_pid" 2>/dev/null || true
wait "$unanswered_pid" 2>/dev/null || true
pass "a running ocode is asked about, and an unanswered prompt builds anyway without touching it"

# 19) The same situation answered no: the session is still left alone and the build still runs.
printf 'fakeabcd\n' >"$CHECKOUT/.git/HEAD"
start_running_ocode
declined_pid=$!
before="$(calls)"
printf 'n\n' >"$TMP/answer"
run_script "$TMP/answer"
[[ "$(rc)" -eq 0 ]] || fail "a declined prompt must exit 0"
grep -q "leaving PID" "$TMP/out" || fail "a declined prompt must say the session is left alone"
[[ "$(calls)" -eq $((before + 1)) ]] || fail "a declined prompt must build anyway"
[[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fakeabcd" ]] || fail "a declined prompt must move the marker"
grep -q "$FAKE_OCODE" "$HOME/.local/bin/ocode" || fail "a declined prompt must install the new binary"
kill -0 "$declined_pid" 2>/dev/null || fail "the running ocode must survive a declined prompt"
kill "$declined_pid" 2>/dev/null || true
wait "$declined_pid" 2>/dev/null || true
pass "a running ocode survives a decline, and the build proceeds"

# 20) Answered yes: the process is killed first, and then the build runs.
printf 'fakefade\n' >"$CHECKOUT/.git/HEAD"
start_running_ocode
accepted_pid=$!
printf 'y\n' >"$TMP/answer"
before="$(calls)"
run_script "$TMP/answer"
[[ "$(rc)" -eq 0 ]] || fail "an accepted prompt must exit 0"
grep -q "killed PID" "$TMP/out" || fail "an accepted prompt must report the kill"
[[ "$(calls)" -eq $((before + 1)) ]] || fail "an accepted prompt must build"
[[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fakefade" ]] || fail "an accepted prompt must move the marker"
grep -q "$FAKE_OCODE" "$HOME/.local/bin/ocode" || fail "an accepted prompt must install the new binary"
wait "$accepted_pid" 2>/dev/null || true
if kill -0 "$accepted_pid" 2>/dev/null; then
    fail "the killed ocode must be gone"
fi
pass "a running ocode is killed when the prompt is accepted, and the build proceeds"

# 21) An unchanged head needs no build, so a running ocode is not asked about at all.
start_running_ocode
unchanged_pid=$!
before="$(calls)"
run_script
[[ "$(rc)" -eq 0 ]] || fail "an unchanged head must exit 0 with ocode running"
[[ "$(calls)" -eq "$before" ]] || fail "an unchanged head must not build with ocode running"
if grep -q "ocode is running" "$TMP/out"; then
    fail "an unchanged head must not prompt about ocode"
fi
kill -0 "$unchanged_pid" 2>/dev/null || fail "the running ocode must be left alone when nothing builds"
kill "$unchanged_pid" 2>/dev/null || true
wait "$unchanged_pid" 2>/dev/null || true
pass "a running ocode is not prompted about when the head is unchanged"

# 22) One started *while* the build runs (the stub starts it mid-build) must not fail the install:
#     a direct cp onto it would die with "Text file busy", the staged rename replaces it.
printf 'fake9999\n' >"$CHECKOUT/.git/HEAD"
export BUN_STUB_RACE=1 BUN_RACE_PID="$TMP/race-pid" BUN_RACE_FIFO="$TMP/never-written"
before="$(calls)"
run_script
unset BUN_STUB_RACE BUN_RACE_PID BUN_RACE_FIFO
race_pid="$(cat "$TMP/race-pid")"
[[ "$(rc)" -eq 0 ]] || fail "a process started mid-build must not fail the install"
if grep -q "Text file busy" "$TMP/out"; then
    fail "the install must not lose the running-binary race"
fi
[[ "$(calls)" -eq $((before + 1)) ]] || fail "the race case must build once"
[[ "$(cat "$HOME/.cache/ocode-built-commit")" = "fake9999" ]] || fail "the race case must move the marker"
grep -q "$FAKE_OCODE" "$HOME/.local/bin/ocode" || fail "the race case must install the new binary"
kill -0 "$race_pid" 2>/dev/null || fail "the racing process must be left running (it holds the old file)"
kill "$race_pid" 2>/dev/null || true
wait "$race_pid" 2>/dev/null || true
pass "a process started mid-build cannot fail the install"

# --- The bun the checkout pins ---------------------------------------------------------------
# The cases above ran with a resolved bun at the pinned version. From here the machine's bun has
# drifted past the pin, the way `bun upgrade` leaves it -- the incident's second half, where bun
# 1.4.4 refused a patch file that the checkout's 1.4.2 pin applies.
make_bun_stub "$BUN_STUB/bun" "$NEWER"
cache="$HOME/.cache/ocode-bun/$PIN"
RELEASE="$RELEASE_ROOT/bun-v$PIN"
# Packages $1 as the bun of every Linux asset of the pinned release and publishes the
# SHASUMS256.txt that goes with them, the layout of bun's own releases: <asset>.zip holding
# <asset>/bun.
build_release() {
    local binary="$1" asset
    rm -rf "$TMP/release-src" "$RELEASE"
    mkdir -p "$RELEASE"
    for asset in bun-linux-aarch64 bun-linux-x64-baseline bun-linux-x64; do
        mkdir -p "$TMP/release-src/$asset"
        cp "$binary" "$TMP/release-src/$asset/bun"
        chmod +x "$TMP/release-src/$asset/bun"
        (cd "$TMP/release-src" && zip -q -r "$RELEASE/$asset.zip" "$asset")
    done
    (cd "$RELEASE" && sha256sum bun-linux-aarch64.zip bun-linux-x64-baseline.zip bun-linux-x64.zip >SHASUMS256.txt)
}
make_bun_stub "$TMP/pinned-bun" "$PIN"
build_release "$TMP/pinned-bun"
# bun's installer picks between the two x64 builds by the CPU's AVX2 flag, and so does the
# builder; the cases expect whichever one this machine's /proc/cpuinfo calls for.
if grep -qw avx2 /proc/cpuinfo 2>/dev/null; then
    x64_asset="bun-linux-x64"
else
    x64_asset="bun-linux-x64-baseline"
fi
export FAKE_UNAME_M="x86_64"
# A new head, so the next run builds, and an empty download log for it to fill.
head_seq=0
new_head() {
    head_seq=$((head_seq + 1))
    printf 'pin%04d\n' "$head_seq" >"$CHECKOUT/.git/HEAD"
    : >"$RELEASE_CALLS"
}
# What a download may leave behind: anything in the builder's TMPDIR, and a staged bun that
# never took its cached name.
leftovers() {
    find "$TMP/tmpdir" -mindepth 1 2>/dev/null || true
    find "$HOME/.cache/ocode-bun" -name 'bun.new.*' 2>/dev/null || true
}

# 23) Nothing cached: the pinned bun is downloaded -- the asset for this CPU and the release's
#     SHASUMS256.txt, both HTTPS-only, redirects included -- verified, cached, and then runs the
#     install and the build, first on PATH, so a bun they spawn is the pinned one too.
rm -rf "$HOME/.cache/ocode-bun"
new_head
run_script
[[ "$(rc)" -eq 0 ]] || fail "fetching the pinned bun must exit 0: $(cat "$TMP/out")"
grep -qF "$BUN_RELEASES/bun-v$PIN/$x64_asset.zip" "$RELEASE_CALLS" ||
    fail "the download must fetch the $x64_asset asset of bun v$PIN: $(cat "$RELEASE_CALLS")"
grep -qF "$BUN_RELEASES/bun-v$PIN/SHASUMS256.txt" "$RELEASE_CALLS" || fail "the download must fetch the release's SHASUMS256.txt"
[[ "$(grep -c -v -e "--proto =https --proto-redir =https" "$RELEASE_CALLS" || true)" -eq 0 ]] ||
    fail "every download must be HTTPS-only, redirects included: $(cat "$RELEASE_CALLS")"
[[ "$("$cache/bun" --version 2>/dev/null)" = "$PIN" ]] || fail "the pinned bun must be cached at $cache/bun"
ran_with "$cache/bun" || fail "the cached pinned bun must run the install and the build, first on PATH: $(tail -n 2 "$BUN_LOG")"
grep -qF "the checkout pins bun $PIN and $BUN_STUB/bun reports $NEWER" "$TMP/out" || fail "the drift must be reported"
[[ "$(cat "$HOME/.cache/ocode-built-commit")" == "$(cat "$CHECKOUT/.git/HEAD")" ]] || fail "the build with the pinned bun must move the marker"
[[ -z "$(leftovers)" ]] || fail "the download must leave nothing behind: $(leftovers)"
if grep -q "WARN" "$TMP/out"; then
    fail "a successful fetch must not warn: $(grep WARN "$TMP/out")"
fi
pass "a drifted bun gets the pinned one downloaded, verified and cached, and that one installs and builds"

# 24) Cached: used as it is, nothing is downloaded.
new_head
run_script
[[ "$(rc)" -eq 0 ]] || fail "a cached pinned bun must build"
[[ ! -s "$RELEASE_CALLS" ]] || fail "a cached pinned bun must not be downloaded again: $(cat "$RELEASE_CALLS")"
ran_with "$cache/bun" || fail "the cached pinned bun must run the install and the build: $(tail -n 2 "$BUN_LOG")"
grep -qF "using the cached $cache/bun" "$TMP/out" || fail "the cached bun must be named"
pass "a cached copy of the pinned bun is used without a download"

# 25) A cached file that does not report the pin -- replaced, or cut short -- is not trusted: the
#     pinned bun is fetched again over it.
make_bun_stub "$cache/bun" "0.0.0"
new_head
run_script
[[ "$(rc)" -eq 0 ]] || fail "a stale cached bun must not fail the build"
grep -qF "/bun-v$PIN/$x64_asset.zip" "$RELEASE_CALLS" || fail "a stale cached bun must be fetched again"
[[ "$("$cache/bun" --version 2>/dev/null)" = "$PIN" ]] || fail "the stale cached bun must be replaced by the pinned one"
ran_with "$cache/bun" || fail "the refetched bun must run the install and the build"
pass "a cached bun that does not report the pin is fetched again rather than trusted"

# 26) An arm64 machine fetches the aarch64 build.
rm -rf "$HOME/.cache/ocode-bun"
export FAKE_UNAME_M="aarch64"
new_head
run_script
export FAKE_UNAME_M="x86_64"
[[ "$(rc)" -eq 0 ]] || fail "an arm64 fetch must exit 0"
grep -qF "$BUN_RELEASES/bun-v$PIN/bun-linux-aarch64.zip" "$RELEASE_CALLS" ||
    fail "an arm64 machine must fetch bun-linux-aarch64: $(cat "$RELEASE_CALLS")"
ran_with "$cache/bun" || fail "the aarch64 build must run the install and the build"
pass "an arm64 machine fetches the aarch64 build"

# 27) No network: the download fails, the build falls back to the resolved bun with a warning and
#     still runs, and nothing is cached -- an apply without the network still finishes.
rm -rf "$HOME/.cache/ocode-bun"
export RELEASE_FAIL=1
new_head
run_script
unset RELEASE_FAIL
[[ "$(rc)" -eq 0 ]] || fail "a failed download must not fail the apply"
grep -qF "WARN: failed to download bun $PIN from $BUN_RELEASES/bun-v$PIN" "$TMP/out" || fail "a failed download must say what failed"
grep -qF "WARN: bun $PIN is not available, so the build uses $BUN_STUB/bun" "$TMP/out" || fail "the fallback must name the bun it uses"
ran_with "$BUN_STUB/bun" || fail "without the network the resolved bun must run the install and the build"
[[ ! -e "$cache/bun" ]] || fail "a failed download must cache nothing"
[[ "$(cat "$HOME/.cache/ocode-built-commit")" == "$(cat "$CHECKOUT/.git/HEAD")" ]] || fail "the fallback build must move the marker"
[[ -z "$(leftovers)" ]] || fail "a failed download must leave nothing behind: $(leftovers)"
pass "without the network the build warns and falls back to the resolved bun"

# 28) A zip that does not match the release's SHASUMS256.txt -- a corrupted download -- is never
#     extracted or cached, and the build falls back.
cp "$RELEASE/$x64_asset.zip" "$TMP/good.zip"
printf 'x' >>"$RELEASE/$x64_asset.zip"
new_head
run_script
cp "$TMP/good.zip" "$RELEASE/$x64_asset.zip"
[[ "$(rc)" -eq 0 ]] || fail "a checksum mismatch must not fail the apply"
grep -qF "WARN: $x64_asset.zip does not match the checksum in the SHASUMS256.txt of bun $PIN" "$TMP/out" ||
    fail "a checksum mismatch must be reported"
[[ ! -e "$cache" ]] || fail "a zip that fails its checksum must not reach the cache"
ran_with "$BUN_STUB/bun" || fail "a checksum mismatch must fall back to the resolved bun"
[[ -z "$(leftovers)" ]] || fail "a checksum mismatch must leave nothing behind: $(leftovers)"
pass "a zip that does not match the release's SHASUMS256.txt is not used"

# 29) A verified binary that cannot report the pinned version -- one this CPU cannot start, say --
#     is discarded before it takes its cached name, and the build falls back.
printf '#!/bin/bash\nexit 132\n' >"$TMP/broken-bun"
build_release "$TMP/broken-bun"
new_head
run_script
build_release "$TMP/pinned-bun"
[[ "$(rc)" -eq 0 ]] || fail "a bun that cannot start must not fail the apply"
grep -qF "WARN: the downloaded bun reports no version rather than $PIN" "$TMP/out" || fail "a bun that cannot start must be reported"
[[ ! -e "$cache" ]] || fail "a bun that cannot start must not be cached, nor leave its directory"
ran_with "$BUN_STUB/bun" || fail "a bun that cannot start must fall back to the resolved one"
[[ -z "$(leftovers)" ]] || fail "a discarded bun must leave nothing behind: $(leftovers)"
pass "a downloaded bun that cannot report the pinned version is discarded"

# 30) An architecture bun publishes no Linux build for downloads nothing and falls back.
rm -rf "$HOME/.cache/ocode-bun"
export FAKE_UNAME_M="riscv64"
new_head
run_script
export FAKE_UNAME_M="x86_64"
[[ "$(rc)" -eq 0 ]] || fail "an unsupported architecture must not fail the apply"
grep -qF "WARN: bun publishes no Linux build for riscv64" "$TMP/out" || fail "an unsupported architecture must be reported"
[[ ! -s "$RELEASE_CALLS" ]] || fail "an unsupported architecture must download nothing: $(cat "$RELEASE_CALLS")"
ran_with "$BUN_STUB/bun" || fail "an unsupported architecture must fall back to the resolved bun"
pass "an architecture without a bun build falls back without a download"

# 31) No packageManager at all: nothing to fetch, so the resolved bun builds, with a warning.
printf '{\n  "name": "opencode"\n}\n' >"$CHECKOUT/package.json"
new_head
run_script
[[ "$(rc)" -eq 0 ]] || fail "a missing pin must not fail the apply"
grep -qF "WARN: $CHECKOUT/package.json pins no bun release (packageManager is missing)" "$TMP/out" || fail "a missing pin must be reported"
[[ ! -s "$RELEASE_CALLS" ]] || fail "a missing pin must download nothing"
ran_with "$BUN_STUB/bun" || fail "a missing pin must fall back to the resolved bun"
pass "a checkout that pins no bun builds with the resolved one"

# 32) A packageManager that names no bun release -- a tag, a range, another package manager -- is
#     no pin a release download can serve.
for value in "bun@canary" "bun@^1.4.2" "pnpm@9.15.0"; do
    write_manifest "$value"
    new_head
    run_script
    [[ "$(rc)" -eq 0 ]] || fail "$value: must not fail the apply"
    grep -qF "pins no bun release (packageManager is $value)" "$TMP/out" || fail "$value: must be reported as no pin"
    [[ ! -s "$RELEASE_CALLS" ]] || fail "$value: must download nothing"
    ran_with "$BUN_STUB/bun" || fail "$value: must fall back to the resolved bun"
done
pass "a packageManager that names no bun release falls back without a download"

# 33) A package.json that is not JSON cannot be read at all, which warns the same way.
printf 'not json\n' >"$CHECKOUT/package.json"
new_head
run_script
[[ "$(rc)" -eq 0 ]] || fail "an unreadable package.json must not fail the apply"
grep -qF "WARN: could not read packageManager from $CHECKOUT/package.json" "$TMP/out" || fail "an unreadable package.json must be reported"
[[ ! -s "$RELEASE_CALLS" ]] || fail "an unreadable package.json must download nothing"
ran_with "$BUN_STUB/bun" || fail "an unreadable package.json must fall back to the resolved bun"
pass "an unreadable package.json falls back to the resolved bun"
write_manifest "bun@$PIN"

# 34) A failed install fails the apply before anything is built, and leaves the marker where it
#     was, so the next apply tries again.
make_bun_stub "$BUN_STUB/bun" "$PIN"
marker_before="$(cat "$HOME/.cache/ocode-built-commit")"
before="$(calls)"
export BUN_INSTALL_FAIL=1
new_head
run_script
unset BUN_INSTALL_FAIL
[[ "$(rc)" -ne 0 ]] || fail "a failed install must fail the apply"
grep -qF "ERROR: bun install --frozen-lockfile failed in $CHECKOUT" "$TMP/out" || fail "a failed install must say what failed"
[[ "$(calls)" -eq "$before" ]] || fail "a failed install must not build"
[[ "$(cat "$HOME/.cache/ocode-built-commit")" = "$marker_before" ]] || fail "a failed install must leave the marker, so the next apply retries"
pass "a failed dependency install fails the apply before the build"

# 35) The version follows the release the checkout is built on: a checkout rebased onto the next
#     upstream release stamps that release, still marked as the fork's build.
write_cli_manifest "2.2.0"
new_head
run_script
[[ "$(rc)" -eq 0 ]] || fail "a build on another release must succeed: $(cat "$TMP/out")"
identity="$(tail -n 1 "$BUN_ENV")"
[[ "${identity##*/}" =~ ^2\.2\.0-reworked\.[0-9]{10}$ ]] || fail "the version must follow the checkout's release: $identity"
pass "the build version follows the upstream release the checkout is built on"

# 36) A CLI package that names no release version -- no version at all, a pre-release, a file that
#     is not JSON -- stamps 2.0.0 instead, still marked as the fork's build, and says so, so the
#     build stays release-grade and the apply goes on.
for manifest in '{"name": "@opencode/cli"}' '{"name": "@opencode/cli", "version": "0.0.0-dev-202610241230"}' 'not json'; do
    printf '%s\n' "$manifest" >"$CHECKOUT/packages/cli/package.json"
    new_head
    run_script
    [[ "$(rc)" -eq 0 ]] || fail "$manifest: a CLI package without a release version must not fail the apply"
    identity="$(tail -n 1 "$BUN_ENV")"
    [[ "${identity##*/}" =~ ^2\.0\.0-reworked\.[0-9]{10}$ ]] || fail "$manifest: must stamp 2.0.0 as the fork's build: $identity"
    grep -qE "WARN: .*$CHECKOUT/packages/cli/package\.json.*so the build is stamped 2\.0\.0" "$TMP/out" ||
        fail "$manifest: the fallback must be reported: $(grep WARN "$TMP/out")"
done
write_cli_manifest "$CLONE_RELEASE"
pass "a CLI package that names no release version stamps 2.0.0 with a warning"

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-ocode] all ocode fork-builder and bun provisioning tests passed" >&2
fi
exit $EXIT_CODE
