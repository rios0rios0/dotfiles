# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

Cross-platform dotfiles managed with **chezmoi** targeting three platforms: **Linux (Kali on WSL)**, **Windows 11**, and **Android (Termux)**. Secrets are managed via **1Password CLI** and sensitive files are encrypted with **age**.

The "build" is `chezmoi apply`. A CI pipeline validates templates, scripts, and platform logic.

## Quality Commands

```bash
make lint                           # shellcheck, Go template syntax, Python, PowerShell, YAML/JSON
make test                           # template rendering (mock op), .chezmoiignore logic, script order
make sast                           # gitleaks + semgrep secret/code scanning
make lint-shellcheck                # shell scripts only
make lint-templates                 # Go template syntax only
make test-template-render           # template rendering with mock 1Password
make test-chezmoiignore             # platform file inclusion logic
make test-script-order              # script dependency ordering
make test-modify-scripts            # modify script (merge) behavior
make test-remove-dependencies       # dependency removal library (tombstones, $HOME safety rail)
make test-prune-tmp-modcache        # $TMPDIR Go module cache pruning ($TMPDIR safety rail)
make test-shell-credentials         # 1Password credential/workspace loading and removal
```

## Essential Commands

```bash
chezmoi status                      # show managed files and their state
chezmoi diff                        # preview pending changes
chezmoi apply --dry-run             # test without applying
chezmoi apply                       # apply configuration to home directory
chezmoi apply --verbose             # apply with detailed output
chezmoi update                      # pull repo changes and apply
chezmoi edit ~/.zshrc               # edit a managed file
chezmoi add ~/.new-file             # add a new file to management
chezmoi add --encrypt ~/.secret     # add with age encryption
chezmoi cat ~/.ssh/config           # decrypt and display an encrypted file
chezmoi execute-template < file.tmpl  # test template rendering
chezmoi doctor                      # diagnose installation issues
```

## Chezmoi File Naming Conventions

| Prefix/Suffix       | Meaning                                                |
|---------------------|--------------------------------------------------------|
| `dot_`              | Becomes `.` in target (e.g., `dot_zshrc` → `~/.zshrc`) |
| `.tmpl`             | Processed as Go template before deployment             |
| `encrypted_*.age`   | Age-encrypted file, decrypted on apply                 |
| `run_once_before_*` | Script runs once before file application               |
| `run_after_*`       | Script runs after every application                    |
| `run_onchange_after_*` | Script runs after application, only when its own content changes |
| `private_`          | File deployed with restricted permissions              |

## Platform Targeting

Platform-specific logic is handled in two ways:

1. **`.chezmoiignore`** — Uses inline Go templates to exclude files per OS (`eq .chezmoi.os "linux"`, `"windows"`, `"android"`)
2. **`.tmpl` files** — Go template conditionals inside configuration files

Platform-specific scripts in `.chezmoiscripts/` are prefixed: `linux-*`, `windows-*`, `android-*`.

### Platform Matrix

| Aspect     | Linux (WSL)                  | Windows                 | Android (Termux)                 |
|------------|------------------------------|-------------------------|----------------------------------|
| Shell      | Zsh + Oh My Zsh + p10k       | PowerShell + Oh My Posh | Zsh + Oh My Zsh + p10k           |
| Scripts    | `.sh`                        | `.ps1`                  | `.sh`                            |
| Docker     | Native                       | N/A                     | `termux-etc-seccomp` wrapper     |
| MCP config | `modify_dot_claude.json.tmpl` (Docker-based) | `modify_dot_claude.json.tmpl` (Docker-based) | `dot_config/mcphub/` (npx-based) |
| 1Password  | Native `op` CLI              | Native `op` CLI         | `termux-etc-seccomp` wrapper at `.local/bin/op` |

## Key Files

- **`.chezmoi.yaml.tmpl`** — Chezmoi config: 1Password and age encryption settings
- **`dot_gitconfig.tmpl`** — Git config with 1Password SSH signing, per-device SSH keys, platform-specific paths
- **`dot_zshrc.tmpl`** — Shell config: ZINIT plugins, version managers (GVM/NVM/Pyenv/SDKMAN/Cargo), Docker aliases, Kubernetes tools
- **`dot_zshenv.tmpl`** — PATH setup for version managers (critical for IDE integration)
- **`.chezmoiignore`** — Platform-conditional file exclusion rules
- **`.chezmoitemplates/`** — Shared template fragments (shared install functions, font installer, dependency removal, MCP server merge logic, username)

## Template Variables

Commonly used chezmoi template variables in this repo:
- `.chezmoi.os` — `"linux"`, `"windows"`, `"android"`
- `.chezmoi.hostname`, `.chezmoi.homeDir`, `.chezmoi.arch`
- `.chezmoi.kernel` — Used to detect WSL (`microsoft` in kernel name)
- `onepassword` — Fetch full item by name/UUID from 1Password (preferred — returns `.title` + `.fields`)
- `onepasswordRead` — Fetch a single scalar field by `op://` URI (use only for simple direct reads)

## 1Password Template Pattern

Each device has a single **"Device: \<deviceName\>"** Secure Note in the `personal` vault. The note combines two storage mechanisms:

