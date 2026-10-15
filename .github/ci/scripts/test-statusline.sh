#!/bin/bash
set -euo pipefail

# Exercises dot_claude/executable_statusline-command.sh, the status line both Claude Code
# profiles run: the regular one and claude-omni's, which differ in what the script finds
# through CLAUDE_CONFIG_DIR -- a claude.ai login, or none -- and in claude-omni's case in the
# table of windows it writes, which ctx reads after /model switches models.
#
# The script reads the JSON Claude Code pipes to a status line, with CLAUDE_CONFIG_DIR at a
# scratch profile, so nothing here touches the developer's real credentials or usage cache.
# curl and mkdir are shadowed by recording stubs: curl's prove the OAuth token reaches it on
# stdin and never in its arguments, which any local user can read in /proc/<pid>/cmdline,
# and mkdir's prove that a profile without a login takes no refresh lock -- the one step a
# refresh takes in the foreground before it forks and detaches.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$REPO_ROOT/dot_claude/executable_statusline-command.sh"
EXIT_CODE=0

echo "[test-statusline] testing the Claude Code status line..." >&2

if ! command -v jq >/dev/null 2>&1; then
    echo "[test-statusline] SKIP: needs jq, which the status line itself requires" >&2
    exit 0
fi

# The script measures widths in characters, which bash counts only under a UTF-8 locale.
export LC_ALL=C.UTF-8

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
LOG="$SANDBOX/log"

# A repository found the way the script finds any: by its .git/HEAD, with no git binary.
PROJECT="$SANDBOX/work/project"
mkdir -p "$PROJECT/.git" "$PROJECT/src"
printf 'ref: refs/heads/feat/look\n' > "$PROJECT/.git/HEAD"

STUBS="$SANDBOX/bin"
mkdir -p "$STUBS"
printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "$STATUSLINE_TEST_LOG/curl.argv"\ncat > "$STATUSLINE_TEST_LOG/curl.stdin"\ncat "$STATUSLINE_TEST_LOG/response.json"\n' \
    > "$STUBS/curl"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$STATUSLINE_TEST_LOG/mkdir.calls"\nexec %q "$@"\n' "$(command -v mkdir)" \
    > "$STUBS/mkdir"
chmod +x "$STUBS/curl" "$STUBS/mkdir"

# claude-omni's profile: no .credentials.json, since OmniRoute's key never lands there, and the
# windows table claude-omni writes at launch.
OMNI_PROFILE="$SANDBOX/claude-omni"
mkdir -p "$OMNI_PROFILE"
printf '{"numStartups": 1}\n' > "$OMNI_PROFILE/.claude.json"
printf 'ollama/qwen3.8:27b\t65536\nopenrouter/moonshotai/kimi-k2.7-code\t262144\n' > "$OMNI_PROFILE/omniroute-windows.tsv"

# The regular profile, logged in with a token that has an hour left.
REGULAR_PROFILE="$SANDBOX/claude"
mkdir -p "$REGULAR_PROFILE"
printf '{"oauthAccount": {"emailAddress": "someone@example.com"}}\n' > "$REGULAR_PROFILE/.claude.json"
printf '{"claudeAiOauth": {"accessToken": "fixture-token-placeholder", "expiresAt": %s}}\n' \
    "$(( ($(date +%s) + 3600) * 1000 ))" > "$REGULAR_PROFILE/.credentials.json"

reset_log() {
    rm -rf "$LOG"
    mkdir -p "$LOG"
}

# A cache fetched just now, so a redraw of the regular profile starts no refresh in the
# background, where it would write to the log after its case has moved on.
fresh_cache() {
    printf 'fetched=%s\naccount=someone@example.com\nscoped=Fable:43:0\n' "$(date +%s)" \
        > "$REGULAR_PROFILE/statusline-usage.cache"
}

# payload <cwd> <model display name> [rate_limits object]
payload() {
    jq -nc --arg cwd "$1" --arg model "$2" --argjson limits "${3:-null}" '
        {workspace: {current_dir: $cwd}, model: {display_name: $model},
         context_window: {remaining_percentage: 83, total_input_tokens: 21800, context_window_size: 131072}}
        + (if $limits == null then {} else {rate_limits: $limits} end)'
}

# render <profile> <payload> [COLUMNS]: the two lines, colours stripped
render() {
    printf '%s' "$2" |
        CLAUDE_CONFIG_DIR="$1" COLUMNS="${3:-200}" PATH="$STUBS:$PATH" STATUSLINE_TEST_LOG="$LOG" bash "$SCRIPT" |
        sed 's/\x1b\[[0-9;]*m//g'
}

