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
- `onepasswordRead` / `onepassword` — Fetch secrets from 1Password

## Important Timing Constraints

Dependency installation scripts (`.chezmoiscripts/run_once_before_*-install-dependencies.*`) take **45-120 minutes**. Never cancel them mid-execution. Use timeouts of 120+ minutes when running full installations.

## Encryption Setup

- Private key: `~/.ssh/chezmoi`
- Recipients file: `~/.age_recipients` (template at `dot_age_recipients.tmpl`)
- Encrypted files end in `.age` and must show `"age encrypted file, ASCII armored"` when checked with `file`
