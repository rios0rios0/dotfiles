#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

echo "[test-modify-scripts] testing modify scripts with sample input..." >&2

# Test a modify script by feeding input and checking output
test_modify() {
    local file="$1"
    local input="$2"
    local check_pattern="$3"
    local description="$4"

    if [ ! -f "$file" ]; then
        echo "[test-modify-scripts] SKIP: $description (file not found)" >&2
        return
    fi

    local output
    output=$(echo "$input" | bash "$file" 2>/dev/null) || {
        echo "[test-modify-scripts] FAIL: $description (script failed)" >&2
        EXIT_CODE=1
        return
    }

    if [ -n "$check_pattern" ] && ! echo "$output" | grep -qE "$check_pattern"; then
        echo "[test-modify-scripts] FAIL: $description (expected pattern '$check_pattern' not in output)" >&2
        EXIT_CODE=1
        return
    fi

    echo "[test-modify-scripts] PASS: $description" >&2
}

# Test termux.properties modify script
test_modify \
    "$REPO_ROOT/dot_termux/modify_termux.properties.tmpl" \
    "" \
    "extra-keys" \
    "termux.properties adds extra-keys"

# --- JSON modify-templates ---------------------------------------------------
# These run only inside chezmoi -- there is no script to execute -- so each case
# builds a throwaway source/destination pair, writes the target's current content,
# and reads the result back with `chezmoi cat`. `--override-data` stands in for
# another platform, and HOME for the directories the trust template scans.

run_case() {
    local description="$1"
    shift
    if "$@"; then
        echo "[test-modify-scripts] PASS: $description" >&2
    else
        echo "[test-modify-scripts] FAIL: $description" >&2
        EXIT_CODE=1
    fi
}

# $1 source file, $2 target path, $3 the target's current content ("" = no file);
# the rest are extra chezmoi flags. Prints the result; the status is chezmoi's.
apply_modify_template() {
    local source_file="$1" target="$2" content="$3"
    shift 3
    local case_dir
    case_dir=$(mktemp -d "$SANDBOX/case.XXXXXX")
    mkdir -p "$case_dir/src/$(dirname "$source_file")" "$case_dir/dest/$(dirname "$target")" "$case_dir/home"
    cp -r "$REPO_ROOT/.chezmoitemplates" "$case_dir/src/"
    cp "$REPO_ROOT/$source_file" "$case_dir/src/$source_file"
    if [ -n "$content" ]; then
        printf '%s' "$content" > "$case_dir/dest/$target"
    fi
    : > "$case_dir/chezmoi.yaml"
    HOME="${CASE_HOME:-$case_dir/home}" chezmoi --config "$case_dir/chezmoi.yaml" \
        --source "$case_dir/src" --destination "$case_dir/dest" \
        --persistent-state "$case_dir/state.boltdb" --cache "$case_dir/cache" \
        "$@" cat "$case_dir/dest/$target" 2>/dev/null
}

mcp_creates_the_file() {
    # given no ~/.claude.json

    # when
    local out
    out=$(apply_modify_template modify_dot_claude.json .claude.json "") || return 1

    # then
    [ "$(jq -c 'keys' <<<"$out")" = '["mcpServers"]' ] &&
        [ "$(jq -c '.mcpServers | keys' <<<"$out")" = '["azure-devops","github","kubernetes","sonarqube"]' ]
}

mcp_passes_a_matching_file_through() {
    # given a file whose servers already match, in its owner's key order
    local servers
    servers=$(apply_modify_template modify_dot_claude.json .claude.json "" | jq -c '.mcpServers') || return 1
    jq --indent 2 --argjson servers "$servers" \
        '{zeta: "café <b> & c", numStartups: 42, mcpServers: ($servers + {custom: {command: "x"}})}' \
        <<<'{}' > "$SANDBOX/matching.json"

    # when
    apply_modify_template modify_dot_claude.json .claude.json "$(cat "$SANDBOX/matching.json")"$'\n' \
        > "$SANDBOX/matching.out" || return 1

    # then
    cmp -s "$SANDBOX/matching.json" "$SANDBOX/matching.out"
}

