# Dotfiles Repository - Personal Configuration Management
Cross-platform dotfiles repository managed with [chezmoi](https://www.chezmoi.io/) for Kali Linux (WSL), Windows 11, and Android (Termux). Uses 1Password CLI for secrets and age encryption for sensitive files.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Bootstrap and Apply Dotfiles Configuration
**CRITICAL**: This repository does NOT have a traditional "build" process. It applies configuration files across systems.

#### Linux/WSL Prerequisites and Installation
- Install prerequisites:
  ```bash
  sudo apt update
  sudo apt install -y git age
  ```
- Install chezmoi and apply dotfiles:
  ```bash
  sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply rios0rios0
  ```
- **TIMING**: Initial installation takes 15-45 minutes depending on dependencies. NEVER CANCEL - Set timeout to 60+ minutes.

#### Windows Prerequisites and Installation
- Install PowerShell 7:
  ```powershell
  winget install Microsoft.PowerShell
  ```
- Install basic dependencies:
  ```powershell
  winget install Git.Git
  winget install FiloSottile.age  # Manually add to PATH
  winget install AgileBits.1Password.CLI
  ```
- Apply dotfiles:
  ```powershell
  Set-ExecutionPolicy RemoteSigned -Scope Process
  chezmoi init --apply rios0rios0
  ```

#### Android/Termux Installation
- Install from F-Droid (NOT Google Play Store):
  ```bash
  apt install git chezmoi
  chezmoi init --apply rios0rios0
  ```
- Android setup includes a proot/Alpine wrapper for running Linux binaries (1Password CLI, terraform, etc.) that cannot run natively on Termux.

### Dependency Installation Scripts
The repository includes comprehensive dependency installation scripts that run automatically during chezmoi application. Scripts are numbered to control execution order.

#### Script Execution Order

Scripts execute in this order per platform (numbers = execution priority):

| Order | Linux (WSL)                                            | Windows                          | Android (Termux)                       |
|-------|--------------------------------------------------------|----------------------------------|----------------------------------------|
| 001   | `create-op-wrapper.sh`                                 | `install-dependencies.ps1`       | `create-op-wrapper.sh`                 |
| 002   | `install-dependencies.sh` *(also baremetal variant)*   | `configure-dependencies.ps1`     | `install-dependencies.sh.tmpl`         |
| 003   | `configure-dependencies.sh`                            | `install-fonts.ps1`              | `install-fonts.sh.tmpl`                |
| 004   | `install-fonts.sh.tmpl`                                | `export-private-key.ps1`         | —                                      |
| 005   | `export-private-key.sh`                                | —                                | —                                      |

After all `run_once_before_*` scripts, `run_once_after_*` scripts execute once, then `run_after_*` scripts execute on every `chezmoi apply`.

#### Linux Dependencies (`.chezmoiscripts/run_once_before_linux-002-install-dependencies.sh`)
- **TIMING**: Takes 45-90 minutes to complete. NEVER CANCEL - Set timeout to 120+ minutes.
- Installs system packages: git, curl, zip/unzip, age, gpg, zsh, eza, sqlite3, gcc, make, etc.
- Installs development tools via dedicated functions:
  - **Oh My Zsh** — default Zsh framework
  - **GVM** — Go version manager (installs go1.25.5 by default)
  - **kubectl** (v1.32 channel) + **krew** (with `ctx` and `ns` plugins)
  - **Terraform** (HashiCorp apt repository) + **Terragrunt** (v0.76.6)
  - **SDKMAN** — Java/Gradle ecosystem (installs latest Java and Gradle)
  - **NVM** (v0.40.2) — Node.js version manager (installs LTS + corepack)
  - **Pyenv** — Python version manager (installs Python 3.13.2)
  - **Cursor CLI** — AI code editor CLI
  - **Claude CLI** (`@anthropic-ai/claude-code` npm package)
  - **Gemini CLI** (`@google/gemini-cli` npm package)
  - **GitHub CLI** (gh, via apt repository)
  - **Azure CLI** (via pip, installed into pyenv Python)
  - **ggshield** (GitGuardian CLI, via pipx) — installs a global pre-commit hook script at `~/.local/share/ggshield/git-hooks/pre-commit`; `core.hooksPath` in `~/.gitconfig` points all repos there
  - **Speedtest CLI** (Ookla, via packagecloud)
- Each tool installation can take 5-15 minutes individually
- **Critical**: Script requires internet access for downloading tools

#### Linux Baremetal Dependencies (`.chezmoiscripts/run_once_before_linux-002-install-dependencies(baremetal).sh`)
- Only runs on native Linux (skips automatically on WSL and Android)
- Installs GUI/desktop applications: barrier, bleachbit, GIMP, Octave, scrcpy, VLC, pdftk
- Installs Genymotion Android emulator

#### Linux Configuration (`.chezmoiscripts/run_once_before_linux-003-configure-dependencies.sh`)
- Creates `~/.local/bin/bat` symlink (workaround for Debian's `batcat` naming)

#### Android Dependencies (`.chezmoiscripts/run_once_before_android-002-install-dependencies.sh.tmpl`)
- **TIMING**: Takes 45-90 minutes. NEVER CANCEL.
- Installs Termux packages: git, curl, age, eza, sqlite, vim, neovim, zsh, proot, proot-distro, etc.
- Sets up proot/Alpine wrapper for running Linux binaries natively
- Installs: Oh My Zsh, GVM, terra (custom wrapper for terraform/terragrunt), kubectl (ARM64), SDKMAN, NVM, pyenv
- Installs: Claude CLI, Gemini CLI, 1Password CLI (ARM64 binary), GitHub CLI, Azure CLI (via pip)
- Configures NeoVim with AstroVim template (`~/.config/nvim`)
- Configures Termux DNS (8.8.8.8, 8.8.4.4, 1.1.1.1)

#### Windows Dependencies (`.chezmoiscripts/run_once_before_windows-001-install-dependencies.ps1`)
- **TIMING**: Takes 30-60 minutes to complete. NEVER CANCEL - Set timeout to 90+ minutes.
- Uses winget with explicit package IDs (checks already-installed packages before installing)
- Installs: 1Password + CLI, age, Git, Oh My Posh, PowerShell 7, WSL, Windows Terminal
- Installs hardware tools: CPU-Z ROG, AIDA64 Extreme, Logitech G HUB, Brother drivers, PerformanceTest
- Installs utilities: Adobe Reader, GIMP, Notepad++, Spotify, VirtualBox, Grammarly, etc.
- Installs development: Cursor, Claude Code, NVM for Windows, Docker Desktop, GitHub CLI, JetBrains Toolbox, Postman, ripgrep, jq, yq, bat, etc.
- Installs gaming: Steam, Epic Games, EA Desktop, GOG Galaxy
- Installs npm CLI tools: `@google/gemini-cli`

#### Windows Configuration (`.chezmoiscripts/run_once_before_windows-002-configure-dependencies.ps1`)
- Installs/updates Kali Linux WSL distro and sets it as default

#### Font Installation
- All platforms install MesloLGS NF (for Powerlevel10k) and Nerd Fonts (FiraCode, Meslo)
- Linux: `run_once_before_linux-004-install-fonts.sh.tmpl` → installs to `~/.fonts`
- Windows: `run_once_before_windows-003-install-fonts.ps1` → installs to Windows Fonts directory (requires admin)
- Android: `run_once_before_android-003-install-fonts.sh.tmpl`
- Shared font library: `.chezmoitemplates/lib-install-fonts.sh`

#### Private Key Export
- Linux: `run_once_before_linux-005-export-private-key.sh` — reads `op://personal/Chezmoi Key/private key` from 1Password, writes to `~/.ssh/chezmoi`
- Windows: `run_once_before_windows-004-export-private-key.ps1` — same, writes to `~\.ssh\chezmoi`
- Android: Key is retrieved by the `op` wrapper during chezmoi template rendering

#### Post-Apply Scripts (`run_once_after_*` and `run_after_*`)
- `run_once_after_linux-001-extract-compressed-folders.sh` — extracts `.tar.gz` archives for `~/.histdb`, `~/.john`, `~/.kube/config-files`, `~/.sqlmap`
- `run_once_after_linux-002-clone-pentesting-tools.sh` — clones pentesting tools (VHostScan, dirsearch, StegCracker, stegbrute) to `~/Development/Tools/`
- `run_once_after_windows-001-create-ssh-known-hosts.ps1` — pre-populates `~/.ssh/known_hosts` for GitHub, GitLab, Azure DevOps, Bitbucket (avoids SSH freeze in WSL)
- `run_after_linux-001-execute-chezmoi-templates.sh` — re-processes `~/.scripts/*-template.sh` files through `chezmoi execute-template`
- `run_after_linux-002-import-gpg-keys.sh.tmpl` — imports GPG keys from 1Password (device note, `gpg:` entries)
- `run_after_linux-004-install-ggshield-hook.sh` — (re)generates the ggshield global pre-commit hook script; idempotent
- `run_after_windows-001-create-ssh-public-keys.ps1.tmpl` — creates SSH public key files from 1Password (device note, `ssh:` entries)
- `run_after_windows-002-create-ssh-pems.ps1.tmpl` — creates SSH PEM files on Windows (device note, `pem:` entries)
- `run_after_windows-003-copy-app-data-files.ps1.tmpl` — copies files from `AppData/` in the repo to `~\AppData\` on Windows (directory names use `+` as wildcard for version-specific paths)
- `run_after_android-001-create-ssh-keys.sh.tmpl` — creates SSH private/public key files from 1Password (device note, `ssh:` entries)

#### Manual Validation After Installation
- Verify shell configuration: `zsh --version` (Linux/Android) or `pwsh --version` (Windows)
- Test Oh My Zsh/p10k theme: Open new terminal and verify Powerlevel10k prompt appears
- Verify age encryption: `age --version`
- Test chezmoi: `chezmoi status` should show managed files
- Verify 1Password CLI: `op --version` (requires authentication setup first)
- **File format validation**: `file encrypted_*.age` should show "age encrypted file, ASCII armored"
- **Script permissions**: Ensure `.chezmoiscripts/*.sh` files are executable

## Core Repository Structure

### Repository Files and Structure
- `dot_*` files: Managed dotfiles (become `.filename` in home directory)
- `dot_*.tmpl`: Template files processed by chezmoi (e.g., `dot_zshrc.tmpl` → `~/.zshrc`)
- `encrypted_*.age`: Encrypted files using age encryption (format: "age encrypted file, ASCII armored")
- `.chezmoi.yaml.tmpl`: Main chezmoi config — sets age encryption and platform-specific `op` command path
- `.chezmoiignore`: Platform-conditional file exclusion (uses Go templates with `.chezmoi.os`)
- `.chezmoiscripts/`: Automated setup and configuration scripts (numbered for execution order)
- `.chezmoitemplates/`: Shared template fragments (`lib-install-fonts.sh`, `username.tmpl`)
- `AppData/`: Windows-specific app config files deployed via `run_after_windows-003-copy-app-data-files.ps1.tmpl`

### Key Managed Files
- `dot_zshrc.tmpl` → `~/.zshrc`: Zsh configuration with ZINIT plugins, version managers, aliases
- `dot_zshenv` → `~/.zshenv`: PATH setup for all Zsh invocations (critical for IDE integration)
- `dot_gitconfig.tmpl` → `~/.gitconfig`: Git config with 1Password SSH/GPG signing, per-device keys
- `dot_p10k.zsh` → `~/.p10k.zsh`: Powerlevel10k theme configuration
- `dot_oh-my-posh.json` → `~/.oh-my-posh.json`: Oh My Posh theme (Windows only)
- `dot_age_recipients.tmpl` → `~/.age_recipients`: Age encryption recipients
- `dot_cursor/mcp.json` → `~/.cursor/mcp.json`: MCP servers for Cursor (Linux, Docker-based)
- `dot_config/mcphub/servers.json.tmpl` → `~/.config/mcphub/servers.json`: MCP servers for mcphub (Android, npx-based)
- `dot_config/nvim/` → `~/.config/nvim/`: NeoVim config (Android only, AstroVim-based)
- `dot_scripts/` → `~/.scripts/`: User utility scripts

### Scripts and Automation
- `.chezmoiscripts/`: All automated setup scripts
- `dot_scripts/`: User scripts deployed to `~/.scripts/`:
  - `linux-engineering-version-manager.sh`: Auto-detects `go.mod`/`.nvmrc`/`pyproject.toml` and switches Go/Node/Python versions
  - `linux-engineering-detect-kube-config-files.sh`: Auto-loads kubeconfig files from `~/.kube/config-files/`
  - `linux-engineering-workspace-information-template.sh.tmpl`: Workspace info template (re-processed on every apply)
  - `linux-toolbox-watch-compress-folders.sh`: Background script watching and compressing `~/.histdb`, `~/.john`, etc.

### Platform Matrix

| Aspect           | Linux (WSL/Kali)                        | Windows 11                          | Android (Termux)                        |
|------------------|-----------------------------------------|-------------------------------------|-----------------------------------------|
| Shell            | Zsh + Oh My Zsh + Powerlevel10k         | PowerShell + Oh My Posh             | Zsh + Oh My Zsh + Powerlevel10k         |
| Prompt theme     | Powerlevel10k (`~/.p10k.zsh`)           | Oh My Posh (`~/.oh-my-posh.json`)   | Powerlevel10k (`~/.p10k.zsh`)           |
| Script extension | `.sh`                                   | `.ps1`                              | `.sh`                                   |
| Editor           | (any)                                   | Cursor / Visual Studio              | NeoVim (AstroVim, `~/.config/nvim/`)    |
| MCP config       | `~/.cursor/mcp.json` (Docker-based)     | N/A                                 | `~/.config/mcphub/servers.json` (npx)   |
| Terraform        | Native binaries                         | N/A                                 | proot/Alpine wrapper (`terra` command)  |
| 1Password CLI    | `~/.local/bin/op` wrapper → `op.exe`    | Native `op.exe`                     | `~/.local/bin/op` → proot Alpine binary |
| Docker           | Native                                  | Docker Desktop                      | N/A (uses proot)                        |
| SSH keys         | `~/.ssh/chezmoi` (age private key)      | `~\.ssh\chezmoi` (age private key)  | Retrieved via `op` wrapper              |

## Validation Scenarios

### Essential Validation Steps
**ALWAYS** perform these validations after making changes:

1. **Configuration Application Test**:
   ```bash
   chezmoi status  # Should show managed files
   chezmoi diff    # Show pending changes
   chezmoi apply --dry-run  # Test without applying
   ```

2. **Shell Configuration Test**:
   - Start new shell session
   - Verify Powerlevel10k prompt appears correctly (Linux/Android)
   - Test aliases: `ll`, `la` (should use eza with icons)
   - Verify PATH includes custom scripts: `echo $PATH`

3. **Encryption Test**:
   ```bash
   age --version  # Verify age is available
   file encrypted_dot_npmrc.age  # Should show "age encrypted file, ASCII armored"
   test -f ~/.ssh/chezmoi && echo "Private key exists" || echo "Missing private key"
   ```

4. **Cross-platform Validation**:
   - Linux: Verify Zsh + Powerlevel10k configuration
   - Windows: Verify PowerShell profile and Oh My Posh theme
   - Android: Verify NeoVim and proot wrapper work
   - Test Windows Terminal settings on Windows

5. **Development Tools Test** (after dependency installation):
   ```bash
   # Verify key tools are installed
   kubectl version --client
   terraform version
   go version
   node --version
   python --version
   ```

### Complete End-to-End Validation Scenario
**After fresh installation, verify the complete workflow**:

1. **Environment Setup Test**:
   ```bash
   # Check shell is properly configured
   echo $SHELL  # Should show zsh path on Linux/Android
   which zsh    # Should find zsh executable
   
   # Verify custom PATH additions
   echo $PATH | grep -q ".local/bin" && echo "Custom PATH configured" || echo "PATH issue"
   ```

2. **Configuration Files Test**:
   ```bash
   # Check dotfiles are properly linked/copied
   ls -la ~/.zshrc ~/.zshenv ~/.gitconfig
   
   # Verify templates were processed correctly
   grep -q "LOCAL_ROOT" ~/.zshrc && echo "Template processed" || echo "Template issue"
   ```

3. **Encryption and Secrets Test**:
   ```bash
   # Test age encryption key exists
   test -f ~/.ssh/chezmoi && echo "Private key exists" || echo "Missing private key"
   
   # Verify chezmoi can decrypt files
   chezmoi cat ~/.npmrc > /dev/null && echo "Decryption works" || echo "Decryption failed"
   ```

4. **Development Environment Test**:
   ```bash
   # Test key development tools
   kubectl version --client 2>/dev/null && echo "kubectl works" || echo "kubectl not available"
   terraform version 2>/dev/null && echo "terraform works" || echo "terraform not available"
   ```

5. **Shell Integration Test**:
   ```bash
   # Test aliases and functions work
   type ll >/dev/null 2>&1 && echo "Aliases configured" || echo "Aliases missing"
   
   # Test version manager auto-switching (run inside a Go project)
   # Should automatically switch Go version when go.mod is detected
   ```

## Common Tasks and Troubleshooting

### Adding New Configuration Files
1. Add file to repository as `dot_filename` or `dot_filename.tmpl`
2. Test with: `chezmoi add ~/.filename`
3. Apply changes: `chezmoi apply`
4. **Always verify**: Check file appears correctly in home directory
5. Update `.chezmoiignore` if the file should be excluded on certain platforms

### Working with Encrypted Files
1. Use age encryption for sensitive files
2. Add encrypted files with: `chezmoi add --encrypt ~/.sensitive-file`
3. **Critical**: Verify private key exists at `~/.ssh/chezmoi`
4. Test decryption: `chezmoi cat ~/.sensitive-file`

### Debugging Installation Issues
- Check chezmoi status: `chezmoi doctor`
- View verbose output: `chezmoi apply --verbose`
- Check script execution: Look for logs in `/tmp/` during installation
- **SSH Issues**: Windows pre-populates known_hosts via `run_once_after_windows-001-create-ssh-known-hosts.ps1`. For Linux, run `ssh -o StrictHostKeyChecking=accept-new git@github.com` manually.

### Known Limitations and Workarounds
1. **WSL SSH Issues**: Git may freeze with SSH against unknown hosts — Windows script pre-populates known_hosts to prevent this
2. **Windows Path Limits**: 256 character limitation when using WSL interoperability
3. **1Password Calls**: Each device has a single "Device: \<deviceName\>" note. The `notesPlain` field lists references to external items (`ssh:`, `gpg:`, `pem:`, `docker:`) fetched from the `Private` vault. Credentials (`cred:`) and workspaces (`ws:`) are stored as fields directly on the device note — no separate items needed. Templates fetch this one note (cached by chezmoi across all template files) and filter by type prefix
4. **Internet Required**: All installations require internet access for downloads
5. **Android NVM/Go**: Native Termux packages are used when GVM build fails due to DNS issues in Termux

## Time Expectations
- **Full fresh installation**: 60-120 minutes
- **Dependency installation only**: 45-90 minutes (Linux), 30-60 minutes (Windows)
- **Configuration application**: 2-5 minutes
- **Individual tool installations**: 5-15 minutes each

**CRITICAL**: NEVER CANCEL long-running installations. Set appropriate timeouts:
- Use 120+ minute timeouts for full installations
- Use 60+ minute timeouts for dependency scripts
- Use 30+ minute timeouts for individual tool installations

## Repository-specific Commands

### Frequent Operations
```bash
# Check what files are managed
chezmoi managed

# See what would change
chezmoi diff

# Apply configuration changes
chezmoi apply

# Update repository
chezmoi update

# Edit configuration file
chezmoi edit ~/.zshrc

# Add new file to management
chezmoi add ~/.new-config-file

# Re-execute a run_once script (delete its hash to force re-run)
chezmoi state delete-bucket --bucket=scriptStates
```

### Template Processing
- Template files use Go template syntax
- Variables available: `.chezmoi.os`, `.chezmoi.arch`, `.chezmoi.hostname`, `.chezmoi.homeDir`
- `.chezmoi.kernel` — used to detect WSL (contains `"microsoft"` string on WSL)
- `onepassword` — fetch full item by name/UUID (preferred — returns `.title` + `.fields`)
- `onepasswordRead` — fetch a single scalar field by `op://` URI (use only for simple direct reads)
- Test templates: `chezmoi execute-template < template-file`

### 1Password Template Pattern
Each device has a single **"Device: \<deviceName\>"** Secure Note in the `personal` vault. The note combines two storage mechanisms:
- **`notesPlain`**: references to external items (`ssh:`, `gpg:`, `pem:`, `docker:`) fetched from the `Private` vault
- **Custom fields**: credential (`cred:NAME`, concealed) and workspace (`ws:NAME`, text) values stored directly on the note

Templates fetch this note (cached by chezmoi) and filter by type prefix. Runtime shell scripts use the `op-loader` to read `cred:` and `ws:` field values directly from the device note — no separate items in the `Private` vault are fetched for these types.

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

**Always guard with `hasKey . "value"`** — some 1Password fields lack a `value` property.

**Do not use `onepasswordItemFields`** — it only returns section-level fields and misses built-in properties like `"public key"` and `"private key"` on SSH Key items. The `onepassword` + `dict`/`set` pattern accesses all fields and chezmoi caches the underlying `op item get` call across all template files automatically.

### Logging Convention
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

Existing prefixes: `gitconfig`, `ssh-config`, `allowed-signers`, `authorized-keys`, `docker-config`, `wakatime`, `age-recipients`, `android-ssh-keys`, `linux-gpg-keys`, `windows-ssh-keys`, `windows-pem-keys`, `op-wrapper`, `export-key`, `extract-folders`, `clone-tools`, `configure-deps`, `ssh-known-hosts`, `copy-appdata`, `termux-config`, `fonts`, `kube-config`, `mcp-servers`, `claude-trust`, `claude-settings`, `claude-code-patch`, `git-sync`, `ggshield-auth`, `ggshield-hook`

## Security and Encryption
- Private key location: `~/.ssh/chezmoi` (Linux/Windows) or via `op` wrapper (Android)
- Age recipients file: `~/.age_recipients` (template: `dot_age_recipients.tmpl`)
- 1Password integration: Uses `op` CLI; Linux/WSL wraps `op.exe` via `~/.local/bin/op`; Android wraps ARM64 binary via proot Alpine
- SSH commit signing: 1Password `op-ssh-sign` — different binary per platform (`op-ssh-sign-wsl` on WSL, `op-ssh-sign.exe` on Windows, `ssh-keygen` on Android)
- Git signing keys: Read per-device from 1Password "Device: \<deviceName\>" note (`ssh:` and `gpg:` entries), matched by device hostname
- **Never commit**: Raw sensitive files — always use encryption or 1Password references

### Expected Successful Operation

**A successful dotfiles installation should result in**:

1. **Shell Experience**:
   - Powerlevel10k themed terminal prompt (Linux/Android) or Oh My Posh (Windows)
   - Enhanced `ls` command using `eza` with colors and icons
   - Custom aliases: `ll`, `la`, `lp`, `lt`, `t` (eza variants), `k` (kubectl), etc.
   - Properly configured PATH with `~/.local/bin` and all version manager bins

2. **Configuration Files**:
   - `~/.zshrc` (Linux/Android) or PowerShell profile (Windows) with custom settings
   - `~/.zshenv` (Linux/Android) for IDE-compatible PATH setup
   - `~/.gitconfig` with per-device SSH signing via 1Password
   - `~/.cursor/mcp.json` (Linux) or `~/.config/mcphub/servers.json` (Android) with MCP servers

3. **Development Environment**:
   - kubectl, terraform, terragrunt available in PATH
   - Go (GVM), Node.js (NVM), Python (pyenv), Java (SDKMAN), Rust (Cargo) via version managers
   - Version managers auto-switch based on project files (`go.mod`, `.nvmrc`, `pyproject.toml`)
   - Docker via devforge (`dev docker ips`, `dev docker reset`) and Kubernetes shortcuts configured

4. **Security Setup**:
   - Age encryption working with private key at `~/.ssh/chezmoi`
   - 1Password CLI integration for secrets management
   - SSH keys and GPG keys deployed from 1Password per device

**Failure Indicators**:
- Plain, unstyled terminal prompts
- Missing command aliases or PATH issues
- Chezmoi errors about missing encryption keys or 1Password not signed in
- Tools like kubectl, terraform not found in PATH
- SSH signing failures or `op` wrapper not found

Always run validation scenarios after any changes to ensure the dotfiles apply correctly across target platforms.
