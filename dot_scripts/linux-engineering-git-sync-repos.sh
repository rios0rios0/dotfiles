_git_sync_single_repo() {
    local repo_dir="$1"
    local root="$2"
    local wip_branch="wip/auto-stash-$(date +%Y%m%d-%H%M%S-%N)-$RANDOM-$$"
    local name="${repo_dir#$root/}"
    local status_label="SYNCED"

    # detect default branch
    local default_branch
    default_branch=$(git -C "$repo_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    [[ -z "$default_branch" ]] && default_branch="main"

    # save current branch
    local current_branch
    current_branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null)
    [[ -z "$current_branch" ]] && current_branch="$default_branch"

    # check for uncommitted changes (staged + unstaged + untracked)
    local has_changes=false
    if [[ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]]; then
        has_changes=true
    fi

    if $has_changes; then
        # create a WIP branch and commit everything
        if ! git -C "$repo_dir" checkout -b "$wip_branch" </dev/null >/dev/null 2>&1; then
            printf "%-50s FAIL (could not create wip branch)\n" "$name"
            return 1
        fi
        git -C "$repo_dir" add -A </dev/null >/dev/null 2>&1
        if ! git -C "$repo_dir" commit --no-verify -m "wip: auto-stash uncommitted changes" </dev/null >/dev/null 2>&1; then
            git -C "$repo_dir" checkout "$current_branch" </dev/null >/dev/null 2>&1
            git -C "$repo_dir" branch -D "$wip_branch" </dev/null >/dev/null 2>&1
            printf "%-50s FAIL (could not auto-commit wip changes; see git status)\n" "$name"
            return 1
        fi
    fi

    # checkout default branch and sync
    if ! git -C "$repo_dir" checkout "$default_branch" </dev/null >/dev/null 2>&1; then
        if $has_changes; then
            git -C "$repo_dir" checkout "$wip_branch" </dev/null >/dev/null 2>&1
        else
            git -C "$repo_dir" checkout "$current_branch" </dev/null >/dev/null 2>&1
        fi
        printf "%-50s FAIL (could not checkout %s)\n" "$name" "$default_branch"
        return 1
    fi

    git -C "$repo_dir" fetch --all --prune -q </dev/null >/dev/null 2>&1
    if ! git -C "$repo_dir" pull --rebase </dev/null >/dev/null 2>&1; then
        git -C "$repo_dir" rebase --abort </dev/null >/dev/null 2>&1
        if $has_changes; then
            git -C "$repo_dir" checkout "$wip_branch" </dev/null >/dev/null 2>&1
        else
            git -C "$repo_dir" checkout "$current_branch" </dev/null >/dev/null 2>&1
        fi
        printf "%-50s FAIL (pull --rebase failed)\n" "$name"
        return 1
    fi

    # restore original state
    if $has_changes; then
        # rebase wip commits on top of updated default branch
        git -C "$repo_dir" checkout "$wip_branch" </dev/null >/dev/null 2>&1
        if ! git -C "$repo_dir" rebase "$default_branch" </dev/null >/dev/null 2>&1; then
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
        echo "ERROR: directory not found: $root"
        return 1
    fi

    # collect all repos first (avoids stdin issues with the loop)
    local repos=()
    while IFS= read -r git_dir; do
        repos+=("${git_dir%/.git}")
    done < <(find "$root" -name .git -type d 2>/dev/null | sort)

    local total=${#repos[@]}
    if [[ $total -eq 0 ]]; then
        echo "No git repositories found in $root"
        return 0
    fi

    local max_jobs
    max_jobs=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
    local tmp_dir
    tmp_dir=$(mktemp -d) || { echo "ERROR: could not create temp directory"; return 1; }
    trap 'rm -rf "$tmp_dir"' RETURN INT TERM

    echo "Syncing $total repositories ($max_jobs parallel workers)..."
    echo ""

    # process repos in parallel batches
    local i=0
    while [[ $i -lt $total ]]; do
        local batch_end=$((i + max_jobs))
        [[ $batch_end -gt $total ]] && batch_end=$total

        local pids=()
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
    for ((j = 0; j < total; j++)); do
        local line
        line=$(cat "$tmp_dir/$j.out")
        echo "$line"
        case "$line" in
            *"SYNCED (wip:"*) synced=$((synced + 1)); stashed=$((stashed + 1)) ;;
            *SYNCED*) synced=$((synced + 1)) ;;
            *FAIL*) failed=$((failed + 1)) ;;
        esac
    done

    echo ""
    echo "--- Summary ---"
    echo "Total: $total | Synced: $synced | WIP commits: $stashed | Failed: $failed"
}
