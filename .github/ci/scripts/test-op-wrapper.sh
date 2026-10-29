#!/bin/bash
set -euo pipefail

# Tests how chezmoi reaches 1Password's Windows app. The app removes the pipe op connects to for
# about 0.9 s after an `op account list`, and an op started in that gap exits at once with "cannot
# connect to 1Password app, make sure it is running"; chezmoi runs `op account list` and then
# `op signin` back to back, so every apply failed at its first 1Password template. And on Windows
# an approval belongs to the process that runs op, so op has to be chezmoi's own child there.
#
# Covers the WSL wrapper that run_once_before_linux-001-create-op-wrapper.sh writes -- a turned-away
# call retried with only the retry's output passed on, giving up after four attempts with the last
# error, any other failure passed on at once with its own exit code, a terminal's op left alone,
# WSLENV still exported -- the config .chezmoi.yaml.tmpl renders on each platform, read back the way
# chezmoi loads it (op.exe itself and OP_ACCOUNT on Windows, no submodule recursion), the templates
# naming no account on Windows, so that chezmoi runs no `account list` there, and no template naming
# the account itself. op.exe, op and sleep are stubs, so nothing reaches 1Password and no case waits.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXIT_CODE=0

pass() { echo "[test-op-wrapper] PASS: $1" >&2; }
fail() { echo "[test-op-wrapper] FAIL: $1" >&2; EXIT_CODE=1; }

echo "[test-op-wrapper] testing the retry in front of op.exe..." >&2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The wrapper, as the script writes it.
HOME="$TMP/home" bash "$REPO_ROOT/.chezmoiscripts/run_once_before_linux-001-create-op-wrapper.sh" 2>/dev/null
WRAPPER="$TMP/home/.local/bin/op"
bash -n "$WRAPPER" || fail "the wrapper is not valid bash"

# op.exe stub: logs each call and the WSLENV it got; while the calls so far are within
# $OP_TURNED_AWAY it fails the way the desktop app's gap makes op fail, and after that it prints
# $OP_STDOUT and $OP_STDERR and exits $OP_EXIT. The sleep stub logs its argument instead of waiting.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/op.exe" <<'STUB'
#!/bin/bash
echo "$*" >>"$OP_LOG"
echo "$WSLENV" >"$OP_WSLENV"
if [[ "$(wc -l <"$OP_LOG")" -le "${OP_TURNED_AWAY:-0}" ]]; then
    echo "[ERROR] 2026/10/29 17:13:53 connecting to desktop app: cannot connect to 1Password app, make sure it is running" >&2
    exit 1
fi
printf '%s' "${OP_STDOUT:-}"
if [[ -n "${OP_STDERR:-}" ]]; then echo "$OP_STDERR" >&2; fi
exit "${OP_EXIT:-0}"
STUB
cat >"$TMP/bin/sleep" <<'STUB'
#!/bin/bash
echo "$1" >>"$SLEEP_LOG"
STUB
chmod +x "$TMP/bin/op.exe" "$TMP/bin/sleep"

# run_wrapper <calls turned away> [NAME=value...]: runs `op account list --format=json` through the
# wrapper with stdout captured, as chezmoi does, and sets OUT, ERR, RC, CALLS and SLEEPS.
run_wrapper() {
    local turned_away="$1"
    shift
    : >"$TMP/op.log"
    : >"$TMP/sleep.log"
    RC=0
    OUT="$(env PATH="$TMP/bin:$PATH" OP_LOG="$TMP/op.log" OP_WSLENV="$TMP/wslenv" SLEEP_LOG="$TMP/sleep.log" \
        OP_TURNED_AWAY="$turned_away" "$@" "$WRAPPER" account list --format=json 2>"$TMP/err")" || RC=$?
    ERR="$(cat "$TMP/err")"
    CALLS="$(wc -l <"$TMP/op.log")"
    SLEEPS="$(tr '\n' ' ' <"$TMP/sleep.log")"
}

# given a call the desktop app turns away once
# when
run_wrapper 1 'OP_STDOUT=[{"url":"my.1password.com"}]'
# then
if [[ "$RC" -eq 0 && "$OUT" == '[{"url":"my.1password.com"}]' && "$CALLS" -eq 2 && "$SLEEPS" == "1 " && -z "$ERR" ]]; then
    pass "a call the app turned away is retried a second later, and only the retry's output reaches the caller"
