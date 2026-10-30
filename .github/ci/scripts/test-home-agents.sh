#!/bin/bash
set -euo pipefail

# Tests the agent guide chezmoi writes to the home folder of every platform in place of the
# repository's own AGENTS.md: ~/AGENTS.md everywhere, and the same guide as ~/CLAUDE.md on Linux and
# Termux, where Claude Code runs. Covers the guide rendered for WSL, bare-metal Linux, Termux and
# Windows -- each with its own platform's facts and none of another's, small, fully rendered, and
# holding no line that would end the here-doc or here-string carrying it -- each platform getting
# its own writer and no other, and the writers against a sandbox home: the Linux and Termux scripts
# under bash, the Windows one under pwsh when it is installed. A writer replaces the repository's
# 161 KB copy, creates a missing guide, leaves an identical one untouched and nothing behind, and
# refuses a directory at the target; the Linux and Termux ones write ~/CLAUDE.md identical to
# ~/AGENTS.md, and the Windows one writes no ~/CLAUDE.md, but UTF-8 without a BOM and LF line
# endings, whatever line endings its own checkout has. Whether chezmoi deploys the repository's
# AGENTS.md and CLAUDE.md, and that it deletes aisync's global instruction files, is
# make test-chezmoiignore's and make test-aifiles-sync's.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPTS="$REPO_ROOT/.chezmoiscripts"
LINUX_WRITER="$SCRIPTS/run_onchange_after_linux-019-write-home-agents.sh.tmpl"
ANDROID_WRITER="$SCRIPTS/run_onchange_after_android-011-write-home-agents.sh.tmpl"
WINDOWS_WRITER="$SCRIPTS/run_onchange_after_windows-006-write-home-agents.ps1.tmpl"
EXIT_CODE=0
# The most a rendered guide may weigh. Agents load it into their context -- OpenCode V2 in every
# session under the home folder -- and the file it replaced, the repository's AGENTS.md, was 161 KB.
MAX_BYTES=8192

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-home-agents] testing the home AGENTS.md and its writers..." >&2

pass() { echo "[test-home-agents] PASS: $1" >&2; }
fail() { echo "[test-home-agents] FAIL: $1" >&2; EXIT_CODE=1; }

if ! command -v chezmoi >/dev/null 2>&1; then
    echo "[test-home-agents] FAIL: chezmoi is not on PATH, so nothing can be rendered" >&2
    exit 1
fi

# A config of its own, naming this checkout as the source: the default source directory is another
# clone, or nothing on CI. The guide reads no data key, so none is set.
printf 'sourceDir: "%s"\n' "$REPO_ROOT" >"$TMP/chezmoi.yaml"

# What each platform the guide is rendered for overrides in chezmoi's data. The kernel is a literal,
# so the host that runs this suite -- WSL on a developer's box, bare metal on a CI runner -- never
# decides which branch renders.
declare -A DATA=(
    [wsl]='{"chezmoi":{"os":"linux","kernel":{"osrelease":"6.18.33.2-microsoft-standard-WSL2","ostype":"Linux","version":"#1 SMP"}}}'
    [metal]='{"chezmoi":{"os":"linux","kernel":{"osrelease":"6.11.0-generic","ostype":"Linux","version":"#1 SMP"}}}'
    [android]='{"chezmoi":{"os":"android","kernel":{"osrelease":"5.15.0-android13","ostype":"Linux","version":"#1 SMP"}}}'
    [windows]='{"chezmoi":{"os":"windows"}}'
)
# The title each platform's guide carries.
declare -A TITLE=(
    [wsl]="Kali Linux on WSL 2"
    [metal]="Linux"
    [android]="Termux on Android"
    [windows]="Windows"
)

# The guide as the writers embed it, and a template file, rendered for a platform.
render_guide() {
    chezmoi execute-template --config "$TMP/chezmoi.yaml" --override-data "${DATA[$1]}" \
        '{{ includeTemplate "home-agents.md" . | trim }}'
}
render_file() {
    chezmoi execute-template --config "$TMP/chezmoi.yaml" --override-data "${DATA[$1]}" <"$2"
}

# has / lacks <platform> <text>...: whether the platform's guide says each text.
has() {
    local platform="$1" text
    shift
    for text in "$@"; do
        grep -qF -- "$text" "$TMP/guide-$platform.md" || fail "$platform: the guide must say '$text'"
    done
}
lacks() {
    local platform="$1" text
    shift
    for text in "$@"; do
        if grep -qF -- "$text" "$TMP/guide-$platform.md"; then
            fail "$platform: the guide must not say '$text'"
        fi
    done
}

# --- The guide, per platform ------------------------------------------------------------------

