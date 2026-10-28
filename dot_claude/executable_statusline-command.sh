#!/usr/bin/env bash
# Claude Code status line, styled after ~/.p10k.zsh (Powerlevel10k).
#
#   ╭─ ~/Development/github.com/rios0rios0/autobump ❯ ⎇ main ❯ user@host ❯ account
#   ╰─ Opus 5 ❯ ctx 66% left (339k/1M) ❯ 5h 20% (23:50) ❯ 7d 83% (Tue 22:00) ❯ Fable 43%
#
# Line 1 mirrors the p10k left prompt (dir | vcs) and then carries the identity:
# user@host, as p10k's `context` segment, followed by the Claude account in use.
# Line 2 carries the model, the context window, and the plan limits: the 5-hour
# session window, the 7-day all-models window, and one segment per model-scoped
# weekly cap (Fable, plus any other the account carries).
#
# EVERYTHING IS LEFT-ALIGNED, DELIBERATELY. A right-aligned half has to predict
# the exact column the renderer thinks the line ends at, and two separate things
# make that prediction wrong:
#
#   1. `statusLine.padding` in settings.json defaults to 1 column on EACH side.
#      It is set to 0 there so the frame starts at column 0 like the zsh prompt,
#      but nothing in this script may depend on that.
#   2. Ink measures an East-Asian-Ambiguous character as 2 columns where the
#      terminal draws 1. The box-drawing frame is Ambiguous.
#
# Guess either one wrong and Ink's `wrap:"truncate"` silently eats the end of the
# line ("someone@exampl…"). Flowing left means the content simply stops well
# inside the terminal and no prediction is needed. $AMBIGUOUS and the width
# budget below now only guard the degradation ladder, not the layout.
#
# !! NO PRIVATE-USE-AREA CHARACTERS !!  Claude Code sanitises status line text
# through a filter that strips `\p{Co}` / [U+E000-U+F8FF] before drawing it, and
# that is exactly where every Nerd Font glyph lives -- Powerline separators
# (U+E0B0-E0B3) and icons alike. They render as nothing. The zsh prompt draws
# them in the same terminal and font, so the sanitiser is what removes them, not
# a missing glyph. Substitutes used here, all ordinary Unicode and all width 1:
# `╭─`/`╰─` for the frame, `❯` for the separator (which p10k also draws for its
# `prompt_char`), `⎇` for the branch where p10k uses U+F126, `…` for truncation.
#
# The 5-hour and 7-day figures arrive on stdin under `rate_limits` and are always
# current. Model-scoped weekly caps are NOT in that payload, so they come from
# /api/oauth/usage -- the endpoint `/usage` itself calls -- through a cache that a
# detached background refresh rewrites at most once every USAGE_TTL seconds. A
# render never waits on the network; it draws whatever the cache last held.
#
# Colours are lifted from ~/.p10k.zsh so the two prompts read as one: frame 238,
# dir 9 with bold-21 anchors, vcs 76, context 180. The p10k segment background
# (234) is deliberately NOT reproduced -- it blends into zsh's own backdrop but
# reads as a grey box against the Claude Code transcript.
#
# chezmoi deploys this from dot_claude/executable_statusline-command.sh. CFG
# follows CLAUDE_CONFIG_DIR, so a profile of its own reads its own credentials,
# usage cache and account; one without a claude.ai login shows no plan limits.

CFG=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
USAGE_CACHE="$CFG/statusline-usage.cache"
USAGE_LOCK="$CFG/statusline-usage.lock"
USAGE_TTL=300      # seconds a cached model-scoped cap stays fresh
USAGE_STALE=3600   # past this the cached figure is drawn dimmed

# =============================================================================
# Background refresh: /api/oauth/usage -> flat key=value cache
# =============================================================================