- **`notesPlain`**: lists references to external items (SSH keys, GPG keys, PEM certs, Docker registries) in `type:Item Name` format, one per line
- **Custom fields**: store credential and workspace values directly on the device note, with `type:name` labels (e.g., `cred:GH_TOKEN`, `ws:mine`)

Templates fetch this note (cached by chezmoi across all template files) and filter by type prefix.

**Type prefixes:**

| Prefix | Storage | Consumer |
|--------|---------|----------|
| `ssh`  | `notesPlain` entry referencing SSH Key item in `Private` vault | Chezmoi templates |
| `gpg`  | `notesPlain` entry referencing Secure Note in `Private` vault | Chezmoi templates |
| `pem`    | `notesPlain` entry referencing Secure Note in `Private` vault | Chezmoi templates |
| `docker` | `notesPlain` entry referencing Docker registry item in `Private` vault | Chezmoi templates |
| `cred`   | Field on device note (`cred:NAME` label, concealed value) | Runtime `op-loader` |
| `ws`     | Field on device note (`ws:NAME` label, text value) | Runtime `op-loader` |

**Device-note pattern with type filtering:**
```go
{{- $deviceNotes := "" -}}
{{- range (onepassword (printf "Device: %s" $deviceName) "personal" "my").fields -}}
  {{- if and (eq .label "notesPlain") (hasKey . "value") -}}
    {{- $deviceNotes = .value -}}
  {{- end -}}
{{- end -}}
{{- range splitList "\n" $deviceNotes -}}
  {{- $entry := . | trim -}}
  {{- if ne $entry "" -}}
    {{- $type := index (split ":" $entry) "_0" -}}
    {{- $name := trimPrefix (printf "%s:" $type) $entry | trim -}}
    {{- if eq $type "ssh" -}}
      {{- $item := onepassword $name "Private" "my" -}}
      {{- $f := dict -}}
      {{- range $item.fields -}}
        {{- if hasKey . "value" -}}
          {{- $_ := set $f .label .value -}}
        {{- end -}}
      {{- end -}}
      {{- $val := index $f "field name" -}}
```

**Always guard with `hasKey . "value"`** — some 1Password fields lack a `value` property; accessing it without a guard causes `map has no entry for key "value"`.

**Do not use `onepasswordItemFields`** — it only returns section-level fields and misses built-in properties like `"public key"` and `"private key"` on SSH Key items. The `onepassword` + `dict`/`set` pattern accesses all fields and chezmoi caches the underlying `op item get` call across all template files automatically.

## Runtime Credential Lifecycle (Removal Needs a Manifest)

`cred:` and `ws:` fields are loaded at shell startup by `dot_scripts/linux-engineering-{shell-credentials,workspace-aliases}.sh` and cached in `~/.cache/op-{credentials,workspaces}.env` (mode `600`, 24h TTL). `reload-credentials` re-reads both.

**A rewritten cache cannot remove anything.** Once `export GH_TOKEN` has run, the value lives in the environment, not in the file — so deleting the field from the device note drops it from the cache while the variable survives in that shell and in every shell forked from it (tmux panes, IDE terminals, MCP subshells inherit the environment, never the cache).

Each successful load therefore writes the names it returned into `_OP_CRED_NAMES` / `_OP_WS_NAMES`, both in the cache file and in the environment:

| Half | Mechanism |
|------|-----------|
| The shell that reloads | `_op_prune_removed` in the loader scripts diffs the inherited manifest (plus the names the on-disk cache still assigns) against the fresh load, and unsets the difference |
| Shells that inherited the value | `dot_zshenv.tmpl` runs the same diff after sourcing the caches, which is what makes a newly opened terminal drop a credential deleted elsewhere |

**When touching this code, keep three invariants:**

1. **Never prune on a failed fetch.** A locked vault, a missing `op`/`jq`, and a deleted field all look identical — "not in the response". `_op_load_references` returns non-zero when it never reached 1Password, and callers must leave the environment alone; pruning there would wipe every credential during a brief outage.
2. **Never delete the caches to force a reload.** `reload-credentials` sets `_OP_RELOAD=1` to bypass the TTL instead, because the fetch reads the outgoing cache to recognise credentials exported by revisions that wrote no manifest.
3. **Keep the `.zshenv` prune off the hot path.** It runs on every shell, so it is guarded on a manifest that was both inherited *and* changed, and `_op_read_cache_names` returns through a global rather than command substitution — the Termux phantom-process budget makes avoidable forks expensive.

`make test-shell-credentials` covers all of this against a mock `op`.

## Logging Convention

All scripts and templates use a standardized `[prefix]` logging format to stderr:

```
[prefix] message              # informational (default)
[prefix] WARN: message        # non-fatal issues, skips
[prefix] ERROR: message       # fatal issues before exit
```

| Channel | How |
|---------|-----|
| Templates (`.tmpl`) | `warnf "[prefix] message"` — writes to stderr during rendering (do NOT add `\n`, chezmoi appends its own newline) |
| Shell scripts (`.sh`) | `echo "[prefix] message" >&2` |
| PowerShell (`.ps1`) | `Write-Host "[prefix] message"` |
| Python (in `modify_*`) | `print("[prefix] message", file=sys.stderr)` |