for platform in wsl metal android windows; do
    if ! render_guide "$platform" >"$TMP/guide-$platform.md" 2>"$TMP/render-err"; then
        fail "$platform: the guide does not render: $(cat "$TMP/render-err")"
        continue
    fi
    guide="$TMP/guide-$platform.md"
    [[ "$(head -n 1 "$guide")" == "# Working on this machine: ${TITLE[$platform]}" ]] ||
        fail "$platform: the title must name the platform: $(head -n 1 "$guide")"
    has "$platform" ".chezmoitemplates/home-agents.md" "Secrets live in 1Password"
    size="$(wc -c <"$guide")"
    ((size <= MAX_BYTES)) || fail "$platform: the guide weighs $size bytes, past the $MAX_BYTES it may"
    if grep -qF -e '{{' -e '}}' "$guide"; then
        fail "$platform: the guide holds an unrendered template action"
    fi
    # The repository's AGENTS.md, which agents working on the dotfiles read, is not this file.
    lacks "$platform" "## Quality Commands" "## Dependency Lifecycle"
    # The writers carry the guide in a here-doc ended by HOME_AGENTS_MD and in a here-string ended
    # by a line that starts with '@.
    if grep -qx 'HOME_AGENTS_MD' "$guide" || grep -q "^'@" "$guide"; then
        fail "$platform: a line of the guide would end the here-doc or here-string that carries it"
    fi
done
pass "every platform's guide renders, names its platform, stays under $MAX_BYTES bytes and is not the repository's AGENTS.md"

# zsh's caveats on the three platforms that run it: the interactive cp/rm/mv guards, eza, global
# aliases, globs and the differences from bash. The guide is also ~/CLAUDE.md there, and it carries
# what aisync's deleted ~/.claude/CLAUDE.md held beyond it: the git rules, Claude Code's own
# directories and the credential loader.
for platform in wsl metal android; do
    has "$platform" '`command cp`' "NO_NOMATCH" '`H` is `| head`' "eza -1 --classify" "zsh -c" \
        '`path` is tied to `PATH`' "<<'EOF'" '/proc/<pid>/cmdline' 'and `~/CLAUDE.md`' \
        "## Git and GitHub" 'rebased on top of `main`' '`~/.claude/rules/`' \
        "linux-engineering-shell-credentials.sh" '`OMNIROUTE_API_KEY`'
    lacks "$platform" '$LASTEXITCODE' "Remove-Item"
done
pass "the zsh platforms get the cp/rm/mv guards, eza, global aliases, globs, quoting, the git rules and Claude Code's notes"

# OpenCode is ocode, on Linux alone; what aisync's deleted ~/.config/opencode/AGENTS.md held beyond
# the guide -- the pointer to its standards, its directories, its models -- comes with it.
for platform in wsl metal; do
    has "$platform" '`ocode`' '`~/.config/opencode/rules/`' '`omniroute/auto/coding`' 'http://127.0.0.1:20128'
done
pass "Linux's guides point ocode at its standards, directories and models"

has wsl "/mnt/c" "ssh.exe" '`wsl.exe` on the way to Windows' "Docker Desktop" "agent refused operation" \
    "credential.helper='!gh auth git-credential'" "--no-gpg-sign" '`local-services/omniroute/`'
pass "WSL's guide covers Windows' programs, its 1Password, the layers on the way to Windows and pushing over HTTPS"

lacks metal ".exe" "/mnt" "Windows" "1Password app" "Termux" "credential.helper" "--no-gpg-sign" "local-services"
pass "bare-metal Linux's guide says nothing of Windows, Termux or WSL's push and signing rules"

has android '$PREFIX' "termux-exec" '$TMPDIR' "bionic" "signal 9"
lacks android ".exe" "/mnt" "Windows" "1Password app" "ocode" "~/.config/opencode/rules/" "credential.helper" "--no-gpg-sign"
pass "the Termux guide covers its paths, shebangs, C library and process budget, and nothing of Windows, WSL or ocode"

has windows "wsl.exe -d kali-linux --exec zsh -c" '$LASTEXITCODE' "Remove-Item -Recurse -Force" \
    "curl.exe" "UTF-16" "agent refused operation"
lacks windows '`command cp`' "NO_NOMATCH" "eza" '/proc/<pid>/cmdline' "termux-exec" "CLAUDE.md" \
    "## Git and GitHub" "Claude Code" "ocode"
pass "the Windows guide covers PowerShell, reaching WSL and its 1Password, and nothing of zsh, Claude Code or ocode"

# --- Each platform runs its own writer --------------------------------------------------------

