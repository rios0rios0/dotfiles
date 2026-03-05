git-sync-repos() {
    local root="${1:-$PWD}"
    local wip_branch="wip/auto-stash-$(date +%Y%m%d-%H%M%S)"

    if [[ ! -d "$root" ]]; then
        echo "ERROR: directory not found: $root"
        return 1
    fi

    local total=0 synced=0 stashed=0 failed=0
    local repo_dir name default_branch current_branch has_changes pull_output

    # find all git repos recursively at any depth
    while IFS= read -r git_dir; do
        repo_dir="${git_dir%/.git}"
        total=$((total + 1))

        name="${repo_dir#$root/}"
        printf "%-50s " "$name"

        # detect default branch
        default_branch=$(git -C "$repo_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
        [[ -z "$default_branch" ]] && default_branch="main"

        # save current branch
        current_branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null)
        [[ -z "$current_branch" ]] && current_branch="$default_branch"

        # check for uncommitted changes (staged + unstaged + untracked)
        has_changes=false
        if [[ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]]; then
            has_changes=true
        fi

        if $has_changes; then
            # create a WIP branch and commit everything
            git -C "$repo_dir" checkout -b "$wip_branch" 2>/dev/null
            if [[ $? -ne 0 ]]; then
                echo "FAIL (could not create wip branch)"
                failed=$((failed + 1))
                continue
            fi
            git -C "$repo_dir" add -A 2>/dev/null
            git -C "$repo_dir" commit --no-verify -m "wip: auto-stash uncommitted changes" 2>/dev/null
            stashed=$((stashed + 1))
        fi

        # checkout default branch and sync
        git -C "$repo_dir" checkout "$default_branch" 2>/dev/null
        if [[ $? -ne 0 ]]; then
            # restore original branch if checkout failed
            if $has_changes; then
                git -C "$repo_dir" checkout "$wip_branch" 2>/dev/null
            else
                git -C "$repo_dir" checkout "$current_branch" 2>/dev/null
            fi
            echo "FAIL (could not checkout $default_branch)"
            failed=$((failed + 1))
            continue
        fi

        git -C "$repo_dir" fetch --all --prune -q 2>/dev/null
        pull_output=$(git -C "$repo_dir" pull --rebase 2>&1)
        if [[ $? -ne 0 ]]; then
            git -C "$repo_dir" rebase --abort 2>/dev/null
            if $has_changes; then
                git -C "$repo_dir" checkout "$wip_branch" 2>/dev/null
            else
                git -C "$repo_dir" checkout "$current_branch" 2>/dev/null
            fi
            echo "FAIL (pull --rebase failed)"
            failed=$((failed + 1))
            continue
        fi

        # restore the original branch (or wip branch if changes were stashed)
        if $has_changes; then
            git -C "$repo_dir" checkout "$wip_branch" 2>/dev/null
            echo "SYNCED (wip: $wip_branch)"
        else
            if [[ "$current_branch" != "$default_branch" ]]; then
                git -C "$repo_dir" checkout "$current_branch" 2>/dev/null
            fi
            echo "SYNCED"
        fi
        synced=$((synced + 1))
    done < <(find "$root" -name .git -type d 2>/dev/null | sort)

    echo ""
    echo "--- Summary ---"
    echo "Total: $total | Synced: $synced | WIP commits: $stashed | Failed: $failed"
}
