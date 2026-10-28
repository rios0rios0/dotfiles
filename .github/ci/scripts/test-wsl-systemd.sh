#!/bin/bash
set -euo pipefail

# Tests turning systemd on in WSL: the render gate of the script that writes /etc/wsl.conf, its
# merge into a file that already carries settings, the no-op when systemd is already on, both
# restart messages, and the systemd line that makes every installer calling systemctl run again
# once systemd starts.

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CI_DIR="$REPO_ROOT/.github/ci"
EXIT_CODE=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[test-wsl-systemd] testing systemd on WSL..." >&2

pass() { echo "[test-wsl-systemd] PASS: $1" >&2; }
fail() { echo "[test-wsl-systemd] FAIL: $1" >&2; EXIT_CODE=1; }

chmod +x "$CI_DIR/fixtures/mock-op.sh"
cat > "$TMP/chezmoi.yaml" <<EOF
sourceDir: "$REPO_ROOT"
onePassword:
  command: "$CI_DIR/fixtures/mock-op.sh"
data:
  deviceName: "testdevice"
EOF

# The Ollama installer renders only with an NVIDIA driver on PATH, so every render runs with a PATH
# holding chezmoi and a fake driver.
CHEZMOI="$(command -v chezmoi)"
mkdir -p "$TMP/bin"
ln -s "$CHEZMOI" "$TMP/bin/chezmoi"
printf '#!/bin/sh\necho "NVIDIA Test GPU, 24576 MiB"\n' > "$TMP/bin/nvidia-smi"
chmod +x "$TMP/bin/nvidia-smi"

# Whether systemd runs is read from /run/systemd/system, and whether this is WSL from the kernel,
# so the host running this suite would decide both: each render points the first at a directory
# that exists or not, and overrides the second.
mkdir -p "$TMP/systemd-on"
WSL='{"chezmoi":{"os":"linux","kernel":{"osrelease":"5.15.167.4-microsoft-standard-WSL2","version":"#1 SMP"}}}'
BARE_METAL='{"chezmoi":{"os":"linux","kernel":{"osrelease":"6.8.0-45-generic","version":"#45-Ubuntu SMP"}}}'

# render <on|off> <source file> [override JSON]
render() {
    local state="$1" template="$2" override="${3:-}"
    sed "s|stat \"/run/systemd/system\"|stat \"$TMP/systemd-$state\"|g" "$template" |
        PATH="$TMP/bin" chezmoi execute-template --config "$TMP/chezmoi.yaml" \
            ${override:+--override-data "$override"}
}

SCRIPT="$REPO_ROOT/.chezmoiscripts/run_before_linux-000-enable-wsl-systemd.sh.tmpl"

# --- render gate ---------------------------------------------------------------------------------

# given WSL without systemd
# when
script="$(render off "$SCRIPT" "$WSL")"
# then
if [[ "$(head -1 <<<"$script")" == "#!/bin/bash" ]] && bash -n <<<"$script"; then
    pass "WSL without systemd gets a script that turns it on"
else
    fail "WSL without systemd: the script did not render to valid bash"
fi

# given WSL already running systemd
# when
script="$(render on "$SCRIPT" "$WSL")"
# then: chezmoi never runs a script that renders to whitespace
[[ -z "${script//[[:space:]]/}" ]] && pass "WSL running systemd renders to nothing" ||
    fail "WSL running systemd rendered a script"

# given bare-metal Linux without systemd, which has no /etc/wsl.conf to read
# when
script="$(render off "$SCRIPT" "$BARE_METAL")"
# then
[[ -z "${script//[[:space:]]/}" ]] && pass "bare-metal Linux renders to nothing" ||
    fail "bare-metal Linux rendered a script"

# --- writing /etc/wsl.conf -------------------------------------------------------------------------

# The script under test, pointed at a scratch wsl.conf and a stand-in systemd binary. Both
# substitutions are checked, so that a renamed variable fails here rather than letting a test
# reach the real /etc/wsl.conf.
render off "$SCRIPT" "$WSL" |
    sed -e "s|^conf=\"/etc/wsl.conf\"$|conf=\"$TMP/wsl.conf\"|" \
        -e "s|^systemd_bin=\"/usr/lib/systemd/systemd\"$|systemd_bin=\"$TMP/systemd\"|" > "$TMP/enable.sh"