read_account() {  # the e-mail of the account Claude Code is currently logged in as
    local raw f="$CFG/.claude.json"
    [[ -r "$f" ]] || f="$HOME/.claude.json"
    raw=$(grep -m1 -o '"emailAddress"[[:space:]]*:[[:space:]]*"[^"]*"' \
          "$f" 2>/dev/null) || return 0
    raw=${raw#*:}                    # drop the key
    raw=${raw#"${raw%%\"*}"}         # drop the whitespace before the value
    raw=${raw#\"}
    printf '%s' "${raw%\"}"
}

refresh_usage() {
    local cred="$CFG/.credentials.json" tok exp now resp tmp account

    [[ -r "$cred" ]] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    command -v jq   >/dev/null 2>&1 || return 1

    tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$cred" 2>/dev/null)
    exp=$(jq -r '((.claudeAiOauth.expiresAt // 0) / 1000) | floor' "$cred" 2>/dev/null)
    [[ -n "$tok" ]] || return 1

    # An expired token would only earn a 401. Leave the cache alone and let a
    # later render retry once Claude Code has refreshed the credentials itself.
    now=$EPOCHSECONDS
    [[ "${exp:-0}" -gt "$((now + 30))" ]] || return 1

    # The token goes to curl on stdin (-H @-), never in argv: every local user can
    # read a process's arguments in /proc/<pid>/cmdline.
    resp=$(curl -sS -m 12 'https://api.anthropic.com/api/oauth/usage' \
        -H @- \
        -H 'Content-Type: application/json' \
        -H 'anthropic-beta: oauth-2025-04-20' \
        <<<"Authorization: Bearer $tok" 2>/dev/null) || return 1
    [[ -n "$resp" ]] || return 1

    account=$(read_account)

    tmp="$USAGE_CACHE.$$"
    printf '%s' "$resp" | jq -r --argjson now "$now" --arg account "$account" '
        def iso2epoch:
            if . == null then 0
            else ((sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z")) | fromdateiso8601? // 0)
            end;
        [
          "fetched=\($now)",
          "account=\($account)",
          (if .five_hour.utilization != null
             then "five=\(.five_hour.utilization | floor)" else empty end),
          (if .five_hour.resets_at != null
             then "five_at=\(.five_hour.resets_at | iso2epoch)" else empty end),
          (if .seven_day.utilization != null
             then "seven=\(.seven_day.utilization | floor)" else empty end),
          (if .seven_day.resets_at != null
             then "seven_at=\(.seven_day.resets_at | iso2epoch)" else empty end),
          ("scoped=" + ([ (.limits // [])[]
              | select(.kind == "weekly_scoped" and .scope.model.display_name != null)
              | (.scope.model.display_name | gsub("[:|=]"; " "))
                + ":\(.percent | floor)"
                + ":\(.resets_at | iso2epoch)" ] | join("|")))
        ] | .[]
    ' > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }

    [[ -s "$tmp" ]] || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$USAGE_CACHE" 2>/dev/null || rm -f "$tmp"
}

if [[ "$1" = "--refresh-usage" ]]; then
    refresh_usage
    exit
fi

# =============================================================================
# Input
# =============================================================================

input=$(cat)

# Single jq pass; one value per line, so paths with spaces stay intact.
{
    IFS= read -r raw_cwd
    IFS= read -r model
    IFS= read -r ctx_left
    IFS= read -r ctx_tokens
    IFS= read -r ctx_size
    IFS= read -r five_pct
    IFS= read -r five_at
    IFS= read -r seven_pct
    IFS= read -r seven_at
} < <(printf '%s' "$input" | jq -r '
        (.workspace.current_dir // .cwd // ""),
        (.model.display_name // .model.id // ""),
        (.context_window.remaining_percentage // -1 | floor),
        (.context_window.total_input_tokens // 0),
        (.context_window.context_window_size // 0),
        (.rate_limits.five_hour.used_percentage // .rate_limits.five_hour.utilization // -1 | floor),
        (.rate_limits.five_hour.resets_at // 0 | floor),
        (.rate_limits.seven_day.used_percentage // .rate_limits.seven_day.utilization // -1 | floor),
        (.rate_limits.seven_day.resets_at // 0 | floor)
    ' 2>/dev/null)

# =============================================================================
# Cache read (pure bash, no subprocess) and background refresh
# =============================================================================

usage_fetched=0 usage_scoped="" usage_account=""
usage_five=-1 usage_five_at=0 usage_seven=-1 usage_seven_at=0
if [ -r "$USAGE_CACHE" ]; then
    while IFS='=' read -r _k _v; do
        case $_k in
            fetched)  usage_fetched=$_v   ;;
            account)  usage_account=$_v   ;;
            scoped)   usage_scoped=$_v    ;;
            five)     usage_five=$_v      ;;
            five_at)  usage_five_at=$_v   ;;
            seven)    usage_seven=$_v     ;;
            seven_at) usage_seven_at=$_v  ;;
            *)        ;;   # a key this revision does not read
        esac
    done < "$USAGE_CACHE"
fi

# Read live: `ccswitch` rotates accounts underneath us and the identity on screen
# has to follow immediately, not on the cache's schedule.
account=$(read_account)

# Caps cached under a different account describe someone else's plan.
if [[ -n "$usage_account" ]] && [[ -n "$account" ]] && [[ "$usage_account" != "$account" ]]; then
    usage_scoped=""
    usage_fetched=0
fi

now=$EPOCHSECONDS
usage_age=$(( now - usage_fetched ))
# A profile without a claude.ai login has nothing to fetch, and a refresh that
# cannot succeed never writes the cache, so trying anyway would fork one on
# every redraw.
if [[ "$usage_age" -ge "$USAGE_TTL" ]] && [[ -r "$CFG/.credentials.json" ]]; then
    if [[ -d "$USAGE_LOCK" ]]; then
        # Reap a lock left behind by a refresh that was killed mid-flight.
        lock_age=$(( now - $(stat -c %Y "$USAGE_LOCK" 2>/dev/null || echo "$now") ))
        [[ "$lock_age" -gt 120 ]] && rmdir "$USAGE_LOCK" 2>/dev/null
    fi
    if mkdir "$USAGE_LOCK" 2>/dev/null; then
        # Fully detached: all three descriptors are closed, so Claude Code never
        # waits on this child for the status line's pipe to reach EOF.
        ( refresh_usage; rmdir "$USAGE_LOCK" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
        disown 2>/dev/null
    fi
fi

# stdin is authoritative for the two windows it carries; the cache fills in only
# when the payload omits them (API-key auth, or an older CLI).
[[ "${five_pct:--1}"  -lt 0 ]] && { five_pct=$usage_five;   five_at=$usage_five_at;   }
[[ "${seven_pct:--1}" -lt 0 ]] && { seven_pct=$usage_seven; seven_at=$usage_seven_at; }

# =============================================================================
# p10k palette (~/.p10k.zsh)
# =============================================================================

R=$'\033[0m'        # full reset
B=$'\033[1m'        # bold on
NB=$'\033[22m'      # bold off

C_FRAME=$'\033[38;5;238m'     # MULTILINE_*_PROMPT_PREFIX
C_SEP=$'\033[38;5;245m'       # subsegment separator, a little brighter than p10k's
C_DIR=$'\033[38;5;9m'         # DIR_FOREGROUND
C_ANCHOR=$'\033[38;5;21m'     # DIR_ANCHOR_FOREGROUND (bold)
C_VCS=$'\033[38;5;76m'        # VCS_CLEAN_FOREGROUND
C_ACCT=$'\033[38;5;180m'      # CONTEXT_FOREGROUND, reused for the Claude account
C_CONTEXT=$'\033[38;5;110m'   # user@host -- soft blue, as the old Kali-style line had it
C_MODEL=$'\033[38;5;37m'      # teal, as p10k uses for the language segments
C_DIM=$'\033[38;5;244m'
C_OK=$'\033[38;5;76m'
C_WARN=$'\033[38;5;178m'      # VCS_MODIFIED_FOREGROUND
C_CRIT=$'\033[38;5;160m'      # STATUS_ERROR_FOREGROUND

SEP='❯'        # stands in for p10k's LEFT_SUBSEGMENT_SEPARATOR (U+E0B1); also its prompt_char
I_BRANCH='⎇'   # p10k's VCS_BRANCH_ICON is U+F126, which Claude Code strips

# =============================================================================
# Helpers
# =============================================================================

# Characters the terminal draws 1 column wide but Ink measures as 2 (East Asian
# width "Ambiguous"). Keep in step with every non-ASCII character emitted below;
# `❯` and `⎇` are Neutral -- 1 column to both -- and deliberately absent.
AMBIGUOUS='╭╰─…·'

# Width of a string ignoring SGR escapes, as the terminal draws it ($VIS) and as
# Ink measures it ($VIS_INK). Both land in globals so the caller pays no subshell.
VIS=0
VIS_INK=0
vis_len() {
    local s=$1 out="" bare
    while [[ $s == *$'\033'* ]]; do
        out+=${s%%$'\033'*}
        s=${s#*$'\033'}
        s=${s#\[}
        s=${s#*m}
    done
    out+=$s
    VIS=${#out}
    bare=${out//[$AMBIGUOUS]/}
    VIS_INK=$(( VIS + VIS - ${#bare} ))
}

# Room for a line, in Ink's units. Three columns are held back to cover
# `statusLine.padding` being restored to its default of 1 on each side.
BUDGET=$(( ${COLUMNS:-0} - 3 ))
[[ "$BUDGET" -gt 0 ]] || BUDGET=0     # 0 == width unknown, never degrade

fits() {
    local text="$1"
    [[ "$BUDGET" -le 0 ]] && return 0
    vis_len "$text"
    [[ "$VIS_INK" -le "$BUDGET" ]]
}

human() {  # 94045 -> 94k, 1000000 -> 1M
    local n=$1
    if [[ "$n" -ge 1000000 ]]; then
        local whole=$(( n / 1000000 )) frac=$(( (n % 1000000) / 100000 ))
        if [[ "$frac" -eq 0 ]]; then printf '%dM' "$whole"
        else printf '%d.%dM' "$whole" "$frac"; fi
    elif [[ "$n" -ge 1000 ]]; then
        printf '%dk' $(( n / 1000 ))
    else
        printf '%d' "$n"
    fi
}

# Green below 70%, amber to 89%, red from 90% -- the point at which `ccswitch`
# rotates to a backup account.
usage_color() {
    local p=$1
    if   [[ "$p" -ge 90 ]]; then printf '%s' "$C_CRIT"
    elif [[ "$p" -ge 70 ]]; then printf '%s' "$C_WARN"
    else                       printf '%s' "$C_OK"
    fi
}

# Join segments with the separator. Answer lands in $PROMPT, no subshell.
PROMPT=""
join_segments() {
    local body="" s
    for s in "$@"; do
        [[ -n "$s" ]] || continue
        [[ -n "$body" ]] && body+=" ${C_SEP}${SEP} "
        body+=$s
    done
    PROMPT="${body}${R}"
    [[ -n "$body" ]]
}

# Last-resort trim so a line can never exceed the terminal and be truncated by
# Ink (which would swallow the end and append its own ellipsis). The degradation
# ladders below normally keep every line inside the budget; this only fires on a
# terminal too narrow for even the most degraded form. SGR sequences are copied
# through untouched so colours stay balanced.
clamp_line() {  # clamp_line <line> -> $LINE
    local s=$1 out="" chunk c w=0 step
    LINE=$s
    [[ "$BUDGET" -gt 0 ]] || return 0
    vis_len "$s"
    [[ "$VIS_INK" -gt "$BUDGET" ]] || return 0
    while [[ -n "$s" ]]; do
        if [[ $s == $'\033'* ]]; then
            chunk="${s%%m*}m"
            out+=$chunk
            s=${s#"$chunk"}
            continue
        fi
        c=${s:0:1}
        if [[ $AMBIGUOUS == *"$c"* ]]; then step=2; else step=1; fi
        [[ $(( w + step )) -le "$BUDGET" ]] || break
        out+=$c
        w=$(( w + step ))
        s=${s:1}
    done
    LINE="${out}${R}"
}

# =============================================================================
# Line 1 -- dir | branch | user@host | account
# =============================================================================

# Repo root and branch, read straight off .git without a subprocess.
repo_root="" branch=""
{
    _d=$raw_cwd
    while [[ -n "$_d" ]] && [[ "$_d" != "/" ]] && [[ ! -e "$_d/.git" ]]; do
        _d=${_d%/*}
    done
    if [[ -n "$_d" ]] && [[ -e "$_d/.git" ]]; then
        repo_root=$_d
        _gitdir="$_d/.git"
        if [[ -f "$_gitdir" ]]; then
            # worktree or submodule: ".git" is a file holding "gitdir: <path>"
            IFS= read -r _line < "$_gitdir" && _gitdir=${_line#gitdir: }
            [[ "${_gitdir#/}" = "$_gitdir" ]] && _gitdir="$_d/$_gitdir"
        fi
        if [[ -r "$_gitdir/HEAD" ]] && IFS= read -r _head < "$_gitdir/HEAD"; then
            case $_head in
                "ref: refs/heads/"*) branch=${_head#ref: refs/heads/} ;;
                "ref: "*)            branch=${_head#ref: } ;;
                ?*)                  branch=${_head:0:7} ;;   # detached HEAD
                *)                   ;;                        # an empty HEAD file: no branch
            esac
        fi
    fi
} 2>/dev/null

# p10k shortens a branch over 32 characters to the first 12 ... the last 12.
[[ ${#branch} -gt 32 ]] && branch="${branch:0:12}…${branch: -12}"

# $HOME collapses to ~, as p10k's dir segment does.
cwd=$raw_cwd
case $cwd in
    "$HOME")   cwd='~' ;;
    "$HOME"/*) cwd="~${cwd#"$HOME"}" ;;
    *)         ;;   # outside $HOME: shown as it is
esac

# The repo root is an anchor (DIR_ANCHOR_FOREGROUND, bold); the rest takes
# DIR_FOREGROUND. `level` shortens the leading components when space runs out,
# approximating POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_unique.
dir_segment() {  # dir_segment <level 0|1|2>
    local level=$1 anchor="" head="" tail="" out
    if [[ -n "$repo_root" ]]; then
        anchor=${repo_root##*/}
        head=${cwd%/"$anchor"*}
        [[ "$head" = "$cwd" ]] && anchor=""
    fi
    [[ -z "$anchor" ]] && head=$cwd
    [[ -n "$anchor" ]] && tail=${cwd#"$head"/"$anchor"}

    if [[ "$level" -ge 1 ]]; then
        local first=${head%%/*} rest=${head#*/} acc part parts
        acc=$first
        if [[ "$rest" != "$head" ]]; then
            # Split with read rather than an unquoted $rest, which would also glob.
            IFS=/ read -ra parts <<< "$rest"
            for part in "${parts[@]}"; do
                [[ -n "$part" ]] || continue
                if [[ "$level" -ge 2 ]]; then acc+="/${part:0:1}"
                else                        acc+="/${part:0:3}"; fi
            done
        fi
        head=$acc
    fi

    out="${C_DIR}${head}"
    [[ -n "$anchor" ]] && out+="${C_DIR}/${B}${C_ANCHOR}${anchor}${NB}${C_DIR}${tail}"
    printf '%s' "$out"
}

seg_vcs=""
[[ -n "$branch" ]] && seg_vcs="${C_VCS}${I_BRANCH} ${branch}"
seg_acct=""
[[ -n "$account" ]] && seg_acct="${C_ACCT}${account}"

# p10k's `context` segment (%n@%m). $HOSTNAME is not exported to hook commands,
# so the host comes from procfs -- a file read rather than a `hostname` fork.
_user=${USER:-${LOGNAME:-}}
[[ -n "$_user" ]] || _user=$(id -un 2>/dev/null)
_host=${HOSTNAME:-}
[[ -n "$_host" ]] || { IFS= read -r _host < /proc/sys/kernel/hostname 2>/dev/null || _host=""; }
_host=${_host%%.*}
seg_context=""
[[ -n "$_user" ]] && [[ -n "$_host" ]] && seg_context="${C_CONTEXT}${_user}@${_host}"

chroot_prefix=""
[[ -n "$debian_chroot" ]] && chroot_prefix="${C_DIM}(${debian_chroot})${R} "

# The leading reset matters: Claude Code draws each row inside an Ink
# <Text dimColor>, so without it the frame comes out dimmed twice and vanishes.
# The path is shortened all the way down first; only then does the identity give
# ground -- user@host goes, then the account's domain.
for level in 0 1 2 3 4 5 6; do
    case $level in
        0|1|2) join_segments "$(dir_segment "$level")" "$seg_vcs" "$seg_context" "$seg_acct" ;;
        3)     join_segments "$(dir_segment 2)" "$seg_vcs" "$seg_acct" ;;
        4)     join_segments "${C_DIR}${cwd##*/}" "$seg_vcs" "${account:+${C_ACCT}${account%%@*}}" ;;
        5)     join_segments "${C_DIR}${cwd##*/}" "${account:+${C_ACCT}${account%%@*}}" ;;
        *)     join_segments "${C_DIR}${cwd##*/}" ;;
    esac
    LINE="${R}${C_FRAME}╭─${R} ${chroot_prefix}${PROMPT}"
    fits "$LINE" && break
done
line1=$LINE

# =============================================================================
# Line 2 -- model | ctx | 5h | 7d | per-model weekly caps
# =============================================================================

model=${model% (*)}   # the window size is already spelled out by the ctx segment
seg_model=""
[[ -n "$model" ]] && seg_model="${B}${C_MODEL}${model}${NB}"

seg_venv=""
[[ -n "$VIRTUAL_ENV" ]] && seg_venv="${C_DIM}${VIRTUAL_ENV##*/}"

ctx_segment() {  # ctx_segment <level 0|1>
    local level=$1 out
    if [[ "${ctx_left:--1}" -lt 0 ]]; then
        printf '%s' "${C_DIM}ctx n/a"
        return
    fi
    out="$(usage_color $(( 100 - ctx_left )))ctx ${ctx_left}% left"
    if [[ "$level" -eq 0 ]] && [[ "${ctx_size:-0}" -gt 0 ]]; then
        out+="${C_DIM} ($(human "${ctx_tokens:-0}")/$(human "$ctx_size"))"
    fi
    printf '%s' "$out"
}

# Model-scoped weekly caps (Fable, and anything else the plan carries).
scoped_segments=()
if [[ -n "$usage_scoped" ]]; then
    _stale=""
    [[ "$usage_age" -ge "$USAGE_STALE" ]] && _stale=1
    IFS='|' read -ra _entries <<< "$usage_scoped"
    for _e in "${_entries[@]}"; do
        [[ -n "$_e" ]] || continue
        IFS=':' read -r _name _pct _at <<< "$_e"
        [[ -n "$_name" ]] && [[ -n "$_pct" ]] || continue
        if [[ -n "$_stale" ]]; then
            scoped_segments+=( "${C_DIM}${_name} ${_pct}%" )
        else
            scoped_segments+=( "$(usage_color "$_pct")${_name} ${_pct}%" )
        fi
    done
fi

LIMITS=()
limit_segments() {  # limit_segments <level 0|1>
    local level=$1 s
    LIMITS=()
    if [[ "${five_pct:--1}" -ge 0 ]]; then
        s="$(usage_color "$five_pct")5h ${five_pct}%"
        if [[ "$level" -eq 0 ]] && [[ "${five_at:-0}" -gt 0 ]]; then
            printf -v s '%s%s (%(%H:%M)T)' "$s" "$C_DIM" "$five_at"
        fi
        LIMITS+=( "$s" )
    fi
    if [[ "${seven_pct:--1}" -ge 0 ]]; then
        s="$(usage_color "$seven_pct")7d ${seven_pct}%"
        if [[ "$level" -eq 0 ]] && [[ "${seven_at:-0}" -gt 0 ]]; then
            printf -v s '%s%s (%(%a %H:%M)T)' "$s" "$C_DIM" "$seven_at"
        fi
        LIMITS+=( "$s" )
    fi
    LIMITS+=( "${scoped_segments[@]}" )
}

# Shed detail cheapest first -- reset times and token counts, then the context
# segment, then the model -- so the limits survive on a narrow terminal. They are
# the reason this line exists.
for level in 0 1 2 3; do
    limit_segments "$(( level > 0 ? 1 : 0 ))"
    case $level in
        0|1) join_segments "$seg_model" "$(ctx_segment "$level")" "$seg_venv" "${LIMITS[@]}" ;;
        2)   join_segments "$seg_model" "${LIMITS[@]}" ;;
        *)   join_segments "${LIMITS[@]}" ;;
    esac
    LINE="${R}${C_FRAME}╰─${R} ${PROMPT}"
    fits "$LINE" && break
done
line2=$LINE

clamp_line "$line1"; line1=$LINE
clamp_line "$line2"; line2=$LINE

printf '%s\n%s' "$line1" "$line2"
