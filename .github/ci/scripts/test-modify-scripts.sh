#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0
SERVERS='.mcpServers'
SERVER_NAMES='.mcpServers | keys'

echo "[test-modify-scripts] testing modify scripts with sample input..." >&2

# Test a modify script by feeding input and checking output
test_modify() {
    local file="$1"
    local input="$2"
    local check_pattern="$3"
    local description="$4"

    if [[ ! -f "$file" ]]; then
        echo "[test-modify-scripts] SKIP: $description (file not found)" >&2
        return
    fi

    local output
    output=$(echo "$input" | bash "$file" 2>/dev/null) || {
        echo "[test-modify-scripts] FAIL: $description (script failed)" >&2
        EXIT_CODE=1
        return
    }

    if [[ -n "$check_pattern" ]] && ! echo "$output" | grep -qE "$check_pattern"; then
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

# --- JSON modify-templates -----------------------------------------------------
# These run only inside chezmoi -- there is no script to execute -- so each case
# builds a throwaway source/destination pair, writes the target's current content,
# and reads the result back with `chezmoi cat`. `--override-data` stands in for
# another platform, and HOME for the directories the trust template scans and the
# home the status line path is rendered from.

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
    cp -r "$REPO_ROOT/.chezmoidata" "$case_dir/src/"
    cp "$REPO_ROOT/$source_file" "$case_dir/src/$source_file"
    if [[ -n "${CASE_CONTENT_FILE:-}" ]]; then
        # for content a shell string cannot hold, such as UTF-16's NUL bytes
        cp "$CASE_CONTENT_FILE" "$case_dir/dest/$target"
    elif [[ -n "$content" ]]; then
        printf '%s' "$content" > "$case_dir/dest/$target"
    fi
    : > "$case_dir/chezmoi.yaml"
    HOME="${CASE_HOME:-$case_dir/home}" chezmoi --config "$case_dir/chezmoi.yaml" \
        --source "$case_dir/src" --destination "$case_dir/dest" \
        --persistent-state "$case_dir/state.boltdb" --cache "$case_dir/cache" \
        "$@" cat "$case_dir/dest/$target" 2>/dev/null
}

# The MCP servers and ~/.claude/settings.json both differ by platform, so every case names the
# platform it stands for rather than inheriting the host's. Windows is not among them: Claude
# Code is not installed there, and .chezmoiignore keeps ~/.claude.json and ~/.claude off it.
ANDROID=(--override-data '{"chezmoi": {"os": "android"}}')
LINUX=(--override-data '{"chezmoi": {"os": "linux"}}')

# Prints ~/.claude.json created from nothing on each platform that gets it, one JSON document
# after another.
render_mcp_on_every_platform() {
    apply_modify_template modify_dot_claude.json .claude.json "" "${LINUX[@]}" &&
        apply_modify_template modify_dot_claude.json .claude.json "" "${ANDROID[@]}"
}

mcp_creates_the_file() {
    # given no ~/.claude.json on Linux

    # when
    local out
    out=$(apply_modify_template modify_dot_claude.json .claude.json "" "${LINUX[@]}") || return 1

    # then
    [[ "$(jq -c 'keys' <<<"$out")" = '["mcpServers"]' ]] &&
        [[ "$(jq -c "$SERVER_NAMES" <<<"$out")" = '["chrome-devtools","context7"]' ]]
}

mcp_passes_a_matching_file_through() {
    # given a file whose servers already match, in its owner's key order
    local servers
    servers=$(apply_modify_template modify_dot_claude.json .claude.json "" "${LINUX[@]}" | jq -c "$SERVERS") ||
        return 1
    jq --indent 2 --argjson servers "$servers" \
        '{zeta: "café <b> & c", numStartups: 42, mcpServers: ($servers + {custom: {command: "x"}})}' \
        <<<'{}' > "$SANDBOX/matching.json"

    # when
    apply_modify_template modify_dot_claude.json .claude.json "$(cat "$SANDBOX/matching.json")"$'\n' \
        "${LINUX[@]}" > "$SANDBOX/matching.out" || return 1

    # then
    cmp -s "$SANDBOX/matching.json" "$SANDBOX/matching.out"
}

