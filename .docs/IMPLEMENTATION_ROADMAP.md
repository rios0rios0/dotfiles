# Implementation Roadmap - Automation Improvements

## Overview

This document outlines a roadmap for improving the installation automation based on the gap analysis from the [INSTALLATION_CHECKLIST.md](INSTALLATION_CHECKLIST.md). It prioritizes improvements by impact and effort.

---

## Current State

- **70% Automated**: Core development tools, WSL setup, shell configuration
- **20% Semi-automated**: JetBrains IDEs, gaming platforms, some utilities
- **10% Manual**: Hardware drivers, Microsoft Store apps, licensed software

---

## Gap Analysis Summary

### Category 1: Easy Wins (High Impact, Low Effort)

These can be implemented immediately with minimal code changes:

| Item | Current State | Target State | Effort | Impact |
|------|--------------|--------------|--------|--------|
| Powerlevel10k theme | Not installed | Automated | 15 min | High |
| pdftk package | Commented out | Enabled | 5 min | Medium |
| imagemagick package | Commented out | Enabled | 5 min | Medium |
| Validation script | None | Created | 2 hours | High |
| Font installation docs | Basic | Enhanced | 30 min | Low |

### Category 2: Medium Effort (High Impact, Medium Effort)

These require more investigation or development:

| Item | Current State | Target State | Effort | Impact |
|------|--------------|--------------|--------|--------|
| Terra tool | Not automated | Automated | 1 hour | Medium |
| Microsoft Store apps | Manual | Semi-automated | 4 hours | Medium |
| Hardware profiles | Not supported | Supported | 3 hours | Medium |
| Error handling | Basic | Robust | 2 hours | High |
| Package retry logic | None | Implemented | 2 hours | High |

### Category 3: Complex Projects (High Impact, High Effort)

These are larger projects requiring significant development:

| Item | Current State | Target State | Effort | Impact |
|------|--------------|--------------|--------|--------|
| Driver automation | Manual | Semi-automated | 8 hours | Medium |
| Post-install wizard | None | Created | 16 hours | High |
| Backup automation | Manual | Automated | 8 hours | Medium |
| Cloud sync | None | Implemented | 12 hours | Low |

---

## Priority Roadmap

### Sprint 1: Quick Wins (Week 1)

**Goal**: Improve existing automation with minimal changes

#### Task 1.1: Add Powerlevel10k Installation
**Priority**: High  
**Effort**: 15 minutes  
**Impact**: High (frequently requested, improves terminal UX)

**Implementation:**
```bash
# Add to .chezmoiscripts/run_once_before_linux-001-install-dependencies.sh

install_powerlevel10k() {
    # https://github.com/romkatv/powerlevel10k#oh-my-zsh
    if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
            ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
        echo "Powerlevel10k installed. Set ZSH_THEME=\"powerlevel10k/powerlevel10k\" in ~/.zshrc"
    else
        echo "Powerlevel10k already installed..."
    fi
}

# Add to execution section
install_powerlevel10k
```

**Testing:**
```bash
# Verify theme directory exists
ls -la ~/.oh-my-zsh/custom/themes/powerlevel10k

# Test in new shell
zsh
```

---

#### Task 1.2: Enable pdftk and imagemagick
**Priority**: Medium  
**Effort**: 5 minutes  
**Impact**: Medium (requested tools)

**Implementation:**
```bash
# In .chezmoiscripts/run_once_before_linux-001-install-dependencies.sh
# Uncomment in utilities array:

utilities=(
    "imagemagick"      # it's for image manipulation (convert, identify, etc.)
    # ... other utilities
)

# Also add pdftk to requirements if needed, or add new utility:
utilities+=(
    "pdftk"           # it's for PDF manipulation
)
```

**Testing:**
```bash
pdftk --version
convert --version
identify --version
```

---

#### Task 1.3: Create Post-Installation Validation Script
**Priority**: High  
**Effort**: 2 hours  
**Impact**: High (ensures installation success)