Existing prefixes: `gitconfig`, `ssh-config`, `allowed-signers`, `authorized-keys`, `docker-config`, `wakatime`, `age-recipients`, `android-ssh-keys`, `linux-gpg-keys`, `windows-ssh-keys`, `windows-pem-keys`, `wrapper`, `op-wrapper`, `gh-wrapper`, `acli-wrapper`, `golangci-lint-wrapper`, `claude-wrapper`, `codex-wrapper`, `copilot`, `codex`, `export-key`, `extract-folders`, `clone-tools`, `configure-deps`, `ssh-known-hosts`, `copy-appdata`, `termux-config`, `fonts`, `kube-config`, `mcp-servers`, `claude-trust`, `claude-settings`, `claude-code-patch`, `ggshield-auth`, `ggshield-hook`, `jetbrains-themes`, `acli`, `send`, `credentials`, `workspaces`, `dev-toolkit`, `aws-cli`, `azure-cli`, `golangci-lint`, `sync-repo`, `install-deps`, `remove-deps`, `tmp-modcache`, `sentry-setup`, `claude-exec-shim`

## Dependency Lifecycle (Removal Is Explicit)

This repository is a **sync**, not a bootstrapper. Deleting an `install_*()` function from a dependency installer only stops *new* machines from getting the tool — machines that already ran it keep it forever. chezmoi has no history of the source state and no concept of packages, so **both halves of a removal must be declared explicitly**.

| Half | Mechanism |
|------|-----------|
| Files orphaned in `$HOME` | `.chezmoiremove` (deleted on every apply; patterns are home-relative, `#` starts a comment) |
| Installed packages | `.chezmoiscripts/run_onchange_after_<platform>-*-remove-dependencies.*` tombstones |

**When removing a dependency, always do all three:**

1. Delete the `install_*()` function (or package-list entry) from the platform installer.
2. Add a `"<strategy>:<target>"` tombstone to the removal script of **every** platform that installed it, with a comment referencing the removing commit.
3. Add any orphaned config directory to `.chezmoiremove`.

Strategies live in `.chezmoitemplates/lib-remove-dependencies.sh` (shared by Linux and Android; Windows has its own inline set): `apt`, `gh_extension`, `npm_global`, `path`, `pipx`, `winget`. Every handler is idempotent and silent when the target is already absent.

`remove_path` refuses any target outside `$HOME` — these scripts run unattended, so never widen that guard. `make test-remove-dependencies` covers it.

See `.docs/dependency-lifecycle.md` for the rationale, including why Nix/home-manager was evaluated and rejected (it cannot cover Windows-native or Termux).

## Shared Install Library

`.chezmoitemplates/lib-install-deps.sh` holds the install functions whose body is correct on both Linux/WSL and Android without a conditional: `command_exists`, `install_oh_my_zsh`, `install_sdkman`, `install_nvm`, `install_fly_cli`, `install_sentry_cli`, plus the `run_remote_installer` helper they use to download an installer script to a temp file and run it (never pipe `curl` into `bash`; without `pipefail` an HTTP error page runs silently). Both dependency installers pull it in with `{{ template "lib-install-deps.sh" }}`, which is the only reason the Linux installer is a `.sh.tmpl`.

Keep platform-specific provisioning in the platform installers: apt repositories versus binary downloads (`gh`, `kubectl`), upstream install scripts versus source builds (`terra`, `dev-toolkit`, `aisync`), pyenv versus Termux's native Python. A function moves into the library only when the same body is right on both platforms. The library is pure bash (no template directives), so `make lint-shellcheck` lints it as a plain `.sh` file, and its messages use the `[install-deps]` prefix.

Oh My Zsh is installed with `--unattended` on both platforms, so the login shell is switched explicitly right after it, and only when the install succeeded: `usermod` on Linux, Termux's `chsh -s zsh` on Android. Every remote installer in the library (Oh My Zsh, SDKMAN, NVM) goes through `run_remote_installer`, which forwards extra arguments to the script; do not reintroduce `sh -c "$(curl ...)"`, because a failed download becomes an empty command that exits 0. On Termux `install_nvm` keeps the native `nodejs` package and only enables corepack; the check is on Termux's prefix, not on where `npm` resolves from, because WSL exposes Windows' `npm` through PATH interop.

## Important Timing Constraints

Dependency installation scripts (`.chezmoiscripts/run_once_before_*-install-dependencies.*`) take **45-120 minutes**. Never cancel them mid-execution. Use timeouts of 120+ minutes when running full installations.

### Android Wrapper Timing

On Android, tool wrappers (`op`, `gh`) **must be `run_once_before` scripts**, NOT chezmoi-managed files under `dot_local/bin/`. This is because `run_once_before` scripts execute before chezmoi applies managed files. The install-dependencies script (`run_once_before_android-002`) calls `op` and `gh` during installation — if these wrappers were chezmoi-managed files, they wouldn't exist yet when the install script runs, causing crashes.