# omni_payload <model id> <label> <window>: what Claude Code pipes in a claude-omni session, after
# /model chose <model id>; the window is the session's, which /model does not change
omni_payload() {
    jq -nc --arg id "$1" --arg label "$2" --argjson window "$3" '
        {workspace: {current_dir: "/tmp"}, model: {id: $id, display_name: $label},
         context_window: {remaining_percentage: 80, total_input_tokens: 13000, context_window_size: $window}}'
}

# omni_render <launch model> <payload>: the second line of a claude-omni session, colours kept
omni_render() {
    printf '%s' "$2" |
        CLAUDE_CONFIG_DIR="$OMNI_PROFILE" CLAUDE_OMNI_MODEL="$1" COLUMNS=200 PATH="$STUBS:$PATH" \
            STATUSLINE_TEST_LOG="$LOG" bash "$SCRIPT" | sed -n 2p
}

run_case() {
    local description="$1"
    shift
    if "$@"; then
        echo "[test-statusline] PASS: $description" >&2
    else
        echo "[test-statusline] FAIL: $description" >&2
        EXIT_CODE=1
    fi
}

omni_session_shows_the_model_and_no_limits() {
    # given claude-omni's profile, in a subdirectory of a repository
    reset_log

    # when
    local out line1 line2
    out=$(render "$OMNI_PROFILE" "$(payload "$PROJECT/src" "qwen3.8:27b")") || return 1
    line1=$(sed -n 1p <<<"$out")
    line2=$(sed -n 2p <<<"$out")

    # then: the directory, the branch, the model and its window -- and no plan limits
    [[ "$line1" == *"project/src"* && "$line1" == *"feat/look"* ]] &&
        [[ "$line2" == *"qwen3.8:27b"* && "$line2" == *"ctx 83% left (21k/131k)"* ]] &&
        [[ "$out" != *"5h "* && "$out" != *"7d "* ]]
}

omni_session_starts_no_refresh() {
    # given claude-omni's profile, whose usage cache never exists, so it is always stale
    reset_log

    # when
    render "$OMNI_PROFILE" "$(payload "$PROJECT" "qwen3.8:27b")" >/dev/null || return 1

    # then: no lock was taken, so no refresh forked, and curl never ran
    [ ! -s "$LOG/mkdir.calls" ] && [ ! -e "$LOG/curl.argv" ]
}

refresh_sends_the_token_on_stdin_only() {
    # given the regular profile, logged in, and the usage endpoint's answer
    reset_log
    rm -f "$REGULAR_PROFILE/statusline-usage.cache"
    cat > "$LOG/response.json" <<'EOF'
{"five_hour": {"utilization": 20.4, "resets_at": "2026-10-14T23:50:00+00:00"},
 "seven_day": {"utilization": 83, "resets_at": "2026-10-20T22:00:00+00:00"},
 "limits": [{"kind": "weekly_scoped", "scope": {"model": {"display_name": "Fable"}},
             "percent": 43, "resets_at": "2026-10-20T22:00:00+00:00"}]}
EOF

    # when: the refresh a redraw forks, run in the foreground
    CLAUDE_CONFIG_DIR="$REGULAR_PROFILE" PATH="$STUBS:$PATH" STATUSLINE_TEST_LOG="$LOG" \
        bash "$SCRIPT" --refresh-usage </dev/null || return 1

    # then: the header arrived on stdin, the arguments never held the token, and the
    # answer reached the cache
    ! grep -q 'fixture-token-placeholder' "$LOG/curl.argv" &&
        grep -qx 'Authorization: Bearer fixture-token-placeholder' "$LOG/curl.stdin" &&
        grep -qx 'five=20' "$REGULAR_PROFILE/statusline-usage.cache" &&
        grep -qx 'account=someone@example.com' "$REGULAR_PROFILE/statusline-usage.cache" &&
        grep -q '^scoped=Fable:43:' "$REGULAR_PROFILE/statusline-usage.cache"
}

