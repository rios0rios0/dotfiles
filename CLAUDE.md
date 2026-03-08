# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

Cross-platform dotfiles managed with **chezmoi** targeting three platforms: **Linux (Kali on WSL)**, **Windows 11**, and **Android (Termux)**. Secrets are managed via **1Password CLI** and sensitive files are encrypted with **age**.

There is no traditional build/lint/test pipeline. The "build" is `chezmoi apply`.

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
| Docker     | Native                       | N/A                     | Proot wrapper                    |
| MCP config | `dot_cursor/` (Docker-based) | N/A                     | `dot_config/mcphub/` (npx-based) |
| 1Password  | Native `op` CLI              | Native `op` CLI         | Proot wrapper at `.local/bin/op` |

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

"Active *" items (e.g., "Active SSHs") are Secure Notes in the personal vault. Item titles are listed **one per line in the notes field** (`notesPlain`). Templates read notes, filter by device locally, and only fetch matching items by title — avoiding unnecessary API calls.

**Notes-based pattern with device filtering:**
```go
{{- $notes := "" -}}
{{- range (onepassword "Active SSHs" "personal" "my").fields -}}
  {{- if eq .label "notesPlain" -}}
    {{- $notes = .value -}}
  {{- end -}}
{{- end -}}
{{- range splitList "\n" $notes -}}
  {{- $title := . | trim -}}
  {{- if ne $title "" -}}
    {{- $parts := split "@" $title -}}
    {{- $device := index $parts "_0" -}}
    {{- if eq $device $deviceName -}}
      {{- $item := onepassword $title "Private" "my" -}}
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

Existing prefixes: `gitconfig`, `ssh-config`, `allowed-signers`, `authorized-keys`, `docker-config`, `wakatime`, `age-recipients`, `android-ssh-keys`, `linux-gpg-keys`, `windows-ssh-keys`, `windows-pem-keys`, `op-wrapper`, `export-key`, `extract-folders`, `clone-tools`, `configure-deps`, `ssh-known-hosts`, `copy-appdata`, `termux-config`, `fonts`, `kube-config`, `mcp-servers`, `claude-trust`, `claude-settings`, `claude-code-patch`, `git-sync`

## Important Timing Constraints

Dependency installation scripts (`.chezmoiscripts/run_once_before_*-install-dependencies.*`) take **45-120 minutes**. Never cancel them mid-execution. Use timeouts of 120+ minutes when running full installations.

## Encryption Setup

- Private key: `~/.ssh/chezmoi`
- Recipients file: `~/.age_recipients` (template at `dot_age_recipients.tmpl`)
- Encrypted files end in `.age` and must show `"age encrypted file, ASCII armored"` when checked with `file`