else
    fail "turned away once: exit $RC, $CALLS calls, sleeps '$SLEEPS', stdout '$OUT', stderr '$ERR'"
fi

# given an app that turns every call away
# when
run_wrapper 99
# then
if [[ "$RC" -eq 1 && "$CALLS" -eq 4 && "$SLEEPS" == "1 1 2 " && "$(grep -c 'cannot connect to 1Password app' <<<"$ERR")" -eq 1 ]]; then
    pass "the wrapper gives up after four attempts and reports the last one's error once"
else
    fail "turned away every time: exit $RC, $CALLS calls, sleeps '$SLEEPS', stderr '$ERR'"
fi

# given another failure, such as an item that does not exist
# when
run_wrapper 0 OP_EXIT=3 "OP_STDERR=[ERROR] \"Device: test\" isn't an item in the \"personal\" vault"
# then
if [[ "$RC" -eq 3 && "$CALLS" -eq 1 && -z "$SLEEPS" && "$ERR" == *"isn't an item"* ]]; then
    pass "any other failure is passed on at once, with its own exit code and message"
else
    fail "another failure: exit $RC, $CALLS calls, sleeps '$SLEEPS', stderr '$ERR'"
fi

# given a call that succeeds at once
# when
run_wrapper 0 OP_STDOUT=done
# then
if [[ "$RC" -eq 0 && "$OUT" == "done" && "$CALLS" -eq 1 && -z "$SLEEPS" ]]; then
    pass "a call that succeeds runs once and waits for nothing"
else
    fail "a successful call: exit $RC, $CALLS calls, sleeps '$SLEEPS', stdout '$OUT'"
fi
if [[ "$(cat "$TMP/wslenv")" == "OP_FORMAT:OP_INTEGRATION_NAME:OP_INTEGRATION_ID:OP_INTEGRATION_BUILDNUMBER" ]]; then
    pass "op.exe still gets the variables WSLENV shares with Windows"
else
    fail "op.exe got WSLENV '$(cat "$TMP/wslenv")'"
fi

# given a person at a terminal: script(1) gives the wrapper one, and SHELL is bash so that no zsh
# startup file can put the real op.exe ahead of the stub
if command -v script >/dev/null 2>&1; then
    : >"$TMP/op.log"
    : >"$TMP/sleep.log"
    rc=0
    # when
    env SHELL=/bin/bash PATH="$TMP/bin:$PATH" OP_LOG="$TMP/op.log" OP_WSLENV="$TMP/wslenv" SLEEP_LOG="$TMP/sleep.log" \
        OP_TURNED_AWAY=1 script -qec "'$WRAPPER' account list" /dev/null >/dev/null 2>&1 || rc=$?
    # then
    if [[ "$rc" -eq 1 && "$(wc -l <"$TMP/op.log")" -eq 1 && ! -s "$TMP/sleep.log" ]]; then
        pass "at a terminal the wrapper runs op.exe once, as typed"
    else
        fail "at a terminal: exit $rc, $(wc -l <"$TMP/op.log") calls, sleeps '$(tr '\n' ' ' <"$TMP/sleep.log")'"
    fi
else
    echo "[test-op-wrapper] SKIP: no script(1) to give the wrapper a terminal" >&2
fi

