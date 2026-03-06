# Quick Start Guide - Empty Environment Setup

## Overview

This guide provides the fastest path to getting your development environment up and running from scratch. For detailed information, see [INSTALLATION_CHECKLIST.md](INSTALLATION_CHECKLIST.md).

---

## 🚀 Fast Track Installation (30 minutes)

### Prerequisites
- Windows 11 with administrator access
- Stable internet connection

---

## Step 1: Enable Windows Features (5 minutes)

**Open PowerShell as Administrator** and run:

```powershell
# Enable WSL and Virtual Machine Platform
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

# Restart computer
Restart-Computer
```

⏸️ **Computer will restart** - Continue after reboot

---

## Step 2: Install PowerShell 7 (2 minutes)

Open Windows PowerShell and run:

```powershell
winget install Microsoft.PowerShell
```

**Close PowerShell and reopen PowerShell 7** (search for "PowerShell 7" in Start Menu)

---

## Step 3: Install Prerequisites (3 minutes)

In PowerShell 7, run:

```powershell
# Install core tools
winget install Git.Git
winget install FiloSottile.age
winget install AgileBits.1Password
winget install AgileBits.1Password.CLI
```

**⚠️ IMPORTANT**: After installation, add `age.exe` to your PATH:
- Default location: `C:\Users\<username>\AppData\Local\Microsoft\WinGet\Packages\FiloSottile.age_*\`
- Add this directory to your System PATH environment variable

---

## Step 4: Bootstrap Windows Environment (15-30 minutes)

```powershell
# Allow script execution
Set-ExecutionPolicy RemoteSigned -Scope Process

# Bootstrap chezmoi - this installs EVERYTHING
chezmoi init --apply rios0rios0
```

☕ **This will take 15-30 minutes**. It installs:
- All development tools (JetBrains Toolbox, Docker, VSCode, etc.)
- Communication apps (Slack, Discord, Zoom)
- Office utilities (Notepad++, GIMP, PDFtk, etc.)
- Gaming platforms (Steam, Epic, EA, GOG)
- WSL2 with Kali Linux
- And much more...

---

## Step 5: Bootstrap WSL Environment (45-90 minutes)

After Windows bootstrap completes, enter WSL:

```bash
# Enter WSL
wsl

# Install prerequisites
sudo apt update
sudo apt install git age

# Bootstrap chezmoi in WSL
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply rios0rios0
```

☕☕ **This will take 45-90 minutes**. It installs:
- Oh My Zsh with theme
- Development tools (kubectl, terraform, terragrunt)
- Version managers (Go, Node, Python, Java)
- Azure CLI
- All WSL utilities

---

## ✅ Verification

### Windows
```powershell
# Check installations
pwsh --version
git --version
age --version
docker --version
kubectl version --client

# Check chezmoi
chezmoi doctor
```

### WSL
```bash
# Check installations
zsh --version
kubectl version --client
terraform version
go version
node --version
python --version
az --version

# Check chezmoi
chezmoi doctor
chezmoi managed
```

---

## 📋 Manual Steps Required

After automation completes, you still need to:

### 1. Install Microsoft Store Apps (10 minutes)
Open Microsoft Store and install:
- WhatsApp
- Telegram  
- Spotify (or use winget with known issues)
- CineBench
- Draw.io Desktop
- JW Library

### 2. Install JetBrains IDEs (15 minutes)
Open **JetBrains Toolbox** (already installed) and install:
- GoLand
- IntelliJ IDEA Ultimate
- WebStorm
- Rider
- PyCharm Professional
- DataGrip

### 3. Login to Accounts (5 minutes)
- Microsoft Account (sync settings)
- OneDrive (sync files)
- Edge (sync bookmarks)
- 1Password (setup authentication)

### 4. Install Hardware-Specific Drivers (varies)
Based on your hardware, manually download and install:
- ASUS ROG USB Wireless Driver
- NVIDIA App
- Lian Li L-Connect 3
- Samsung Magician
- Any other manufacturer-specific software

### 5. Restore Backups (if applicable)
```powershell
# Clean Zone.Identifier files from OneDrive backups
Get-ChildItem -Path "C:\Users\$env:USERNAME\OneDrive\Backup" -Filter "*:Zone.Identifier" -Recurse -File | Remove-Item -Force
```

---

## 🔧 Common Issues

### Age not in PATH
```powershell
# Add to PATH manually
$agePath = Get-ChildItem "C:\Users\$env:USERNAME\AppData\Local\Microsoft\WinGet\Packages" -Filter "FiloSottile.age*" -Directory | Select-Object -First 1
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$($agePath.FullName)", "User")
```

### WSL Installation Issues
```powershell
# Check status
wsl --status

