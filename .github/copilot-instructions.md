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

### Dependency Installation Scripts
The repository includes comprehensive dependency installation scripts that run automatically during chezmoi application:

#### Linux Dependencies (`.chezmoiscripts/run_once_before_linux-001-install-dependencies.sh`)
- **TIMING**: Takes 45-90 minutes to complete. NEVER CANCEL - Set timeout to 120+ minutes.
- 149-line script that installs: Oh My Zsh, GVM (Go), kubectl, krew, terraform, terragrunt, SDKMAN, NVM, pyenv, Azure CLI
- Each tool installation can take 5-15 minutes individually
- **Critical**: Script requires internet access for downloading tools
- **Note**: Script may need execution permissions: `chmod +x .chezmoiscripts/run_once_before_linux-001-install-dependencies.sh`

#### Windows Dependencies (`.chezmoiscripts/run_once_before_windows-001-install-dependencies.ps1`)
- **TIMING**: Takes 30-60 minutes to complete. NEVER CANCEL - Set timeout to 90+ minutes.
- Uses winget for package management
- Installs development tools, hardware utilities, and communication apps

#### Manual Validation After Installation
- Verify shell configuration: `zsh --version` (Linux) or `pwsh --version` (Windows)
- Test Oh My Zsh theme: Open new terminal and verify prompt appears correctly
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
- `.chezmoi.yaml.tmpl`: Main chezmoi configuration template
- `.chezmoiignore`: Files to ignore during processing
- `.chezmoiscripts/`: Automated setup and configuration scripts

### Scripts and Automation
- `.chezmoiscripts/`: Automated setup and configuration scripts
- `dot_scripts/`: User scripts deployed to `~/.scripts/`
- `run_once_before_*`: Scripts that run once before applying configurations
- `run_after_*`: Scripts that run after applying configurations

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
   - Verify prompt theme appears correctly
   - Test aliases: `ll`, `la` (should use eza/exa)
   - Verify PATH includes custom scripts: `echo $PATH`

3. **Encryption Test**:
   ```bash
   chezmoi cat ~/.ssh/config  # Should decrypt and display SSH config
   age --version  # Verify age is available
   file encrypted_dot_npmrc.age  # Should show "age encrypted file, ASCII armored"
   ```

4. **Cross-platform Validation**:
   - Linux: Verify Zsh configuration and Oh My Zsh theme
   - Windows: Verify PowerShell profile and Oh My Posh theme
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
   echo $SHELL  # Should show zsh path on Linux
   which zsh    # Should find zsh executable
   
   # Verify custom PATH additions
   echo $PATH | grep -q ".local/bin" && echo "Custom PATH configured" || echo "PATH issue"
   ```

2. **Configuration Files Test**:
   ```bash
   # Check dotfiles are properly linked/copied
   ls -la ~/.zshrc ~/.gitconfig ~/.oh-my-posh.json
   
   # Verify templates were processed correctly
   grep -q "LOCAL_ROOT" ~/.zshrc && echo "Template processed" || echo "Template issue"
   ```

3. **Encryption and Secrets Test**:
   ```bash
   # Test age encryption is working
   chezmoi cat ~/.ssh/config > /dev/null && echo "Decryption works" || echo "Decryption failed"
   
   # Verify private key exists
   test -f ~/.ssh/chezmoi && echo "Private key exists" || echo "Missing private key"
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
   
   # Test prompt theme
   echo $PROMPT  # Should show Oh My Zsh theme configuration
   ```

## Common Tasks and Troubleshooting

### Adding New Configuration Files
1. Add file to repository as `dot_filename` or `dot_filename.tmpl`
2. Test with: `chezmoi add ~/.filename`
3. Apply changes: `chezmoi apply`
4. **Always verify**: Check file appears correctly in home directory

### Working with Encrypted Files
1. Use age encryption for sensitive files
2. Add encrypted files with: `chezmoi add --encrypt ~/.sensitive-file`
3. **Critical**: Verify private key exists at `~/.ssh/chezmoi`
4. Test decryption: `chezmoi cat ~/.sensitive-file`

### Debugging Installation Issues
- Check chezmoi status: `chezmoi doctor`
- View verbose output: `chezmoi apply --verbose`
- Check script execution: Look for logs in `/tmp/` during installation
- **SSH Issues**: Run `ssh git@<host>` to add to known_hosts manually

### Known Limitations and Workarounds
1. **WSL SSH Issues**: Git may freeze with SSH - manually add hosts to known_hosts
2. **Windows Path Limits**: 256 character limitation when using WSL interoperability
3. **1Password Calls**: Multiple calls during installation (see TODO in README)
4. **Internet Required**: All installations require internet access for downloads

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
```

### Template Processing
- Template files use Go template syntax
- Variables available: `.chezmoi.os`, `.chezmoi.arch`, `.chezmoi.hostname`
- Test templates: `chezmoi execute-template < template-file`

## Security and Encryption
- Private key location: `~/.ssh/chezmoi`
- Age recipients file: `~/.age_recipients`
- 1Password integration: Requires `op` CLI authentication
- **Never commit**: Raw sensitive files - always use encryption

### Expected Successful Operation

**A successful dotfiles installation should result in**:

1. **Shell Experience**:
   - Beautiful, themed terminal prompt (Oh My Zsh on Linux, Oh My Posh on Windows)
   - Enhanced `ls` command using `eza` with colors and icons
   - Custom aliases: `ll`, `la`, `k` (kubectl), etc.
   - Properly configured PATH with `~/.local/bin` included

2. **Configuration Files**:
   - `~/.zshrc` (Linux) or PowerShell profile (Windows) with custom settings
   - `~/.gitconfig` with personal settings and commit signing
   - `~/.ssh/config` with SSH configurations (decrypted from encrypted file)
   - Windows Terminal configuration with custom settings and themes

3. **Development Environment**:
   - kubectl, terraform, terragrunt available in PATH
   - Go, Node.js, Python environments set up via version managers
   - Docker aliases and Kubernetes shortcuts configured

4. **Security Setup**:
   - Age encryption working with private key at `~/.ssh/chezmoi`
   - 1Password CLI integration for secrets management
   - SSH keys and configurations properly deployed

**Failure Indicators**:
- Plain, unstyled terminal prompts
- Missing command aliases or PATH issues
- Chezmoi errors about missing encryption keys
- Tools like kubectl, terraform not found in PATH
- SSH configuration errors or missing files

Always run validation scenarios after any changes to ensure the dotfiles apply correctly across target platforms.