mcp_replaces_a_stale_server_only() {
    # given a stale managed server next to a server and a key the user added
    local input='{"theme": "dark", "mcpServers": {"github": {"command": "old"}, "custom": {"command": "mine"}}}'

    # when
    local out
    out=$(apply_modify_template modify_dot_claude.json .claude.json "$input") || return 1

    # then
    [ "$(jq -r '.theme' <<<"$out")" = "dark" ] &&
        [ "$(jq -r '.mcpServers.custom.command' <<<"$out")" = "mine" ] &&
        [ "$(jq -r '.mcpServers.github.command' <<<"$out")" = "docker" ] &&
        [ "$(jq -r '.mcpServers | length' <<<"$out")" = "5" ]
}

mcp_sets_the_http_server_on_android() {
    # given an Android machine with a server the user added

    # when
    local out
    out=$(apply_modify_template modify_dot_claude.json .claude.json '{"mcpServers": {"custom": {}}}' \
        --override-data '{"chezmoi": {"os": "android"}}') || return 1

    # then
    [ "$(jq -c '.mcpServers | keys' <<<"$out")" = '["custom","github"]' ] &&
        [ "$(jq -r '.mcpServers.github.type' <<<"$out")" = "http" ]
}

mcphub_uses_the_same_servers() {
    # given no ~/.config/mcphub/servers.json

    # when
    local out
    out=$(apply_modify_template dot_config/mcphub/modify_servers.json .config/mcphub/servers.json "") || return 1

    # then
    [ "$(jq -c '.mcpServers | keys' <<<"$out")" = '["azure-devops","github","kubernetes","sonarqube"]' ]
}

trust_covers_every_repository() {
    # given a development base with two repositories and a stray file
    local home="$SANDBOX/trust-home"
    local base="$home/Development/github.com/rios0rios0"
    mkdir -p "$base/repo-a" "$base/repo-b"
    touch "$base/notes.txt"

    # when
    local out
    out=$(CASE_HOME="$home" apply_modify_template dot_claude/modify_dot_claude.json .claude/.claude.json \
        '{"projects": {"'"$home"'": {"allowedTools": ["Read"]}}}') || return 1

    # then
    [ "$(jq -r '.projects | keys | length' <<<"$out")" = "4" ] &&
        [ "$(jq -r --arg d "$base/repo-b" '.projects[$d].hasTrustDialogAccepted' <<<"$out")" = "true" ] &&
        [ "$(jq -r --arg d "$home" '.projects[$d].allowedTools[0]' <<<"$out")" = "Read" ] &&
        [ "$(jq -r --arg d "$base/notes.txt" '.projects[$d]' <<<"$out")" = "null" ]
}

trust_passes_a_trusted_file_through() {
    # given a file in which every directory is already trusted
    local home="$SANDBOX/trusted-home"
    mkdir -p "$home"
    jq --indent 2 --arg home "$home" --arg base "$home/Development/github.com/rios0rios0" \
        '{projects: {($home): {hasTrustDialogAccepted: true}, ($base): {hasTrustDialogAccepted: true}}}' \
        <<<'{}' > "$SANDBOX/trusted.json"

    # when
    CASE_HOME="$home" apply_modify_template dot_claude/modify_dot_claude.json .claude/.claude.json \
        "$(cat "$SANDBOX/trusted.json")"$'\n' > "$SANDBOX/trusted.out" || return 1

    # then
    cmp -s "$SANDBOX/trusted.json" "$SANDBOX/trusted.out"
}

settings_fills_a_missing_file() {
    # given no ~/.claude/settings.json

    # when
    local out
    out=$(apply_modify_template dot_claude/modify_settings.json .claude/settings.json "") || return 1

    # then
    [ "$(jq -r '.effortLevel' <<<"$out")" = "high" ] &&
        [ "$(jq -r '.permissions.allow | length' <<<"$out")" = "23" ]
}