# The scripts chezmoi resolves for an OS, from the whole source state.
scripts_for() {
    chezmoi --config "$TMP/chezmoi.yaml" --destination "$TMP/dest-$1" --persistent-state "$TMP/$1.boltdb" \
        --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" managed --include scripts --path-style relative
}
declare -A WRITER=(
    [linux]=".chezmoiscripts/linux-019-write-home-agents.sh"
    [android]=".chezmoiscripts/android-011-write-home-agents.sh"
    [windows]=".chezmoiscripts/windows-006-write-home-agents.ps1"
)
for os in linux android windows; do
    if ! scripts="$(scripts_for "$os" 2>&1)"; then
        fail "$os: chezmoi could not resolve the source state: $(tail -n 1 <<<"$scripts")"
        continue
    fi
    for writer_os in linux android windows; do
        if grep -qxF "${WRITER[$writer_os]}" <<<"$scripts"; then
            [[ "$writer_os" == "$os" ]] || fail "$os: must not run ${WRITER[$writer_os]}"
        else
            [[ "$writer_os" != "$os" ]] || fail "$os: must run ${WRITER[$writer_os]}"
        fi
    done
done
pass "each platform runs its own writer and no other"

# --- The Linux and Termux writers, under bash -------------------------------------------------

# A stand-in for the repository's AGENTS.md, which every home folder held before: 161 KB of it.
make_old_copy() { head -c 164864 /dev/zero | tr '\0' 'x' >"$1"; }

run_bash_writer() {
    local status=0
    HOME="$1" bash "$2" >"$TMP/out" 2>&1 || status=$?
    echo "$status" >"$TMP/rc"
}
rc() { cat "$TMP/rc"; }
staged_leftovers() {
    find "$1" -maxdepth 1 \( -name '.AGENTS.md.*' -o -name '.CLAUDE.md.*' -o -name '.home-agents.*' \) 2>/dev/null
}

for platform in wsl android; do
    if [[ "$platform" == "wsl" ]]; then writer="$LINUX_WRITER"; else writer="$ANDROID_WRITER"; fi
    if ! render_file "$platform" "$writer" >"$TMP/writer-$platform.sh" 2>"$TMP/render-err"; then
        fail "$platform: the writer does not render: $(cat "$TMP/render-err")"
        continue
    fi
    home="$TMP/home-$platform"
    mkdir -p "$home"
    printf '%s\n' "$(cat "$TMP/guide-$platform.md")" >"$TMP/expected-$platform.md"

    # The repository's copies are replaced by the guide, in both files, readable by all, ending in
    # one newline: ~/AGENTS.md for OpenCode, ~/CLAUDE.md for Claude Code.
    make_old_copy "$home/AGENTS.md"
    make_old_copy "$home/CLAUDE.md"
    run_bash_writer "$home" "$TMP/writer-$platform.sh"
    [[ "$(rc)" -eq 0 ]] || fail "$platform: replacing the old copies must succeed: $(cat "$TMP/out")"
    for name in AGENTS.md CLAUDE.md; do
        cmp -s "$TMP/expected-$platform.md" "$home/$name" ||
            fail "$platform: ~/$name must hold the rendered guide and a final newline"
        [[ "$(stat -c %a "$home/$name")" == "644" ]] || fail "$platform: ~/$name must be mode 644"
        grep -qF "[home-agents] wrote the agent guide for this machine to $home/$name" "$TMP/out" ||
            fail "$platform: the write of ~/$name must be reported: $(cat "$TMP/out")"
    done

    # An identical guide is left alone in both files: no write, so their times stay where they were
    # put, and no line.
    touch -d '2001-01-01 00:00' "$home/AGENTS.md" "$home/CLAUDE.md"
    run_bash_writer "$home" "$TMP/writer-$platform.sh"
    [[ "$(rc)" -eq 0 ]] || fail "$platform: an unchanged guide must exit 0"
    for name in AGENTS.md CLAUDE.md; do
        [[ "$(stat -c %Y "$home/$name")" -eq "$(date -d '2001-01-01 00:00' +%s)" ]] ||
            fail "$platform: an identical ~/$name must not be rewritten"
    done
    [[ ! -s "$TMP/out" ]] || fail "$platform: an identical guide must be left without a word: $(cat "$TMP/out")"

    # A missing ~/CLAUDE.md -- the state of every machine before this guide -- is created, and the
    # ~/AGENTS.md beside it, already the guide, is left alone.
    rm -f "$home/CLAUDE.md"
    run_bash_writer "$home" "$TMP/writer-$platform.sh"
    cmp -s "$TMP/expected-$platform.md" "$home/CLAUDE.md" || fail "$platform: a missing ~/CLAUDE.md must be created"
    if grep -qF "$home/AGENTS.md" "$TMP/out"; then
        fail "$platform: an ~/AGENTS.md that is already the guide must not be rewritten"
    fi

    # A missing guide is created.
    rm -f "$home/AGENTS.md"
    run_bash_writer "$home" "$TMP/writer-$platform.sh"
    cmp -s "$TMP/expected-$platform.md" "$home/AGENTS.md" || fail "$platform: a missing ~/AGENTS.md must be created"
    [[ -z "$(staged_leftovers "$home")" ]] || fail "$platform: the writer must leave nothing behind: $(staged_leftovers "$home")"

    # A directory at ~/AGENTS.md is refused, not filled with the guide.
    rm -f "$home/AGENTS.md"
    mkdir "$home/AGENTS.md"
    run_bash_writer "$home" "$TMP/writer-$platform.sh"
    [[ "$(rc)" -ne 0 ]] || fail "$platform: a directory at ~/AGENTS.md must fail the writer"
    [[ -z "$(find "$home/AGENTS.md" -mindepth 1)" ]] || fail "$platform: the guide must not be moved into the directory"
    grep -qF "ERROR: could not move the agent guide into place" "$TMP/out" || fail "$platform: the refusal must say what failed: $(cat "$TMP/out")"
    [[ -z "$(staged_leftovers "$home")" ]] || fail "$platform: a refused write must leave nothing behind"
    rmdir "$home/AGENTS.md"
