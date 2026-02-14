# Installation Checklist - Empty Environment Setup

## Overview

This document provides a comprehensive installation checklist for setting up a complete development environment from scratch. It maps all required software to their installation methods and provides the correct installation order.

## Design Document

### Purpose
To provide a systematic approach to installing all required software, drivers, and tools on a fresh Windows 11 system with WSL2 (Kali Linux), ensuring all dependencies are met and installations happen in the correct order.

### Scope
- Windows 11 Host OS
- WSL2 with Kali Linux
- Development Tools
- Gaming Platforms
- Office Utilities
- Hardware Drivers

---

## Installation Flow Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 0: PREREQUISITES                        │
│  • Windows 11 Fresh Install                                     │
│  • Internet Connection                                          │
│  • Administrator Access                                         │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│         PHASE 1: CORE WINDOWS FEATURES & DEPENDENCIES           │
│  1. Windows Features (Virtual Machine Platform, WSL)            │
│  2. PowerShell 7                                                │
│  3. Git, Age, 1Password CLI                                     │
│  4. Windows Terminal                                            │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│              PHASE 2: WSL2 INSTALLATION                         │
│  1. Enable WSL2                                                 │
│  2. Install Kali Linux                                          │
│  3. Configure WSL2 as default version                           │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│          PHASE 3: CHEZMOI BOOTSTRAP (Windows)                   │
│  • Run: chezmoi init --apply rios0rios0                         │
│  • Automated installation via winget:                           │
│    - Drivers & Hardware Tools                                   │
│    - Office Utilities                                           │
│    - Development Tools (base)                                   │
│    - Communication Apps                                         │
│    - Gaming Platforms                                           │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│           PHASE 4: CHEZMOI BOOTSTRAP (WSL)                      │
│  • Run inside WSL: chezmoi init --apply rios0rios0              │
│  • Automated installation:                                      │
│    - Oh My Zsh + P10K theme                                     │
│    - Development tools (kubectl, terraform, etc.)               │
│    - Version managers (pyenv, nvm, sdkman, gvm)                 │
│    - CLI utilities                                              │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│              PHASE 5: MANUAL INSTALLATIONS                      │
│  • Microsoft Store Apps                                         │
│  • Licensed Software (manual installers)                        │
│  • Hardware-specific drivers                                    │
│  • Font installations                                           │
│  • Account logins & backups restore                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Detailed Installation Matrix

### Legend
- ✅ **Automated via chezmoi**: Installed automatically by running `chezmoi init --apply`
- 📦 **Winget Available**: Can be installed via Windows Package Manager
- 🏪 **Microsoft Store**: Available in Microsoft Store
- 📥 **Manual Download**: Requires manual download and installation
- ❓ **Investigation Needed**: Not confirmed if winget/automation available
- ⚠️ **Platform-specific**: Only for certain hardware configurations

---

## PHASE 1: Core Windows Setup

### Windows Features (Manual - Run as Administrator)

**Installation Order: 1**

| Feature | Method | Status | Command |
|---------|--------|--------|---------|
| Virtual Machine Platform | PowerShell | Manual Required | `dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart` |
| Windows Subsystem for Linux | PowerShell | Manual Required | `dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart` |

**Commands:**
```powershell
# Enable Windows Features (requires restart)
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

# Restart computer
Restart-Computer
```

### Core Prerequisites (Manual)

**Installation Order: 2**

| Software | Method | Status | Command |
|----------|--------|--------|---------|
| PowerShell 7 | winget | 📦 | `winget install Microsoft.PowerShell` |
| Git | winget | ✅ Automated | `winget install Git.Git` |
| Age | winget | ✅ Automated | `winget install FiloSottile.age` |
| 1Password | winget | ✅ Automated | `winget install AgileBits.1Password` |
| 1Password CLI | winget | ✅ Automated | `winget install AgileBits.1Password.CLI` |

