<h1 align="center">dotfiles</h1>
<p align="center">
    <a href="https://github.com/rios0rios0/dotfiles/releases/latest">
        <img src="https://img.shields.io/github/release/rios0rios0/dotfiles.svg?style=for-the-badge&logo=github" alt="Latest Release"/></a>
    <a href="https://github.com/rios0rios0/dotfiles/blob/main/LICENSE">
        <img src="https://img.shields.io/github/license/rios0rios0/dotfiles.svg?style=for-the-badge&logo=github" alt="License"/></a>
    <a href="https://sonarcloud.io/summary/overall?id=rios0rios0_dotfiles">
        <img src="https://img.shields.io/sonar/coverage/rios0rios0_dotfiles?server=https%3A%2F%2Fsonarcloud.io&style=for-the-badge&logo=sonarqubecloud" alt="Coverage"/></a>
    <a href="https://sonarcloud.io/summary/overall?id=rios0rios0_dotfiles">
        <img src="https://img.shields.io/sonar/quality_gate/rios0rios0_dotfiles?server=https%3A%2F%2Fsonarcloud.io&style=for-the-badge&logo=sonarqubecloud" alt="Quality Gate"/></a>
    <a href="https://www.bestpractices.dev/projects/12024">
        <img src="https://img.shields.io/cii/level/12024?style=for-the-badge&logo=opensourceinitiative" alt="OpenSSF Best Practices"/></a>
</p>

