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

### Added

- added 1Password integration for MCP server credentials and API keys
- added Android-compatible MCP configuration with npx alternatives to Docker-based servers
- added Linux WSL features to handle Git and SSH configuration with 1Password 
- added Shell Script features to handle watching multiple files (and compressing them) for Kubernetes secrets
- added Windows feature to copy configuration inside `AppData` folder
- added a new feature to compress and watch many folders instead of just one folder
- added feature to handle SSH, PEM and GPG keys seamlessly with 1Password
- added feature to use 1Password and SSH keys to encrypt and decrypt files

### Changed

- converted MCP configuration from static JSON to Chezmoi template for cross-platform compatibility and secure credential management
- deduplicated MCP server merge scripts into a shared `lib-modify-mcp-servers.sh` chezmoi template
- deduplicated shell credentials and workspace aliases into a shared `linux-engineering-op-loader.sh` loader with structured logging
- enhanced Android SSH script to export both private and public keys from 1Password, renamed from `run_after_android-001-create-ssh-private-keys.sh.tmpl` to `run_after_android-001-create-ssh-keys.sh.tmpl`
- improved logging across modify scripts with `[prefix]` tags for `mcp-servers`, `claude-trust`, `claude-settings`, `credentials`, `workspaces`, and `git-sync`
- reduced 1Password API calls by replacing per-field `onepasswordRead` with `onepasswordItemFields` across 9 template files (~18 fewer `op` CLI invocations per apply)
- segregated MCP configurations into platform-specific files: `.cursor/mcp.json` for Linux (Docker-based) and `.config/mcphub/servers.json` for Android (npx-based), eliminating cross-platform conditional logic
- simplified 1Password calls by replacing list/join patterns with printf format for improved readability and consistency
- suppressed proot warnings on Android using `PROOT_VERBOSE=-1` and `--no-arch-warning` flags
- unified `deviceName` computation into `.chezmoi.yaml.tmpl` data section, removing duplication across 7 template files
