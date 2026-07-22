# Dependency Lifecycle: Adding *and* Removing

This repository is a **sync**, not a bootstrapper. Removing something from the source
must remove it from every machine, not merely stop new machines from getting it.

This document describes how removal works here, and records why the obvious
off-the-shelf tools (Nix/home-manager, Homebrew Bundle, Ansible) were not selected.

## The Problem

chezmoi's declarative model covers the *contents* of files it manages. It does not
cover the *existence* of things it once created, and it has no concept of packages
at all. Two distinct gaps follow from that.

Deleting `install_cursor_cli()` from the dependency installer in commit `601cbeb`
stopped new machines from getting Cursor. It did nothing to the machines that had
already run it — a month later `cursor-agent` and `gemini` were still installed and
still on `PATH`. The same applies to files: deleting `dot_cursor/` from the source
did not delete `~/.cursor/` from any machine that had already applied it.

chezmoi is explicit that this is by design:

> chezmoi only looks at the current state of the source directory, it doesn't know
> anything about its history, and so can't tell if a file has been removed.
> — [`.chezmoiremove` reference](https://www.chezmoi.io/reference/special-files/chezmoiremove/)

> Uninstalling has to be explicit. chezmoi has no concept of brew or packages.
> chezmoi only knows about scripts.
> — chezmoi maintainer, [discussion #4650](https://github.com/twpayne/chezmoi/discussions/4650)

## The Model

| Half | Mechanism | Where |
|------|-----------|-------|
| **Files** — config left in `$HOME` | [`.chezmoiremove`](https://www.chezmoi.io/reference/special-files/chezmoiremove/) | `.chezmoiremove` at the repository root |
| **Packages** — installed binaries | Tombstone scripts | `.chezmoiscripts/run_onchange_after_<platform>-*-remove-dependencies.*` |

### File removal

`.chezmoiremove` lists target paths that must never exist on a managed machine.
Anything matching is deleted on **every** `chezmoi apply`. Patterns are relative to
the home directory, `#` starts a comment, and the file is always interpreted as a
Go template.

### Package removal

The tombstone scripts hold an explicit list of things this repository used to
install. Each entry pairs a **removal strategy** with a **target**:

```bash
TOMBSTONES=(
    # Gemini CLI and Cursor CLI -- removed in 601cbeb (2026-07-21)
    "npm_global:@google/gemini-cli"
    "path:$HOME/.local/bin/cursor-agent"
    "path:$HOME/.local/share/cursor-agent"
)
```

Strategies are implemented once in `.chezmoitemplates/lib-remove-dependencies.sh`
(shared by Linux and Android) and inline in the Windows script. Every handler is
idempotent, so a clean machine produces no output.

| Strategy | Platforms | Removes |
|----------|-----------|---------|
| `apt` | Linux, Android | A dpkg/apt package |
| `gh_extension` | Linux, Android | A `gh` CLI extension |
| `npm_global` | all | A globally installed npm package |
| `path` | all | A file, symlink, or directory (constrained to `$HOME`) |
| `pipx` | Linux, Android | A pipx-managed application |
| `winget` | Windows | A winget package by exact ID |

The scripts are `run_onchange_`, so chezmoi re-runs them whenever the tombstone
list changes and skips them otherwise.

## Workflow: Removing a Dependency

1. Delete the `install_*()` function (or package-list entry) from the platform's
   `run_once_before_*-install-dependencies.*` script — as before.
2. **Add a tombstone** to the matching `run_onchange_after_*-remove-dependencies.*`
   script for every platform that installed it, with the strategy that undoes how
   it was installed.
3. **Add any leftover config directory** to `.chezmoiremove`.
4. Reference the removing commit in a comment so the entry can be retired later.
5. Update `CHANGELOG.md` under `[Unreleased] > Removed`.

Steps 2 and 3 are the ones that make the repository a sync. Skipping them leaves
the tool installed forever on every existing machine.

## Alternatives Considered

### Nix + home-manager — rejected: cannot cover the platform matrix

[home-manager](https://github.com/nix-community/home-manager) is the genuinely
declarative answer. It builds generations and `home-manager switch` removes
whatever you deleted from the configuration, with no explicit uninstall list. It is
strictly better than tombstones *where it runs*.

It cannot run across this repository's three targets:

| Target | home-manager | Consequence |
|--------|--------------|-------------|
| Kali on WSL | supported | would work |
| Windows 11 native | **not supported** | winget, PowerShell, Oh My Posh, Windows Terminal, and the `AppData/` tree have no Nix story — Nix on Windows exists only inside WSL |
| Termux on Android | only via [nix-on-droid](https://github.com/nix-community/nix-on-droid) | nix-on-droid is a **fork** of the Termux app with its own bootstrap, incompatible with the `termux-etc-seccomp` wrapper architecture (`op`, `gh`, `acli`, `claude`) that this repository depends on |

Adopting Nix would mean either abandoning two of three platforms or maintaining two
parallel dependency systems — strictly more complexity than a tombstone list, for a
benefit that only lands on one platform. The cost is also front-loaded: every
existing `install_*()` function would need a Nix expression before the first
removal could be expressed declaratively.

This is a platform-matrix constraint, not a judgement about Nix. If Windows and
Android were ever dropped, home-manager would be the correct replacement for both
the installer and the tombstone scripts.

### Homebrew Bundle — rejected: only reconciles its own packages

[`brew bundle cleanup --force`](https://docs.brew.sh/Brew-Bundle-and-Brewfile)
uninstalls anything not listed in the `Brewfile`, which is true reconciliation and
works on Linux. It only sees packages Homebrew installed.

The Linux installer alone uses six mechanisms — `apt` (×8), `pip` (×4), upstream
`curl | sh` installers (×4), `npm -g` (×3), `pipx` (×2), and `go install` — plus
GVM, SDKMAN, NVM, Pyenv, krew, and Oh My Zsh, each with a bespoke installer.
Homebrew would reconcile none of them without first migrating every dependency to
Homebrew, which is not possible for the version managers and does not help Windows
or Android at all.

### Ansible — rejected: not actually reconciliation

Ansible's `state: absent` still requires naming every package to remove, so it is
the same explicit list as a tombstone script with a heavier runtime added. It would
replace a shell array with a YAML array and pull in a Python control-node
dependency on Termux and Windows.

## Known Limitations

These are accepted trade-offs, not oversights.

- **The tombstone list is append-only and hand-maintained.** It is a record of
  removals, not a diff against a declared set. Forgetting step 2 silently leaves
  the dependency installed. This is the cost of not adopting Nix.
- **`.chezmoiremove` entries are permanent while listed.** If Cursor were ever
  reinstalled manually, `~/.cursor` would be deleted on the next apply until the
  entry is removed from `.chezmoiremove`.
- **`apt` removals need passwordless sudo on Linux/WSL.** chezmoi runs unattended,
  so the handler warns and skips rather than blocking on a password prompt.
  Termux needs no privilege escalation and is unaffected.
- **Entries can be retired, but only deliberately.** Once every machine has
  converged, a tombstone can be deleted. There is no signal for when that is true,
  so the commit reference in each comment is the only dating mechanism.

True reconciliation — recording what the repository installed and diffing it
against a declared manifest — would remove the first limitation at the cost of
building a small package manager. Revisit if the tombstone list becomes unwieldy.

## References

- [chezmoi: install packages declaratively](https://www.chezmoi.io/user-guide/advanced/install-packages-declaratively/)
- [chezmoi: `.chezmoiremove`](https://www.chezmoi.io/reference/special-files/chezmoiremove/)
- [chezmoi discussion #4650 — managing brew installations/uninstallations](https://github.com/twpayne/chezmoi/discussions/4650)
- [home-manager](https://github.com/nix-community/home-manager) / [nix-on-droid](https://github.com/nix-community/nix-on-droid)
- [Homebrew Bundle and Brewfile](https://docs.brew.sh/Brew-Bundle-and-Brewfile)