# The config .chezmoi.yaml.tmpl renders: for each platform, then read back by chezmoi from the
# rendered file, as `command | OP_ACCOUNT | recurseSubmodules`.
if command -v chezmoi >/dev/null 2>&1; then
    : >"$TMP/empty.yaml"
    config_settings() {
        chezmoi --source "$REPO_ROOT" execute-template --config "$TMP/empty.yaml" --override-data "$1" \
            <"$REPO_ROOT/.chezmoi.yaml.tmpl" >"$TMP/rendered.yaml" &&
            chezmoi --source "$REPO_ROOT" execute-template --config "$TMP/rendered.yaml" \
                '{{ .chezmoi.config.onepassword.command }} | {{ with .chezmoi.config.env }}{{ get . "OP_ACCOUNT" }}{{ end }} | {{ .chezmoi.config.update.recurseSubmodules }}' 2>/dev/null
    }

    # given Windows
    # when
    got="$(config_settings '{"chezmoi":{"os":"windows"}}')" || got="(no render)"
    # then
    if [[ "$got" == "op.exe | my | false" ]]; then
        pass "the Windows config runs op.exe itself, with OP_ACCOUNT=my, and recurses into no submodules"
    else
        fail "the Windows config reads back as '$got', not 'op.exe | my | false'"
    fi

    # given Linux
    home="$(chezmoi --source "$REPO_ROOT" execute-template --config "$TMP/empty.yaml" '{{ .chezmoi.homeDir }}')"
    # when
    got="$(config_settings '{"chezmoi":{"os":"linux"}}')" || got="(no render)"
    # then
    if [[ "$got" == "$home/.local/bin/op |  | false" ]]; then
        pass "the Linux config runs op through the wrapper in ~/.local/bin, sets no OP_ACCOUNT, and recurses into no submodules"
    else
        fail "the Linux config reads back as '$got', not '$home/.local/bin/op |  | false'"
    fi

    # The calls the templates deployed on Windows make, logged by the mock op, rendered for Windows
    # and for Linux. The mock serves the device-note fixture, whose entries make each template call
    # 1Password more than once.
    MOCK_OP="$REPO_ROOT/.github/ci/fixtures/mock-op.sh"
    printf 'sourceDir: "%s"\nonePassword:\n  command: "%s"\ndata:\n  deviceName: "testdevice"\n' \
        "$REPO_ROOT" "$MOCK_OP" >"$TMP/mock.yaml"
    op_calls() {
        local template
        : >"$TMP/calls.log"
        for template in dot_gitconfig.tmpl dot_ssh/config.tmpl dot_ssh/allowed_signers.tmpl dot_ssh/authorized_keys.tmpl \
            dot_wakatime.cfg.tmpl .chezmoiscripts/run_after_windows-001-create-ssh-public-keys.ps1.tmpl \
            .chezmoiscripts/run_after_windows-002-create-ssh-pems.ps1.tmpl; do
            chezmoi execute-template --config "$TMP/mock.yaml" --override-data "$1" <"$REPO_ROOT/$template" \
                2>&1 >/dev/null | sed -n 's/^\[mock-op\] called with: //p' >>"$TMP/calls.log" ||
                echo "(template failed: $template)" >>"$TMP/calls.log"
        done
    }

    # given Windows
    # when
    op_calls '{"chezmoi":{"os":"windows"}}'
    # then
    if grep -q 'template failed' "$TMP/calls.log"; then
        fail "a template no longer renders for Windows: $(grep 'template failed' "$TMP/calls.log" | tr '\n' ' ')"
    elif [[ "$(grep -c . "$TMP/calls.log")" -gt 0 ]] && ! grep -q -E '^account list|--account' "$TMP/calls.log"; then
        pass "on Windows the templates name no account, so chezmoi runs no account list ($(grep -c . "$TMP/calls.log") op calls)"
    else
        fail "on Windows the templates still name an account: $(grep -E '^account list|--account' "$TMP/calls.log" | head -3 | tr '\n' ';')"
    fi

    # given Linux
    # when
    op_calls '{"chezmoi":{"os":"linux"}}'
    # then
    if grep -q '^account list' "$TMP/calls.log" && grep -q -- '--account test-account-uuid' "$TMP/calls.log" &&
        ! grep -q 'template failed' "$TMP/calls.log"; then
        pass "on Linux the templates still name the account, which the WSL wrapper's retry carries past the gap"
    else
        fail "on Linux the templates no longer name the account: $(head -3 "$TMP/calls.log" | tr '\n' ';')"
    fi
else
    echo "[test-op-wrapper] SKIP: no chezmoi to render .chezmoi.yaml.tmpl and the templates" >&2
fi

# given every template that calls 1Password: each takes the account from lib-onepassword.tmpl, so
# none may name it itself
# when
named="$(grep -rn -E 'onepassword[A-Za-z]* [^}]*"my"' "$REPO_ROOT" --include='*.tmpl' --include='modify_*' \
    --exclude-dir=.git --exclude-dir=.github 2>/dev/null || true)"
# then
if [[ -z "$named" ]]; then
    pass "no template passes the account to a 1Password function itself"
else
    fail "these templates name the account instead of taking \$op.account from lib-onepassword.tmpl: $named"
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-op-wrapper] all op retry tests passed" >&2
fi
exit $EXIT_CODE
