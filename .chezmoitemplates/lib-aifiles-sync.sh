# shellcheck shell=bash
#
# aifiles_sync: fills ~/.claude and ~/.config/opencode from aifiles, the private repository aisync
# syncs them through, on every apply. run_after_linux-014-sync-aifiles.sh.tmpl and
# run_after_android-008-sync-aifiles.sh.tmpl both pull this in, and pass what differs between the
# platforms. "AI Rules Sync" in CLAUDE.md lists the rules it keeps.
#
# Pull only: it never pushes, never runs `aisync sync` and never adds a source. It never fails the
# apply either: every problem is a WARN followed by exit 0, so the next apply tries again.
#
#   aifiles_sync <recipient> <minimum aisync> <self-update|rebuild> [identity]
#
# recipient   the public key aifiles is encrypted to (.chezmoidata/age-keys.yaml)
# minimum     the oldest aisync that reads aifiles' config.yaml as it is
# self-update an older aisync upgrades itself (Linux: releases carry its binaries);
# rebuild     an older aisync is only reported, with the command that rebuilds it (Termux: built
#             from source, and releases carry no Android binary)
# identity    an age identity to put at ~/.config/aisync/key.txt when no key is there yet

_aifiles_prefix="aifiles"

_aifiles_info() { echo "[$_aifiles_prefix] $*" >&2; }
_aifiles_warn() { echo "[$_aifiles_prefix] WARN: $*" >&2; }

# The paths a first sync can replace, relative to $HOME: aisync's allowlists for the two tools
# aifiles syncs here (internal/domain/entities/allowlist.go in aisync), plus Claude's project
# memories, which travel with the conversations. Conversation logs are left out: a pull only ever
# extends them.
_aifiles_scope=(
    .claude/CLAUDE.md .claude/AGENTS.md .claude/settings.json .claude/hooks.json
    .claude/rules .claude/agents .claude/commands .claude/hooks .claude/skills .claude/memories
    .claude/output-styles .claude/scripts
    .config/opencode/AGENTS.md .config/opencode/settings.json .config/opencode/rules
    .config/opencode/agents .config/opencode/commands .config/opencode/skills
    .config/opencode/instructions .config/opencode/memories .config/opencode/plugins
)