mcp_replaces_a_stale_server_only() {
    # given a stale managed server next to a server and a key the user added
    local input='{"theme": "dark", "mcpServers": {"context7": {"type": "http", "url": "https://old.example/mcp"}, "custom": {"command": "mine"}}}'

    # when
    local out
    out=$(apply_modify_template modify_dot_claude.json .claude.json "$input" "${LINUX[@]}") || return 1

    # then
    [[ "$(jq -r '.theme' <<<"$out")" = "dark" ]] &&
        [[ "$(jq -r '.mcpServers.custom.command' <<<"$out")" = "mine" ]] &&
        [[ "$(jq -r '.mcpServers.context7.url' <<<"$out")" = "https://mcp.context7.com/mcp" ]] &&
        [[ "$(jq -r '.mcpServers | length' <<<"$out")" = "3" ]]
}

mcp_retires_the_dropped_servers() {
    # given a Linux file that already holds today's servers, next to the four this repository set
    # until they were retired, a server the user added, and a key of Claude Code's own
    local servers
    servers=$(apply_modify_template modify_dot_claude.json .claude.json "" "${LINUX[@]}" | jq -c "$SERVERS") ||
        return 1
    local input
    input=$(jq -c --argjson servers "$servers" '{numStartups: 42, mcpServers: ($servers + {
        github: {command: "docker"}, "azure-devops": {command: "docker"}, sonarqube: {command: "docker"},
        kubernetes: {type: "stdio", command: "npx", args: ["-y", "kubernetes-mcp-server@latest"]},
        custom: {command: "mine"}})}' <<<'{}')

    # when
    local out
    out=$(apply_modify_template modify_dot_claude.json .claude.json "$input" "${LINUX[@]}") || return 1

    # then: removing them is a change on its own, so the file is rewritten without them
    [[ "$(jq -c "$SERVER_NAMES" <<<"$out")" = '["chrome-devtools","context7","custom"]' ]] &&
        [[ "$(jq -r '.numStartups' <<<"$out")" = "42" ]]
}

mcp_retires_only_what_the_platform_had() {
    # given an Android file with the HTTP GitHub server this repository set there, and a
    # Kubernetes server it never set on Android, so one the user added

    # when
    local out
    out=$(apply_modify_template modify_dot_claude.json .claude.json \
        '{"mcpServers": {"github": {"type": "http"}, "kubernetes": {"command": "mine"}}}' "${ANDROID[@]}") ||
        return 1

    # then
    [[ "$(jq -c "$SERVER_NAMES" <<<"$out")" = '["context7","kubernetes"]' ]] &&
        [[ "$(jq -r '.mcpServers.kubernetes.command' <<<"$out")" = "mine" ]]
}

mcp_keeps_the_browser_on_linux() {
    # given no ~/.claude.json on Android, which has no supported Chrome for the DevTools server
    # to drive

    # when
    local out
    out=$(apply_modify_template modify_dot_claude.json .claude.json "" "${ANDROID[@]}") || return 1

    # then
    [[ "$(jq -c "$SERVER_NAMES" <<<"$out")" = '["context7"]' ]]
}

mcp_sets_only_remote_servers_on_android() {
    # given an Android machine with a server the user added

    # when
    local out
    out=$(apply_modify_template modify_dot_claude.json .claude.json '{"mcpServers": {"custom": {}}}' \
        "${ANDROID[@]}") || return 1

    # then: none of ours starts a process against Termux's budget
    [[ "$(jq -c "$SERVER_NAMES" <<<"$out")" = '["context7","custom"]' ]] &&
        [[ "$(jq -r '.mcpServers.context7.type' <<<"$out")" = "http" ]]
}

mcphub_uses_the_same_servers() {
    # given mcp-hub's servers.json on Android, the one platform it is deployed to, still holding
    # the retired GitHub server, and ~/.claude.json in the same state
    local input='{"mcpServers": {"github": {"type": "http"}}}'

    # when
    local hub claude
    hub=$(apply_modify_template dot_config/mcphub/modify_servers.json .config/mcphub/servers.json "$input" \
        "${ANDROID[@]}") || return 1
    claude=$(apply_modify_template modify_dot_claude.json .claude.json "$input" "${ANDROID[@]}") || return 1

    # then
    [[ "$(jq -S -c "$SERVERS" <<<"$hub")" == "$(jq -S -c "$SERVERS" <<<"$claude")" ]] &&
        [[ "$(jq -c "$SERVER_NAMES" <<<"$hub")" = '["context7"]' ]]
}

