# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

Cross-platform dotfiles managed with **chezmoi** targeting three platforms: **Linux (Kali on WSL)**, **Windows 11**, and **Android (Termux)**. Secrets are managed via **1Password CLI** and sensitive files are encrypted with **age**.

The "build" is `chezmoi apply`. A CI pipeline validates templates, scripts, and platform logic.

## Quality Commands

```bash
make lint                           # shellcheck, Go template syntax, Python, PowerShell, YAML/JSON
make test                           # template rendering (mock op), .chezmoiignore logic, script order
make sast                           # gitleaks secret detection
make lint-shellcheck                # shell scripts only
make lint-templates                 # Go template syntax only
make test-template-render           # template rendering with mock 1Password
make test-chezmoiignore             # platform file inclusion logic
make test-script-order              # script dependency ordering
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
| MCP config | `dot_cursor/` (Docker-based) | N/A                     | `dot_config/mcphub/` (npx-based) |
| 1Password  | Native `op` CLI              | Native `op` CLI         | `termux-etc-seccomp` wrapper at `.local/bin/op` |

## Key Files

- **`.chezmoi.yaml.tmpl`** — Chezmoi config: 1Password and age encryption settings
- **`dot_gitconfig.tmpl`** — Git config with 1Password SSH signing, per-device SSH keys, platform-specific paths
- **`dot_zshrc.tmpl`** — Shell config: ZINIT plugins, version managers (GVM/NVM/Pyenv/SDKMAN/Cargo), Docker aliases, Kubernetes tools
- **`dot_zshenv`** — PATH setup for version managers (critical for IDE integration)
- **`.chezmoiignore`** — Platform-conditional file exclusion rules
- **`.chezmoitemplates/`** — Shared template fragments (font installer, username)

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

Existing prefixes: `gitconfig`, `ssh-config`, `allowed-signers`, `authorized-keys`, `docker-config`, `wakatime`, `age-recipients`, `android-ssh-keys`, `linux-gpg-keys`, `windows-ssh-keys`, `windows-pem-keys`, `wrapper`, `op-wrapper`, `gh-wrapper`, `gh-copilot`, `export-key`, `extract-folders`, `clone-tools`, `configure-deps`, `ssh-known-hosts`, `copy-appdata`, `termux-config`, `fonts`, `kube-config`, `mcp-servers`, `claude-trust`, `claude-settings`, `claude-code-patch`, `git-sync`, `git-clone`, `ggshield-auth`, `ggshield-hook`

## Important Timing Constraints

Dependency installation scripts (`.chezmoiscripts/run_once_before_*-install-dependencies.*`) take **45-120 minutes**. Never cancel them mid-execution. Use timeouts of 120+ minutes when running full installations.

### Android Wrapper Timing

On Android, tool wrappers (`op`, `gh`) **must be `run_once_before` scripts**, NOT chezmoi-managed files under `dot_local/bin/`. This is because `run_once_before` scripts execute before chezmoi applies managed files. The install-dependencies script (`run_once_before_android-002`) calls `op` and `gh` during installation — if these wrappers were chezmoi-managed files, they wouldn't exist yet when the install script runs, causing crashes.

The wrapper scripts follow a strict execution order:
1. `android-001-create-wrapper.sh` — generic `termux-etc-seccomp` wrapper (all tool wrappers depend on this)
2. `android-001a-create-op-wrapper.sh` — `op` wrapper (needed by chezmoi templates)
3. `android-001b-create-gh-wrapper.sh` — `gh` wrapper (needed by install script for copilot)
4. `android-002-install-dependencies.sh.tmpl` — installs binaries and extensions

The generic `termux-etc-seccomp` wrapper is the only exception — it exists as BOTH a bootstrap script (for timing) AND a chezmoi-managed file (`dot_local/bin/executable_wrapper`) to keep it updated on subsequent applies.

## Android Performance (Termux)

Android 12+ includes a **Phantom Process Killer** that enforces a system-wide limit of ~32 forked child processes. Claude Code spawns many Node.js children, so running 3+ sessions causes `[Process completed (signal 9)]` — this is SIGKILL from the phantom killer, not OOM.

**Fix (Android 14+, no root required):** Enable `Settings > System > Developer Options > "Disable child process restrictions"`.

**Supplementary:** Run `termux-wake-lock` to prevent deep sleep. Use `tmux` instead of multiple Termux tabs to consolidate process trees.

**Environment tuning** (set in `dot_zshenv.tmpl`, Android-only):
- `UV_THREADPOOL_SIZE=16` — increases Node.js libuv thread pool from default 4, critical for Claude Code I/O
- `MALLOC_ARENA_MAX=2` — reduces glibc memory arena fragmentation on mobile

**Manual Android settings:** Exclude Termux from battery optimization (`Unrestricted`), set animation scales to `0.5x`, enable RAM Plus if available.

## Encryption Setup

- Private key: `~/.ssh/chezmoi`
- Recipients file: `~/.age_recipients` (template at `dot_age_recipients.tmpl`)
- Encrypted files end in `.age` and must show `"age encrypted file, ASCII armored"` when checked with `file`