**Commands:**
```powershell
# Install PowerShell 7 first
winget install Microsoft.PowerShell

# Restart PowerShell 7 terminal, then install prerequisites
winget install Git.Git
winget install FiloSottile.age
winget install AgileBits.1Password
winget install AgileBits.1Password.CLI

# IMPORTANT: Add age.exe to PATH manually
# Default location: C:\Users\<username>\AppData\Local\Microsoft\WinGet\Packages\FiloSottile.age_*\
```

---

## PHASE 2: WSL2 Installation

**Installation Order: 3**

| Action | Method | Status | Command |
|--------|--------|--------|---------|
| Update WSL | PowerShell | ✅ Automated | `wsl --update` |
| Set WSL version to 2 | PowerShell | ✅ Automated | `wsl --set-default-version 2` |
| Install Kali Linux | PowerShell | ✅ Automated | `wsl --install kali-linux` |

**Note**: This is automated in `.chezmoiscripts/run_once_before_windows-002-configure-dependencies.ps1`

**Commands:**
```powershell
wsl --update
wsl --set-default-version 2
wsl --install kali-linux
```

---

## PHASE 3: Chezmoi Bootstrap (Windows)

**Installation Order: 4**

Clone and apply dotfiles:
```powershell
# Set execution policy
Set-ExecutionPolicy RemoteSigned -Scope Process

# Bootstrap chezmoi
chezmoi init --apply rios0rios0
```

This will automatically install the following via `.chezmoiscripts/run_once_before_windows-001-install-dependencies.ps1`:

### Drivers & Hardware

| Software | Method | Status | Notes |
|----------|--------|--------|-------|
| Wireless Driver with ASUS Rog USB | Manual | 📥 | Download from ASUS website |
| Armoury Crate | Manual | ❓ | Available as `Asus.ArmouryCrate` but has installation issues (commented out) |
| AIDA64 Extreme | winget | ✅ Automated | `FinalWire.AIDA64.Extreme` |
| CPUID/CPU-Z ROG | winget | ✅ Automated | `CPUID.CPU-Z.ROG` |
| GPU Tweak III | Manual | ❓ | Package `Asus.GPUTweak` commented out (Desktop only) |
| NVIDIA App | Manual | 📥 | Download from nvidia.com |
| Logitech G HUB | winget | ✅ Automated | `Logitech.GHUB` |
| Lian Li L-Connect 3 | Manual | 📥 | Download from lian-li.com |
| Samsung Magician | Manual | 📥 | Download from Samsung website |
| Brother Full Driver | winget | ✅ Automated | `Brother.FullDriver` |
| PerformanceTest 11.0 | winget | ✅ Automated | `PerformanceTest` |

### Office Utilities

| Software | Method | Status | Notes |
|----------|--------|--------|-------|
| Notion | Manual | 📥 | Download from notion.so |
| Grammarly | winget | ✅ Automated | `Grammarly.Grammarly` |
| PassMark PerformanceTest | winget | ✅ Automated | `PerformanceTest` |
| EaseUS Partition Master Pro | Manual | 📥 | OneDrive backup or download |
| Revo Uninstaller Pro 5 | winget | ✅ Automated | `RevoUninstaller.RevoUninstallerPro` |
| Adobe Acrobat Reader | winget | ✅ Automated | `Adobe.Acrobat.Reader.64-bit` |
| CCleaner Professional | winget | ✅ Automated | `Piriform.CCleaner` |
| Recuva | winget | ✅ Automated | `Piriform.Recuva` |
| PowerChute Serial Shutdown | Manual | 📥 | Download from apc.com |
| ExpressVPN | winget | ✅ Automated | `ExpressVPN.ExpressVPN` |
| Notepad++ | winget | ✅ Automated | `Notepad++.Notepad++` |
| Office 365 | Manual | 📥 | Download from account.microsoft.com |
| Zoom Workplace | winget | ✅ Automated | `Zoom.Zoom.EXE` |
| Authy Desktop | Manual | ❓ | Investigation needed for winget availability |
| GIMP | winget | ✅ Automated | `GIMP.GIMP` |
| CyberPower Personal | Manual | ❓ | Package commented out (Desktop only) |
| OneDrive | winget | ✅ Automated | `Microsoft.OneDrive` |
| TranslucentTB | winget | ✅ Automated | `CharlesMilette.TranslucentTB` |
| PDFtk Free | winget | ✅ Automated | `PDFLabs.PDFtk.Free` |