**Implementation:**
```bash
# Create .chezmoiscripts/run_after_linux-002-validate-installation.sh

#!/bin/bash

echo "=== Validating Installation ==="
echo ""

ERRORS=0

# Function to check command exists
check_command() {
    if command -v "$1" &> /dev/null; then
        echo "✅ $1 installed"
    else
        echo "❌ $1 NOT installed"
        ((ERRORS++))
    fi
}

# Core tools
echo "--- Core Tools ---"
check_command git
check_command curl
check_command age
check_command zsh

# Development tools
echo ""
echo "--- Development Tools ---"
check_command kubectl
check_command terraform
check_command terragrunt
check_command go
check_command node
check_command python
check_command az

# Version managers
echo ""
echo "--- Version Managers ---"
[ -d "$HOME/.gvm" ] && echo "✅ GVM installed" || { echo "❌ GVM NOT installed"; ((ERRORS++)); }
[ -d "$HOME/.nvm" ] && echo "✅ NVM installed" || { echo "❌ NVM NOT installed"; ((ERRORS++)); }
[ -d "$HOME/.pyenv" ] && echo "✅ pyenv installed" || { echo "❌ pyenv NOT installed"; ((ERRORS++)); }
[ -d "$HOME/.sdkman" ] && echo "✅ SDKMan installed" || { echo "❌ SDKMan NOT installed"; ((ERRORS++)); }

# Oh My Zsh
echo ""
echo "--- Shell Configuration ---"
[ -d "$HOME/.oh-my-zsh" ] && echo "✅ Oh My Zsh installed" || { echo "❌ Oh My Zsh NOT installed"; ((ERRORS++)); }

# Chezmoi
echo ""
echo "--- Configuration Management ---"
check_command chezmoi
[ -f "$HOME/.ssh/chezmoi" ] && echo "✅ Chezmoi private key exists" || { echo "❌ Chezmoi private key missing"; ((ERRORS++)); }

echo ""
echo "================================"
if [ $ERRORS -eq 0 ]; then
    echo "✅ All validations passed!"
else
    echo "⚠️  $ERRORS validation(s) failed"
    echo "See errors above for details"
fi
echo "================================"
```

**For Windows**, create `.chezmoiscripts/run_after_windows-004-validate-installation.ps1`:
```powershell
#!/usr/bin/env pwsh

Write-Host "=== Validating Installation ===" -ForegroundColor Cyan
Write-Host ""

$errors = 0

function Test-Command {
    param([string]$cmd)
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Host "✅ $cmd installed" -ForegroundColor Green
    } else {
        Write-Host "❌ $cmd NOT installed" -ForegroundColor Red
        $script:errors++
    }
}

Write-Host "--- Core Tools ---"
Test-Command "pwsh"
Test-Command "git"
Test-Command "age"
Test-Command "op"

Write-Host ""
Write-Host "--- Development Tools ---"
Test-Command "docker"
Test-Command "kubectl"
Test-Command "terraform"
Test-Command "go"
Test-Command "node"

Write-Host ""
Write-Host "--- Configuration ---"
Test-Command "chezmoi"
Test-Command "oh-my-posh"

Write-Host ""
Write-Host "================================"
if ($errors -eq 0) {
    Write-Host "✅ All validations passed!" -ForegroundColor Green
} else {
    Write-Host "⚠️  $errors validation(s) failed" -ForegroundColor Yellow
    Write-Host "See errors above for details"
}
Write-Host "================================"
```

---

### Sprint 2: Medium Improvements (Week 2-3)

#### Task 2.1: Add Terra Installation
**Priority**: Medium  
**Effort**: 1 hour  
**Impact**: Medium (custom tool)

**Implementation:**
```bash
# Add to .chezmoiscripts/run_once_before_linux-001-install-dependencies.sh

# https://github.com/rios0rios0/terra
install_terra() {
    if [ ! -f "/usr/local/bin/terra" ]; then
        echo "Installing Terra..."
        cd /tmp
        git clone https://github.com/rios0rios0/terra.git
        cd terra
        sudo apt install --no-install-recommends --yes file
        sudo make install
        cd ..
        rm -rf terra
        echo "Terra installed successfully"
    else
        echo "Terra already installed..."
    fi
}

# Add to execution section
install_terra
```

---

#### Task 2.2: Improve Error Handling and Retry Logic
**Priority**: High  
**Effort**: 2 hours  
**Impact**: High (improves reliability)

**Implementation:**
```bash
# Add to beginning of install scripts

# Retry function for network operations
retry_command() {
    local max_attempts=3
    local delay=5
    local attempt=1
    local command="$@"
    
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts: $command"
        if eval "$command"; then
            return 0
        else
            echo "Command failed. Retrying in ${delay}s..."
            sleep $delay
            ((attempt++))
            delay=$((delay * 2))
        fi
    done
    
    echo "❌ Command failed after $max_attempts attempts: $command"
    return 1
}

# Usage:
retry_command "curl -fsSL https://example.com/installer.sh | bash"
```

