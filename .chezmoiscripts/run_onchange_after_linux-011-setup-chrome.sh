#!/bin/bash

# Installs Google Chrome from Google's apt repository, for the Chrome DevTools MCP server that
# Claude Code gets on Linux (see "MCP Servers" in CLAUDE.md).
#
# The server is pointed at /opt/google/chrome/chrome, where this package puts it, rather than left
# to Puppeteer's search: on WSL that search goes on to Windows' Chrome through cmd.exe when the
# Linux one is missing, and the server then fails to drive it (ChromeDevTools/chrome-devtools-mcp
# #690). A WSL machine cannot borrow the Windows browser at all: its debugging port listens on the
# Windows loopback, which WSL's NAT keeps out of reach.
#
# Kali's `chromium` is not an alternative. It trails Google's stable channel by releases, not days
# (150 against 155 when this was written), and this is the browser Claude points at pages nobody
# has vetted; Google's package moves with every `apt upgrade`.
#
# `run_onchange_` rather than `run_once_`, so that it reaches machines that predate it.

set -euo pipefail

prefix="chrome"

# Google's repository and signing key: one primary key, whose signing subkeys Google rotates. apt
# trusts it for this repository only (Signed-By), and only after the primary proves to be Google's.
# The key and source paths, and the source's content, are the ones the package's own postinst
# writes, so the install takes them over instead of adding a second source for the same repository.
repo="https://dl.google.com/linux/chrome-stable/deb/"
key_url="https://dl.google.com/linux/linux_signing_key.pub"
signer_fingerprint="EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796"
keyring="/usr/share/keyrings/google-chrome.gpg"
sources="/etc/apt/sources.list.d/google-chrome.sources"

if command -v google-chrome-stable >/dev/null 2>&1; then
    exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "[$prefix] WARN: no apt-get here; install Google Chrome by hand (https://www.google.com/chrome/), or the Chrome DevTools MCP server finds no browser" >&2
    exit 0
fi

arch="$(dpkg --print-architecture)"
if [[ "$arch" != "amd64" && "$arch" != "arm64" ]]; then
    echo "[$prefix] WARN: Google publishes no Chrome for $arch, so the Chrome DevTools MCP server finds no browser here" >&2
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "$key_url" -o "$tmp/key.asc"
# One key, and Google's: a keyring that carried a second key would have apt trust it too.
keys="$(gpg --show-keys --with-colons "$tmp/key.asc" 2>/dev/null | grep -c '^pub:' || true)"
primary="$(gpg --show-keys --with-colons "$tmp/key.asc" 2>/dev/null |
    awk -F: '$1 == "pub" { seen = 1; next } seen && $1 == "fpr" { print $10; exit }')"
if [[ "$keys" != "1" || "$primary" != "$signer_fingerprint" ]]; then
    echo "[$prefix] ERROR: the repository key is not Google's ($signer_fingerprint); refusing to trust it" >&2
    exit 1
fi
gpg --dearmor < "$tmp/key.asc" > "$tmp/keyring.gpg"

cat > "$tmp/google-chrome.sources" <<EOF
### THIS FILE IS AUTOMATICALLY CONFIGURED ###
# Changes to this file will not be preserved.
# This file will not be recreated if removed.
X-Repolib-Name: Google Chrome
Types: deb
URIs: $repo
Suites: stable
Components: main
Architectures: $arch
Signed-By: $keyring
EOF

echo "[$prefix] installing Google Chrome from $repo" >&2
sudo install -D -m 0644 "$tmp/keyring.gpg" "$keyring"
sudo install -D -m 0644 "$tmp/google-chrome.sources" "$sources"
# Only Google's source is refreshed: the rest of the system is the dependency installer's.
sudo apt-get update -o Dir::Etc::sourcelist="$sources" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
sudo apt-get install --yes --no-install-recommends google-chrome-stable

echo "[$prefix] $(google-chrome-stable --version)" >&2
