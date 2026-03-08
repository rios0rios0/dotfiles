_git_sync_single_repo() {
    local repo_dir="$1"
    local root="$2"
    local wip_branch="wip/auto-stash-$(date +%Y%m%d-%H%M%S-%N)-$RANDOM-$$"
    local name="${repo_dir#$root/}"
    local status_label="SYNCED"
    local _err

    # detect default branch
    local default_branch
    default_branch=$(git -C "$repo_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    if [[ -z "$default_branch" ]]; then
        default_branch="main"
        printf "  [%s] WARN: could not detect default branch, assuming '%s'\n" "$name" "$default_branch"
    fi

    # save current branch
    local current_branch
    current_branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null)
    if [[ -z "$current_branch" ]]; then
        current_branch="$default_branch"
        printf "  [%s] WARN: detached HEAD, assuming '%s'\n" "$name" "$default_branch"
    fi

    # check for uncommitted changes (staged + unstaged + untracked)
    local has_changes=false
    if [[ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]]; then
        has_changes=true
    fi

    printf "  [%s] branch='%s' default='%s' dirty=%s\n" "$name" "$current_branch" "$default_branch" "$has_changes"

    if $has_changes; then
        # create a WIP branch and commit everything
        if ! _err=$(git -C "$repo_dir" checkout -b "$wip_branch" </dev/null 2>&1); then
            printf "  [%s] ERROR: could not create wip branch: %s\n" "$name" "$_err"
            printf "%-50s FAIL (could not create wip branch)\n" "$name"
            return 1
        fi
        git -C "$repo_dir" add -A </dev/null >/dev/null 2>&1
        if ! _err=$(git -C "$repo_dir" commit --no-verify -m "wip: auto-stash uncommitted changes" </dev/null 2>&1); then
            printf "  [%s] ERROR: could not auto-commit wip changes: %s\n" "$name" "$_err"
            local cleanup_note=""
            if ! git -C "$repo_dir" checkout "$current_branch" </dev/null >/dev/null 2>&1; then
                cleanup_note="; still on '$wip_branch', clean up manually"
                printf "  [%s] ERROR: failed to restore branch '%s'\n" "$name" "$current_branch"
            elif ! git -C "$repo_dir" branch -D "$wip_branch" </dev/null >/dev/null 2>&1; then
                cleanup_note="; delete '$wip_branch' manually"
                printf "  [%s] WARN: failed to delete temporary branch '%s'\n" "$name" "$wip_branch"
            fi
            printf "%-50s FAIL (wip commit failed%s)\n" "$name" "$cleanup_note"
            return 1
        fi
        printf "  [%s] stashed changes on '%s'\n" "$name" "$wip_branch"
    fi

    # checkout default branch and sync
    if ! _err=$(git -C "$repo_dir" checkout "$default_branch" </dev/null 2>&1); then
        printf "  [%s] ERROR: could not checkout '%s': %s\n" "$name" "$default_branch" "$_err"
        if $has_changes; then
            git -C "$repo_dir" checkout "$wip_branch" </dev/null >/dev/null 2>&1
        else
            git -C "$repo_dir" checkout "$current_branch" </dev/null >/dev/null 2>&1
        fi
        printf "%-50s FAIL (could not checkout %s)\n" "$name" "$default_branch"
        return 1
    fi

    if ! _err=$(git -C "$repo_dir" fetch --all --prune -q </dev/null 2>&1); then
        printf "  [%s] WARN: fetch failed: %s\n" "$name" "$_err"
    fi

    if ! _err=$(git -C "$repo_dir" pull --rebase </dev/null 2>&1); then
        printf "  [%s] ERROR: pull --rebase failed: %s\n" "$name" "$_err"
        git -C "$repo_dir" rebase --abort </dev/null >/dev/null 2>&1
        if $has_changes; then
            git -C "$repo_dir" checkout "$wip_branch" </dev/null >/dev/null 2>&1
            printf "  [%s] restored to wip branch '%s'\n" "$name" "$wip_branch"
        else
            git -C "$repo_dir" checkout "$current_branch" </dev/null >/dev/null 2>&1
            printf "  [%s] restored to '%s'\n" "$name" "$current_branch"
        fi
        printf "%-50s FAIL (pull --rebase failed)\n" "$name"
        return 1
    fi

    # restore original state
    if $has_changes; then
        # rebase wip commits on top of updated default branch
        git -C "$repo_dir" checkout "$wip_branch" </dev/null >/dev/null 2>&1
        if ! _err=$(git -C "$repo_dir" rebase "$default_branch" </dev/null 2>&1); then
            printf "  [%s] WARN: wip rebase on '%s' failed, aborted: %s\n" "$name" "$default_branch" "$_err"
            git -C "$repo_dir" rebase --abort </dev/null >/dev/null 2>&1
        fi
        # return to the original branch the user was on
        git -C "$repo_dir" checkout "$current_branch" </dev/null >/dev/null 2>&1
        status_label="SYNCED (wip: $wip_branch)"
    else
        if [[ "$current_branch" != "$default_branch" ]]; then
            git -C "$repo_dir" checkout "$current_branch" </dev/null >/dev/null 2>&1
        fi
    fi

    printf "%-50s %s\n" "$name" "$status_label"
    return 0
}