### Communication

| Software | Method | Status | Notes |
|----------|--------|--------|-------|
| Slack | winget | ✅ Automated | `SlackTechnologies.Slack` |
| Discord | winget | ✅ Automated | `Discord.Discord` |
| Zoom | winget | ✅ Automated | `Zoom.Zoom.EXE` |

### Development Tools (Windows)

| Software | Method | Status | Notes |
|----------|--------|--------|-------|
| JetBrains Toolbox | winget | ✅ Automated | `JetBrains.Toolbox` |
| Visual Studio 2022 Community | winget | ✅ Automated | `Microsoft.VisualStudio.2022.Community` |
| Docker Desktop | winget | ✅ Automated | `Docker.DockerDesktop` |
| Git | winget | ✅ Automated | `Git.Git` |
| OpenVPN Connect | winget | ✅ Automated | `OpenVPNTechnologies.OpenVPNConnect` |
| K8s Lens | winget | ✅ Automated | `Mirantis.Lens` |
| PowerShell 7 | winget | ✅ Automated | `Microsoft.PowerShell` |
| GoLang | winget | ✅ Automated | `GoLang.Go` |
| chezmoi | Manual | 📦 | `winget install twpayne.chezmoi` |
| jq | winget | ✅ Automated | `jqlang.jq` |
| age | winget | ✅ Automated | `FiloSottile.age` |
| oh-my-posh | winget | ✅ Automated | `JanDeDobbeleer.OhMyPosh` |
| NVM for Windows | winget | ✅ Automated | `CoreyButler.NVMforWindows` |
| Microsoft Azure Storage Explorer | winget | ✅ Automated | `Microsoft.AzureStorageExplorer` |
| Postman | winget | ✅ Automated | `Postman.Postman` |
| bat | winget | ✅ Automated | `sharkdp.bat` |

**JetBrains IDEs** (Installed via Toolbox):
- GoLand
- IntelliJ IDEA Ultimate
- WebStorm
- Rider
- PyCharm Professional
- DataGrip
- ReSharper Tools

### Gaming Platforms

| Software | Method | Status | Notes |
|----------|--------|--------|-------|
| Steam | winget | ✅ Automated | `Valve.Steam` |
| Battle.net | winget | ❓ | Package `Blizzard.BattleNet` has installation issues (commented out) |
| Epic Games Launcher | winget | ✅ Automated | `EpicGames.EpicGamesLauncher` |
| EA App | winget | ✅ Automated | `ElectronicArts.EADesktop` |
| GOG Galaxy | winget | ✅ Automated | `GOG.Galaxy` |
| Ubisoft Connect | winget | ❓ | Package hash mismatch issue (commented out) |
| Mavis HUB | Manual | ❓ | Investigation needed |

---

## PHASE 4: Chezmoi Bootstrap (WSL - Kali Linux)

**Installation Order: 5**

Enter WSL and bootstrap:
```bash
# Enter WSL
wsl

# Install prerequisites
sudo apt update
sudo apt install git age

# Bootstrap chezmoi
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply rios0rios0
```

This will automatically install the following via `.chezmoiscripts/run_once_before_linux-001-install-dependencies.sh`:

### Core Development Tools (WSL)