---

#### Task 2.3: Add Hardware Profile Support
**Priority**: Medium  
**Effort**: 3 hours  
**Impact**: Medium (better customization)

**Implementation:**
```bash
# Add to .chezmoi.yaml.tmpl

data:
  hardware_profile: "{{ .hardware_profile | default "laptop" }}"
```

Then in scripts:
```bash
# In .chezmoiscripts/run_once_before_windows-001-install-dependencies.ps1

# Desktop-specific hardware
{{ if eq .hardware_profile "desktop" }}
$hardwareDesktop = @(
    "Asus.GPUTweak",
    "CyberPowerSystems.PowerPanel.Personal"
)
Install-PackageList $hardwareDesktop
{{ end }}
```

Prompt user during initialization:
```bash
# Can be set via:
chezmoi init --data '{"hardware_profile":"desktop"}'
```

---

### Sprint 3: Advanced Features (Week 4-6)

#### Task 3.1: Semi-Automate Microsoft Store Apps
**Priority**: Medium  
**Effort**: 4 hours  
**Impact**: Medium (reduces manual steps)

**Research needed**: Check if `winget` can install MS Store apps:
```powershell
# Some MS Store apps are available via winget
# Example:
winget search whatsapp
winget search telegram
winget search spotify

# If available, add to script with --source msstore flag
winget install --id 9NKSQGP7F2NH --source msstore  # WhatsApp
```

**Implementation:**
```powershell
# Add to .chezmoiscripts/run_once_before_windows-001-install-dependencies.ps1

# Microsoft Store Apps (if available via winget)
$storeApps = @()

# Try to find winget IDs for these apps
$appsToSearch = @("WhatsApp", "Telegram", "Spotify", "CineBench")

foreach ($app in $appsToSearch) {
    $result = winget search $app --source msstore 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Found $app in Microsoft Store via winget"
        # Add to automation
    } else {
        Write-Host "⚠️  $app requires manual installation from Microsoft Store"
    }
}
```

---

#### Task 3.2: Create Interactive Post-Install Wizard
**Priority**: High  
**Effort**: 16 hours  
**Impact**: High (improves UX)

**Features:**
- Check what was installed successfully
- List what needs manual installation
- Provide direct links to download pages
- Option to open links in browser
- Generate installation report

**Implementation sketch:**
```powershell
# .chezmoiscripts/run_after_windows-005-post-install-wizard.ps1

function Show-PostInstallWizard {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   Post-Installation Wizard" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Check installations
    $report = @{
        Installed = @()
        Missing = @()
        ManualRequired = @()
    }
    
    # ... validation logic ...
    
    # Show summary
    Write-Host "✅ Installed: $($report.Installed.Count) items" -ForegroundColor Green
    Write-Host "❌ Missing: $($report.Missing.Count) items" -ForegroundColor Red
    Write-Host "📥 Manual Required: $($report.ManualRequired.Count) items" -ForegroundColor Yellow
    Write-Host ""
    
    # Offer to open manual installation links
    if ($report.ManualRequired.Count -gt 0) {
        Write-Host "The following items require manual installation:" -ForegroundColor Yellow
        foreach ($item in $report.ManualRequired) {
            Write-Host "  • $($item.Name) - $($item.Url)"
        }
        Write-Host ""
        $response = Read-Host "Open download links in browser? (y/n)"
        if ($response -eq "y") {
            foreach ($item in $report.ManualRequired) {
                Start-Process $item.Url
            }
        }
    }
    
    # Generate report
    $reportPath = "$HOME\Desktop\installation_report.txt"
    $report | ConvertTo-Json | Out-File $reportPath
    Write-Host "Installation report saved to: $reportPath" -ForegroundColor Green
}

Show-PostInstallWizard
```

---

#### Task 3.3: Automate Driver Detection and Download Links
**Priority**: Medium  
**Effort**: 8 hours  
**Impact**: Medium (helps with manual steps)