git-sync-repos() {
    local root="${1:-$PWD}"

    if [[ ! -d "$root" ]]; then
        echo "[git-sync] ERROR: directory not found: $root"
        return 1
    fi

    # collect all repos first (avoids stdin issues with the loop)
    local repos=()
    while IFS= read -r git_dir; do
        repos+=("${git_dir%/.git}")
    done < <(find "$root" -name .git -type d 2>/dev/null | sort)

    local total=${#repos[@]}
    if [[ $total -eq 0 ]]; then
        echo "[git-sync] No git repositories found in $root"
        return 0
    fi

    local max_jobs
    max_jobs=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    local tmp_dir
    tmp_dir=$(mktemp -d) || { echo "[git-sync] ERROR: could not create temp directory"; return 1; }

    # Save and replace INT/TERM traps to clean up tmp_dir on signal; restore before returning
    local _saved_int _saved_term
    _saved_int=$(trap -p INT 2>/dev/null)
    _saved_term=$(trap -p TERM 2>/dev/null)
    trap 'rm -rf "$tmp_dir"' INT TERM

    echo "[git-sync] syncing $total repositories ($max_jobs parallel workers) from $root"
    echo ""

    # process repos in parallel batches
    local i=0
    while [[ $i -lt $total ]]; do
        local batch_end=$((i + max_jobs))
        [[ $batch_end -gt $total ]] && batch_end=$total

        local pids=()
        local j
        for ((j = i; j < batch_end; j++)); do
            _git_sync_single_repo "${repos[$j]}" "$root" > "$tmp_dir/$j.out" 2>&1 &
            pids+=("$!")
        done
        if [[ ${#pids[@]} -gt 0 ]]; then
            wait "${pids[@]}"
        fi

        i=$batch_end
    done

    # print results and tally
    local synced=0 stashed=0 failed=0
    local j
    for ((j = 0; j < total; j++)); do
        local output
        output=$(cat "$tmp_dir/$j.out")
        echo "$output"
        case "$output" in
            *"SYNCED (wip:"*) synced=$((synced + 1)); stashed=$((stashed + 1)) ;;
            *SYNCED*) synced=$((synced + 1)) ;;
            *FAIL*) failed=$((failed + 1)) ;;
        esac
    done

    echo ""
    echo "[git-sync] --- Summary ---"
    echo "[git-sync] Total: $total | Synced: $synced | WIP commits: $stashed | Failed: $failed"

    rm -rf "$tmp_dir"
    if [[ -n "$_saved_int" ]]; then eval "$_saved_int"; else trap - INT; fi
    if [[ -n "$_saved_term" ]]; then eval "$_saved_term"; else trap - TERM; fi
}