| Software | Method | Status | Installation Function |
|----------|--------|--------|----------------------|
| Oh My Zsh | Script | ✅ Automated | `install_oh_my_zsh()` |
| Powerlevel10k | Manual | ❓ | Not in current scripts (needs investigation) |
| GVM (Go Version Manager) | Script | ✅ Automated | `install_gvm()` |
| kubectl | Script | ✅ Automated | `install_kubectl()` |
| krew | Script | ✅ Automated | `install_krew()` |
| kubectl ctx plugin | Script | ✅ Automated | In `install_krew()` |
| kubectl ns plugin | Script | ✅ Automated | In `install_krew()` |
| terraform | Script | ✅ Automated | `install_terraform()` |
| terragrunt | Script | ✅ Automated | `install_terragrunt()` |
| SDKMan | Script | ✅ Automated | `install_sdkman()` |
| Java (via SDKMan) | Script | ✅ Automated | In `install_sdkman()` |
| Gradle (via SDKMan) | Script | ✅ Automated | In `install_sdkman()` |
| NVM (Node Version Manager) | Script | ✅ Automated | `install_nvm()` |
| pyenv | Script | ✅ Automated | `install_pyenv()` |
| Python 3.13.2 (via pyenv) | Script | ✅ Automated | In `install_pyenv()` |
| Azure CLI | Script | ✅ Automated | `install_azure_cli()` |
| Terra | Manual | ❓ | Not in current scripts |
| eza | apt | ✅ Automated | In requirements array |
| sqlite3 | apt | ✅ Automated | In requirements array |
| jq | apt | ✅ Automated | In utilities array |
| age | apt | ✅ Automated | In requirements array |
| inotify-tools | apt | ✅ Automated | In utilities array |
| bat | apt | ✅ Automated | In utilities array |
| pdftk | apt | Manual | Not automated (mentioned in issue) |
| imagemagick | apt | Manual | Commented out in script |

### System Utilities (WSL)

| Software | Method | Status | Category |
|----------|--------|--------|----------|
| curl | apt | ✅ Automated | Requirements |
| zip/unzip | apt | ✅ Automated | Requirements |
| gpg/gpg-agent | apt | ✅ Automated | Requirements |
| htop | apt | ✅ Automated | Hardware monitoring |
| screenfetch | apt | ✅ Automated | Hardware monitoring |
| silversearcher-ag | apt | ✅ Automated | Utilities |
| dos2unix | apt | ✅ Automated | Utilities |
| expect | apt | ✅ Automated | Utilities |
| aria2c | apt | ✅ Automated | Utilities |
| file | apt | ✅ Automated | Utilities |
| parallel | apt | ✅ Automated | Utilities |

---

## PHASE 5: Manual Installations & Configuration

### Microsoft Store Apps

**Installation Order: 6**

These must be installed manually from the Microsoft Store:

| App | Status | Notes |
|-----|--------|-------|
| 1Password | 🏪 | Already automated via winget |
| WhatsApp | 🏪 | Manual required |
| Spotify | 🏪 | Has winget issues (code 29 error) |
| Telegram | 🏪 | Manual required |
| TranslucentTB | 🏪 | Already automated via winget |
| CineBench | 🏪 | Manual required |
| oh-my-posh | 🏪 | Already automated via winget |
| Draw.io | 🏪 | Manual required |
| JW Library | 🏪 | Manual required |

### Fonts Installation

**Installation Order: 7**

Download and install fonts:
- **Fira Code** (6 files)
  - Download from: https://github.com/tonsky/FiraCode/releases
  - Extract and install all .ttf files
- **MesloLGS NF** (4 files)
  - Required for Powerlevel10k
  - Download from: https://github.com/romkatv/powerlevel10k#fonts
  - Or run in PowerShell: `oh-my-posh font install meslo`

**Automated via chezmoi:**
Fonts are installed by `.chezmoiscripts/run_once_before_windows-003-install-fonts.ps1`

### Account Logins & Synchronization

**Installation Order: 8**