mcp_placeholders_resolve_in_both_readers() {
    # given the servers of every platform

    # when
    local placeholders
    placeholders=$(render_mcp_on_every_platform | jq -r '.. | strings' | grep -o '\${[^}]*}') || return 1

    # then: a bare ${NAME} is the one form mcp-hub resolves; it reads ${NAME:-x} as a variable
    # named "NAME:-x" and refuses to start the server
    ! grep -q -v -x -E '\$\{[A-Za-z_][A-Za-z0-9_]*\}' <<<"$placeholders"
}

mcp_keeps_secrets_off_argv() {
    # given the servers of every platform

    # when
    local argv
    argv=$(render_mcp_on_every_platform | jq -r '.mcpServers[] | (.command // empty), (.args // [])[]') ||
        return 1

    # then: a placeholder there would put its value on the process's argv, which any local user
    # can read in /proc/<pid>/cmdline -- values travel through env or a header instead
    [[ -n "$argv" ]] && ! grep -q -F '${' <<<"$argv"
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
    [[ "$(jq -r '.projects | keys | length' <<<"$out")" = "4" ]] &&
        [[ "$(jq -r --arg d "$base/repo-b" '.projects[$d].hasTrustDialogAccepted' <<<"$out")" = "true" ]] &&
        [[ "$(jq -r --arg d "$home" '.projects[$d].allowedTools[0]' <<<"$out")" = "Read" ]] &&
        [[ "$(jq -r --arg d "$base/notes.txt" '.projects[$d]' <<<"$out")" = "null" ]]
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

# ~/.claude/settings.json carries the permission rules on Android and the look on Linux, which
# is why these cases pass the platform arrays defined above the MCP cases.

settings_fills_a_missing_file() {
    # given no ~/.claude/settings.json on Android

    # when
    local out
    out=$(apply_modify_template dot_claude/modify_settings.json .claude/settings.json "" "${ANDROID[@]}") || return 1

    # then: the rules and effortLevel, and none of Linux's look
    [[ "$(jq -c 'keys' <<<"$out")" = '["effortLevel","permissions"]' ]] &&
        [[ "$(jq -r '.effortLevel' <<<"$out")" = "high" ]] &&
        [[ "$(jq -r '.permissions.allow | length' <<<"$out")" = "22" ]]
}

settings_keeps_user_choices() {
    # given a chosen effortLevel, a rule added by hand, and one managed rule
    local input='{"effortLevel": "low", "permissions": {"allow": ["Bash(make:*)", "Read"], "deny": ["Bash(rm:*)"]}}'

    # when
    local out
    out=$(apply_modify_template dot_claude/modify_settings.json .claude/settings.json "$input" "${ANDROID[@]}") ||
        return 1

    # then
    [[ "$(jq -r '.effortLevel' <<<"$out")" = "low" ]] &&
        [[ "$(jq -r '.permissions.allow[0]' <<<"$out")" = "Bash(make:*)" ]] &&
        [[ "$(jq -r '.permissions.allow | length' <<<"$out")" = "23" ]] &&
        [[ "$(jq -r '.permissions.allow | unique | length' <<<"$out")" = "23" ]] &&
        [[ "$(jq -r '.permissions.deny[0]' <<<"$out")" = "Bash(rm:*)" ]]
}

settings_retires_the_github_mcp_rule() {
    # given an Android file whose rules hold the one granting the retired GitHub MCP server,
    # between a rule added by hand and a managed one
    local input='{"permissions": {"allow": ["Bash(make:*)", "mcp__github__*", "Read"]}}'

    # when
    local out
    out=$(apply_modify_template dot_claude/modify_settings.json .claude/settings.json "$input" "${ANDROID[@]}") ||
        return 1

    # then: the rule is gone and the others keep their order
    [[ "$(jq -r '.permissions.allow | index("mcp__github__*")' <<<"$out")" = "null" ]] &&
        [[ "$(jq -r '.permissions.allow[0:2] | join(" ")' <<<"$out")" = "Bash(make:*) Read" ]]
}

settings_passes_a_complete_file_through() {
    # given a file that already holds every managed setting
    apply_modify_template dot_claude/modify_settings.json .claude/settings.json "" "${ANDROID[@]}" \
        | jq --indent 2 '{permissions: .permissions, effortLevel: .effortLevel}' > "$SANDBOX/complete.json"

    # when
    apply_modify_template dot_claude/modify_settings.json .claude/settings.json "$(cat "$SANDBOX/complete.json")"$'\n' \
        "${ANDROID[@]}" > "$SANDBOX/complete.out" || return 1

    # then
    cmp -s "$SANDBOX/complete.json" "$SANDBOX/complete.out"
}

settings_gives_linux_the_look_only() {
    # given a Linux file with the user's own keys and a theme picked with /theme
    local home="$SANDBOX/look-home"
    mkdir -p "$home"
    local input='{"model": "opus", "permissions": {"defaultMode": "auto"}, "theme": "light"}'

    # when
    local out
    out=$(CASE_HOME="$home" apply_modify_template dot_claude/modify_settings.json .claude/settings.json "$input" \
        "${LINUX[@]}") || return 1

    # then: the look is set, the user's keys stay, and no rule or effortLevel arrives
    [[ "$(jq -r '.theme' <<<"$out")" = "dark-ansi" ]] &&
        [[ "$(jq -r '.tui' <<<"$out")" = "fullscreen" ]] &&
        [[ "$(jq -r '.statusLine.command' <<<"$out")" = "bash $home/.claude/statusline-command.sh" ]] &&
        [[ "$(jq -r '.statusLine.padding' <<<"$out")" = "0" ]] &&
        [[ "$(jq -r '.model' <<<"$out")" = "opus" ]] &&
        [[ "$(jq -c '.permissions' <<<"$out")" = '{"defaultMode":"auto"}' ]] &&
        [[ "$(jq -r 'has("effortLevel")' <<<"$out")" = "false" ]]
}

settings_passes_a_linux_file_with_the_look_through() {
    # given a Linux file that already has the look, in its owner's key order
    local home="$SANDBOX/look-through-home"
    mkdir -p "$home"
    CASE_HOME="$home" apply_modify_template dot_claude/modify_settings.json .claude/settings.json "" "${LINUX[@]}" \
        | jq --indent 2 '{model: "opus", statusLine: .statusLine, tui: .tui, theme: .theme, voiceEnabled: true}' \
        > "$SANDBOX/look.json"

    # when
    CASE_HOME="$home" apply_modify_template dot_claude/modify_settings.json .claude/settings.json \
        "$(cat "$SANDBOX/look.json")"$'\n' "${LINUX[@]}" > "$SANDBOX/look.out" || return 1

    # then
    cmp -s "$SANDBOX/look.json" "$SANDBOX/look.out"
}

# --- WSL's .wslconfig ----------------------------------------------------------
# An INI file the WSL Settings app writes too: the template keeps .chezmoidata/wsl.yaml's keys and
# every other line, comparing case-insensitively and keeping the file's line endings.

wslconfig_creates_the_settings() {
    # given no ~/.wslconfig

    # when
    local out
    out=$(apply_modify_template modify_dot_wslconfig .wslconfig "") || return 1

    # then: both sections, in the CRLF the WSL Settings app writes
    [[ "$out" = $'[experimental]\r\nautoMemoryReclaim=Gradual\r\nsparseVhd=true\r\n[general]\r\ninstanceIdleTimeout=-1\r' ]]
}

wslconfig_passes_the_apps_file_through() {
    # given the file exactly as the WSL Settings app wrote it: CRLF, no final newline, and a
    # lowercase value the app would write capitalised
    printf '[experimental]\r\nautoMemoryReclaim=gradual\r\nsparseVhd=true\r\n[general]\r\ninstanceIdleTimeout=-1' \
        > "$SANDBOX/wslconfig.app"

    # when
    apply_modify_template modify_dot_wslconfig .wslconfig "$(cat "$SANDBOX/wslconfig.app")" \
        > "$SANDBOX/wslconfig.out" || return 1

    # then
    cmp -s "$SANDBOX/wslconfig.app" "$SANDBOX/wslconfig.out"
}

wslconfig_keeps_everything_else() {
    # given hand-written settings, a comment, a wrong value under another case, and an empty section
    local input=$'# mine\n[wsl2]\nmemory=16GB\n\n[experimental]\nAutoMemoryReclaim=dropcache\nnetworkingMode=mirrored\n\n[general]\n'

    # when
    local out
    out=$(apply_modify_template modify_dot_wslconfig .wslconfig "$input") || return 1

    # then: the value is set back in place, the missing keys join their sections, and the rest stays
    [[ "$out" = $'# mine\n[wsl2]\nmemory=16GB\n\n[experimental]\nautoMemoryReclaim=Gradual\nnetworkingMode=mirrored\nsparseVhd=true\n\n[general]\ninstanceIdleTimeout=-1' ]]
}

wslconfig_keeps_a_utf8_bom() {
    # given the file as Windows PowerShell 5.1's `Set-Content -Encoding UTF8` writes it: a BOM
    # before the first section, which must not hide that section
    local input=$'\xef\xbb\xbf[experimental]\r\nautoMemoryReclaim=dropcache\r\nsparseVhd=true\r\n[general]\r\ninstanceIdleTimeout=-1\r\n'

    # when
    local out
    out=$(apply_modify_template modify_dot_wslconfig .wslconfig "$input") || return 1

    # then: the value is set back under the BOM, with no second [experimental] section
    [[ "$out" = $'\xef\xbb\xbf[experimental]\r\nautoMemoryReclaim=Gradual\r\nsparseVhd=true\r\n[general]\r\ninstanceIdleTimeout=-1\r' ]]
}

wslconfig_leaves_utf16_alone() {
    # given the file as Windows PowerShell 5.1's `>` writes it: UTF-16 LE, BOM first, and a value
    # that differs
    printf '[experimental]\r\nautoMemoryReclaim=dropcache\r\n' | iconv -f UTF-8 -t UTF-16 > "$SANDBOX/wslconfig.utf16"

    # when
    CASE_CONTENT_FILE="$SANDBOX/wslconfig.utf16" apply_modify_template modify_dot_wslconfig .wslconfig "" \
        > "$SANDBOX/wslconfig.utf16.out" || return 1

    # then: passed through untouched, since no line of it could be read
    cmp -s "$SANDBOX/wslconfig.utf16" "$SANDBOX/wslconfig.utf16.out"
}

# --- Docker Desktop's settings-store.json ---------------------------------------
# Docker Desktop's own settings, as JSON: the template keeps .chezmoidata/docker-desktop.yaml's
# settings and WSL distributions, and every other key Docker Desktop writes.

DOCKER_SOURCE="AppData/Roaming/Docker/modify_settings-store.json"
DOCKER_TARGET="AppData/Roaming/Docker/settings-store.json"
DOCKER_MANAGED='del(.AutoStart, .EnableIntegrationWithDefaultWslDistro, .IntegratedWslDistros)'

docker_creates_the_settings() {
    # given no settings-store.json, as before Docker Desktop's first start

    # when
    local out
    out=$(apply_modify_template "$DOCKER_SOURCE" "$DOCKER_TARGET" "") || return 1

    # then: the integration with the WSL distribution, and the start at sign-in
    jq -e '. == {"AutoStart": true, "EnableIntegrationWithDefaultWslDistro": true, "IntegratedWslDistros": ["kali-linux"]}' \
        <<<"$out" >/dev/null
}

docker_passes_a_matching_file_through() {
    # given the file as Docker Desktop writes it, every managed setting in place and another
    # distribution listed first
    printf '{\n  "AutoStart": true,\n  "EnableIntegrationWithDefaultWslDistro": true,\n  "IntegratedWslDistros": [\n    "Ubuntu",\n    "kali-linux"\n  ],\n  "MemoryMiB": 8192\n}' \
        > "$SANDBOX/docker.json"

    # when
    apply_modify_template "$DOCKER_SOURCE" "$DOCKER_TARGET" "$(cat "$SANDBOX/docker.json")" \
        > "$SANDBOX/docker.out" || return 1

    # then
    cmp -s "$SANDBOX/docker.json" "$SANDBOX/docker.out"
}

docker_keeps_other_keys_and_distros() {
    # given another distribution, settings of Docker Desktop's own, and the start at sign-in off
    local input='{"AutoStart": false, "IntegratedWslDistros": ["Ubuntu"], "MemoryMiB": 8192, "ProxyHttpMode": "system", "Extensions": {"enabled": true, "list": [1, 2]}}'

    # when
    local out
    out=$(apply_modify_template "$DOCKER_SOURCE" "$DOCKER_TARGET" "$input") || return 1

    # then: the distribution joins after the one listed, the settings are set, and the rest stays
    jq -e '.IntegratedWslDistros == ["Ubuntu", "kali-linux"] and .AutoStart == true and .EnableIntegrationWithDefaultWslDistro == true' \
        <<<"$out" >/dev/null &&
        [[ "$(jq -cS "$DOCKER_MANAGED" <<<"$out")" == "$(jq -cS "$DOCKER_MANAGED" <<<"$input")" ]]
}

docker_fails_on_invalid_json() {
    # given a corrupt settings-store.json

    # when
    if apply_modify_template "$DOCKER_SOURCE" "$DOCKER_TARGET" '{"AutoStart": ' >/dev/null; then
        # then: the template must not have produced a replacement
        return 1
    fi
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
    : > "$SANDBOX/empty.yaml"

    run_case "claude.json: creates the MCP servers when the file is missing" mcp_creates_the_file
    run_case "claude.json: passes a file whose servers match through byte for byte" mcp_passes_a_matching_file_through
    run_case "claude.json: replaces a stale managed server and keeps the user's" mcp_replaces_a_stale_server_only
    run_case "claude.json: removes the retired servers from an existing file" mcp_retires_the_dropped_servers
    run_case "claude.json: removes a retired server only on a platform it was set on" \
        mcp_retires_only_what_the_platform_had
    run_case "claude.json: gives Chrome DevTools to Linux only" mcp_keeps_the_browser_on_linux
    run_case "claude.json: sets only the remote servers on Android" mcp_sets_only_remote_servers_on_android
    run_case "mcphub servers.json: gets the same servers as claude.json on Android, retirements included" \
        mcphub_uses_the_same_servers
    run_case "claude.json: writes every placeholder in the one form mcp-hub also resolves" \
        mcp_placeholders_resolve_in_both_readers
    run_case "claude.json: puts no placeholder on a server's command line" mcp_keeps_secrets_off_argv
    run_case "claude/.claude.json: trusts home, the dev base and each repository, not files" trust_covers_every_repository
    run_case "claude/.claude.json: passes an already trusted file through byte for byte" trust_passes_a_trusted_file_through
    run_case "settings.json: fills effortLevel and every rule when missing" settings_fills_a_missing_file
    run_case "settings.json: keeps a chosen effortLevel and hand-added rules in place" settings_keeps_user_choices
    run_case "settings.json: takes out the retired GitHub MCP rule" settings_retires_the_github_mcp_rule
    run_case "settings.json: passes a complete file through byte for byte" settings_passes_a_complete_file_through
    run_case "settings.json: gives Linux the look and none of the rules" settings_gives_linux_the_look_only
    run_case "settings.json: passes a Linux file that has the look through byte for byte" \
        settings_passes_a_linux_file_with_the_look_through
    run_case "claude.json: fails on invalid JSON instead of replacing the file" invalid_json_fails_instead_of_replacing
    run_case "wslconfig: creates both sections when the file is missing" wslconfig_creates_the_settings
    run_case "wslconfig: passes the WSL Settings app's file through byte for byte" wslconfig_passes_the_apps_file_through
    run_case "wslconfig: sets a value back and keeps every other line" wslconfig_keeps_everything_else
    run_case "wslconfig: keeps a UTF-8 BOM and reads the section behind it" wslconfig_keeps_a_utf8_bom
    run_case "wslconfig: leaves a UTF-16 file as it is" wslconfig_leaves_utf16_alone
    run_case "Docker Desktop settings: created with the managed keys when the file is missing" docker_creates_the_settings
    run_case "Docker Desktop settings: passes a file with every setting in place through byte for byte" \
        docker_passes_a_matching_file_through
    run_case "Docker Desktop settings: sets the managed keys and keeps every other key and distribution" \
        docker_keeps_other_keys_and_distros
    run_case "Docker Desktop settings: fails on invalid JSON instead of replacing the file" docker_fails_on_invalid_json
    run_case "every modify_ file that deploys on Windows is a modify-template" windows_deploys_only_modify_templates
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-modify-scripts] all modify script tests passed" >&2
fi

exit $EXIT_CODE
