#!/bin/bash
set -euo pipefail

# Tests the retry in front of op.exe. 1Password for Windows removes the pipe op connects to for
# about 0.9 s after every CLI call, and an op started in that gap exits at once with "cannot connect
# to 1Password app, make sure it is running"; chezmoi runs `op account list` and `op signin` back to
# back, so every apply failed at its first 1Password template. Covers the WSL wrapper that
# run_once_before_linux-001-create-op-wrapper.sh writes -- a turned-away call retried with only the
# retry's output passed on, giving up after four attempts with the last error, any other failure
# passed on at once with its own exit code, a terminal's op left alone, WSLENV still exported -- and
# the command .chezmoi.yaml.tmpl gives chezmoi on each platform, read back the way chezmoi loads it.
# op.exe and sleep are stubs, so nothing reaches 1Password and no case waits.

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

# The command .chezmoi.yaml.tmpl gives chezmoi: rendered for a platform, then read back by chezmoi
# from the rendered file, so the YAML quoting is checked along with the path.
if command -v chezmoi >/dev/null 2>&1; then
    : >"$TMP/empty.yaml"
    config_command() {
        chezmoi --source "$REPO_ROOT" execute-template --config "$TMP/empty.yaml" --override-data "$1" \
            <"$REPO_ROOT/.chezmoi.yaml.tmpl" >"$TMP/rendered.yaml" &&
            chezmoi --source "$REPO_ROOT" execute-template --config "$TMP/rendered.yaml" \
                '{{ .chezmoi.config.onepassword.command }}' 2>/dev/null
    }

    # given a Windows home whose name holds a space and an apostrophe
    # when
    got="$(config_command '{"chezmoi":{"os":"windows","homeDir":"C:/Users/O'"'"'Brien Test"}}')" || got="(no render)"
    # then
    want='C:\Users\O'"'"'Brien Test\.local\bin\op-retry.cmd'
    if [[ "$got" == "$want" ]]; then
        pass "the Windows config runs op through $want"
    else
        fail "the Windows config runs op as '$got', not '$want'"
    fi

    # given Linux
    home="$(chezmoi --source "$REPO_ROOT" execute-template --config "$TMP/empty.yaml" '{{ .chezmoi.homeDir }}')"
    # when
    got="$(config_command '{"chezmoi":{"os":"linux"}}')" || got="(no render)"
    # then
    if [[ "$got" == "$home/.local/bin/op" ]]; then
        pass "the Linux config runs op through the wrapper in ~/.local/bin"
    else
        fail "the Linux config runs op as '$got', not '$home/.local/bin/op'"
    fi
else
    echo "[test-op-wrapper] SKIP: no chezmoi to render .chezmoi.yaml.tmpl" >&2
fi

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-op-wrapper] all op retry tests passed" >&2
fi
exit $EXIT_CODE