1. **Microsoft Account**
   - Login to Windows with Microsoft Account
   - Enable OneDrive sync

2. **OneDrive**
   - Wait for OneDrive to sync
   - Access backup files from `C:\Users\<username>\OneDrive\Backup\Windows\Default`

3. **Microsoft Edge**
   - Login to sync bookmarks and settings

4. **1Password**
   - Login and configure 1Password
   - Setup 1Password CLI authentication

### Backup Restoration

**Installation Order: 9**

1. **Restore from OneDrive backups**
   - Location: `C:\Users\<username>\OneDrive\Backup\Windows\Default`
   - EaseUS Partition Master Professional 17.x installer

2. **Clean Zone.Identifier files**
   ```powershell
   # Run in backup directory
   Get-ChildItem -Path . -Filter "*:Zone.Identifier" -Recurse -File | Remove-Item -Force
   ```
   Or in WSL:
   ```bash
   find . -name "*:Zone.Identifier" -type f -delete
   ```

---

## Missing/Gap Analysis

### Not Automated (Investigation Required)

1. **Hardware Drivers:**
   - Wireless Driver with ASUS Rog USB (manual download)
   - NVIDIA App (manual download)
   - Lian Li L-Connect 3 (manual download)
   - Samsung Magician (manual download)

2. **Office Utilities:**
   - Notion (manual download)
   - PowerChute Serial Shutdown (manual download)
   - Office 365 (manual download)
   - Authy Desktop (winget availability unknown)

3. **Gaming:**
   - Battle.net (winget has issues)
   - Ubisoft Connect (winget has hash mismatch)
   - Mavis HUB (unknown package name)

4. **WSL Tools:**
   - Powerlevel10k theme (not automated)
   - Terra tool (not automated)
   - pdftk (not automated)
   - imagemagick (commented out)

5. **Microsoft Store Only:**
   - WhatsApp
   - Telegram
   - CineBench
   - Draw.io Desktop
   - JW Library

### Known Issues

1. **Asus.ArmouryCrate**: Package never found, always asking to install
2. **Spotify**: Installation error (code 29)
3. **Blizzard.BattleNet**: Asking for a path, never installs
4. **Ubisoft.Connect**: Hash not matching, Windows prevents installation
5. **Git**: Needs manual install to avoid OpenSSH installing and check ASLR issues

---

## Recommended Installation Order (Complete Flow)

### Step-by-Step Commands

#### 1. Enable Windows Features (Restart Required)
```powershell
# Run as Administrator
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
Restart-Computer
```

#### 2. Install PowerShell 7
```powershell
winget install Microsoft.PowerShell
# Close and reopen terminal in PowerShell 7
```

#### 3. Install Core Prerequisites
```powershell
winget install Git.Git
winget install FiloSottile.age
winget install AgileBits.1Password
winget install AgileBits.1Password.CLI

# Add age to PATH manually
# Default: C:\Users\<username>\AppData\Local\Microsoft\WinGet\Packages\FiloSottile.age_*\
```

#### 4. Bootstrap Chezmoi (Windows)
```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
chezmoi init --apply rios0rios0
```

#### 5. Install Kali Linux in WSL2
```powershell
# Already automated by chezmoi scripts
# Or manually:
wsl --update
wsl --set-default-version 2
wsl --install kali-linux
```

#### 6. Bootstrap Chezmoi (WSL)
```bash
# Enter WSL
wsl

# Install prerequisites
sudo apt update
sudo apt install git age

# Bootstrap
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply rios0rios0
```

#### 7. Install Missing WSL Tools
```bash
# If needed:
sudo apt install pdftk imagemagick

# Install Powerlevel10k (if not automated)
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k

# Install Terra (if needed)
# Follow: https://github.com/rios0rios0/terra#installation
```

#### 8. Manual Installations (Windows)
- Download and install hardware-specific drivers
- Install Microsoft Store apps
- Install fonts (if not automated)
- Login to accounts (Microsoft, OneDrive, Edge, 1Password)

