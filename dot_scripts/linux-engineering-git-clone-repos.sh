# shellcheck shell=bash

# Provider registry (Mapper pattern — add new providers here)
# Using zsh-compatible typeset -A syntax
typeset -gA _GCR_PROVIDERS=(
  [github.com]=_gcr_github
  [dev.azure.com]=_gcr_azure_devops
)

# Provider: scan depth for local directories (how deep repos nest under root)
typeset -gA _GCR_SCAN_DEPTH=(
  [github.com]=1
  [dev.azure.com]=2
)

_gcr_log() { printf '[git-clone] %s\n' "$*" >&2; }

_gcr_detect_provider() {
    local root="$1"
    local provider
    # shellcheck disable=SC2296
    for provider in "${(k)_GCR_PROVIDERS[@]}"; do
        if [[ "$root" == *"/$provider/"* || "$root" == *"/$provider" ]]; then
            echo "$provider"
            return 0
        fi
    done
    return 1
}

_gcr_extract_owner() {
    local root="$1"
    local provider="$2"
    # /home/user/Development/github.com/rios0rios0 -> rios0rios0
    # /home/user/Development/dev.azure.com/MyOrg -> MyOrg
    if [[ "$root" != *"/$provider/"* ]]; then
        _gcr_log "ERROR: could not extract owner from '$root' for provider '$provider' (expected .../$provider/<owner>/...)"
        return 1
    fi
    local after="${root##*/$provider/}"
    # strip trailing slashes and take only the first segment
    after="${after%%/*}"
    if [[ -z "$after" ]]; then
        _gcr_log "ERROR: empty owner extracted from '$root' for provider '$provider' (expected .../$provider/<owner>/...)"
        return 1
    fi
    echo "$after"
}

_gcr_build_clone_url() {
    local provider="$1"
    local ssh_alias="$2"
    local owner="$3"
    local repo_path="$4"

    case "$provider" in
        github.com)
            echo "git@github.com-${ssh_alias}:${owner}/${repo_path}.git"
            ;;
        dev.azure.com)
            # repo_path is "project/repo", owner is the org
            echo "git@dev.azure.com-${ssh_alias}:v3/${owner}/${repo_path}"
            ;;
    esac
}

_gcr_github() {
    local owner="$1"
    local include_archived="$2"

    if ! command -v gh &>/dev/null; then
        _gcr_log "ERROR: 'gh' CLI not found"
        return 1
    fi

    # detect if owner is User or Organization
    local owner_type
    owner_type=$(gh api "/users/$owner" --jq '.type' 2>/dev/null)
    if [[ -z "$owner_type" ]]; then
        _gcr_log "ERROR: could not determine type for '$owner' (check GH_TOKEN or gh auth)"
        return 1
    fi

    local endpoint
    if [[ "$owner_type" == "Organization" ]]; then
        endpoint="/orgs/$owner/repos?per_page=100"
        _gcr_log "detected Organization: $owner"
    else
        endpoint="/users/$owner/repos?per_page=100"
        _gcr_log "detected User: $owner"
    fi

    local jq_filter='.[] | select(true'
    if [[ "$include_archived" != "true" ]]; then
        jq_filter+=' and (.archived | not)'
    fi
    jq_filter+=') | .name'

    gh api --paginate "$endpoint" --jq "$jq_filter" 2>/dev/null
}

_gcr_azure_devops() {
    local org="$1"
    local include_archived="$2"

    if [[ -z "$AZURE_DEVOPS_EXT_PAT" ]]; then
        _gcr_log "ERROR: AZURE_DEVOPS_EXT_PAT not set"
        return 1
    fi
    if ! command -v curl &>/dev/null; then
        _gcr_log "ERROR: 'curl' not found"
        return 1
    fi
    if ! command -v jq &>/dev/null; then
        _gcr_log "ERROR: 'jq' not found"
        return 1
    fi

    local api_url="https://dev.azure.com/$org/_apis/git/repositories?api-version=7.0"
    local response
    response=$(curl -s -u ":$AZURE_DEVOPS_EXT_PAT" "$api_url" 2>/dev/null)

    if [[ -z "$response" ]] || ! printf '%s' "$response" | jq -e '.value' &>/dev/null; then
        _gcr_log "ERROR: failed to fetch repos from Azure DevOps (check AZURE_DEVOPS_EXT_PAT and org name)"
        return 1
    fi

    local jq_filter='.value[]'
    if [[ "$include_archived" != "true" ]]; then
        jq_filter+=' | select(.isDisabled | not)'
    fi
    jq_filter+=' | "\(.project.name)/\(.name)"'

    printf '%s' "$response" | jq -r "$jq_filter" 2>/dev/null
}