# _aifiles_version <aisync>: the release `aisync version` reports; nothing for a development build.
_aifiles_version() {
    local output
    output="$("$1" version 2>/dev/null)" || return 0
    if [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
        printf '%s\n' "${BASH_REMATCH[0]}"
    fi
}

# _aifiles_at_least <version> <minimum>
_aifiles_at_least() {
    local have_version="$1" want_version="$2"
    local -a have want
    local i
    IFS=. read -r -a have <<<"$have_version"
    IFS=. read -r -a want <<<"$want_version"
    for i in 0 1 2; do
        ((10#${have[i]:-0} > 10#${want[i]:-0})) && return 0
        ((10#${have[i]:-0} < 10#${want[i]:-0})) && return 1
    done
    return 0
}

# _aifiles_key_matches <file> <recipient>: an identity age-keygen wrote names its public key in a
# comment; one written without it is asked of age-keygen, where there is one.
_aifiles_key_matches() {
    local key_file="$1" public_key="$2"
    [[ -f "$key_file" ]] || return 1
    grep -qxF "# public key: $public_key" "$key_file" && return 0
    command -v age-keygen >/dev/null 2>&1 && [[ "$(age-keygen -y "$key_file" 2>/dev/null)" == "$public_key" ]]
}

# _aifiles_write_key <file> <recipient> <identity>: stages the identity beside the target and
# renames it into place only once it is the key aifiles is encrypted to.
_aifiles_write_key() {
    local target="$1" recipient="$2" identity="$3" staged
    mkdir -p "${target%/*}"
    chmod 700 "${target%/*}"
    staged="$(mktemp "$target.XXXXXX")"
    printf '%s\n' "$identity" >"$staged"
    if grep -q '^AGE-SECRET-KEY-1' "$staged" && _aifiles_key_matches "$staged" "$recipient"; then
        chmod 600 "$staged"
        mv -f "$staged" "$target"
        return 0
    fi
    rm -f "$staged"
    return 1
}

# aifiles_sync runs the sync with errexit in a subshell of its own, so the first failure nothing
# below expected stops it there -- and is still a warning, never a failed apply.
aifiles_sync() {
    local status
    set +e
    (
        set -e
        _aifiles_sync "$@"
    )
    status=$?
    set -e
    if ((status)); then
        _aifiles_warn "the sync stopped unexpectedly (exit $status), so aifiles may be partly applied; the next apply tries again (~/.cache/aifiles-sync/last-pull.log)"
    fi
    return 0
}

_aifiles_sync() {
    local recipient="$1" min_version="$2" upgrade="$3" identity="${4:-}"
    # The alias of the personal key in the SSH config dot_ssh/config.tmpl renders for Windows (which
    # WSL's ssh.exe reads) and Android: a bare github.com offers every key in the agent, and the
    # first one GitHub accepts may be an account that cannot read aifiles.
    local remote_url="git@github.com-mine:rios0rios0/aifiles.git"
    local config_dir="$HOME/.config/aisync"
    local repo="$config_dir/repo" key="$config_dir/key.txt"
    local state_dir="$HOME/.cache/aifiles-sync"
    local marker="$state_dir/synced-refs" pending="$state_dir/first-sync" log="$state_dir/last-pull.log"
    local rebuild="(cd ~/Development/github.com/rios0rios0/aisync && git pull --ff-only && make install)"

    if [[ "${SKIP_AIFILES_SYNC:-}" == 1 ]]; then
        _aifiles_info "skipped: SKIP_AIFILES_SYNC=1"
        return 0
    fi

    local aisync
    aisync="$(command -v aisync || true)"
    if [[ -z "$aisync" && -x "$HOME/.local/bin/aisync" ]]; then
        aisync="$HOME/.local/bin/aisync"
    fi
    if [[ -z "$aisync" ]]; then
        _aifiles_warn "aisync is not installed, so nothing was synced; the dependency installer's install_aisync installs it"
        return 0
    fi

    mkdir -p "$state_dir"
    chmod 700 "$state_dir"
    (umask 077 && : >"$log")

    # A development build reports no release, and is left to whoever built it.
    local version
    version="$(_aifiles_version "$aisync")"
    if [[ -n "$version" ]] && ! _aifiles_at_least "$version" "$min_version"; then
        if [[ "$upgrade" == self-update ]]; then
            _aifiles_info "aisync $version is older than $min_version, which aifiles needs; upgrading it..."
            timeout -k 30 300 "$aisync" self-update --force </dev/null >>"$log" 2>&1 || true
            version="$(_aifiles_version "$aisync")"
        fi
        if [[ -z "$version" ]] || ! _aifiles_at_least "$version" "$min_version"; then
            if [[ "$upgrade" == self-update ]]; then
                _aifiles_warn "aisync is still ${version:-unknown}, older than the $min_version aifiles needs, so nothing was synced ($log)"
            else
                _aifiles_warn "aisync $version is older than the $min_version aifiles needs, so nothing was synced; rebuild it: $rebuild"
            fi
            return 0
        fi
    fi

    if [[ -n "$identity" && ! -e "$key" ]]; then
        if _aifiles_write_key "$key" "$recipient" "$identity"; then
            _aifiles_info "wrote $key from 1Password"
        else
            _aifiles_warn "1Password returned no age identity for $recipient, so nothing was synced; the next apply tries again"
            return 0
        fi
    fi
    if ! _aifiles_key_matches "$key" "$recipient"; then
        if [[ -e "$key" ]]; then
            _aifiles_warn "$key holds another key, and aifiles is encrypted to $recipient; nothing was synced until it is moved aside (it may decrypt something) and the next apply fetches the right one"
        else
            _aifiles_warn "there is no aisync age key at $key yet, so nothing was synced; the next apply fetches it from 1Password"
        fi
        return 0
    fi

    # Every SSH connection goes through whatever the git config names (ssh.exe on WSL, which
    # reaches 1Password on Windows), and none of them may ask a question: BatchMode turns a
    # prompt into a failure. A host never seen before is accepted once, as a first manual
    # connection would; a key that changed still fails.
    local ssh_command
    ssh_command="$(git config --global --get core.sshCommand || true)"
    export GIT_SSH_COMMAND="${ssh_command:-ssh} -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new"
    export GIT_TERMINAL_PROMPT=0

    # aisync syncs Claude's memories only where ~/.claude/projects exists, and Claude Code creates
    # it at its first conversation; never ~/.claude itself, which would make Claude look installed.
    if [[ -d "$HOME/.claude" ]]; then
        mkdir -p "$HOME/.claude/projects"
    fi

    if [[ ! -e "$repo/.git" ]]; then
        if [[ -e "$repo" ]]; then
            _aifiles_warn "$repo exists but is no checkout, so it was left alone and nothing was synced"
            return 0
        fi
        # Cloned beside the target and renamed into place, so a failed clone leaves nothing a later
        # apply could mistake for a checkout. `init` runs only here: it is not safe to repeat.
        local staging
        mkdir -p "$config_dir"
        chmod 700 "$config_dir"
        staging="$(mktemp -d "$repo.XXXXXX")"
        _aifiles_info "cloning aifiles into $repo..."
        if ! timeout -k 30 600 "$aisync" --use-system-git --repo "$staging" init --remote-url "$remote_url" \
            </dev/null >>"$log" 2>&1; then
            rm -rf "$staging"
            _aifiles_warn "could not clone $remote_url (offline, the SSH key's use not approved in 1Password, or no github.com-mine alias in the SSH config); the next apply tries again ($log)"
            return 0
        fi
        mv "$staging" "$repo"
        # init adds the tools it detects to config.yaml and saves it, and a tracked file that differs
        # makes every later `git pull` fail once aifiles changes it.
        if ! git -C "$repo" diff --quiet -- config.yaml; then
            git -C "$repo" checkout --quiet -- config.yaml
            _aifiles_info "restored the config.yaml aisync init rewrote"
        fi
    fi

    local origin
    origin="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
    if [[ ! "$origin" =~ [:/]rios0rios0/aifiles(\.git)?$ ]]; then
        _aifiles_warn "$repo is no clone of rios0rios0/aifiles (origin: ${origin:-none}), so nothing was synced"
        return 0
    fi

    # One cheap round trip that also bounds a wait for 1Password's approval, and tells whether
    # anything moved since the last sync.
    local refs
    if ! refs="$(timeout -k 10 90 git -C "$repo" ls-remote origin refs/heads/main refs/heads/transcripts 2>>"$log")"; then
        _aifiles_warn "aifiles is unreachable (offline, or the SSH key's use not approved in 1Password); the next apply tries again ($log)"
        return 0
    fi
    local state="aisync=${version:-dev}" sha ref
    while read -r sha ref; do
        if [[ -n "$ref" ]]; then
            state+=" $ref=$sha"
        fi
    done <<<"$refs"

    # A device that never synced: no manifest aisync keeps in ~/.claude, no conversation state in
    # the clone, or a first sync an earlier apply started and did not finish.
    local first=false
    if [[ -e "$pending" ]] ||
        { [[ ! -e "$HOME/.claude/.aisync-manifest.json" ]] && [[ ! -e "$repo/.aisync/transcripts-base.json" ]]; }; then
        first=true
    fi
    if ! $first && [[ -f "$marker" && "$(<"$marker")" == "$state" ]]; then
        _aifiles_info "aifiles is unchanged since the last sync"
        return 0
    fi

    local -a args=(--force)
    local backup_dir="" sums=""
    if $first; then
        # aifiles' copy wins every conflict on the first sync, so whatever it replaces is kept
        # first: every file in scope goes into a private directory in $TMPDIR, with its checksum
        # to name afterwards the ones that were replaced.
        : >"$pending"
        args+=(--prefer remote)
        local -a present=() files=()
        local path file
        for path in "${_aifiles_scope[@]}" "$HOME"/.claude/projects/*/memory; do
            path="${path#"$HOME"/}"
            if [[ -e "$HOME/$path" ]]; then
                present+=("$path")
            fi
        done
        if ((${#present[@]})); then
            while IFS= read -r -d '' file; do
                files+=("$file")
            done < <(cd "$HOME" && find "${present[@]}" -type f \
                ! -path '.claude/skills/synced/*' ! -path '.claude/skills/.trash/*' -print0)
        fi
        if ((${#files[@]})); then
            backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/aifiles-first-sync.XXXXXX")"
            sums="$backup_dir/checksums"
            if ! (cd "$HOME" && umask 077 &&
                printf '%s\0' "${files[@]}" | tar -czf "$backup_dir/before.tar.gz" --null -T - &&
                printf '%s\0' "${files[@]}" | xargs -0 sha256sum >"$sums"); then
                _aifiles_warn "could not back up the ${#files[@]} local file(s) a first sync would replace, so nothing was synced"
                return 0
            fi
            _aifiles_info "first sync: aifiles' copy wins every conflict; the ${#files[@]} local file(s) it may replace are backed up in $backup_dir/before.tar.gz"
        else
            _aifiles_info "first sync: nothing local overlaps aifiles, so there is nothing to back up"
        fi
    fi

    local status=0
    _aifiles_info "pulling aifiles (aisync pull ${args[*]})..."
    timeout -k 30 1800 "$aisync" --use-system-git --repo "$repo" pull "${args[@]}" </dev/null 2>&1 |
        tee -a "$log" >&2 || status="${PIPESTATUS[0]}"
    case "$status" in
        0) ;;
        124 | 137)
            _aifiles_warn "aisync pull timed out; the next apply resumes it ($log)"
            return 0
            ;;
        *)
            _aifiles_warn "aisync pull exited $status; the next apply tries again ($log, and 'git -C $repo status' if the clone cannot fast-forward)"
            return 0
            ;;
    esac

    if [[ -n "$sums" ]]; then
        local -a replaced=()
        local line
        while IFS= read -r line; do
            replaced+=("${line%: FAILED*}")
        done < <(cd "$HOME" && sha256sum --quiet -c "$sums" 2>/dev/null || true)
        if ((${#replaced[@]})); then
            _aifiles_info "the first sync replaced ${#replaced[@]} local file(s), kept in $backup_dir/before.tar.gz: ${replaced[*]}"
        else
            _aifiles_info "the first sync replaced none of the local files backed up in $backup_dir/before.tar.gz"
        fi
    fi
    rm -f "$pending"

    if grep -qF 'conflict(s) skipped' "$log"; then
        _aifiles_warn "changes on both sides were left alone and are reported again on every apply; run 'aisync sync' in a terminal to settle them"
        return 0
    fi
    printf '%s\n' "$state" >"$marker"
    _aifiles_info "in sync with aifiles"
}