done
pass "the Linux and Termux writers put the guide in ~/AGENTS.md and ~/CLAUDE.md, replace old copies, create missing ones, leave identical ones alone and refuse a directory"

# --- The Windows writer, under pwsh -----------------------------------------------------------

if ! command -v pwsh >/dev/null 2>&1; then
    echo "[test-home-agents] SKIP: pwsh is not installed, so the Windows writer is not run" >&2
elif ! render_file windows "$WINDOWS_WRITER" >"$TMP/writer-windows.ps1" 2>"$TMP/render-err"; then
    fail "windows: the writer does not render: $(cat "$TMP/render-err")"
else
    # A Windows checkout made with core.autocrlf, Git for Windows' default, has CRLF line endings,
    # and a here-string keeps the script's own.
    sed 's/$/\r/' "$TMP/writer-windows.ps1" >"$TMP/writer-windows-crlf.ps1"
    home="$TMP/home-windows"
    mkdir -p "$home"
    printf '%s\n' "$(cat "$TMP/guide-windows.md")" >"$TMP/expected-windows.md"
    run_pwsh_writer() {
        local status=0
        HOME="$home" pwsh -NoProfile -NonInteractive -File "$1" >"$TMP/out" 2>&1 || status=$?
        echo "$status" >"$TMP/rc"
    }

    for script in "$TMP/writer-windows.ps1" "$TMP/writer-windows-crlf.ps1"; do
        label="$(basename "$script")"
        make_old_copy "$home/AGENTS.md"
        run_pwsh_writer "$script"
        [[ "$(rc)" -eq 0 ]] || fail "$label: replacing the old copy must succeed: $(cat "$TMP/out")"
        cmp -s "$TMP/expected-windows.md" "$home/AGENTS.md" ||
            fail "$label: ~/AGENTS.md must hold the rendered guide with LF endings and a final newline: $(od -c "$home/AGENTS.md" | head -n 2)"
        [[ "$(head -c 3 "$home/AGENTS.md" | od -An -tx1 | tr -d ' ')" != "efbbbf" ]] || fail "$label: ~/AGENTS.md must have no BOM"
        grep -qF "[home-agents] wrote the agent guide for this machine to" "$TMP/out" || fail "$label: a write must be reported"
        [[ ! -e "$home/AGENTS.md.new" ]] || fail "$label: the writer must leave nothing behind"
        # Claude Code is not installed on Windows, so no ~/CLAUDE.md is written there.
        [[ ! -e "$home/CLAUDE.md" ]] || fail "$label: the Windows writer must write no ~/CLAUDE.md"
    done

    touch -d '2001-01-01 00:00' "$home/AGENTS.md"
    run_pwsh_writer "$TMP/writer-windows-crlf.ps1"
    [[ "$(rc)" -eq 0 ]] || fail "windows: an unchanged guide must exit 0"
    [[ "$(stat -c %Y "$home/AGENTS.md")" -eq "$(date -d '2001-01-01 00:00' +%s)" ]] ||
        fail "windows: an identical guide must not be rewritten"
    [[ ! -s "$TMP/out" ]] || fail "windows: an identical guide must be left without a word: $(cat "$TMP/out")"
    pass "the Windows writer replaces the old copy with UTF-8, no BOM and LF endings from either checkout, writes no ~/CLAUDE.md, and leaves an identical guide alone"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-home-agents] all home AGENTS.md tests passed" >&2
fi
exit $EXIT_CODE