The wrapper scripts follow a strict execution order:
1. `android-001-create-wrapper.sh` — generic `termux-etc-seccomp` wrapper (all tool wrappers depend on this)
2. `android-001a-create-op-wrapper.sh` — `op` wrapper (needed by chezmoi templates)
3. `android-001b-create-gh-wrapper.sh` — `gh` wrapper (backs the `gh_linux_arm64` binary installed in step 8)
4. `android-001c-create-golangci-lint-wrapper.sh` — `golangci-lint` wrapper (backs the `golangci-lint_linux_arm64` binary installed in step 8)
5. `android-001d-create-acli-wrapper.sh` — `acli` wrapper (backs the `acli_linux_arm64` binary installed in step 8)
6. `android-001e-create-claude-wrapper.sh` — `claude` wrapper for Claude Code's `linux-arm64-musl` build (handles the background `patchelf`-aware auto-updater; first-time bootstrap is still manual via `examples/claude-code.md` in `rios0rios0/termux-etc-redirect`) It parks `LD_PRELOAD` in `TERMUX_ETC_LD_PRELOAD` instead of dropping it (see below) and takes `termux-wake-lock` before the `exec`. It also writes `~/.local/bin/claude-zsh`, the `CLAUDE_CODE_SHELL` launcher that restores the parked value before each tool-call zsh starts (see below).
7. `android-001f-create-codex-wrapper.sh` — `codex` wrapper for the Codex CLI's static `aarch64-unknown-linux-musl` release (see "Codex CLI on Termux" below). It parks `LD_PRELOAD` the same way and hands the parked value to Codex's own tool-call shells with `-c 'shell_environment_policy.set.LD_PRELOAD=…'` (see below), takes `termux-wake-lock`, and downloads the release itself: in the foreground on the first launch, which is how step 8 bootstraps it, and through a background check afterwards, because `codex update` refuses a manual install
8. `android-002-install-dependencies.sh.tmpl` — installs binaries and extensions

The generic `termux-etc-seccomp` wrapper is the only exception — it exists as BOTH a bootstrap script (for timing) AND a chezmoi-managed file (`dot_local/bin/executable_wrapper`) to keep it updated on subsequent applies.

## Android Performance (Termux)

Android 12+ includes a **Phantom Process Killer** that enforces a system-wide limit of ~32 forked child processes. Claude Code spawns many Node.js children, so running 3+ sessions causes `[Process completed (signal 9)]` — this is SIGKILL from the phantom killer, not OOM.

**Fix (Android 14+, no root required):** Enable `Settings > System > Developer Options > "Disable child process restrictions"`.

**Supplementary:** Run `termux-wake-lock` to prevent deep sleep. Use `tmux` instead of multiple Termux tabs to consolidate process trees.

**Environment tuning** (set in `dot_zshenv.tmpl`, Android-only):
- `UV_THREADPOOL_SIZE=16` — increases Node.js libuv thread pool from default 4, critical for Claude Code I/O
- `MALLOC_ARENA_MAX=2` — reduces glibc memory arena fragmentation on mobile
- `DBUS_SESSION_BUS_ADDRESS=disabled:` — blocks D-Bus session autolaunch. Without it, tools run through `termux-etc-seccomp` (`op`, `gh`, `acli`, `claude`) leak a `dbus-daemon --session --fork` that reparents to PID 1 and is never reaped, silently consuming the ~32-process phantom budget until any new subprocess trips the killer. `op` is the likeliest source (leaked daemons appeared in the same second as its `op-daemon.pid`), but the guard covers every wrapped tool

**`LD_PRELOAD` contract with `termux-etc-mount`:** the musl Claude binary cannot load Termux's bionic preload shims, so the wrapper and `termux-etc-mount` both move `LD_PRELOAD` to `TERMUX_ETC_LD_PRELOAD` before the `exec`. Three things hand it back, and each covers a case the others cannot, because an export from inside a running shell reaches only that shell's children, never the shell itself:

| Where the shims come back | Mechanism |
|---------------------------|-----------|
| In the tool-call shell itself | The wrapper exports `CLAUDE_CODE_SHELL=~/.local/bin/claude-zsh` (both files come from `001e`). Claude Code accepts the override because the path contains `zsh` and is executable, and derives the shell type and rc file from that string; the launcher restores the variable and `exec`s the real zsh, so `termux-exec` is mapped before the shell's first `execve`. This is what lets a tool call exec `sentry` or any other npm bin directly: those keep their `#!/usr/bin/env node` shebang, and the kernel resolves it only through the caller's preload (`copilot`'s launcher now starts too; that CLI then fails on its own, its `pty.node` native module has no `android-arm64` build, which is unrelated). The launcher also drops the `NODE_EXTRA_CA_CERTS` the wrapper sets for Claude's own musl Node, which bionic Node never needs and the Sentry CLI warns about on every run |
| In everything a shell spawns | The Android block of `dot_zshenv.tmpl` re-exports the parked value (falling back to `termux-exec` alone when nothing was parked). On its own this half fixed `make` targets and pipelines scripts — children of the shell — but not a script exec'd straight from the tool call, which failed with `bad interpreter: /usr/bin/env` while `zsh -c 'sentry --version'` worked. It stays for a `termux-etc-mount` run by hand, an SSH login and an older wrapper |
| In Codex's tool-call shells | The `codex` wrapper (`001f`) appends `-c 'shell_environment_policy.set.LD_PRELOAD=…'` with the parked value (same `termux-exec` fallback as the other two). Codex applies that policy to the environment it spawns tool commands with, so the shims are mapped at `execve` time. Neither of the halves above can reach those shells: Codex ignores `$SHELL` and resolves the shell from the password database (`getpwuid_r`), whose Termux entry is `$PREFIX/bin/login` — a name it does not recognise — so it falls back to `which bash` and runs `$PREFIX/bin/bash -lc "<cmd>"`, which never sources `~/.zshenv`. `CODEX_WRAPPER_KEEP_LD_PRELOAD=1` opts out |

Keep the variable name in step with `rios0rios0/termux-etc-redirect`; a `CLAUDE_CODE_SHELL` already in the environment wins over the launcher.

**The other half of that contract — `claude-exec-shim`:** restoring `LD_PRELOAD` in the tool-call shell re-breaks the one thing that runs the musl binary *from* that shell. Claude Code appends its own `grep` and `find` functions to the shell snapshot it sources into every tool call, and both run the Claude Code binary itself under another `argv[0]` (`ARGV0=ugrep "$CLAUDE_CODE_EXECPATH" …`, `ARGV0=bfs …`), because that binary is multi-call and dispatches on `argv[0]` alone. `$CLAUDE_CODE_EXECPATH` points straight at the musl build, so with `LD_PRELOAD` back every `grep` and `find` in a tool call exits 127 with eleven `symbol not found` lines. Three properties decide the fix:

| Property | Consequence |
|----------|-------------|
| The snapshot's functions are appended *after* `~/.zshenv` is sourced | Defining `grep`/`find` in an rc file cannot win — the snapshot's definitions always override them |
| The functions read `$CLAUDE_CODE_EXECPATH` at call time, and `~/.zshenv` runs before the snapshot | The path they `exec` is the only lever, so the Android block repoints it |
| The kernel replaces `argv[0]` with the interpreter path when it runs a `#!` file | A wrapper *script* cannot sit in between: `ugrep` would be lost and the binary would start as the Claude CLI. Only a real executable passes `argv` through untouched |

So `.chezmoiscripts/run_after_android-007-build-claude-exec-shim.sh` compiles a ~30-line C program to `~/.local/bin/claude-exec-shim`, and `dot_zshenv.tmpl` points `$CLAUDE_CODE_EXECPATH` at it while parking the real path in `TERMUX_CLAUDE_EXEC_TARGET`. The shim parks `LD_PRELOAD` under the same `TERMUX_ETC_LD_PRELOAD` name and `execv`s the target with `argv` untouched. It is the `claude` wrapper's job done at a level where `argv[0]` survives — the wrapper stays in charge of the CLI itself (`termux-etc-mount`, wake lock, updates), which the shim deliberately does not do, because `ugrep` and `bfs` are leaf processes that need no `/etc` redirection.

Both guards in the `.zshenv` block matter: a shell nested under a tool call inherits the repointed value and must not park the shim as its own target, and a missing shim (an apply that has not built it yet) must leave `$CLAUDE_CODE_EXECPATH` alone. `clang` is why this is a `run_after_` script rather than a `run_once_before_` wrapper — it is installed by `run_once_before_android-002`, so the build cannot happen before it.

**Diagnosing a phantom kill:** count forked children with `ps -A -o pid,ppid,cmd | grep com.termux | wc -l`. At ~30 you are saturated regardless of free RAM — check `free -m` to rule out real memory pressure, then look for orphans (`ppid == 1`) that should have been reaped.

**Manual Android settings:** Exclude Termux from battery optimization (`Unrestricted`), set animation scales to `0.5x`, enable RAM Plus if available.

### Never Let a Go Module Cache Land in `$TMPDIR`

Termux clears `$TMPDIR` from `TermuxService.onDestroy()`. That routine collects one stack trace per entry it fails to delete and then stringifies the whole batch, so a directory full of undeletable files turns app shutdown into an `OutOfMemoryError` — the heap growth limit is 256 MB and ~16k failures produced a 98 MB string.

Go module caches are exactly that kind of directory: entries are written as `0400` files inside `0500` directories, and unlinking a child needs its *parent* writable, so `rm -rf` fails with `EACCES` on every one. Anything cleaning `$TMPDIR` hits the same wall.

They get there because Go derives `GOMODCACHE` from `GOPATH`, and the pipelines Go scripts set `GOPATH="$(pwd)/.go"` when it is unset. Run `make test` with a cwd under `$TMPDIR` — Claude Code scratchpads live at `$TMPDIR/claude-<pid>/...` — and the cache is created there.

| Half | Mechanism |
|------|-----------|
| Prevention | `dot_zshenv.tmpl` exports `GOMODCACHE="$HOME/go/pkg/mod"`, so no `GOPATH` a script picks can move the cache |
| Cleanup | `.chezmoiscripts/run_after_android-005-prune-tmp-modcache.sh` chmods and removes any `*/pkg/mod` still found under `$TMPDIR` |

Both are needed: the pin cannot retroactively remove caches left by older revisions, nor reach a tool that exports its own `GOMODCACHE`. When deleting one by hand, always `chmod -R u+w` first.

**Diagnosing it:** `find "$TMPDIR" ! -writable | wc -l`. Anything in the thousands will crash Termux on exit. A telltale sign in the crash report is an *identical* allocation size across separate crashes — the file set is unchanged, so the string is deterministic.

## Codex CLI on Termux

`npm install -g @openai/codex` cannot work on Termux, so do not retry it there: the package is a Node launcher plus one optional dependency per platform, and `@openai/codex-linux-arm64` declares `os: linux` in its `package.json` while Termux's Node reports `android`. npm skips it silently and the launcher throws `Missing optional dependency`. The Android installer (`install_codex_cli`) removes such an install, and `run_once_before_android-001f-create-codex-wrapper.sh` provides `~/.local/bin/codex` instead, which runs the GitHub release's `codex-aarch64-unknown-linux-musl` binary — a **static** executable, so unlike Claude Code it needs no musl loader and no `patchelf`.

The wrapper encodes five Termux facts, each verified on a device:

| Fact | Consequence in the wrapper |
|------|----------------------------|
| musl resolves DNS by reading `/etc/resolv.conf` through direct syscalls, and Android has no such file | The binary runs through `termux-etc-mount` (Tier 3), like `claude`. Tier 2 (`termux-etc-seccomp`) is wrong here: its `SIGSYS -> ENOSYS` rewrite reaches every descendant, and Codex spawns Node for tool calls |
| Codex (rustls) probes the usual CA bundle paths with `stat()`, which Tier 3 does not redirect (`openat` only), so every handshake fails with `invalid peer certificate: UnknownIssuer` | `SSL_CERT_FILE` defaults to `$PREFIX/etc/tls/cert.pem` |
| The Linux sandbox is bubblewrap, which needs unprivileged user namespaces; Android's SELinux policy denies them (`unshare(CLONE_NEWUSER)` returns `EINVAL`), so `read-only` and `workspace-write` panic before running any command | `-c 'sandbox_mode="danger-full-access"'` is prepended to every launch unless `CODEX_WRAPPER_KEEP_SANDBOX=1`. A `--sandbox` on the command line still wins; a `-c` of your own has to come *before* the subcommand (`codex -c key=value exec …`), because Codex's `-c` is per parse level and one given after the subcommand replaces the wrapper's whole override list instead of merging with it. Approval prompts are unaffected |
| `termux-etc-mount` drops `LD_PRELOAD` before the `exec`, and Codex starts its tool-call shells itself — `$PREFIX/bin/bash -lc "<cmd>"`, because it resolves the shell from the password database (`getpwuid_r` → `$PREFIX/bin/login`, which names no shell it knows) and never from `$SHELL` — so `~/.zshenv` is not even sourced and every `#!/usr/bin/env` script a tool call runs dies with `bad interpreter` | `-c 'shell_environment_policy.set.LD_PRELOAD=…'` is prepended with the parked value (falling back to `termux-exec` alone). Codex applies that policy to the environment tool commands are spawned with, so `termux-exec` is mapped before the shell's first `execve` whichever shell Codex picks. `CODEX_WRAPPER_KEEP_LD_PRELOAD=1` opts out |
| `codex update` refuses a manual install (`Could not detect the Codex installation method`) | The wrapper resolves the latest release from the `releases/latest` redirect, keeps builds under `~/.local/share/codex/versions/<X.Y.Z>/codex`, checks once per 24h in the background, retains three builds, and silences Codex's own startup update nag while its updater is active. `CODEX_WRAPPER_NO_AUTO_UPDATE=1` and `CODEX_WRAPPER_FORCE_VERSION=X.Y.Z` override this |

Log in with `codex login --device-auth` on the phone: it prints a code to enter at the URL it shows, in any browser, while the default `codex login` expects to open a browser and receive a callback on `localhost:1455`. The `LD_PRELOAD` contract above applies with a third leg of its own: `termux-etc-mount` parks the value and the wrapper hands it to the tool-call shells through Codex's shell environment policy, because those shells are `bash -lc` spawned by Codex and never source `dot_zshenv.tmpl`.

## Sentry CLI (npm, no wrapper)

`sentry` is the new Sentry CLI from [`getsentry/cli`](https://github.com/getsentry/cli), not the classic Rust `sentry-cli`. The Linux/WSL and Android installers both install it through the shared `install_sentry_cli` in `lib-install-deps.sh` with `npm install -g --ignore-scripts sentry`, and there is deliberately **no** Termux wrapper (Windows does not get it):

| Fact | Consequence |
|------|-------------|
| The official install script (`cli.sentry.dev/install`) downloads a Bun-compiled `sentry-linux-<arch>` executable linked against glibc; the `-musl` variants stopped shipping after `0.34.0` | On Termux the kernel cannot start it at all (`/lib/ld-linux-aarch64.so.1` does not exist under bionic), so the script dies with `No such file or directory` before `sentry cli setup` runs. Do not retry it there, and do not reach for `glibc-runner` or a musl loader: the npm route removes the need |
| The npm package `sentry` is the same CLI as a plain JavaScript bundle: no platform package, no lifecycle script, `engines.node >= 20` | It runs under Termux's native `nodejs` (bionic) and under NVM on Linux/WSL with one shared function body. Node 22.15+ uses the built-in `node:sqlite` for `~/.sentry/cli.db`; older Node falls back to a bundled WASM driver |
| Node resolves DNS through bionic and reads Termux's CA bundle | No `termux-etc-seccomp`/`termux-etc-mount`, no `SSL_CERT_FILE`, no `LD_PRELOAD` parking. Verified on a device: `sentry cli upgrade --check` reaches the network and reports `Method: npm` |
| `sentry cli upgrade` detects the npm layout from its own path | Updates go through npm; nothing in the versions-directory style of the `claude` and `codex` wrappers is needed |
| npm links `$PREFIX/bin/sentry` to the package's `dist/bin.cjs` and keeps its `#!/usr/bin/env node` shebang | The kernel resolves that path only through `termux-exec` in the calling process. Plain Termux tabs have it; Claude Code tool calls get it from the `claude-zsh` launcher and Codex tool calls from Codex's shell environment policy (see the `LD_PRELOAD` contract above). Before that launcher every `sentry` call made directly from a tool call died with `bad interpreter: /usr/bin/env: no such file or directory` while `zsh -c 'sentry ...'` worked. Do not `termux-fix-shebang` the file as a workaround: `sentry cli upgrade` reinstalls it through npm and undoes that |

Log in with `sentry auth login`: the OAuth flow is a device code entered at a URL, so it works on the phone as-is, and `--token` accepts an API token instead.

npm installs ship neither shell completions nor the agent skill, so `run_onchange_after_linux-007-setup-sentry-cli.sh` and `run_onchange_after_android-006-setup-sentry-cli.sh` run `sentry cli setup --no-modify-path` after the managed files are applied, with `SHELL` pinned to zsh (the CLI installs completions for the shell `SHELL` names, and the first Linux apply runs under bash). Three things about that command are easy to get wrong:

- **`--no-modify-path` only skips the PATH edit.** The zsh completion step still appends `fpath=("<dir>" $fpath)` to `~/.zshrc` unless the file already contains the completion directory as a quoted absolute path. `dot_zshrc.tmpl` therefore renders `"{{ .chezmoi.homeDir }}/.local/share/zsh/site-functions"` into its own `fpath` line before Oh My Zsh runs compinit. A `$HOME`-based line would not satisfy the check, and the CLI's appended line is exactly what the next apply reverts (observed on a device: a manual run appended it, and `chezmoi diff` wanted it gone).
- **The setup runs after the files on purpose.** From `run_once_before` it would edit the previous `~/.zshrc` first, and the file application that follows would stop to ask about an externally modified target.
- **The agent skill lands in `~/.claude/skills/sentry-cli/` only when `~/.claude` exists**: always on Android, where chezmoi manages it; on Linux after Claude Code's first run, added by the next `sentry cli upgrade`, which re-runs the same setup after every upgrade (that is why the scripts are `run_onchange_` and not `run_after_`). aisync leaves the skill alone: its deletion detection covers only files it synced itself, and it prompts before removing anything.

## AI Rules Sync

AI assistant rules (Claude Code, GitHub Copilot CLI, Codex, etc.) are **not** managed by chezmoi. Directories like `~/.claude/` and `~/.codex/` are excluded from chezmoi and synced separately by [`aisync`](https://github.com/rios0rios0/aisync), a Go CLI installed by `install_aisync()` in the Linux/WSL and Android dependency scripts (replaces the legacy `run_after_*-install-ai-rules.*` scripts that used to curl `install-rules.sh` from `rios0rios0/guide` on every apply).

After the dependency installer finishes, run `aisync init`, `aisync source add guide --source-repo rios0rios0/guide --branch generated`, and `aisync pull` to populate the rules. Subsequent `aisync pull` calls refresh them on demand.

## Non-Interactive Shell Guards

These ship to every platform, not only Android: both blocks sit outside the chezmoi platform conditionals, because the behaviour they guard against comes from Claude Code's Bash tool, which snapshots the interactive shell's aliases and functions into its non-interactive runs on Linux/WSL exactly as on Termux.

- `dot_zshenv.tmpl` relaxes `nomatch` for non-interactive shells (`[[ -o interactive ]] || setopt NO_NOMATCH`), so a glob that matches nothing is passed through to the command instead of aborting the whole line. Interactive shells keep the prompt-time error.
- `dot_zshrc.tmpl` replaces the `common-aliases` `rm`/`cp`/`mv -i` aliases with functions, defined right after oh-my-zsh loads, that keep `-i` only when stdin is a terminal. Against a closed stdin `-i` reads EOF and skips the operation with exit 0 — a `cp` that never happened, reported as success.

## Claude Account Rotation (ccswitch)

Claude Code subscription tokens live in `~/.claude/.credentials.json` (not chezmoi-managed on Linux/WSL). [`ccswitch`](https://github.com/rios0rios0/ccswitch) is a Go CLI installed by `install_ccswitch()` in the Linux/WSL dependency script that monitors Claude Code usage (via the `GET /api/oauth/usage` OAuth endpoint) and rotates between enrolled backup accounts when the active account's limits are exhausted.

`dot_zshrc.tmpl` (Linux only) starts the `ccswitch monitor` daemon in interactive shells and wraps `claude` so each launch first runs `ccswitch ensure` — a no-network guard that installs the current account's credentials. Enroll each account once with `ccswitch enroll` after logging in via `claude` + `/login`; afterwards rotation is automatic, with no repeated `/login`. The `[ccswitch]` log prefix is emitted by the tool itself.

Both entrypoints run the same `_claude_ensure_account` guard before launching, so rotation applies whichever one is used: `claude` (plain) and `claudex` (`--dangerously-skip-permissions --effort max`). The guard is a no-op when `ccswitch` is absent, keeping both usable on platforms that never install it.

Keep `claudex` a **function**, not an alias: zsh refuses to define a function whose name is already an alias, and aliases are expanded only in interactive shells, so an aliased `claudex` does not exist in scripts, `zsh -c`, or `sudo zsh -c`. Keep its guard call **explicit** too — relying on a bare `claude` to pick up the wrapper works only because a bare command word resolves to a function before a binary, so changing it to `command claude` would silently drop rotation.

**Note:** if `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` is set, Claude Code ignores the rotated OAuth credentials; `ccswitch` warns when it detects this.

## Claude Code Voice Input (WSL)

Voice input (push-to-talk on the spacebar) shells out to a recorder binary, probing three options in order:

1. `arecord` (ALSA) — probed first, but WSL exposes no `/dev/snd`, so this path can never succeed here
2. `sox` **and** `rec` — the working path on WSL
3. neither → voice input is reported unavailable and pauses after repeated failures

WSLg already provides the server half: it exports `PULSE_SERVER=unix:/mnt/wslg/PulseServer` and exposes a
`PulseAudioRDPSource` for the microphone. Only the client half is missing, which is why `sox` **and**
`libsox-fmt-pulse` both sit in the `utilities` array of the Linux dependency installer — plain `sox` cannot
reach the WSLg socket without the PulseAudio format handler, and the `sox` package is what provides `rec`.

The failure message ends with "If WSLg is not available (for example WSL1), run Claude Code in native Windows
instead." **That is not a diagnosis** — it is the tail of case 3 and prints whether or not WSLg is present.
Check for `sox` before concluding anything about WSLg.

`run_once_` keys its state on the SHA256 of the script's *contents*, so editing the `utilities` array changes the
hash and `chezmoi apply` re-runs the **whole** installer on machines that already ran the previous version. That is
how a newly added package reaches them — but budget for the 45-120 minute pass noted above, and do not cancel it
(the `install_*()` guards and apt idempotency make most of it a no-op). To pull in just these two packages ahead of
the next apply: `sudo apt install --no-install-recommends --yes sox libsox-fmt-pulse`.

`dot_zshrc.tmpl` must **not** alias `rec` or `play` — both are SoX binaries (`/usr/bin/rec` and `/usr/bin/play`,
from the `sox` package). asciinema previously took both names and shadowed SoX; it now uses the non-conflicting
`record` / `replay` pair. Claude Code was never affected (it spawns via `PATH`, not through an interactive
shell), but the aliases broke testing capture by hand:

```bash
rec -c 1 -r 16000 /tmp/mic-test.wav trim 0 3 && play /tmp/mic-test.wav
```

If SoX picks the wrong driver, force it with `AUDIODRIVER=pulse`.

## Encryption Setup

- Private key: `~/.ssh/chezmoi`
- Recipients file: `~/.age_recipients` (template at `dot_age_recipients.tmpl`)
- Encrypted files end in `.age` and must show `"age encrypted file, ASCII armored"` when checked with `file`

<!-- chlog:start -->
## Changelog (chlog) — MANDATORY

If the repository you are working in uses chlog (a `.chlog.yaml` or `.chlog.yml`
config file, or a `.changes/` directory, exists at the project root), the
following is binding and ALWAYS applies: whenever you make ANY change, you MUST
create a changelog fragment as part of the same change — automatically, without
being asked, before committing.

- Do NOT edit CHANGELOG.md directly; it is generated from fragments.
- Create the fragment with:
  `chlog new --kind <Kind> --body "<imperative description>"`
- Valid kinds: Added, Changed, Deprecated, Removed, Fixed, Security
- Choose the kind that best matches the change (e.g., new feature → Added,
  bug fix → Fixed, behavior change → Changed, removal → Removed, security fix → Security).
- If the change is backward-INCOMPATIBLE with the public API (a breaking
  change), you MUST add the `--breaking` flag:
  `chlog new --kind <Kind> --breaking --body "<description>"`.
  This is the ONLY thing that triggers a major version bump — the kind alone
  never does (per SemVer, major = incompatible change). When unsure whether a
  change breaks compatibility, ask the user instead of guessing.
- Fragments are YAML files in `.changes/unreleased/`; stage them with your commit.
- `chlog check` fails the build when a fragment is missing — never skip it.
<!-- chlog:end -->