logged_in_session_shows_its_limits() {
    # given the regular profile with a fresh cache and a payload carrying both windows
    reset_log
    fresh_cache
    local limits='{"five_hour": {"used_percentage": 20, "resets_at": 1791500000},
                   "seven_day": {"used_percentage": 83, "resets_at": 1791900000}}'

    # when
    local out line1 line2
    out=$(render "$REGULAR_PROFILE" "$(payload "$PROJECT" "Opus 5 (1M context)" "$limits")") || return 1
    line1=$(sed -n 1p <<<"$out")
    line2=$(sed -n 2p <<<"$out")

    # then: the account, the model without its window suffix, both windows and the cap
    [[ "$line1" == *"someone@example.com"* ]] &&
        [[ "$line2" == *"Opus 5 ❯"* && "$line2" == *"5h 20%"* && "$line2" == *"7d 83%"* ]] &&
        [[ "$line2" == *"Fable 43%"* ]] &&
        [ ! -s "$LOG/mkdir.calls" ]
}

draws_no_private_use_area_glyph() {
    # given both profiles' lines
    reset_log
    fresh_cache
    local out
    out=$(render "$OMNI_PROFILE" "$(payload "$PROJECT/src" "qwen3.8:27b")") || return 1
    out+=$(render "$REGULAR_PROFILE" "$(payload "$PROJECT" "Opus 5")") || return 1

    # when / then: Claude Code strips U+E000-U+F8FF, every Nerd Font glyph, so none may be
    # drawn (matched as UTF-8 bytes, so the check needs no locale)
    ! LC_ALL=C grep -qP '\xEE[\x80-\xBF][\x80-\xBF]|\xEF[\x80-\xA3][\x80-\xBF]' <<<"$out"
}

omni_session_names_a_larger_models_window() {
    # given a session started on the GPU model's 64K window, switched with /model to a 256K model
    reset_log

    # when
    local line
    line=$(omni_render "ollama/qwen3.8:27b" \
        "$(omni_payload "openrouter/moonshotai/kimi-k2.7-code" "Kimi K2.7 Code · OpenRouter" 65536)") || return 1

    # then: the label, the session's window, which still decides when it compacts, and the model's own
    line=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$line")
    [[ "$line" == *"Kimi K2.7 Code · OpenRouter ❯ ctx 80% left (13k/65k · model 262k)"* ]]
}

omni_session_warns_when_the_model_is_smaller() {
    # given a session started on a 256K window, switched by hand to the GPU model's 64K one
    reset_log

    # when
    local line
    line=$(omni_render "openrouter/moonshotai/kimi-k2.7-code" \
        "$(omni_payload "ollama/qwen3.8:27b" "qwen3.8:27b · desktop GPU" 262144)") || return 1

    # then: in the error colour, since the session would compact only after the model overflows
    [[ "$line" == *$'\033[38;5;160m'"ctx 80% left · model holds 65k"* ]]
}

omni_session_on_its_launch_model_adds_nothing() {
    # given a session still on the model it started on
    reset_log

    # when
    local line
    line=$(omni_render "ollama/qwen3.8:27b" "$(omni_payload "ollama/qwen3.8:27b" "qwen3.8:27b · desktop GPU" 65536)") || return 1

    # then: the window as Claude Code reports it, and nothing more
    line=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$line")
    [[ "$line" == *"ctx 80% left (13k/65k)"* && "$line" != *"model "* ]]
}

fits_a_narrow_terminal() {
    # given a terminal far narrower than either line
    reset_log
    fresh_cache
    local out line
    out=$(render "$REGULAR_PROFILE" "$(payload "$PROJECT/src" "Opus 5")" 40) || return 1

    # when / then: each line sheds detail until it fits
    while IFS= read -r line; do
        [ "${#line}" -le 40 ] || return 1
    done <<<"$out"
}

run_case "a claude-omni session shows the model and its window, and no plan limits" \
    omni_session_shows_the_model_and_no_limits
run_case "a claude-omni session, which has no login, takes no refresh lock and forks nothing" \
    omni_session_starts_no_refresh
run_case "after /model, ctx names the new model's own window when it is larger" \
    omni_session_names_a_larger_models_window
run_case "after /model to a smaller window, ctx turns red and names it" \
    omni_session_warns_when_the_model_is_smaller
run_case "on the model it started on, a claude-omni session's ctx adds nothing" \
    omni_session_on_its_launch_model_adds_nothing
run_case "a refresh hands the OAuth token to curl on stdin, never in its arguments" \
    refresh_sends_the_token_on_stdin_only
run_case "a logged-in session shows its account, both windows and the model cap" \
    logged_in_session_shows_its_limits
run_case "no line draws a private-use-area glyph" draws_no_private_use_area_glyph
run_case "every line fits a 40-column terminal" fits_a_narrow_terminal

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-statusline] all status line tests passed" >&2
fi
exit "$EXIT_CODE"
