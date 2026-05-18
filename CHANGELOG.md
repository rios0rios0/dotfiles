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

### Changed

- refreshed `.github/copilot-instructions.md` to replace stale proot/Alpine references with `termux-etc-seccomp`, update Linux terraform/terragrunt to `terra`-based management, correct ruff and aisync installation methods, add missing `claude-wrapper` logging prefix, and add `android-patch-claude-code-tmpdir.sh` to `dot_scripts/` listing

## [0.14.1] - 2026-05-08

### Changed

- changed `install_terra` in `run_once_before_linux-002-install-dependencies.sh` to call `terra self-update --force` followed by `yes y | terra update` so terra itself, `terraform`, and `terragrunt` upgrade non-interactively when newer versions are detected (previously `terra update` only refreshed `terraform`/`terragrunt` and printed `WARN: A new version of terra is available`, leaving terra itself stuck on the installed version, and the y/N prompts blocked unattended runs; `yes` is used because the currently installed `terra update` binary exposes no auto-answer flag)
- hardened `install_krew` in `run_once_before_linux-002-install-dependencies.sh` with a new `krew_retry` helper that retries `kubectl krew upgrade`/`install` up to three times and treats persistent failures as non-fatal, so transient HTTP `500`s from the `kubernetes-sigs/krew-index` repository (e.g. `remote: Internal Server Error` during index fetch) no longer break `chezmoi apply`
- hardened `install_sdkman` in `run_once_before_linux-002-install-dependencies.sh` to recreate `$SDKMAN_DIR/tmp` before `sdk install` (preventing `curl: Failed to open .../*.headers.tmp` when SDKMAN's tmp directory has been cleared) and to run `sdk selfupdate force` so candidate metadata stays current
- updated `install_ggshield` in `run_once_before_linux-002-install-dependencies.sh` to run `python -m pipx upgrade ggshield` when ggshield is already present, so a new GitGuardian release no longer prints `A new version of ggshield (vX.Y.Z) has been released` on every commit hook invocation
- updated `install_terra` in `run_once_before_android-002-install-dependencies.sh.tmpl` to pipe `yes y` into `terra update` so the y/N prompts for newer `terraform`/`terragrunt` blobs auto-answer on Android (terra itself is built from source, so `terra self-update` is intentionally not invoked)

## [0.14.0] - 2026-05-03

### Added

- added `netcat-openbsd` to the Android `utilities` array in `run_once_before_android-002-install-dependencies.sh.tmpl` so the SSH `ProxyCommand` blocks in `dot_ssh/config.tmpl` (`nc -z -w 5 …` fallback to `ssh.github.com:443`/`altssh.gitlab.com:443`/`altssh.bitbucket.org:443`) work out of the box on Termux, where `nc` is otherwise unavailable
- added a shared `install_go_tool_from_source` helper in the Android dependency installer that clones a Go repo into `~/Development/<host>/<owner>/<repo>`, syncs to its default branch via `sync_repo_to_default`, and runs `make install`. Inline comment documents why source-build is mandatory on Android: pre-built `GOOS=linux` Go binaries open Linux-only paths (`/etc/resolv.conf`, `/etc/hosts`, `/etc/ssl/certs/...`, `/etc/passwd`) and use the `faccessat2(439)` syscall blocked by Android's seccomp policy, so they would otherwise need `termux-etc-seccomp` wrapping; building locally with the Termux `golang` apt package produces `GOOS=android` binaries that run unwrapped

### Changed

- changed `ruff` provisioning on both Android and Linux/WSL to drop the previous `pipx install ruff` route. On Android: added `"ruff"` to the `utilities` array in `run_once_before_android-002-install-dependencies.sh.tmpl` and removed `install_ruff()` and its call site, since Termux's apt repository ships the upstream Rust binary as a native `aarch64` package. On Linux/WSL: rewrote `install_ruff()` in `run_once_before_linux-002-install-dependencies.sh` to fetch and run Astral's official `https://astral.sh/ruff/install.sh` (Debian/Ubuntu apt only carries `ruff` on `sid`/`plucky` and at version `0.0.291+dfsg1-4` from Aug 2023, so apt isn't a viable cross-distro path). Motivation: the pipx route required a working Python toolchain and was fragile across pipx versions — pre-`0.15` pipx writes metadata that newer pipx refuses to manage, leaving an orphaned venv with no `~/.local/bin/ruff` shim and breaking `make lint-python` even though `ruff` was technically "installed". Migration: existing installs that already ran the dependency installer can `apt install ruff` (Termux) or `curl -fsSL https://astral.sh/ruff/install.sh | sh` (Linux/WSL) once; the broken pipx venv at `~/.local/pipx/venvs/ruff/` (or wherever pipx put it) can be removed with `rm -rf` or `python -m pipx uninstall ruff`
- changed Android `install_terra`, `install_dev_toolkit`, and `install_aisync` to all delegate to the new `install_go_tool_from_source` helper for one consistent source-build pattern. `install_terra` reverts to clone + `make install` (was briefly switched to `install.sh` in this same release cycle), `install_dev_toolkit` drops the `curl … install.sh | bash` fetch, and `install_aisync` drops `go install …@latest`
- changed Android SSH agent management in `dot_zshrc.tmpl` from the Oh My Zsh `ssh-agent` plugin to `keychain` (added to the Android `utilities` array in `run_once_before_android-002-install-dependencies.sh.tmpl`). The OMZ plugin spawns a per-session agent at a random socket path, which leaves child processes (Claude Code, tmux panes, IDE integrations) holding a dead `SSH_AUTH_SOCK` once the originating zsh exits — surfacing as "Couldn't get agent socket?" / "Connection refused" on every signed commit or `git push`. `keychain` runs a single long-lived agent across sessions and exposes a stable socket via `~/.keychain/<host>-sh`, so newly-spawned shells always inherit a live `SSH_AUTH_SOCK`. Caveat: already-running child processes keep whatever socket they inherited at fork time, so if `keychain` does have to restart a dead agent, those long-lived children still need to be restarted to pick up the new socket — the win is for shells started after the restart. Linux/WSL and Windows keep their existing setup; this change is Android-only. Migration: existing Termux installs that already ran `run_once_before_android-002-install-dependencies.sh.tmpl` will not auto-install `keychain` (`run_once_before_*` scripts don't rerun on subsequent `chezmoi apply`s); `dot_zshrc.tmpl` falls back to the OMZ `ssh-agent` plugin when `keychain` is missing so the agent keeps working unchanged. To opt in to keychain on an existing install, run `apt install keychain` once (or `rm ~/.config/chezmoi/scriptState/run_once_before_android-002-install-dependencies.sh.tmpl_*` then `chezmoi apply` to rerun the installer)
- changed Linux/WSL `install_aisync` to fetch the upstream `https://raw.githubusercontent.com/rios0rios0/aisync/main/install.sh` (mirroring `install_dev_toolkit`) instead of `go install`-ing from source — pre-built `GOOS=linux` Go binaries run natively under glibc with no `/etc/*` redirection needed, and this drops the requirement for a working `go` toolchain on the install host
- changed Linux/WSL to install `terra` (via the upstream `install.sh` from `rios0rios0/terra`) and let `terra update` provision `terraform`/`terragrunt`, replacing the standalone `install_terraform` (which added the HashiCorp apt repo + `apt install terraform`) and `install_terragrunt` (which `curl`-ed `terragrunt_linux_amd64` from a pinned Gruntwork release into `/usr/local/bin`). This brings Linux/WSL in line with Android (where `terra` has always been the only path) so per-project `terraform`/`terragrunt` versions are managed identically across platforms; on Linux the binaries `terra update` downloads run natively under glibc and need none of the `termux-etc-seccomp` wrapping that `run_after_android-003-wrap-terra-clis.sh` applies on Android

### Fixed

- fixed `install_termux_etc_redirect` in the Android dependency installer crashing with "There is no tracking information for the current branch" when the local clone was parked on a feature branch — extracted a `sync_repo_to_default` helper that fetches `origin`, resolves the upstream default branch via `refs/remotes/origin/HEAD` (with a `git remote set-head origin --auto` fallback and a final `main` fallback), checks it out, and rebases against `origin/<default>` before running the build/install step
- fixed `make test-template-render` failing on Termux with `fork/exec …/mock-op.sh: no such file or directory` — the fixture had a `#!/bin/bash` shebang that the kernel can't resolve on Termux (no `/bin/bash`, no `/usr/bin/env`). Rewrote `.github/ci/fixtures/mock-op.sh` to POSIX `sh` (`#!/bin/sh`, `[ ]` and `=` instead of `[[ ]]` and `==`) so it runs on Termux's `/bin/sh` (Android's mksh) and CI's Linux `/bin/sh -> dash` equally well
- fixed every zsh startup printing ` * Warning: --agents is deprecated, ignoring.` on Android by dropping `--agents ssh` from the `keychain --eval` invocation in `dot_zshrc.tmpl`. `keychain` `2.9.x` removed the flag — the default already targets `ssh-agent` and only adopts `gpg-agent` when `--ssh-allow-gpg`/`--ssh-spawn-gpg` is passed, so the flag was redundant and only produced noise on every new shell

## [0.13.0] - 2026-04-30

### Added

- added `export CLAUDE_UPDATE_CHANNEL="latest"` to the Android branch of `dot_zshrc.tmpl` so the wrapper's background updater tracks Anthropic's `latest` channel by default on Termux
- added `install_aisync()` to Linux/WSL and Android dependency installers — `go install`s [`rios0rios0/aisync`](https://github.com/rios0rios0/aisync) so the `aisync` binary is available out of the box; this is the tool that took over from the removed `run_after_*-install-ai-rules.*` scripts and is run by the user (e.g., `aisync init`, `aisync source add guide …`, `aisync pull`) to sync AI assistant rules into `~/.claude/`, `~/.cursor/`, etc.
- added `install_ruff()` to Linux/WSL and Android dependency installers — provisions `ruff` via `pipx` so `make lint-python` works locally without a manual `pip install ruff` step (CI already installs `ruff` per the `validate.yaml` workflow)
- added `patchelf` to the Android dependency list in `run_once_before_android-002-install-dependencies.sh.tmpl` so the new `claude` wrapper's auto-updater can `--set-interpreter` on freshly downloaded builds
- added `run_once_before_android-001e-create-claude-wrapper.sh` that generates `~/.local/bin/claude` for the Claude Code `linux-arm64-musl` build. The emitted wrapper exec's the newest installed version (an executable file named `~/.local/share/claude/versions/<X.Y.Z>`) through `termux-etc-mount`, drops the previously hand-edited hardcoded version pin, and fires a non-blocking, rate-limited (24h) background update check that downloads the latest `stable` build from Anthropic's GCS distribution, runs `patchelf --set-interpreter` against the local musl loader, atomically moves it into the versions dir, and prunes everything older than the newest three. The in-binary auto-updater stays disabled (`DISABLE_AUTOUPDATER=1`) because it cannot perform the `patchelf` step the kernel needs to resolve `PT_INTERP` on Termux. Knobs: `CLAUDE_UPDATE_CHANNEL`, `CLAUDE_NO_AUTO_UPDATE`, `CLAUDE_FORCE_VERSION`

### Changed

- changed `devforge` references to `dev-toolkit` to match the upstream rename — install scripts now define `install_dev_toolkit()` and download from `https://raw.githubusercontent.com/rios0rios0/dev-toolkit/main/install.sh` (GitHub auto-redirects the old URL, but new installs use the renamed repository)
- changed log tags and inline comments in `dot_zshrc.tmpl`, `dot_scripts/linux-engineering-version-manager.sh`, `CLAUDE.md`, and `.github/copilot-instructions.md` to use the new project name
- changed the chezmoi prefix listed in `CLAUDE.md` and `.github/copilot-instructions.md` from `devforge` to `dev-toolkit`

### Removed

- removed `run_after_linux-003-install-ai-rules.sh` and `run_after_android-002-install-ai-rules.sh.tmpl` since AI rules are now synced via `aisync` instead of being pulled from the guide repository at chezmoi-apply time
- removed the npm-based `install_claude_cli` from `run_once_before_android-002-install-dependencies.sh.tmpl` and its call site. The `@anthropic-ai/claude-code` npm package distributes the JavaScript build, but on Termux/Android the `linux-arm64-musl` binary is what runs through the new `claude` wrapper. First-time bootstrap (musl loader seed + initial `patchelf`) follows `examples/claude-code.md` in `rios0rios0/termux-etc-redirect`; subsequent updates flow through the wrapper's auto-updater

## [0.12.0] - 2026-04-28

### Added

- added `gist.github.com-{alias}` host blocks to `dot_ssh/config.tmpl` so Gist remotes work alongside GitHub aliases on every device — on Linux/Android the block uses gist's own `HostName gist.github.com` with a `ProxyCommand` (`nc -z -w 5`) that tries port 22 first and falls back to `ssh.github.com:443` when port 22 is blocked; on Windows (which lacks `nc` by default) it uses `HostName ssh.github.com` with `Port 443` directly
- added `gist.github.com` to the Windows `known_hosts` scanner so direct gist hosts are pre-trusted

### Changed

- changed `github.com-{alias}`, `gitlab.com-{alias}`, and `bitbucket.org-{alias}` blocks in `dot_ssh/config.tmpl` to the same dual-mode setup as gist: on Linux/Android, the natural `HostName` with a `ProxyCommand` (`nc -z -w 5`) that tries port 22 first and falls back to the provider's port-443 SSH endpoint (`ssh.github.com:443`, `altssh.gitlab.com:443`, `altssh.bitbucket.org:443`) only when port 22 is blocked; on Windows (which lacks `nc` by default), the alt-host with `Port 443` directly
- changed `run_once_after_windows-001-create-ssh-known-hosts.ps1` to also scan `ssh.github.com`, `altssh.gitlab.com`, and `altssh.bitbucket.org` on port 443, populating the host keys used by the new fallbacks
- refreshed `.github/copilot-instructions.md` to fix stale GVM version claim, update post-apply scripts list, correct `dot_zshenv` → `dot_zshenv.tmpl`, update `dot_scripts/` listing, and sync logging prefix list
- refreshed `CLAUDE.md` to fix `make sast` description (now includes semgrep), add `make test-modify-scripts` target, correct `dot_zshenv` → `dot_zshenv.tmpl`, and update logging prefix list

## [0.11.0] - 2026-04-24

### Added

- added `acli` (Atlassian CLI) install to Android/Termux via `install_acli` in `run_once_before_android-002-install-dependencies.sh.tmpl` (downloads `acli_linux_arm64.tar.gz` into `~/.local/bin/acli_linux_arm64`) plus `run_once_before_android-001d-create-acli-wrapper.sh` that generates a `termux-etc-seccomp` wrapper at `~/.local/bin/acli` so the Go-compiled binary survives Android's seccomp policy
- added `acli` (Atlassian CLI) install to Linux/WSL via `install_acli` in `run_once_before_linux-002-install-dependencies.sh` (downloads `acli_linux_amd64.tar.gz`/`acli_linux_arm64.tar.gz` from `acli.atlassian.com` and installs to `/usr/local/bin`)

## [0.10.1] - 2026-04-21

### Fixed

- fixed `terragrunt hcl format` and any other `terragrunt`/`terraform` call from `terra`, scripts, or non-aliased shells crashing with `SIGSYS` on Android/Termux — Go's `os/exec.LookPath` issues `faccessat2` which hits Android's seccomp trap before `termux-etc-seccomp`'s ptrace layer can rewrite it to `-ENOSYS` when the binary is invoked bare (the `terragruntw`/`terraformw` aliases only cover interactive shell use, not `exec.Command`); new `run_after_android-003-wrap-terra-clis.sh` idempotently renames `~/.local/bin/{terragrunt,terraform}` to `*_raw` and replaces them with shell wrappers that `exec termux-etc-seccomp` against the raw binary, and re-runs on every `chezmoi apply` so `terra update` overwrites are re-wrapped automatically

## [0.10.0] - 2026-04-20

### Added

- added `clang` to the Linux/WSL core requirements in `run_once_before_linux-002-install-dependencies.sh` so toolchains that prefer it over `gcc` (Go/Rust/C) have a compiler available

### Changed

- changed `install_gvm` in `run_once_before_linux-002-install-dependencies.sh` to resolve the latest stable Go version from `https://go.dev/VERSION?m=text` on every run instead of hardcoding `go1.25.5`

## [0.9.0] - 2026-04-19

### Added

- added `dot_gitmessage` (conventional-commits scaffold migrated from the legacy `WKSetup` repo) and wired `commit.template = ~/.gitmessage` in `dot_gitconfig.tmpl`
- added `rec` alias for `asciinema rec` in `dot_zshrc.tmpl` (matches the shorthand from the legacy `WKSetup` repo)
- added `run_after_linux-005-install-jetbrains-themes.sh` and `run_after_windows-004-install-jetbrains-themes.ps1` to fan the staged themes out into every detected JetBrains IDE config directory (`~/.config/JetBrains/*/` on Linux, `%APPDATA%\JetBrains\*\` on Windows) into `colors/`, `codestyles/`, and `materialCustomThemes/`
- added `send` zsh function in `dot_zshrc.tmpl` (Android/Termux-only) that uploads files and directories to the OneDrive `Downloads/` folder via rclone; directories preserve their basename in the destination, and the function guards against missing rclone or an unconfigured `onedrive:` remote
- added staged JetBrains theme assets under `dot_local/share/jetbrains-themes/` (`Darcula Coder.icls`, `Dark Coder.icls`, `Coder.xml` code style, `Dark Coder.xml` Material Theme UI variant) migrated from the legacy `WKSetup` repo
- set `AWS_CRT_BUILD_USE_SYSTEM_LIBCRYPTO=1 PIP_NO_BINARY=awscrt` on the Android/Termux AWS CLI v2 build so `awscrt` links against Termux's OpenSSL 3.x instead of its bundled libcrypto that still references the removed `FIPS_mode` symbol (fixes `ImportError: cannot locate symbol "FIPS_mode"` when loading `_awscrt.abi3.so`)

### Changed

- replaced the stale `PYTHONPATH=$TOOLS_DIR/asciinema python -m asciinema …` `record`/`play` aliases in `dot_zshrc.tmpl` with direct `asciinema rec` / `asciinema play` invocations (asciinema is now installed as a first-class dependency via `apt`/`pipx`)

### Fixed

- fixed `install_azure_cli` on Android/Termux failing to build `PyNaCl` (bundled libsodium `make` errors on Android); the `pip install azure-cli` call now runs with `SODIUM_INSTALL=system` so `PyNaCl` links against Termux's `libsodium` apt package instead of its bundled copy
- fixed `install_azure_cli` on Android/Termux failing with `platform android is not supported` when building `psutil`; the function now pre-installs a patched `psutil 7.2.2` (same `_common.py` one-liner used by `termux-packages` PR #28780 for the upcoming `python-psutil` port) so pip sees the constraint already satisfied when resolving the `azure-cli` dependency tree

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

