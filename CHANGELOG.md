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

- added `dot_gitmessage` (conventional-commits scaffold migrated from the legacy `WKSetup` repo) and wired `commit.template = ~/.gitmessage` in `dot_gitconfig.tmpl`
- added staged JetBrains theme assets under `dot_local/share/jetbrains-themes/` (`Darcula Coder.icls`, `Dark Coder.icls`, `Coder.xml` code style, `Dark Coder.xml` Material Theme UI variant) migrated from the legacy `WKSetup` repo
- added `run_after_linux-005-install-jetbrains-themes.sh` and `run_after_windows-004-install-jetbrains-themes.ps1` to fan the staged themes out into every detected JetBrains IDE config directory (`~/.config/JetBrains/*/` on Linux, `%APPDATA%\JetBrains\*\` on Windows) into `colors/`, `codestyles/`, and `materialCustomThemes/`
- added `rec` alias for `asciinema rec` in `dot_zshrc.tmpl` (matches the shorthand from the legacy `WKSetup` repo)
- added `send` zsh function in `dot_zshrc.tmpl` (Android/Termux-only) that uploads files and directories to the OneDrive `Downloads/` folder via rclone; directories preserve their basename in the destination, and the function guards against missing rclone or an unconfigured `onedrive:` remote
- set `AWS_CRT_BUILD_USE_SYSTEM_LIBCRYPTO=1 PIP_NO_BINARY=awscrt` on the Android/Termux AWS CLI v2 build so `awscrt` links against Termux's OpenSSL 3.x instead of its bundled libcrypto that still references the removed `FIPS_mode` symbol (fixes `ImportError: cannot locate symbol "FIPS_mode"` when loading `_awscrt.abi3.so`)

### Changed

- replaced the stale `PYTHONPATH=$TOOLS_DIR/asciinema python -m asciinema …` `record`/`play` aliases in `dot_zshrc.tmpl` with direct `asciinema rec` / `asciinema play` invocations (asciinema is now installed as a first-class dependency via `apt`/`pipx`)

### Fixed

- fixed `install_azure_cli` on Android/Termux failing with `platform android is not supported` when building `psutil`; the function now pre-installs a patched `psutil 7.2.2` (same `_common.py` one-liner used by `termux-packages` PR #28780 for the upcoming `python-psutil` port) so pip sees the constraint already satisfied when resolving the `azure-cli` dependency tree
- fixed `install_azure_cli` on Android/Termux failing to build `PyNaCl` (bundled libsodium `make` errors on Android); the `pip install azure-cli` call now runs with `SODIUM_INSTALL=system` so `PyNaCl` links against Termux's `libsodium` apt package instead of its bundled copy

## [0.8.0] - 2026-04-17

### Added

- added `dot_config/ggshield/auth_config.yaml.tmpl` rendering the ggshield auth config from 1Password item `Token: ggshield` (fields: `token`, `token name`, `workspace id`)
- added `ggshield` (GitGuardian CLI) installation to Linux dependencies via pipx
- added `kubectl krew upgrade` step to `install_krew` in `run_once_before_linux-002-install-dependencies.sh` so krew and its plugins auto-upgrade on every install run
- added `run_after_linux-004-install-ggshield-hook.sh` to (re)generate the shared ggshield hook script on every apply
- added `shellcheck` to Linux (`apt`), Android/Termux (`apt`) and Windows (`winget koalaman.shellcheck`) dependency installers so `make lint` works out of the box
- added AWS CLI v2 installation to Linux (official `awscli-exe-linux-${arch}.zip` bundle, idempotent via `--update` when `/usr/local/aws-cli` exists) and Android/Termux (source build from the `v2` branch of `aws/aws-cli`, since Termux's bionic libc can't run the glibc-linked official bundle); added `cmake` to Android/Termux deps for `awscrt` C-extension compilation; temporary source/build directories are cleaned up after install
- added global ggshield pre-commit hook on Linux via `core.hooksPath` in `dot_gitconfig.tmpl`, covering all existing and future repositories without per-repo setup
- added PostgreSQL client (`psql`) to Linux (`postgresql-client`) and Android/Termux (`postgresql`, which bundles server + client since Termux doesn't split them) dependency installers

### Changed

- changed 1Password organization from type-centric "Active *" notes to device-centric "Device: \<name\>" notes
- moved Docker registries from standalone "Active Docker Registries" note to per-device `docker:` entries in device notes
- refactored `linux-engineering-op-loader.sh` to read credentials and workspaces from device note fields instead of separate items in the Private vault
- refreshed encrypted `encrypted_dot_npmrc.age` with current home `~/.npmrc`
- updated CI test fixtures to match new device-centric 1Password structure

### Fixed

- fixed `apt install` batch failure on Android/Termux by removing `binutils` / `binutils-is-llvm` from the Android requirements; both conflict with `lld`/`llvm` (pulled in by `clang`), and `clang` + `lld` + `llvm` already provide `ld.lld` / `llvm-ar` / `llvm-nm` / `llvm-strip`, which is everything native pip wheels need
- fixed `dot_docker/config.json.tmpl` emitting an `identitytoken`-only entry with no `auth` (Docker requires both); template now defaults username to the ACR identity-token UUID and always emits `auth` alongside `identitytoken`
- fixed `dot_docker/config.json.tmpl` printing `%!s(<nil>)` when a Docker item lacks the `registry name` field; template now falls back to the 1Password item title
- fixed `install_azure_cli` on Android/Termux skipping installation forever when `~/.azure` existed but `azure-cli` wasn't installed (e.g., left over from a prior uninstall); guard now checks `pip show azure-cli`, matching the Linux installer
- fixed `linux-engineering-shell-credentials.sh` and `linux-engineering-workspace-aliases.sh` skipping the cache write when the env var or alias was already set, leaving `~/.cache/op-credentials.env` empty (deleted at end of script) and forcing every new shell to re-query 1Password; cache is now always written so subsequent shells short-circuit via the 24h TTL check

### Removed

- removed Azure Container Registry entries (`docker:Azure Container Registry (dev)` / `(prod)`) from device notes and archived the two backing 1Password items; ACR login now managed ad-hoc via `az acr login`

## [0.7.0] - 2026-04-14

### Added

- added `rclone` to Android/Termux dependencies for cloud storage sync (OneDrive, Google Drive, S3)
- added rclone OneDrive setup guide (`.docs/rclone-onedrive-setup.md`)

## [0.6.0] - 2026-04-03

### Added

- added [devforge](https://github.com/rios0rios0/devforge) (`dev` CLI) installation to Linux/WSL and Android dependency scripts

## [0.5.0] - 2026-04-01

### Added

- added beginner tmux tutorial for Termux (`docs/tmux-termux-tutorial.md`) covering sessions, windows, panes, and touchscreen-friendly workflows
- added mobile-friendly `tmux` configuration (`dot_tmux.conf`) with `Ctrl+a` prefix, mouse mode, and intuitive split keybindings optimized for Termux extra-keys

## [0.4.0] - 2026-03-31

### Added

- added `clang` dependency (for building `termux-etc-redirect`) to Android requirements alongside existing `proot` and `proot-distro`
- added `golangci-lint` wrapper using `termux-etc-seccomp` for running on Android/Termux

### Changed

- changed `install_wrapper()` to `install_termux_etc_redirect()` which clones and builds the `termux-etc-redirect` project
- changed `terraw`, `terraformw`, `terragruntw` aliases to use `termux-etc-seccomp` directly instead of `wrapper`
- replaced `proot-distro` Alpine wrapper with `termux-etc-seccomp` for running Go binaries (GitHub CLI, 1Password CLI, Terraform, Terragrunt, `kubectl`) natively on Termux
- simplified `gh` wrapper by removing GitHub token forwarding through `proot` (tokens are inherited naturally)
- simplified `op` wrapper by removing `--env` flag forwarding (environment variables are inherited naturally without `proot` boundary)

### Fixed

- fixed 1Password CLI "not owned by the current user" error under `termux-etc-seccomp` by setting `$USER` in the `op` wrapper (Go's `user.Current()` in `GOOS=linux` static binaries requires `$USER` when `/etc/passwd` is missing)

### Removed

- removed `configure_dns()` function (DNS configuration is now handled by `termux-etc-redirect`'s install script)
- removed `linux-engineering-git-clone-repos.sh` — migrated to devforge `dev repo clone`
- removed `proot-distro` Alpine distro setup (`install_wrapper` function with `/etc/profile` PATH patching)
- removed `proot` bind mounts and workspace remapping from the generic wrapper
- removed `proot`-specific environment variables (`PROOTNOCALL_VERIFY`, `PROOT_LINK2SYMLINK`, `PROOT_VERBOSE`)

## [0.3.1] - 2026-03-24

### Changed

- changed `.zshrc` to replace `_vm_use_go`, `_vm_use_node`, `_vm_use_python` calls with a single `dev-use` call after all version managers are sourced
- changed `linux-engineering-version-manager.sh` to only keep pyenv workarounds, added `dev-use` shell wrapper for `dev project use`

### Removed

- removed `linux-engineering-docker-aliases.sh` (`dip`, `dreset`) — migrated to devforge `dev docker ips` and `dev docker reset`
- removed `linux-engineering-git-sync-repos.sh` — migrated to [devforge](https://github.com/rios0rios0/devforge) `dev repo sync`
- removed version detection functions (`_vm_detect_and_use`, `_vm_extract_*`, `_vm_use_*`) — migrated to devforge `dev project use`
- updated Copilot instruction docs to stop listing `linux-engineering-docker-aliases.sh` as an available script

## [0.3.0] - 2026-03-22

### Added

- added `.chezmoiignore` platform logic tests validating file inclusion per OS (linux, windows, android)
- added `git-clone-repos` function that discovers remote repos from GitHub or Azure DevOps, clones missing ones using SSH aliases, and prompts to delete local repos no longer found on the remote
- added `replaceAllRegex` stub to Go template validator for chezmoi's regex replacement function
- added `tmux` to Android dependencies for session multiplexing under a single process tree
- added `UV_THREADPOOL_SIZE` and `MALLOC_ARENA_MAX` environment variables for Android performance tuning
- added Android OS-level optimization guide (battery, animations, RAM Plus, Termux:Boot) to `README.md`
- added CI/CD validation pipeline with GitHub Actions: shellcheck, Go template syntax validation, Python/PowerShell linting, YAML/JSON syntax checks, and gitleaks SAST
- added Go template syntax validator (`cmd/tmplcheck`) that parses all `.tmpl` files with sprig/chezmoi function stubs
- added Makefile with `lint`, `test`, and `sast` targets following the pipelines repo pattern
- added script dependency ordering tests verifying alphabetical sort matches execution requirements
- added template rendering tests with mock 1Password CLI returning deterministic fixtures
- added Termux performance documentation (Phantom Process Killer fix) to `README.md` and `CLAUDE.md`

### Changed

- extended `termux.properties` modify script to set `terminal-transcript-rows`, `bell-character`, and `terminal-cursor-blink-rate` for better performance

### Fixed

- made `sast` Makefile target self-contained instead of depending on external `common.mk` targets
- pinned yq (`v4.45.1`) and gitleaks (`v8.24.0`) to specific versions in CI workflow instead of fetching `releases/latest`

### Removed

- removed flawed cross-prefix comparison in script ordering test that compared `run_once_before` vs `run_after` filenames (chezmoi determines execution order by prefix type, not alphabetical sort)

## [0.2.1] - 2026-03-18

### Changed

- skipped GVM on Android/Termux because standard `linux/arm64` Go builds use `faccessat2` syscall blocked by Android's seccomp filter, causing `SIGSYS` crashes

## [0.2.0] - 2026-03-15

### Added

- added `.local/share` proot bind for persistent gh extensions, fonts, and zinit plugin data
- added GitHub Copilot CLI extension (`gh copilot`) installation to Android dependencies with best-effort authentication check

### Changed

- extracted `gh` CLI proot wrapper from install-dependencies script into its own `run_once_before` script
- split Android wrapper bootstrap into three single-responsibility scripts: generic proot wrapper (`001`), op wrapper (`001a`), and gh wrapper (`001b`)

## [0.1.0] - 2026-03-12

### Added

- added 1Password integration for MCP server credentials and API keys
- added `gh` CLI proot wrapper for Termux that forwards GitHub tokens (`GH_TOKEN`, `GITHUB_PERSONAL_ACCESS_TOKEN`, `GITHUB_TOKEN`) through proot-distro Alpine
- added a new feature to compress and watch many folders instead of just one folder
- added Android-compatible MCP configuration with npx alternatives to Docker-based servers
- added feature to handle SSH, PEM and GPG keys seamlessly with 1Password
- added feature to use 1Password and SSH keys to encrypt and decrypt files
- added Linux WSL features to handle Git and SSH configuration with 1Password 
- added Shell Script features to handle watching multiple files (and compressing them) for Kubernetes secrets
- added Windows feature to copy configuration inside `AppData` folder

### Changed

- added `[prefix]` logging to previously silent scripts: `clone-tools`, `ssh-known-hosts`, `configure-deps`, `kube-config`, `termux-config`, `fonts`
- added `set -euo pipefail` error handling to 5 scripts missing it: `linux-gpg-keys`, `extract-folders`, `clone-tools`, `configure-deps`, `export-key`
- added `warnf` progress logging to all 1Password template operations (`gitconfig`, `ssh-config`, `allowed-signers`, `authorized-keys`, `docker-config`, `wakatime`, `age-recipients`) showing item fetch, device match, and per-item progress
- converted MCP configuration from static JSON to Chezmoi template for cross-platform compatibility and secure credential management
- deduplicated MCP server merge scripts into a shared `lib-modify-mcp-servers.sh` chezmoi template
- deduplicated shell credentials and workspace aliases into a shared `linux-engineering-op-loader.sh` loader with structured logging
- documented 1Password template pattern (`onepassword` + `dict`/`set`) and logging convention in CLAUDE.md
- enhanced Android SSH script to export both private and public keys from 1Password, renamed from `run_after_android-001-create-ssh-private-keys.sh.tmpl` to `run_after_android-001-create-ssh-keys.sh.tmpl`
- improved logging across modify scripts with `[prefix]` tags for `mcp-servers`, `claude-trust`, `claude-settings`, `credentials`, `workspaces`, and `git-sync`
- moved `OP_SESSION_*` env var forwarding from shared `wrapper` into the `op` wrapper script
- moved script echo output from stdout to stderr in `android-ssh-keys`, `linux-gpg-keys`, `copy-appdata` to avoid mixing logs with generated content
- refactored shared proot `wrapper` to accept `--env` flags from tool wrappers instead of hardcoding tool-specific env var forwarding
- replaced `onepasswordRead` + `onepasswordItemFields` with single `onepassword` call per item across all templates, using `dict`/`set` to build local field maps — halves API calls per referenced item and fixes missing built-in fields (`public key`, `private key`)
- segregated MCP configurations into platform-specific files: `.cursor/mcp.json` for Linux (Docker-based) and `.config/mcphub/servers.json` for Android (npx-based), eliminating cross-platform conditional logic
- simplified 1Password calls by replacing list/join patterns with printf format for improved readability and consistency
- standardized bare `echo` messages with `[prefix]` format in `op-wrapper`, `extract-folders`, `export-key`
- standardized logging convention across 20 files with `[prefix]` format to stderr using `warnf` (templates), `echo >&2` (shell), and `Write-Host` (PowerShell)
- suppressed proot warnings on Android using `PROOT_VERBOSE=-1` and `--no-arch-warning` flags
- switched all "Active *" item lookups from REFERENCE field iteration to notes-based (`notesPlain`) filtering — reads item titles from notes, filters by device locally, and only fetches matching items by title (reduces API calls from N+1 to 2 per device-filtered loop)
- unified `deviceName` computation into `.chezmoi.yaml.tmpl` data section, removing duplication across 7 template files
- updated `linux-engineering-op-loader.sh` to use notes-based filtering with `--vault private` for title-based lookups

### Fixed

- fixed `gh` CLI failing DNS lookups in Termux by routing it through proot-distro Alpine (Go reads `/etc/resolv.conf` which doesn't exist in Termux)
- fixed `map has no entry for key "value"` crash in `dict`/`set` field loops by adding `hasKey` guard for 1Password fields without a value property
- fixed `onepasswordItemFields` not returning built-in SSH Key fields (`public key`, `private key`) — these are top-level detail fields not accessible via `onepasswordItemFields` which only reads section-level fields
- fixed `warnf` double newlines by removing explicit `\n` from format strings (chezmoi appends its own newline)
- fixed Unicode curly quotes (U+201C/U+201D) inadvertently introduced in 3 template files