settings_keeps_user_choices() {
    # given a chosen effortLevel, a rule added by hand, and one managed rule
    local input='{"effortLevel": "low", "permissions": {"allow": ["Bash(make:*)", "Read"], "deny": ["Bash(rm:*)"]}}'

    # when
    local out
    out=$(apply_modify_template dot_claude/modify_settings.json .claude/settings.json "$input") || return 1

    # then
    [ "$(jq -r '.effortLevel' <<<"$out")" = "low" ] &&
        [ "$(jq -r '.permissions.allow[0]' <<<"$out")" = "Bash(make:*)" ] &&
        [ "$(jq -r '.permissions.allow | length' <<<"$out")" = "24" ] &&
        [ "$(jq -r '.permissions.allow | unique | length' <<<"$out")" = "24" ] &&
        [ "$(jq -r '.permissions.deny[0]' <<<"$out")" = "Bash(rm:*)" ]
}

settings_passes_a_complete_file_through() {
    # given a file that already holds every managed setting
    apply_modify_template dot_claude/modify_settings.json .claude/settings.json "" \
        | jq --indent 2 '{permissions: .permissions, effortLevel: .effortLevel}' > "$SANDBOX/complete.json"

    # when
    apply_modify_template dot_claude/modify_settings.json .claude/settings.json "$(cat "$SANDBOX/complete.json")"$'\n' \
        > "$SANDBOX/complete.out" || return 1

    # then
    cmp -s "$SANDBOX/complete.json" "$SANDBOX/complete.out"
}

windows_deploys_only_modify_templates() {
    # given the source state as chezmoi resolves it for Windows, which cannot start
    # a #! script: every modify_ file there must be a modify-template
    local sources
    : > "$SANDBOX/windows.yaml"

    # when
    sources=$(chezmoi --config "$SANDBOX/windows.yaml" --source "$REPO_ROOT" --destination "$SANDBOX/windows-home" \
        --persistent-state "$SANDBOX/windows.boltdb" --override-data '{"chezmoi": {"os": "windows"}}' \
        managed --include files --path-style source-relative 2>/dev/null) || return 1

    # then
    local file status=0
    while IFS= read -r file; do
        case "$(basename "$file")" in modify_*) ;; *) continue ;; esac
        if ! grep -q 'chezmoi:modify-template' "$REPO_ROOT/$file"; then
            echo "[test-modify-scripts]   $file deploys on Windows but is not a modify-template" >&2
            status=1
        fi
    done <<<"$sources"
    return $status
}

invalid_json_fails_instead_of_replacing() {
    # given a corrupt ~/.claude.json

    # when
    if apply_modify_template modify_dot_claude.json .claude.json '{"mcpServers": ' >/dev/null; then
        # then: the template must not have produced a replacement
        return 1
    fi
}

if ! command -v chezmoi &>/dev/null || ! command -v jq &>/dev/null; then
    echo "[test-modify-scripts] SKIP: JSON modify-templates (needs chezmoi and jq)" >&2
else
    SANDBOX=$(mktemp -d)
    trap 'rm -rf "$SANDBOX"' EXIT

    run_case "claude.json: creates the MCP servers when the file is missing" mcp_creates_the_file
    run_case "claude.json: passes a file whose servers match through byte for byte" mcp_passes_a_matching_file_through
    run_case "claude.json: replaces a stale managed server and keeps the user's" mcp_replaces_a_stale_server_only
    run_case "claude.json: sets only the HTTP GitHub server on Android" mcp_sets_the_http_server_on_android
    run_case "mcphub servers.json: gets the same servers" mcphub_uses_the_same_servers
    run_case "claude/.claude.json: trusts home, the dev base and each repository, not files" trust_covers_every_repository
    run_case "claude/.claude.json: passes an already trusted file through byte for byte" trust_passes_a_trusted_file_through
    run_case "settings.json: fills effortLevel and every rule when missing" settings_fills_a_missing_file
    run_case "settings.json: keeps a chosen effortLevel and hand-added rules in place" settings_keeps_user_choices
    run_case "settings.json: passes a complete file through byte for byte" settings_passes_a_complete_file_through
    run_case "claude.json: fails on invalid JSON instead of replacing the file" invalid_json_fails_instead_of_replacing
    run_case "every modify_ file that deploys on Windows is a modify-template" windows_deploys_only_modify_templates
fi

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[test-modify-scripts] all modify script tests passed" >&2
fi

exit $EXIT_CODE