_gcr_clone_single() {
    local repo_name="$1"
    local clone_url="$2"
    local target_dir="$3"
    local _err

    mkdir -p "$(dirname "$target_dir")"
    if ! _err=$(git clone "$clone_url" "$target_dir" 2>&1); then
        printf "  %-50s FAIL (%s)\n" "$repo_name" "$_err"
        return 1
    fi
    printf "  %-50s CLONED\n" "$repo_name"
    return 0
}

_gcr_scan_local() {
    local root="$1"
    local depth="$2"
    local results=()
    local d pd rd name project repo

    if [[ "$depth" -eq 1 ]]; then
        # GitHub: root/repo/.git (include hidden dirs like .github)
        for d in "$root"/*(N/) "$root"/.*(N/); do
            name="${d##*/}"
            [[ "$name" == "." || "$name" == ".." ]] && continue
            [[ -d "${d}/.git" ]] || continue
            results+=("$name")
        done
    elif [[ "$depth" -eq 2 ]]; then
        # Azure DevOps: root/project/repo/.git
        for pd in "$root"/*(N/) "$root"/.*(N/); do
            project="${pd##*/}"
            [[ "$project" == "." || "$project" == ".." ]] && continue
            for rd in "$pd"/*(N/) "$pd"/.*(N/); do
                repo="${rd##*/}"
                [[ "$repo" == "." || "$repo" == ".." ]] && continue
                [[ -d "${rd}/.git" ]] || continue
                results+=("$project/$repo")
            done
        done
    fi

    printf '%s\n' "${results[@]}"
}