# Update WSL
wsl --update

# List available distributions
wsl --list --online
```

### Git Stuck in WSL
```bash
# Add hosts to known_hosts
ssh git@github.com
ssh git@dev.azure.com
```

### Chezmoi Decryption Fails
```bash
# Check private key exists
ls -la ~/.ssh/chezmoi

# Verify age is installed
age --version

# Check 1Password CLI authentication
op account list
```

---

## 📊 Total Time Estimate

| Phase | Time |
|-------|------|
| Windows Features + Restart | 10 min |
| Prerequisites | 5 min |
| Windows Bootstrap (automated) | 15-30 min |
| WSL Bootstrap (automated) | 45-90 min |
| Manual Steps | 30-45 min |
| **Total** | **2-3 hours** |

---

## 📚 Next Steps

1. **Configure your development environment**
   - Setup Git: `git config --global user.name "Your Name"`
   - Setup SSH keys (already automated by chezmoi)
   - Configure 1Password CLI authentication

2. **Customize your setup**
   - Edit chezmoi templates: `chezmoi edit ~/.zshrc`
   - Apply changes: `chezmoi apply`

3. **Review detailed documentation**
   - [INSTALLATION_CHECKLIST.md](INSTALLATION_CHECKLIST.md) - Comprehensive installation guide
   - [README.md](../README.md) - Repository overview and usage

4. **Validate everything works**
   - Run validation checklist from INSTALLATION_CHECKLIST.md
   - Test your most-used tools

---

## 🆘 Need Help?

- **Detailed Guide**: See [INSTALLATION_CHECKLIST.md](INSTALLATION_CHECKLIST.md)
- **Chezmoi Docs**: https://www.chezmoi.io/
- **Known Issues**: Check README.md TODO section
- **Troubleshooting**: See INSTALLATION_CHECKLIST.md troubleshooting section

---

## 💡 Pro Tips

1. **Run installations overnight** - The WSL bootstrap can take 90+ minutes
2. **Don't cancel long-running scripts** - They need time to complete
3. **Keep internet connection stable** - Downloads are large
4. **Have 1Password ready** - You'll need it for decryption
5. **Take breaks** - The computer does the work, you wait ☕

---

## What Gets Automated?

### ✅ Fully Automated (70%)
- Windows development tools (60+ packages via winget)
- WSL2 installation and configuration
- Kali Linux installation
- All WSL development tools
- Shell configuration (Zsh, PowerShell)
- Terminal configuration
- Git configuration
- SSH keys generation
- Font installation
- Version managers (Go, Node, Python, Java)

### 🔧 Semi-Automated (20%)
- JetBrains IDEs (Toolbox installed, IDEs installed via Toolbox UI)
- Gaming platforms (installers run, but may need interaction)
- Some drivers (winget installs, but may need configuration)

### 📥 Manual Required (10%)
- Microsoft Store apps
- Hardware-specific drivers
- Account logins
- Licensed software activation
- Some problematic winget packages

---

## Installation Commands at a Glance

### Windows (PowerShell as Admin)
```powershell
# 1. Enable features
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
Restart-Computer

# 2. Install PowerShell 7 (after restart)
winget install Microsoft.PowerShell

# 3. In PowerShell 7
winget install Git.Git
winget install FiloSottile.age
winget install AgileBits.1Password
winget install AgileBits.1Password.CLI

# 4. Bootstrap
Set-ExecutionPolicy RemoteSigned -Scope Process
chezmoi init --apply rios0rios0
```

### WSL (Bash)
```bash
# 1. Enter WSL
wsl

# 2. Install prerequisites
sudo apt update
sudo apt install git age

# 3. Bootstrap
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply rios0rios0
```

---

**That's it! Your development environment is ready! 🎉**
