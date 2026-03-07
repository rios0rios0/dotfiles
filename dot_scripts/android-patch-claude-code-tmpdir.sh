#!/data/data/com.termux/files/usr/bin/bash
# android-patch-claude-code-tmpdir.sh
#
# Patches Claude Code's bundled cli.js to replace hardcoded /tmp/claude paths
# with dynamic paths that respect $TMPDIR on Termux/Android.
#
# Claude Code hardcodes "/tmp/claude" in multiple places within cli.js, which
# fails on Termux because /tmp is owned by shell:shell (0771) and non-root
# users cannot write there. The existing CLAUDE_CODE_TMPDIR env var is
# inconsistently applied — many code paths ignore it entirely.
#
# This script is idempotent: it skips patching if already applied.
# It should be sourced/called from .zshrc on Android to ensure the patch
# survives npm updates of @anthropic-ai/claude-code.
#
# See: https://github.com/anthropics/claude-code/issues/15637

_patch_claude_code_tmpdir() {
    # only run on Termux
    [[ -z "$PREFIX" ]] && return 0

    local termux_tmp="${TMPDIR:-$PREFIX/tmp}"
    export TMPDIR="$termux_tmp"

    # locate cli.js from the globally installed claude-code package
    local npm_root
    npm_root="$(npm root -g 2>/dev/null)" || return 0
    local cli_js="$npm_root/@anthropic-ai/claude-code/cli.js"
    [[ -f "$cli_js" ]] || return 0

    # skip if already patched (check for our sentinel comment)
    if grep -q '__TERMUX_TMPDIR_PATCHED__' "$cli_js" 2>/dev/null; then
        return 0
    fi

    # verify we can write to the file
    if [[ ! -w "$cli_js" ]]; then
        echo "[claude-code-patch] cli.js is not writable: $cli_js" >&2
        return 1
    fi

    # create a backup before patching
    cp "$cli_js" "${cli_js}.bak" 2>/dev/null

    local patched=0

    # -------------------------------------------------------------------------
    # Pattern 1: Main tmpdir resolver (wE function)
    # FROM: CLAUDE_CODE_TMPDIR||(c8()==="windows"?hIz():"/tmp")
    #   TO: CLAUDE_CODE_TMPDIR||(c8()==="windows"?hIz():require("os").tmpdir())
    # -------------------------------------------------------------------------
    if grep -q 'CLAUDE_CODE_TMPDIR||(c8()==="windows"?hIz():"/tmp")' "$cli_js"; then
        sed -i 's#CLAUDE_CODE_TMPDIR||(c8()==="windows"?hIz():"/tmp")#CLAUDE_CODE_TMPDIR||(c8()==="windows"?hIz():require("os").tmpdir())#' "$cli_js"
        patched=$((patched + 1))
    fi

    # -------------------------------------------------------------------------
    # Pattern 2: Sandbox TMPDIR env (VY1 function) — uses CLAUDE_TMPDIR (no _CODE_)
    # FROM: TMPDIR=${process.env.CLAUDE_TMPDIR||"/tmp/claude"}
    #   TO: TMPDIR=${process.env.CLAUDE_TMPDIR||require("os").tmpdir()+"/claude"}
    # -------------------------------------------------------------------------
    if grep -q 'process.env.CLAUDE_TMPDIR||"/tmp/claude"' "$cli_js"; then
        sed -i 's#process.env.CLAUDE_TMPDIR||"/tmp/claude"#process.env.CLAUDE_TMPDIR||require("os").tmpdir()+"/claude"#' "$cli_js"
        patched=$((patched + 1))
    fi

    # -------------------------------------------------------------------------
    # Pattern 3: Sandbox file allowlist ($x6 function)
    # FROM: "/tmp/claude","/private/tmp/claude"
    #   TO: "/tmp/claude","/private/tmp/claude",require("os").tmpdir()+"/claude"
    # -------------------------------------------------------------------------
    if grep -q '"/tmp/claude","/private/tmp/claude"' "$cli_js"; then
        sed -i 's#"/tmp/claude","/private/tmp/claude"#"/tmp/claude","/private/tmp/claude",require("os").tmpdir()+"/claude"#' "$cli_js"
        patched=$((patched + 1))
    fi

    # -------------------------------------------------------------------------
    # Pattern 4: MCP browser bridge directory (jd6 function)
    # FROM: `/tmp/claude-mcp-browser-bridge-${nE8()}`
    #   TO: `${require("os").tmpdir()}/claude-mcp-browser-bridge-${nE8()}`
    # -------------------------------------------------------------------------
    if grep -q '`/tmp/claude-mcp-browser-bridge-' "$cli_js"; then
        sed -i 's#`/tmp/claude-mcp-browser-bridge-#`${require("os").tmpdir()}/claude-mcp-browser-bridge-#' "$cli_js"
        patched=$((patched + 1))
    fi

    # -------------------------------------------------------------------------
    # Pattern 5: MCP browser bridge fallback path (A_4 function)
    # FROM: z=`/tmp/${K}`
    #   TO: z=`${require("os").tmpdir()}/${K}`
    # -------------------------------------------------------------------------
    if grep -q 'z=`/tmp/${K}`' "$cli_js"; then
        sed -i 's#z=`/tmp/${K}`#z=`${require("os").tmpdir()}/${K}`#' "$cli_js"
        patched=$((patched + 1))
    fi

    # -------------------------------------------------------------------------
    # Pattern 6: Task spawn tmpdir (agent/background tasks)
    # FROM: CLAUDE_CODE_TMPDIR||"/tmp",tk8()
    #   TO: CLAUDE_CODE_TMPDIR||require("os").tmpdir(),tk8()
    # -------------------------------------------------------------------------
    if grep -q 'CLAUDE_CODE_TMPDIR||"/tmp",tk8()' "$cli_js"; then
        sed -i 's#CLAUDE_CODE_TMPDIR||"/tmp",tk8()#CLAUDE_CODE_TMPDIR||require("os").tmpdir(),tk8()#' "$cli_js"
        patched=$((patched + 1))
    fi

    # -------------------------------------------------------------------------
    # Pattern 7: Screenshot path resolver
    # FROM: CLAUDE_CODE_TMPDIR||(A==="win32"?process.env.TEMP||"C:\\Temp":"/tmp")
    #   TO: CLAUDE_CODE_TMPDIR||(A==="win32"?process.env.TEMP||"C:\\Temp":require("os").tmpdir())
    # -------------------------------------------------------------------------
    if grep -q 'CLAUDE_CODE_TMPDIR||(A==="win32"?process.env.TEMP' "$cli_js"; then
        sed -i 's#"C:\\\\Temp":"/tmp")#"C:\\\\Temp":require("os").tmpdir())#' "$cli_js"
        patched=$((patched + 1))
    fi

    # add sentinel comment to mark this file as patched
    if [[ $patched -gt 0 ]]; then
        sed -i '1s#^#/* __TERMUX_TMPDIR_PATCHED__ */\n#' "$cli_js"
        echo "[claude-code-patch] Patched $patched hardcoded /tmp path(s) in cli.js"
    else
        echo "[claude-code-patch] No known patterns found — cli.js may have been updated"
    fi
}

_patch_claude_code_tmpdir