git-clone-repos() {
    local ssh_alias=""
    local dry_run=false
    local include_archived=false
    local root=""

    # parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=true
                shift
                ;;
            --include-archived)
                include_archived=true
                shift
                ;;
            --*)
                _gcr_log "ERROR: unknown flag: $1"
                echo "Usage: git-clone-repos <ssh-alias> [--dry-run] [--include-archived] [root-dir]" >&2
                return 1
                ;;
            *)
                if [[ -z "$ssh_alias" ]]; then
                    ssh_alias="$1"
                elif [[ -z "$root" ]]; then
                    root="$1"
                else
                    _gcr_log "ERROR: unexpected argument: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$ssh_alias" ]]; then
        _gcr_log "ERROR: ssh-alias is required"
        echo "Usage: git-clone-repos <ssh-alias> [--dry-run] [--include-archived] [root-dir]" >&2
        return 1
    fi

    root="${root:-$PWD}"
    root="${root%/}"

    if [[ ! -d "$root" ]]; then
        _gcr_log "ERROR: directory not found: $root"
        return 1
    fi

    # detect provider
    local provider
    provider=$(_gcr_detect_provider "$root")
    if [[ -z "$provider" ]]; then
        _gcr_log "ERROR: could not detect provider from path: $root"
        # shellcheck disable=SC2296
        _gcr_log "supported providers: ${(k)_GCR_PROVIDERS[*]}"
        return 1
    fi

    local owner
    owner=$(_gcr_extract_owner "$root" "$provider")
    if [[ -z "$owner" ]]; then
        _gcr_log "ERROR: could not extract owner/org from path: $root"
        return 1
    fi

    local depth="${_GCR_SCAN_DEPTH[$provider]}"
    local provider_fn="${_GCR_PROVIDERS[$provider]}"

    _gcr_log "provider=$provider owner=$owner alias=$ssh_alias"
    if $dry_run; then
        _gcr_log "(dry-run mode)"
    fi

    # fetch remote repos
    _gcr_log "fetching remote repository list..."
    local remote_repos=()
    while IFS= read -r repo; do
        [[ -z "$repo" ]] && continue
        remote_repos+=("$repo")
    done < <("$provider_fn" "$owner" "$include_archived")

    if [[ ${#remote_repos[@]} -eq 0 ]]; then
        _gcr_log "WARN: no remote repos found (check authentication and owner name)"
        return 0
    fi
    _gcr_log "found ${#remote_repos[@]} remote repos"

    # scan local repos
    local local_repos=()
    while IFS= read -r repo; do
        [[ -z "$repo" ]] && continue
        local_repos+=("$repo")
    done < <(_gcr_scan_local "$root" "$depth")
    _gcr_log "found ${#local_repos[@]} local repos"

    # build associative arrays for set operations
    local -A remote_set
    local r
    for r in "${remote_repos[@]}"; do
        remote_set[$r]=1
    done

    local -A local_set
    for r in "${local_repos[@]}"; do
        local_set[$r]=1
    done

    # compute missing (remote but not local)
    local missing=()
    for r in "${remote_repos[@]}"; do
        if (( ! ${+local_set[$r]} )); then
            missing+=("$r")
        fi
    done

    # compute extra (local but not remote)
    local extra=()
    for r in "${local_repos[@]}"; do
        if (( ! ${+remote_set[$r]} )); then
            extra+=("$r")
        fi
    done

    _gcr_log "missing locally: ${#missing[@]} | extra locally: ${#extra[@]}"
    echo ""

    # clone missing repos
    local cloned=0 clone_failed=0
    if [[ ${#missing[@]} -gt 0 ]]; then
        local max_jobs
        max_jobs=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

        if $dry_run; then
            _gcr_log "would clone ${#missing[@]} repos:"
            local url
            for r in "${missing[@]}"; do
                url=$(_gcr_build_clone_url "$provider" "$ssh_alias" "$owner" "$r")
                printf "  %-50s %s\n" "$r" "$url"
            done
        else
            _gcr_log "cloning ${#missing[@]} repos ($max_jobs parallel workers)"
            echo ""

            local tmp_dir
            tmp_dir=$(mktemp -d) || { _gcr_log "ERROR: could not create temp directory"; return 1; }
            local _saved_int _saved_term _gcr_interrupted=0
            _saved_int=$(trap -p INT 2>/dev/null)
            _saved_term=$(trap -p TERM 2>/dev/null)
            trap '_gcr_interrupted=1; rm -rf "$tmp_dir"; if [[ -n "$_saved_int" ]]; then eval "$_saved_int"; else trap - INT; fi; if [[ -n "$_saved_term" ]]; then eval "$_saved_term"; else trap - TERM; fi; _gcr_log "interrupted, aborting clone"; return 130' INT TERM

            local i=1 batch_end repo_name clone_url target_dir j
            local pids=()
            while [[ $i -le ${#missing[@]} ]]; do
                batch_end=$((i + max_jobs - 1))
                [[ $batch_end -gt ${#missing[@]} ]] && batch_end=${#missing[@]}

                pids=()
                for ((j = i; j <= batch_end; j++)); do
                    repo_name="${missing[$j]}"
                    clone_url=$(_gcr_build_clone_url "$provider" "$ssh_alias" "$owner" "$repo_name")
                    target_dir="$root/$repo_name"
                    _gcr_clone_single "$repo_name" "$clone_url" "$target_dir" \
                        > "$tmp_dir/$j.out" 2>&1 &
                    pids+=("$!")
                done
                if [[ ${#pids[@]} -gt 0 ]]; then
                    wait "${pids[@]}"
                fi
                i=$((batch_end + 1))
            done

            # print results and tally
            local output
            for ((j = 1; j <= ${#missing[@]}; j++)); do
                output=$(cat "$tmp_dir/$j.out")
                echo "$output"
                case "$output" in
                    *CLONED*) cloned=$((cloned + 1)) ;;
                    *FAIL*) clone_failed=$((clone_failed + 1)) ;;
                esac
            done

            rm -rf "$tmp_dir"
            if [[ -n "$_saved_int" ]]; then eval "$_saved_int"; else trap - INT; fi
            if [[ -n "$_saved_term" ]]; then eval "$_saved_term"; else trap - TERM; fi
        fi
    fi

    # handle extra local repos
    local deleted=0 kept=0
    if [[ ${#extra[@]} -gt 0 ]]; then
        echo ""
        _gcr_log "WARN: ${#extra[@]} local repos not found on remote:"
        local answer
        for r in "${extra[@]}"; do
            if $dry_run; then
                printf "  - %s (would prompt to delete)\n" "$r"
                kept=$((kept + 1))
            else
                printf '[git-clone] "%s" exists locally but not on remote. Delete? [y/N] ' "$r" >&2
                if read -r answer </dev/tty 2>/dev/null && [[ "$answer" == "y" || "$answer" == "Y" ]]; then
                    rm -rf "${root:?}/${r:?}"
                    printf "  %-50s DELETED\n" "$r"
                    deleted=$((deleted + 1))
                else
                    printf "  %-50s KEPT\n" "$r"
                    kept=$((kept + 1))
                fi
            fi
        done
    fi

    # summary
    echo ""
    _gcr_log "--- Summary ---"
    _gcr_log "Remote: ${#remote_repos[@]} | Local: ${#local_repos[@]} | Cloned: $cloned | Clone failed: $clone_failed | Deleted: $deleted | Kept extra: $kept"
}