#### 9. Restore Backups
```powershell
# Clean Zone.Identifier files
Get-ChildItem -Path "C:\Users\<username>\OneDrive\Backup" -Filter "*:Zone.Identifier" -Recurse -File | Remove-Item -Force
```

#### 10. Configure JetBrains Toolbox
- Open JetBrains Toolbox
- Install required IDEs:
  - GoLand
  - IntelliJ IDEA Ultimate
  - WebStorm
  - Rider
  - PyCharm Professional
  - DataGrip

#### 11. Configure AIDA64 OSD (if installed)
- Open AIDA64
- Configure OSD labels according to screenshot in issue

---

## Implementation Recommendations

### Immediate Improvements

1. **Add Powerlevel10k to Linux automation**
   ```bash
   # Add to .chezmoiscripts/run_once_before_linux-001-install-dependencies.sh
   install_powerlevel10k() {
       git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
           ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
   }
   ```

2. **Add pdftk and imagemagick to WSL automation**
   ```bash
   # Uncomment in utilities array
   utilities=(
       "imagemagick"
       "pdftk"
   )
   ```

3. **Add Microsoft Store apps documentation**
   - Create a separate markdown file listing all MS Store apps
   - Include direct MS Store links

4. **Create driver download documentation**
   - Document exact driver versions and download URLs
   - Create checklist for hardware-specific drivers

5. **Improve winget error handling**
   - Add retry logic for problematic packages
   - Document manual installation steps for problematic packages

### Long-term Improvements

1. **Create post-installation validation script**
   - Check if all expected tools are installed
   - Report missing components

2. **Add support for hardware profiles**
   - Desktop vs Laptop configurations
   - Different driver sets based on hardware

3. **Automate Microsoft Store installations**
   - Use winget ms-store integration (if available)
   - Or document PowerShell methods to trigger MS Store

4. **Create installation time estimates**
   - Document expected duration for each phase
   - Set appropriate timeout values

---

## Time Estimates

| Phase | Description | Estimated Time |
|-------|-------------|----------------|
| 0 | Prerequisites | 0 min (already done) |
| 1 | Core Windows Features | 10 min + restart |
| 2 | WSL2 Installation | 15 min |
| 3 | Chezmoi Bootstrap (Windows) | 30-60 min |
| 4 | Chezmoi Bootstrap (WSL) | 45-90 min |
| 5 | Manual Installations | 30-60 min |
| **Total** | **Complete Setup** | **2.5-4 hours** |

**Notes:**
- Times assume good internet connection
- Manual installations depend on user speed
- Driver installations may require additional restarts
- Initial download and installation times vary

---

## Validation Checklist

After completing all phases, verify:

### Windows
- [ ] PowerShell 7 is default
- [ ] Windows Terminal is configured
- [ ] All winget packages installed successfully
- [ ] Fonts installed correctly
- [ ] Hardware drivers functional
- [ ] Gaming platforms launching correctly

### WSL (Kali Linux)
- [ ] Oh My Zsh installed
- [ ] Zsh is default shell
- [ ] Theme displays correctly (P10K or configured theme)
- [ ] kubectl working: `kubectl version --client`
- [ ] terraform working: `terraform version`
- [ ] Go installed: `go version`
- [ ] Node installed: `node --version`
- [ ] Python installed: `python --version`
- [ ] Azure CLI working: `az --version`

### Configuration
- [ ] Git configured with user details
- [ ] SSH keys generated and deployed
- [ ] 1Password CLI authenticated
- [ ] Age encryption working
- [ ] Chezmoi managing dotfiles: `chezmoi managed`

### Applications
- [ ] JetBrains IDEs installed via Toolbox
- [ ] Docker Desktop running
- [ ] Communication apps configured (Slack, Discord, Zoom)
- [ ] Microsoft Store apps installed

---

## Troubleshooting