**Implementation:**
```powershell
# Detect hardware and provide relevant driver links

function Get-HardwareInfo {
    $hardware = @{
        GPU = Get-WmiObject Win32_VideoController | Select-Object -ExpandProperty Name
        Network = Get-WmiObject Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter } | Select-Object -ExpandProperty Name
        Storage = Get-WmiObject Win32_DiskDrive | Select-Object -ExpandProperty Model
        Motherboard = Get-WmiObject Win32_BaseBoard | Select-Object -ExpandProperty Manufacturer
    }
    
    return $hardware
}

function Get-DriverLinks {
    param($hardware)
    
    $links = @()
    
    # NVIDIA GPU
    if ($hardware.GPU -match "NVIDIA") {
        $links += @{
            Name = "NVIDIA Drivers"
            Url = "https://www.nvidia.com/Download/index.aspx"
        }
    }
    
    # ASUS Hardware
    if ($hardware.Motherboard -match "ASUS") {
        $links += @{
            Name = "ASUS Armoury Crate"
            Url = "https://www.asus.com/supportonly/armoury%20crate/helpdesk_download/"
        }
    }
    
    # Samsung SSD
    if ($hardware.Storage -match "Samsung") {
        $links += @{
            Name = "Samsung Magician"
            Url = "https://semiconductor.samsung.com/consumer-storage/magician/"
        }
    }
    
    return $links
}

$hw = Get-HardwareInfo
$driverLinks = Get-DriverLinks -hardware $hw

Write-Host "Detected Hardware:" -ForegroundColor Cyan
$hw | Format-List

Write-Host ""
Write-Host "Recommended Driver Downloads:" -ForegroundColor Yellow
foreach ($link in $driverLinks) {
    Write-Host "  • $($link.Name): $($link.Url)"
}
```

---

### Sprint 4: Polish & Documentation (Week 7-8)

#### Task 4.1: Enhanced Documentation
**Priority**: High  
**Effort**: 4 hours  
**Impact**: High (improves onboarding)

**Deliverables:**
- [ ] Video walkthrough (5-10 minutes)
- [ ] Screenshots for each phase
- [ ] Troubleshooting guide expansion
- [ ] FAQ section
- [ ] Common error codes and solutions

---

#### Task 4.2: Backup and Restore Automation
**Priority**: Medium  
**Effort**: 8 hours  
**Impact**: Medium (convenience)

**Implementation:**
```powershell
# .chezmoiscripts/run_after_windows-006-restore-backups.ps1

$backupPath = "$env:OneDrive\Backup\Windows\Default"

if (Test-Path $backupPath) {
    Write-Host "Found backup folder: $backupPath" -ForegroundColor Green
    
    # Clean Zone.Identifier files
    Write-Host "Cleaning Zone.Identifier files..."
    Get-ChildItem -Path $backupPath -Filter "*:Zone.Identifier" -Recurse -File | Remove-Item -Force
    
    # List available installers
    $installers = Get-ChildItem -Path $backupPath -Filter "*.exe","*.msi" -Recurse
    
    if ($installers.Count -gt 0) {
        Write-Host ""
        Write-Host "Found $($installers.Count) installer(s) in backup:" -ForegroundColor Yellow
        foreach ($installer in $installers) {
            Write-Host "  • $($installer.Name)"
        }
        
        Write-Host ""
        $response = Read-Host "Install from backups? (y/n)"
        if ($response -eq "y") {
            foreach ($installer in $installers) {
                Write-Host "Installing $($installer.Name)..."
                Start-Process -FilePath $installer.FullName -Wait
            }
        }
    }
} else {
    Write-Host "⚠️  Backup folder not found: $backupPath" -ForegroundColor Yellow
    Write-Host "Skipping backup restoration..."
}
```

---

## Implementation Priority Matrix

```
High Impact ↑
            │  P1: Validation Script      │  P2: Error Handling
            │  P3: Powerlevel10k          │  P4: Post-Install Wizard
            │                             │
            │  P5: Terra Tool             │  P6: Hardware Detection
            │  P7: pdftk/imagemagick      │  P8: Backup Automation
            │                             │
Low Impact  └────────────────────────────┴────────────────────────→ High Effort
            Low Effort
```

**Legend:**
- **P1-P3**: Sprint 1 (Quick Wins)
- **P4-P6**: Sprint 2-3 (Medium & Advanced)
- **P7-P8**: Sprint 4 (Polish)

---

## Success Metrics

### Sprint 1 Success Criteria
- [ ] Powerlevel10k installs without errors
- [ ] pdftk and imagemagick available in WSL
- [ ] Validation script passes on fresh install
- [ ] Validation script identifies missing components

