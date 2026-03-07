#!/data/data/com.termux/files/usr/bin/bash
# android-patch-claude-code-tmpdir.sh
#
# Patches Claude Code for Termux/Android compatibility:
#
# 1. Replaces hardcoded /tmp paths in cli.js with process.env.TMPDIR lookups.
#    Claude Code hardcodes "/tmp" and "/tmp/claude" in multiple places within
#    cli.js, which fails on Termux because /tmp is owned by shell:shell (0771)
#    and non-root users cannot write there.
#
#    NOTE: We use (process.env.TMPDIR||"/tmp") instead of require("os").tmpdir()
#    because cli.js is an ESM bundle where require() is not defined.
#    This is equivalent — Node.js os.tmpdir() just reads TMPDIR on POSIX.
#
# 2. Symlinks the system ripgrep binary into Claude Code's vendor directory.
#    Claude Code ships vendored ripgrep binaries but doesn't include arm64-android,
#    breaking the Grep and Glob tools.
#
# This script uses version-resilient patterns that match the surrounding code
# structure (e.g., ||"/tmp") rather than minified variable names, so it
# survives npm updates without manual pattern maintenance.
#
# This script is idempotent: it skips patching if already applied.
# It should be sourced/called from .zshrc on Android.
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
    local pkg_dir="$npm_root/@anthropic-ai/claude-code"
    local cli_js="$pkg_dir/cli.js"
    [[ -f "$cli_js" ]] || return 0

    # =========================================================================
    # Fix 1: Patch hardcoded /tmp paths in cli.js
    # =========================================================================
    if ! grep -q '__TERMUX_TMPDIR_PATCHED__' "$cli_js" 2>/dev/null; then
        if [[ ! -w "$cli_js" ]]; then
            echo "[claude-code-patch] cli.js is not writable: $cli_js" >&2
            return 1
        fi

        local patched=0
        # Shorthand used in sed replacements:
        local T='(process.env.TMPDIR||"/tmp")'

        # -----------------------------------------------------------------
        # Cleanup: Undo old patches that used require("os").tmpdir()
        # (require is not defined in ESM bundles)
        # -----------------------------------------------------------------
        if grep -q 'require("os").tmpdir()' "$cli_js"; then
            # revert require("os").tmpdir()+"/claude" → "/tmp/claude"
            sed -i 's#require("os").tmpdir()+"/claude"#"/tmp/claude"#g' "$cli_js"
            # revert require("os").tmpdir() → "/tmp"
            sed -i 's#require("os").tmpdir()#"/tmp"#g' "$cli_js"
            # revert template literals ${require("os").tmpdir()} → /tmp
            sed -i 's#${require("os").tmpdir()}#/tmp#g' "$cli_js"
            echo "[claude-code-patch] Reverted old require()-based patches"
        fi

        # -----------------------------------------------------------------
        # Pattern A: Fallback paths ||"/tmp/claude" (sandbox TMPDIR env)
        # These MUST be replaced before the shorter ||"/tmp" pattern.
        # FROM: ||"/tmp/claude"
        #   TO: ||(process.env.TMPDIR||"/tmp")+"/claude"
        # -----------------------------------------------------------------
        if grep -q '||"/tmp/claude"' "$cli_js"; then
            sed -i "s#||\"/tmp/claude\"#||${T}+\"/claude\"#g" "$cli_js"
            patched=$((patched + 1))
        fi

        # -----------------------------------------------------------------
        # Pattern B: All remaining ||"/tmp" fallbacks (main tmpdir resolver,
        # task spawn, screenshot path, etc.)
        # FROM: ||"/tmp"   (as a fallback value in expressions)
        #   TO: ||(process.env.TMPDIR||"/tmp")
        # -----------------------------------------------------------------
        if grep -q '||"/tmp"' "$cli_js"; then
            sed -i "s#||\"/tmp\"#||${T}#g" "$cli_js"
            patched=$((patched + 1))
        fi

        # -----------------------------------------------------------------
        # Pattern C: Colon-prefixed :"/tmp" fallbacks (ternary expressions)
        # FROM: :"/tmp")
        #   TO: :(process.env.TMPDIR||"/tmp"))
        # -----------------------------------------------------------------
        if grep -q ':"/tmp")' "$cli_js"; then
            sed -i "s#:\"/tmp\")#:${T})#g" "$cli_js"
            patched=$((patched + 1))
        fi

        # -----------------------------------------------------------------
        # Pattern D: Sandbox file allowlist — add dynamic path alongside
        # the existing static "/tmp/claude","/private/tmp/claude" entries.
        # -----------------------------------------------------------------
        if grep -q '"/tmp/claude","/private/tmp/claude"' "$cli_js"; then
            sed -i "s#\"/tmp/claude\",\"/private/tmp/claude\"#\"/tmp/claude\",\"/private/tmp/claude\",${T}+\"/claude\"#g" "$cli_js"
            patched=$((patched + 1))
        fi

        # -----------------------------------------------------------------
        # Pattern E: Template literal paths `/tmp/claude-...`
        # (MCP browser bridge directory and similar)
        # FROM: `/tmp/claude-
        #   TO: `${process.env.TMPDIR||"/tmp"}/claude-
        # -----------------------------------------------------------------
        if grep -q '`/tmp/claude-' "$cli_js"; then
            sed -i "s#\`/tmp/claude-#\`\${process.env.TMPDIR||\"/tmp\"}/claude-#g" "$cli_js"
            patched=$((patched + 1))
        fi

        # -----------------------------------------------------------------
        # Pattern F: Template literal fallback paths `/tmp/${...}`
        # (MCP browser bridge fallback and similar)
        # FROM: `/tmp/${
        #   TO: `${process.env.TMPDIR||"/tmp"}/${
        # -----------------------------------------------------------------
        if grep -q '`/tmp/${' "$cli_js"; then
            sed -i "s#\`/tmp/\${#\`\${process.env.TMPDIR||\"/tmp\"}/\${#g" "$cli_js"
            patched=$((patched + 1))
        fi

        # add sentinel to mark this file as patched
        if [[ $patched -gt 0 ]]; then
            if head -n 1 "$cli_js" | grep -q '^#!'; then
                sed -i '1a\/* __TERMUX_TMPDIR_PATCHED__ */' "$cli_js"
            else
                sed -i '1i\/* __TERMUX_TMPDIR_PATCHED__ */' "$cli_js"
            fi
            echo "[claude-code-patch] Patched $patched pattern(s) in cli.js"
        else
            echo "[claude-code-patch] No known patterns found — cli.js may have changed" >&2
        fi
    fi

    # =========================================================================
    # Fix 2: Symlink system ripgrep into Claude Code's vendor directory
    # =========================================================================
    local rg_vendor_dir="$pkg_dir/vendor/ripgrep/arm64-android"
    local rg_vendor_bin="$rg_vendor_dir/rg"
    local rg_system_bin
    rg_system_bin="$(command -v rg 2>/dev/null)"

    if [[ -n "$rg_system_bin" && ! -x "$rg_vendor_bin" ]]; then
        mkdir -p "$rg_vendor_dir" 2>/dev/null
        if ln -sf "$rg_system_bin" "$rg_vendor_bin" 2>/dev/null; then
            echo "[claude-code-patch] Symlinked system ripgrep to $rg_vendor_bin"
        else
            echo "[claude-code-patch] Failed to symlink ripgrep to $rg_vendor_bin" >&2
        fi
    fi
}

_patch_claude_code_tmpdir