### Common Issues

1. **Age not in PATH**
   - Manually add to PATH: `C:\Users\<username>\AppData\Local\Microsoft\WinGet\Packages\FiloSottile.age_*\`

2. **WSL installation fails**
   - Ensure Virtual Machine Platform is enabled
   - Check Windows version supports WSL2
   - Run: `wsl --status` to diagnose

3. **Winget package not found**
   - Update winget: `winget upgrade`
   - Search for package: `winget search <package>`
   - Check package ID is correct

4. **Chezmoi decryption fails**
   - Ensure age is installed
   - Check private key exists: `~/.ssh/chezmoi`
   - Verify 1Password CLI is authenticated

5. **Git operations stuck in WSL**
   - Run: `ssh git@github.com` to add to known_hosts
   - Check SSH configuration

---

## Appendix: Package IDs Reference

### Quick Reference Table

| Software | Winget ID |
|----------|-----------|
| PowerShell 7 | `Microsoft.PowerShell` |
| Git | `Git.Git` |
| Age | `FiloSottile.age` |
| 1Password | `AgileBits.1Password` |
| 1Password CLI | `AgileBits.1Password.CLI` |
| Oh My Posh | `JanDeDobbeleer.OhMyPosh` |
| Windows Terminal | `Microsoft.WindowsTerminal` |
| WSL | `Microsoft.WSL` |
| Docker Desktop | `Docker.DockerDesktop` |
| JetBrains Toolbox | `JetBrains.Toolbox` |
| Visual Studio 2022 | `Microsoft.VisualStudio.2022.Community` |
| Lens | `Mirantis.Lens` |
| GoLang | `GoLang.Go` |
| NVM for Windows | `CoreyButler.NVMforWindows` |
| Postman | `Postman.Postman` |
| Azure Storage Explorer | `Microsoft.AzureStorageExplorer` |
| jq | `jqlang.jq` |
| bat | `sharkdp.bat` |
| Steam | `Valve.Steam` |
| Epic Games | `EpicGames.EpicGamesLauncher` |
| EA Desktop | `ElectronicArts.EADesktop` |
| GOG Galaxy | `GOG.Galaxy` |
| Slack | `SlackTechnologies.Slack` |
| Discord | `Discord.Discord` |
| Zoom | `Zoom.Zoom.EXE` |
| Notepad++ | `Notepad++.Notepad++` |
| GIMP | `GIMP.GIMP` |
| Adobe Reader | `Adobe.Acrobat.Reader.64-bit` |
| Grammarly | `Grammarly.Grammarly` |
| CCleaner | `Piriform.CCleaner` |
| Recuva | `Piriform.Recuva` |
| Revo Uninstaller | `RevoUninstaller.RevoUninstallerPro` |
| TranslucentTB | `CharlesMilette.TranslucentTB` |
| OneDrive | `Microsoft.OneDrive` |
| EaseUS Partition Master | `EaseUS.PartitionMaster` |
| PDFtk | `PDFLabs.PDFtk.Free` |
| ExpressVPN | `ExpressVPN.ExpressVPN` |
| OpenVPN | `OpenVPNTechnologies.OpenVPNConnect` |
| AIDA64 | `FinalWire.AIDA64.Extreme` |
| CPU-Z ROG | `CPUID.CPU-Z.ROG` |
| Logitech G HUB | `Logitech.GHUB` |
| Brother Driver | `Brother.FullDriver` |
| PerformanceTest | `PerformanceTest` |

---

## Conclusion

This document provides a comprehensive roadmap for installing all required software from an empty environment. The installation is approximately **60-70% automated** through chezmoi and winget, with the remaining 30-40% requiring manual intervention for:

- Hardware-specific drivers
- Microsoft Store applications
- Licensed software requiring manual activation
- Account logins and synchronization
- Some problematic winget packages

By following this guide in order, you can ensure all dependencies are met and software is installed in the correct sequence.
