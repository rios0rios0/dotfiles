#!/bin/bash

# Installs the relay behind the SSH agent bridge and activates its socket unit.
#
# On WSL every SSH key lives in 1Password on the Windows side, reachable only through the
# named pipe \\.\pipe\openssh-ssh-agent. Two mechanisms carry that across the boundary today
# and both work by running a Windows binary: the `ssh` -> `ssh.exe` wrapper in ~/.local/bin,
# and `gpg.ssh.program = op-ssh-sign-wsl` in ~/.gitconfig, which is what signs every commit.
#
# Neither reaches a program that does SSH *itself* instead of shelling out to `ssh`. go-git
# (AutoBump), Go's x/crypto/ssh, and libgit2 all authenticate by dialing an AF_UNIX socket
# and speaking the agent protocol; `core.sshCommand` is never consulted, because no binary
# is ever executed. Go cannot dial a Windows named pipe, so for those tools the keys simply
# do not exist -- which is why signing succeeds and `git push` succeeds while AutoBump alone
# reports no usable SSH credential.
#
# npiperelay copies bytes between stdio and the pipe; ssh-agent-bridge.socket supplies the
# AF_UNIX listener and hands each accepted connection over on stdio. That is the job socat
# normally does in this recipe, and dropping it removes both a package and a shell-spawned
# background daemon. The keys stay in 1Password with its approval prompt intact.
#
# `run_onchange_` rather than `run_once_`: existing machines already ran every `run_once_`
# script, so a new installer there would never reach them. This runs when its own content
# changes, which covers the machines that predate the bridge and the ones built after it.

set -euo pipefail

prefix="ssh-agent-bridge"

# Pinned with the checksum upstream publishes; npiperelay ships no arm64 build, and a wrong
# binary here would fail per connection rather than at install time.
version="0.1.0"
archive="npiperelay_windows_amd64.zip"
checksum="6b9ef61ffd17c03507a9a3d54d815dceb3dae669ac67fc3bf4225d1e764ce5f6"
url="https://github.com/jstarks/npiperelay/releases/download/v${version}/${archive}"

relay="$HOME/.local/bin/npiperelay.exe"
socket_unit="ssh-agent-bridge.socket"

# The bridge only means anything on WSL: elsewhere there is no Windows agent to reach, and
# the unit files are not deployed at all (see .chezmoiignore).
if ! grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
    exit 0
fi

if ! command -v systemctl >/dev/null 2>&1 || ! systemctl --user show-environment >/dev/null 2>&1; then
    echo "[$prefix] WARN: no systemd user session; enable systemd in /etc/wsl.conf to use the bridge" >&2
    exit 0
fi

install_relay() {
    local workdir status

    if [[ -x "$relay" ]]; then
        echo "[$prefix] npiperelay is already installed, skipping download" >&2
        return 0
    fi

    if [[ "$(uname -m)" != "x86_64" ]]; then
        echo "[$prefix] WARN: npiperelay publishes no $(uname -m) build; bridge not installed" >&2
        return 1
    fi

    workdir="$(mktemp -d)"
    status=0

    # Downloaded to a file and verified before use: piping the archive straight into unzip
    # would extract an HTTP error page as happily as a release.
    if ! curl --proto '=https' -fsSL "$url" -o "$workdir/$archive"; then
        echo "[$prefix] ERROR: failed to download npiperelay from $url" >&2
        rm -rf "$workdir"
        return 1
    fi

    if ! echo "$checksum  $workdir/$archive" | sha256sum --check --status; then
        echo "[$prefix] ERROR: checksum mismatch for $archive; refusing to install" >&2
        rm -rf "$workdir"
        return 1
    fi

    if ! unzip -q -o "$workdir/$archive" npiperelay.exe -d "$workdir"; then
        echo "[$prefix] ERROR: failed to extract npiperelay.exe" >&2
        rm -rf "$workdir"
        return 1
    fi

    mkdir -p "$(dirname "$relay")"
    install -m 0755 "$workdir/npiperelay.exe" "$relay" || status=1
    rm -rf "$workdir"

    if [[ "$status" -ne 0 ]]; then
        echo "[$prefix] ERROR: failed to install npiperelay to $relay" >&2
        return 1
    fi

    echo "[$prefix] installed npiperelay $version to $relay" >&2
    return 0
}

if ! install_relay; then
    echo "[$prefix] WARN: bridge not activated; SSH_AUTH_SOCK will have nothing listening" >&2
    exit 0
fi

systemctl --user daemon-reload

# `enable --now` both wires the socket into sockets.target for later logins and binds it for
# this one. Restart rather than start, so a unit already bound to an older ExecStart picks up
# the new one instead of reporting success and continuing to run the previous relay.
if ! systemctl --user enable "$socket_unit" >/dev/null 2>&1; then
    echo "[$prefix] WARN: could not enable $socket_unit" >&2
    exit 0
fi

if ! systemctl --user restart "$socket_unit"; then
    echo "[$prefix] WARN: could not start $socket_unit; check 'systemctl --user status $socket_unit'" >&2
    exit 0
fi

echo "[$prefix] bridge listening at \$HOME/.ssh/agent.sock" >&2