### Sprint 2 Success Criteria
- [ ] Terra tool installs and runs successfully
- [ ] Failed installations retry automatically
- [ ] Hardware profile selection works
- [ ] Desktop/laptop configurations apply correctly

### Sprint 3 Success Criteria
- [ ] Post-install wizard shows accurate report
- [ ] Direct links open for manual installations
- [ ] Hardware detection identifies GPU, storage, network
- [ ] Driver download links are relevant

### Sprint 4 Success Criteria
- [ ] Documentation includes screenshots
- [ ] FAQ covers 80% of common questions
- [ ] Backup restoration works automatically
- [ ] Zone.Identifier files cleaned successfully

---

## Long-term Vision

### Phase 2: Cloud Integration (Future)
- Sync settings across machines
- Store encrypted backups in cloud
- Share configurations with team
- CI/CD for dotfiles testing

### Phase 3: Community Features (Future)
- Public dotfiles templates
- Plugin marketplace
- Configuration presets (DevOps, Data Science, Gaming, etc.)
- Community contributions

### Phase 4: AI-Powered Setup (Future)
- Detect usage patterns
- Suggest tools based on projects
- Auto-configure based on team stack
- Predictive package installation

---

## Testing Strategy

### Unit Testing
- Test each installation function independently
- Mock network calls for CI/CD
- Verify idempotency (safe to re-run)

### Integration Testing
- Test full Windows bootstrap
- Test full WSL bootstrap
- Test combined workflow

### Validation Testing
- Fresh VM for each test
- Windows 11 clean install
- Multiple hardware profiles
- Various network conditions

### Performance Testing
- Measure installation times
- Optimize slow steps
- Parallel installation where possible

---

## Rollout Strategy

### Alpha (Internal Testing)
1. Implement Sprint 1 changes
2. Test on personal machines
3. Collect feedback
4. Iterate

### Beta (Limited Release)
1. Implement Sprint 2-3 changes
2. Share with 5-10 early adopters
3. Monitor issues
4. Fix critical bugs

### General Availability
1. Complete Sprint 4 polish
2. Comprehensive documentation
3. Public announcement
4. Monitor community feedback

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking changes in dependencies | Medium | High | Pin versions, test before updating |
| Winget package unavailability | Low | Medium | Fallback to manual installation |
| WSL2 installation failures | Low | High | Better error messages, troubleshooting guide |
| Hardware incompatibilities | Medium | Medium | Hardware profiles, detection logic |
| Network failures during install | High | Medium | Retry logic, offline installers |
| 1Password authentication issues | Low | High | Clear setup guide, validation |

---

## Maintenance Plan

### Weekly
- Check for package updates
- Test on Windows Insider builds
- Review GitHub issues

### Monthly
- Update package versions
- Test full installation flow
- Update documentation

### Quarterly
- Major feature additions
- Performance optimization
- Security audit

---

## Contributing

To implement items from this roadmap:

1. **Pick a task** from Sprint 1 (Quick Wins)
2. **Create a feature branch**: `git checkout -b feature/task-name`
3. **Implement changes** following the code in this document
4. **Test thoroughly** on fresh installation
5. **Update documentation** to reflect changes
6. **Submit PR** with clear description

### Code Style
- Follow existing conventions
- Add comments for complex logic
- Use descriptive variable names
- Include error handling

### Testing Checklist
- [ ] Tested on fresh Windows 11 install
- [ ] Tested on fresh WSL2 Kali install
- [ ] No breaking changes to existing functionality
- [ ] Documentation updated
- [ ] Validation script passes

---

## Conclusion

This roadmap provides a clear path to improve the dotfiles automation from 70% to potentially 85-90% automation. The focus is on:

1. **Quick wins** that immediately improve UX
2. **Reliability** through better error handling
3. **Flexibility** with hardware profiles
4. **User experience** with post-install wizard
5. **Long-term maintainability** with validation and testing

By following this roadmap, the installation process will become more robust, user-friendly, and require less manual intervention.

---

## Related Documents

- [INSTALLATION_CHECKLIST.md](INSTALLATION_CHECKLIST.md) - Current state analysis
- [QUICK_START_GUIDE.md](QUICK_START_GUIDE.md) - User-facing guide
- [INSTALLATION_FLOW.md](INSTALLATION_FLOW.md) - Visual diagrams
- [README.md](../README.md) - Repository overview