Cross-platform dotfiles managed with [chezmoi](https://www.chezmoi.io/), [1Password CLI](https://developer.1password.com/docs/cli/) for secrets, and [age](https://github.com/FiloSottile/age) for file encryption. Targets three platforms: **Linux (Kali on WSL)**, **Windows 11**, and **Android (Termux)**.

![Kali Linux on WSL](.docs/wsl-with-kali.png)
![PowerShell 7 on Windows](.docs/windows-with-powershell-7.png)
![Termux on Android](.docs/android-with-termux.png)

## What's Managed

### Shells and Prompt

| Component | Linux (WSL) | Windows | Android (Termux) |
|-----------|-------------|---------|------------------|
| Shell | Zsh | PowerShell 7 | Zsh |
| Framework | Oh My Zsh + ZINIT | Oh My Posh | Oh My Zsh + ZINIT |
| Theme | Powerlevel10k | Oh My Posh (custom) | Powerlevel10k |

### Version Managers

- **GVM** (Go), **NVM** (Node.js), **Pyenv** (Python), **SDKMAN** (Java, Gradle, Maven, Kotlin), **Cargo** (Rust)
- Automatic version switching via `dot_scripts/linux-engineering-version-manager.sh` (detects `go.mod`, `.nvmrc`, `pyproject.toml`)

### Cloud and Infrastructure

- **Kubernetes**: kubectl, krew (ctx/ns plugins), kubeconfig auto-detection
- **Terraform** + Terragrunt
- **AWS CLI**, **Azure CLI**, **Heroku CLI**, **GitHub CLI**
- **Docker** + Docker Compose

### Development Tools

- **Cursor** (AI editor with Docker-based MCP servers on Linux)
- **Claude Code** + **Gemini CLI** (AI coding assistants)
- **Neovim** with AstroVim (Android)

### Security and Pentesting

- John the Ripper, SQLMap, VHostScan, dirsearch, StegCracker, stegbrute

### Utilities

- eza (ls replacement), bat (syntax highlighting), ripgrep, jq/yq, ffmpeg, ImageMagick, pdftk, asciinema, Speedtest CLI, CycloneDX (SBOM)

## Platform Matrix

| Aspect | Linux (WSL/Kali) | Windows 11 | Android (Termux) |
|--------|------------------|------------|------------------|
| Shell | Zsh + Oh My Zsh + p10k | PowerShell + Oh My Posh | Zsh + Oh My Zsh + p10k |
| Scripts | `.sh` (bash) | `.ps1` (PowerShell) | `.sh` (bash) |
| 1Password | `op` wrapper (calls `op.exe` from WSL) | Native `op.exe` | `op` wrapper (proot Alpine) |
| Docker | Native | Docker Desktop | N/A (proot wrappers) |
| MCP Config | `~/.cursor/mcp.json` (Docker) | N/A | `~/.config/mcphub/servers.json` (npx) |
| Editor | Any | Cursor | Neovim (AstroVim) |

## Installation

### Prerequisites

All platforms require:
- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [age](https://github.com/FiloSottile/age)
- [1Password CLI](https://developer.1password.com/docs/cli/get-started)

### Kali Linux on WSL

```sh
sudo apt install git age
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply rios0rios0
```

### PowerShell 7 on Windows

```powershell
winget install Microsoft.PowerShell
winget install Git.Git           # if ASLR is enabled, install from https://git-scm.com/download/win
winget install FiloSottile.age   # add the age executable to PATH manually
winget install 1password-cli

Set-ExecutionPolicy RemoteSigned -Scope Process
chezmoi init --apply rios0rios0
```

### Termux on Android

> **Important**: Install Termux from [F-Droid](https://f-droid.org/en/packages/com.termux/), not the Play Store ([reason](https://www.reddit.com/r/termux/comments/zu8ets/do_not_install_termux_from_play_store/)).

```sh
apt install git chezmoi
chezmoi init --apply rios0rios0
```

> **Note**: Full dependency installation takes 45-120 minutes. Do not cancel mid-execution.

## Repository Structure

```
.chezmoiscripts/         # 21 platform-specific setup scripts (run_once_before_*, run_after_*)
.chezmoitemplates/       # Shared template fragments (font installer, MCP server logic, username)
dot_claude/              # Claude Code config (settings, permissions, trust) -> ~/.claude/
dot_config/              # XDG config (mcphub MCP servers for Android) -> ~/.config/
dot_cursor/              # Cursor MCP config (Docker-based, Linux only) -> ~/.cursor/
dot_docker/              # Docker daemon config -> ~/.docker/
dot_scripts/             # Utility scripts (version manager, credential loader, git sync, etc.)
dot_ssh/                 # SSH config, keys, signing (1Password-backed) -> ~/.ssh/
dot_aws/                 # Encrypted AWS credentials -> ~/.aws/
dot_azure/               # Encrypted Azure profile -> ~/.azure/
dot_kube/                # Encrypted Kubernetes configs -> ~/.kube/
AppData/                 # Windows Terminal settings (Windows only)
modify_dot_claude.json.tmpl  # MCP server config for Claude Code -> ~/.claude.json
```

Chezmoi translates `dot_` prefixes to `.` in the target path (e.g., `dot_zshrc.tmpl` becomes `~/.zshrc`).

## Secrets and Encryption

This repository uses a layered approach to secrets management:

- **1Password CLI** fetches SSH keys, GPG keys, and credentials at template render time via `onepasswordRead` / `onepassword` template functions
- **Age encryption** protects sensitive files at rest (AWS, Azure, Kubernetes configs, npmrc). Private key stored at `~/.ssh/chezmoi`, recipients at `~/.age_recipients`
- **Per-device SSH/GPG signing** matches keys by hostname against 1Password items ("Active SSHs", "Active GPGs")

Encrypted files end in `.age` and are automatically decrypted during `chezmoi apply`.

## Claude Code Configuration

This repository manages four Claude Code configuration files. Each targets a different file on disk because Claude Code separates instructions, permissions, and MCP servers into distinct subsystems that cannot be consolidated into a single file.

| Repository Path | Deployed To | Purpose |
|-----------------|-------------|---------|
| `dot_claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | Global instructions loaded into every Claude Code session (WSL preferences) |
| `dot_claude/modify_settings.json.tmpl` | `~/.claude/settings.json` | Default permission rules (`allow` list) and effort level |
| `dot_claude/modify_dot_claude.json.tmpl` | `~/.claude/.claude.json` | Auto-trusts project directories to skip the trust dialog |
| `modify_dot_claude.json.tmpl` (root) | `~/.claude.json` | User-scoped MCP servers (GitHub, Azure DevOps, SonarQube, Kubernetes) |

The three `modify_*.tmpl` files are chezmoi [modify scripts](https://www.chezmoi.io/reference/source-state-attributes/#modify): they receive the current file content on stdin, merge desired settings via embedded Python, and output the result. This preserves any user-added configuration while ensuring defaults are always present.

> **Note**: The `dot_claude/` directory is deployed only on **Windows** and **Android** (excluded on Linux via `.chezmoiignore`).

### Gitignore Design

The global `~/.gitignore` (managed via `dot_gitignore`) ignores `.claude/` by default to prevent accidentally committing Claude Code's internal files (caches, memory, `settings.local.json`) across all repositories. However, `.claude/settings.json` is explicitly un-ignored because Claude Code designates it as team-shared project configuration — meant to be committed alongside the codebase. Personal or machine-specific settings belong in `.claude/settings.local.json`, which remains ignored.

## Chezmoi Conventions

| Prefix/Suffix | Meaning |
|---------------|---------|
| `dot_` | Becomes `.` in target (e.g., `dot_zshrc` becomes `~/.zshrc`) |
| `.tmpl` | Processed as Go template before deployment |
| `encrypted_*.age` | Age-encrypted file, decrypted on apply |
| `run_once_before_*` | Script runs once before file application |
| `run_after_*` | Script runs after every application |
| `private_` | File deployed with restricted permissions |
| `modify_` | Script that merges changes into an existing file |

Platform-specific scripts are prefixed: `linux-*`, `windows-*`, `android-*`. Exclusion rules in `.chezmoiignore` ensure only the correct platform's files are applied.

## Debugging

- Run `chezmoi doctor` to diagnose installation issues
- Run `chezmoi diff` to preview pending changes before applying
- Use `GIT_TRACE=1` for verbose Git output
- Use `chezmoi execute-template < file.tmpl` to test template rendering

### Known Issues

1. **Git stuck on SSH commands (WSL)**: Zsh and Git both use `ssh.exe` from Windows. If `known_hosts` is missing, commands hang. Fix: run `ssh git@<HOST>` once to populate `known_hosts`.

2. **Age decryption errors**: Chezmoi's built-in age support cannot decrypt with SSH keys. The standalone `age` binary is required. Without it:
   ```
   chezmoi: error at line 1: malformed secret key: separator
   ```

3. **Windows path length limit (256 chars)**: WSL interop calls to `.exe` files may fail with `Invalid argument` if the working directory path is too long.

4. **Termux sessions killed with `[Process completed (signal 9)]` (Android 12+)**: Android's **Phantom Process Killer** enforces a system-wide limit of ~32 forked child processes. Heavy CLI tools like Claude Code spawn many Node.js children, quickly exceeding this limit — regardless of available RAM.

   **Fix (Android 14+, no root required):**
   1. Enable Developer Options: `Settings > About Phone > tap "Build Number" 7 times`
   2. Go to `Settings > System > Developer Options`
   3. Enable **"Disable child process restrictions"**

   **Supplementary tips:**
   - Run `termux-wake-lock` to prevent Android from deep-sleeping Termux
   - Use `tmux` instead of multiple Termux tabs — it consolidates all sessions under a single process tree, reducing the visible child process count to Android

   **Additional Android OS settings (no root required):**
   - **Battery optimization:** `Settings > Apps > Termux > Battery > Unrestricted` — prevents Doze mode from throttling Termux
   - **Animation scales:** In Developer Options, set Window/Transition/Animator duration scales to `0.5x` — reduces UI overhead
   - **RAM Plus / Extended RAM:** If available (Samsung: `Settings > Battery and device care > RAM Plus`), enable 4-8GB of virtual RAM
   - **Termux:Boot:** Install from [F-Droid](https://f-droid.org/en/packages/com.termux.boot/), create `~/.termux/boot/start.sh` with `termux-wake-lock` to auto-acquire wake lock on boot

## References

- [chezmoi documentation](https://www.chezmoi.io/user-guide/command-overview/)
- [chezmoi template variables](https://www.chezmoi.io/reference/templates/variables/)
- [chezmoi scripts reference](https://www.chezmoi.io/reference/special-files-and-directories/chezmoiscripts/)
- [Sprig template functions](https://masterminds.github.io/sprig/)
- Inspired by [patrick-5546/dotfiles](https://github.com/patrick-5546/dotfiles), [budimanjojo/dotfiles](https://github.com/budimanjojo/dotfiles), [romkatv/dotfiles-public](https://github.com/romkatv/dotfiles-public)

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

See [LICENSE](LICENSE) for details.