if ! grep -qx "conf=\"$TMP/wsl.conf\"" "$TMP/enable.sh" || ! grep -qx "systemd_bin=\"$TMP/systemd\"" "$TMP/enable.sh"; then
    fail "the script no longer sets conf= and systemd_bin= on lines of their own; refusing to run it"
    exit 1
fi

# Stubs: sudo records itself and runs the command as this user, unless told to refuse; ps reports
# how long ago PID 1 started.
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >> "$TMP/sudo.calls"
[[ -e "$TMP/sudo-refuses" ]] && exit 1
exec "\$@"
EOF
cat > "$STUBS/ps" <<EOF
#!/bin/bash
cat "$TMP/pid1-age"
EOF
chmod +x "$STUBS"/*

# reset [wsl.conf content]: no wsl.conf without an argument, systemd installed, no sudo calls, and
# a WSL that started a minute ago
reset() {
    rm -f "$TMP/wsl.conf" "$TMP/sudo.calls" "$TMP/sudo-refuses"
    [[ $# -gt 0 ]] && printf '%b' "$1" > "$TMP/wsl.conf"
    printf '#!/bin/sh\n' > "$TMP/systemd"
    chmod +x "$TMP/systemd"
    echo 60 > "$TMP/pid1-age"
}

# run_script: stderr and stdout together
run_script() {
    PATH="$STUBS:/usr/bin:/bin" bash "$TMP/enable.sh" 2>&1
}

# conf_is <expected content, printf %b>
conf_is() {
    local expected="$1"
    printf '%b' "$expected" | cmp -s - "$TMP/wsl.conf"
}

# given a distribution with no /etc/wsl.conf, as Kali's WSL image ships
reset
# when
output="$(run_script)" && status=0 || status=$?
# then: a [boot] section that turns systemd on, written through sudo, and the restart to do next
if [[ "$status" -eq 0 && "$output" == *"enabled systemd in"* && "$output" == *"wsl.exe --shutdown"* ]] &&
    conf_is '[boot]\nsystemd=true\n' && [[ "$(stat -c %a "$TMP/wsl.conf")" == "644" ]] && [[ -s "$TMP/sudo.calls" ]]; then
    pass "a missing wsl.conf is created with systemd on, and the restart is spelled out"
else
    fail "no wsl.conf: status=$status output=$output content=$(cat "$TMP/wsl.conf" 2>/dev/null | tr '\n' '|')"
fi

# given a wsl.conf with other settings and no final newline
reset '[interop]\nappendWindowsPath=false\n\n[user]\ndefault=kali'
# when
output="$(run_script)" && status=0 || status=$?
# then: every line kept, and a [boot] section appended after a blank line
if [[ "$status" -eq 0 ]] && conf_is '[interop]\nappendWindowsPath=false\n\n[user]\ndefault=kali\n\n[boot]\nsystemd=true\n'; then
    pass "a wsl.conf without [boot] keeps its settings and gains the section"
else
    fail "wsl.conf without [boot]: status=$status content=$(tr '\n' '|' < "$TMP/wsl.conf")"
fi

# given a [boot] section with systemd off and a command of its own
reset '[boot]\ncommand=service docker start\nsystemd=false\n\n[network]\nhostname=kali\n'
# when
output="$(run_script)" && status=0 || status=$?
# then: the old value replaced right under the header, everything else where it was
if [[ "$status" -eq 0 ]] && conf_is '[boot]\nsystemd=true\ncommand=service docker start\n\n[network]\nhostname=kali\n'; then
    pass "systemd=false under [boot] becomes systemd=true, and the rest of the file stays"
else
    fail "systemd=false: status=$status content=$(tr '\n' '|' < "$TMP/wsl.conf")"
fi

# given systemd=true in a section that is not [boot], which WSL does not read
reset '[user]\nsystemd=true\n'
# when
output="$(run_script)" && status=0 || status=$?
# then
if [[ "$status" -eq 0 ]] && conf_is '[user]\nsystemd=true\n\n[boot]\nsystemd=true\n'; then
    pass "only the systemd key under [boot] counts"
else
    fail "systemd outside [boot]: status=$status content=$(tr '\n' '|' < "$TMP/wsl.conf")"
fi

# given systemd already on, written after this WSL started
reset '[boot]\nsystemd = True\n'
# when
output="$(run_script)" && status=0 || status=$?
# then: nothing written, no sudo, and the restart still due
if [[ "$status" -eq 0 && "$output" == *"wsl.exe --shutdown"* && "$output" != *"enabled systemd"* ]] &&
    conf_is '[boot]\nsystemd = True\n' && [[ ! -e "$TMP/sudo.calls" ]]; then
    pass "a wsl.conf that already turns systemd on is left alone, and the restart is still asked for"
else
    fail "systemd already on: status=$status output=$output sudo=$(cat "$TMP/sudo.calls" 2>/dev/null)"
fi

# given systemd already on since before this WSL started
reset '[boot]\nsystemd=true\n'
touch -d '2 hours ago' "$TMP/wsl.conf"
# when
output="$(run_script)" && status=0 || status=$?
# then: a restart would not help, so it says what would
if [[ "$status" -eq 0 && "$output" == *"0.67.6"* && "$output" == *"wsl.exe --update"* && "$output" != *"wsl.exe --shutdown"* ]] &&
    [[ ! -e "$TMP/sudo.calls" ]]; then
    pass "a setting that did not take at the last boot points at updating WSL"
else
    fail "a setting older than the boot: status=$status output=$output"
fi

# given sudo refused
reset '[interop]\nenabled=true\n'
touch "$TMP/sudo-refuses"
# when
output="$(run_script)" && status=0 || status=$?
# then: the file untouched, and the apply goes on
if [[ "$status" -eq 0 && "$output" == *"could not write"* ]] && conf_is '[interop]\nenabled=true\n'; then
    pass "a refused sudo leaves wsl.conf alone and does not fail the apply"
else
    fail "a refused sudo: status=$status output=$output"
fi

# given a distribution without systemd installed
reset
rm -f "$TMP/systemd"
# when
output="$(run_script)" && status=0 || status=$?
# then: nothing asks WSL to boot a systemd that is not there
if [[ "$status" -eq 0 && "$output" == *"not installed"* && ! -e "$TMP/wsl.conf" && ! -e "$TMP/sudo.calls" ]]; then
    pass "without systemd installed, wsl.conf is not touched"
else
    fail "systemd not installed: status=$status output=$output"
fi

# --- the installers that need systemd --------------------------------------------------------------

# Each script chezmoi records as done -- run_once_ by its content, run_onchange_ by its content
# under its name -- and that calls systemctl must say whether systemd was running, or one that
# skipped its setup without systemd never runs again once it starts.
checked=0
while IFS= read -r installer; do
    name="$(basename "$installer")"
    checked=$((checked + 1))
    # given an installer that calls systemctl
    # then: it carries the systemd line, rendered from the check it makes at run time
    if ! grep -q 'stat "/run/systemd/system"' "$installer"; then
        fail "$name calls systemctl but has no systemd line, so it never runs again once systemd starts"
        continue
    fi
    # when
    on="$(render on "$installer" | grep -x '#   systemd .*' || true)"
    off="$(render off "$installer" | grep -x '#   systemd .*' || true)"
    # then
    if [[ "$on" == "#   systemd running" && "$off" == "#   systemd not running" ]]; then
        pass "$name changes when systemd starts, so it runs again"
    else
        fail "$name: systemd line '$on' with systemd and '$off' without"
    fi
done < <(grep -l 'systemctl' "$REPO_ROOT"/.chezmoiscripts/run_once_* "$REPO_ROOT"/.chezmoiscripts/run_onchange_* | LC_ALL=C sort)

[[ "$checked" -ge 3 ]] || fail "expected the bridge, Ollama and Tailscale installers among the scripts calling systemctl, found $checked"

if [[ "$EXIT_CODE" -eq 0 ]]; then
    echo "[test-wsl-systemd] all systemd-on-WSL tests passed" >&2
fi

exit $EXIT_CODE
