# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

When a new release is proposed:

1. Create a new branch `bump/x.x.x` (this isn't a long-lived branch!!!);
2. The Unreleased section on `CHANGELOG.md` gets a version number and date;
3. Open a Pull Request with the bump version changes targeting the `main` branch;
4. When the Pull Request is merged a new Git tag must be created using [GitHub environment](https://github.com/rios0rios0/dotfiles/tags).

Releases to productive environments should run from a tagged version.
Exceptions are acceptable depending on the circumstances (critical bug fixes that can be cherry-picked, etc.).

## [Unreleased]

## [0.2.0] - 2026-03-15

### Added

- added GitHub Copilot CLI extension (`gh copilot`) installation to Android dependencies with best-effort authentication check
- added `.local/share` proot bind for persistent gh extensions, fonts, and zinit plugin data

### Changed

- extracted `gh` CLI proot wrapper from install-dependencies script into its own `run_once_before` script
- split Android wrapper bootstrap into three single-responsibility scripts: generic proot wrapper (`001`), op wrapper (`001a`), and gh wrapper (`001b`)

## [0.1.0] - 2026-03-12

### Added

- added `gh` CLI proot wrapper for Termux that forwards GitHub tokens (`GH_TOKEN`, `GITHUB_PERSONAL_ACCESS_TOKEN`, `GITHUB_TOKEN`) through proot-distro Alpine
- added 1Password integration for MCP server credentials and API keys
- added Android-compatible MCP configuration with npx alternatives to Docker-based servers
- added Linux WSL features to handle Git and SSH configuration with 1Password 
- added Shell Script features to handle watching multiple files (and compressing them) for Kubernetes secrets
- added Windows feature to copy configuration inside `AppData` folder
- added a new feature to compress and watch many folders instead of just one folder
- added feature to handle SSH, PEM and GPG keys seamlessly with 1Password
- added feature to use 1Password and SSH keys to encrypt and decrypt files

### Changed

- refactored shared proot `wrapper` to accept `--env` flags from tool wrappers instead of hardcoding tool-specific env var forwarding
- moved `OP_SESSION_*` env var forwarding from shared `wrapper` into the `op` wrapper script
- converted MCP configuration from static JSON to Chezmoi template for cross-platform compatibility and secure credential management
- deduplicated MCP server merge scripts into a shared `lib-modify-mcp-servers.sh` chezmoi template
- deduplicated shell credentials and workspace aliases into a shared `linux-engineering-op-loader.sh` loader with structured logging
- enhanced Android SSH script to export both private and public keys from 1Password, renamed from `run_after_android-001-create-ssh-private-keys.sh.tmpl` to `run_after_android-001-create-ssh-keys.sh.tmpl`
- improved logging across modify scripts with `[prefix]` tags for `mcp-servers`, `claude-trust`, `claude-settings`, `credentials`, `workspaces`, and `git-sync`
- segregated MCP configurations into platform-specific files: `.cursor/mcp.json` for Linux (Docker-based) and `.config/mcphub/servers.json` for Android (npx-based), eliminating cross-platform conditional logic
- simplified 1Password calls by replacing list/join patterns with printf format for improved readability and consistency
- suppressed proot warnings on Android using `PROOT_VERBOSE=-1` and `--no-arch-warning` flags
- unified `deviceName` computation into `.chezmoi.yaml.tmpl` data section, removing duplication across 7 template files
- replaced `onepasswordRead` + `onepasswordItemFields` with single `onepassword` call per item across all templates, using `dict`/`set` to build local field maps — halves API calls per referenced item and fixes missing built-in fields (`public key`, `private key`)
- switched all "Active *" item lookups from REFERENCE field iteration to notes-based (`notesPlain`) filtering — reads item titles from notes, filters by device locally, and only fetches matching items by title (reduces API calls from N+1 to 2 per device-filtered loop)
- updated `linux-engineering-op-loader.sh` to use notes-based filtering with `--vault private` for title-based lookups
- standardized logging convention across 20 files with `[prefix]` format to stderr using `warnf` (templates), `echo >&2` (shell), and `Write-Host` (PowerShell)
- added `warnf` progress logging to all 1Password template operations (`gitconfig`, `ssh-config`, `allowed-signers`, `authorized-keys`, `docker-config`, `wakatime`, `age-recipients`) showing item fetch, device match, and per-item progress
- added `[prefix]` logging to previously silent scripts: `clone-tools`, `ssh-known-hosts`, `configure-deps`, `kube-config`, `termux-config`, `fonts`
- moved script echo output from stdout to stderr in `android-ssh-keys`, `linux-gpg-keys`, `copy-appdata` to avoid mixing logs with generated content
- standardized bare `echo` messages with `[prefix]` format in `op-wrapper`, `extract-folders`, `export-key`
- added `set -euo pipefail` error handling to 5 scripts missing it: `linux-gpg-keys`, `extract-folders`, `clone-tools`, `configure-deps`, `export-key`
- documented 1Password template pattern (`onepassword` + `dict`/`set`) and logging convention in CLAUDE.md

### Fixed

- fixed `gh` CLI failing DNS lookups in Termux by routing it through proot-distro Alpine (Go reads `/etc/resolv.conf` which doesn't exist in Termux)
- fixed `onepasswordItemFields` not returning built-in SSH Key fields (`public key`, `private key`) — these are top-level detail fields not accessible via `onepasswordItemFields` which only reads section-level fields
- fixed `warnf` double newlines by removing explicit `\n` from format strings (chezmoi appends its own newline)
- fixed `map has no entry for key "value"` crash in `dict`/`set` field loops by adding `hasKey` guard for 1Password fields without a value property
- fixed Unicode curly quotes (U+201C/U+201D) inadvertently introduced in 3 template files

