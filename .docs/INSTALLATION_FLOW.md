# Installation Flow Diagram

This document provides visual representations of the installation flow for setting up a complete development environment from scratch.

## Overview Flow

```mermaid
graph TD
    A[Fresh Windows 11 Install] --> B[Phase 1: Core Windows Features]
    B --> C[Restart Required]
    C --> D[Phase 2: Prerequisites]
    D --> E[Phase 3: Chezmoi Bootstrap Windows]
    E --> F[Phase 4: WSL2 + Kali Linux]
    F --> G[Phase 5: Chezmoi Bootstrap WSL]
    G --> H[Phase 6: Manual Installations]
    H --> I[Phase 7: Configuration & Validation]
    I --> J[Complete Environment Ready]
    
    style A fill:#f9f,stroke:#333,stroke-width:2px
    style J fill:#9f9,stroke:#333,stroke-width:2px
    style C fill:#ff9,stroke:#333,stroke-width:2px
```

## Detailed Installation Phases

```mermaid
graph TD
    subgraph "Phase 1: Windows Features"
        A1[Enable Virtual Machine Platform]
        A2[Enable WSL]
        A3[Restart Computer]
        A1 --> A2 --> A3
    end
    
    subgraph "Phase 2: Prerequisites"
        B1[Install PowerShell 7]
        B2[Install Git]
        B3[Install Age]
        B4[Install 1Password]
        B5[Install 1Password CLI]
        B1 --> B2 --> B3 --> B4 --> B5
    end
    
    subgraph "Phase 3: Windows Bootstrap"
        C1[Run chezmoi init]
        C2[Install 60+ Packages via winget]
        C3[Install Development Tools]
        C4[Install Gaming Platforms]
        C5[Install Office Utilities]
        C6[Install Communication Apps]
        C1 --> C2
        C2 --> C3 & C4 & C5 & C6
    end
    
    subgraph "Phase 4: WSL Setup"
        D1[wsl --update]
        D2[wsl --set-default-version 2]
        D3[wsl --install kali-linux]
        D1 --> D2 --> D3
    end
    
    subgraph "Phase 5: WSL Bootstrap"
        E1[apt install git age]
        E2[Run chezmoi init in WSL]
        E3[Install Oh My Zsh]
        E4[Install Development Tools]
        E5[Install Version Managers]
        E6[Install kubectl/terraform]
        E1 --> E2
        E2 --> E3 --> E4 --> E5 --> E6
    end
    
    subgraph "Phase 6: Manual Steps"
        F1[Microsoft Store Apps]
        F2[JetBrains IDEs]
        F3[Hardware Drivers]
        F4[Account Logins]
        F5[Restore Backups]
    end
    
    A3 --> B1
    B5 --> C1
    C6 --> D1
    D3 --> E1
    E6 --> F1 & F2 & F3 & F4 & F5
    
    style A3 fill:#ff9,stroke:#333
    style C1 fill:#9ff,stroke:#333
    style E2 fill:#9ff,stroke:#333
```

## Automation Coverage

```mermaid
pie title Installation Automation Coverage
    "Fully Automated (chezmoi)" : 70
    "Semi-Automated (Toolbox/Store)" : 20
    "Manual Required" : 10
```

## Software Categories Distribution

```mermaid
pie title Software by Category
    "Development Tools" : 35
    "Office Utilities" : 20
    "Gaming Platforms" : 10
    "Communication Apps" : 8
    "Hardware/Drivers" : 12
    "System Utilities" : 15
```

## Installation Time Breakdown

```mermaid
gantt
    title Installation Timeline (Total: 2-3 hours)
    dateFormat HH:mm
    axisFormat %H:%M
    
    section Windows Setup
    Enable Features & Restart     :done, w1, 00:00, 10m
    Install Prerequisites         :done, w2, after w1, 5m
    
    section Automated Install
    Windows Bootstrap (Automated) :active, w3, after w2, 30m
    WSL Bootstrap (Automated)     :active, w4, after w3, 90m
    
    section Manual Steps
    Microsoft Store Apps          :w5, after w4, 10m
    JetBrains IDEs               :w6, after w4, 15m
    Hardware Drivers             :w7, after w4, 15m
    Account Logins               :w8, after w4, 5m
    Backup Restoration           :w9, after w4, 10m
```

## Dependency Graph

```mermaid
graph LR
    subgraph "Core Dependencies"
        PS7[PowerShell 7]
        GIT[Git]
        AGE[Age]
        OP[1Password]
        OPCLI[1Password CLI]
    end
    
    subgraph "Windows Features"
        WSL[WSL2]
        VMP[Virtual Machine Platform]
    end
    
    subgraph "Chezmoi Bootstrap"
        CZ[Chezmoi]
        CZWIN[Windows Bootstrap]
        CZWSL[WSL Bootstrap]
    end
    
    subgraph "Development Tools"
        DOCKER[Docker]
        K8S[kubectl]
        TF[Terraform]
        GO[Go]
        NODE[Node.js]
        PYTHON[Python]
    end
    
    VMP --> WSL
    PS7 --> GIT
    GIT --> AGE
    AGE --> OP
    OP --> OPCLI
    OPCLI --> CZ
    WSL --> CZWSL
    CZ --> CZWIN
    CZ --> CZWSL
    CZWIN --> DOCKER
    CZWSL --> K8S
    CZWSL --> TF
    CZWSL --> GO
    CZWSL --> NODE
    CZWSL --> PYTHON
    
    style CZ fill:#9ff,stroke:#333,stroke-width:3px
    style CZWIN fill:#9ff,stroke:#333,stroke-width:2px
    style CZWSL fill:#9ff,stroke:#333,stroke-width:2px
```

## Platform Distribution

```mermaid
graph TD
    subgraph "Windows Host"
        WIN[Windows 11]
        WINTOOLS[Windows Development Tools<br/>60+ packages via winget]
        GAMING[Gaming Platforms<br/>Steam, Epic, EA, GOG]
        OFFICE[Office Utilities<br/>Office 365, Notion, etc.]
        COMM[Communication<br/>Slack, Discord, Zoom]
    end
    
    subgraph "WSL2 - Kali Linux"
        WSL[Kali Linux]
        WSLTOOLS[Development Tools<br/>kubectl, terraform, etc.]
        VERMAN[Version Managers<br/>pyenv, nvm, sdkman, gvm]
        SHELL[Shell Environment<br/>Oh My Zsh, P10K]
    end
    
    WIN --> WINTOOLS & GAMING & OFFICE & COMM
    WIN --> WSL
    WSL --> WSLTOOLS & VERMAN & SHELL
    
    style WIN fill:#0080ff,stroke:#333,color:#fff
    style WSL fill:#ff6b35,stroke:#333,color:#fff
```

## Installation Method by Category

```mermaid
graph LR
    subgraph "Installation Methods"
        WINGET[winget<br/>Automated]
        APT[apt<br/>Automated]
        SCRIPT[Shell Scripts<br/>Automated]
        MANUAL[Manual<br/>Download/Install]
        STORE[Microsoft Store<br/>Manual]
    end
    
    subgraph "Software Categories"
        DEV[Development<br/>Tools]
        GAME[Gaming<br/>Platforms]
        OFF[Office<br/>Utilities]
        HARD[Hardware<br/>Drivers]
        COM[Communication<br/>Apps]
    end
    
    WINGET -->|35 packages| DEV
    WINGET -->|5 packages| GAME
    WINGET -->|15 packages| OFF
    WINGET -->|6 packages| HARD
    WINGET -->|3 packages| COM
    
    APT -->|30 packages| DEV
    SCRIPT -->|10 tools| DEV
    
    MANUAL -->|Most| HARD
    STORE -->|6 apps| OFF
    STORE -->|2 apps| COM
    
    style WINGET fill:#9f9,stroke:#333
    style APT fill:#9f9,stroke:#333
    style SCRIPT fill:#9f9,stroke:#333
    style MANUAL fill:#f99,stroke:#333
    style STORE fill:#ff9,stroke:#333
```

## Decision Tree: Installation Method

```mermaid
graph TD
    START[Software to Install] --> Q1{Operating System?}
    
    Q1 -->|Windows| Q2{Available in winget?}
    Q1 -->|WSL Linux| Q3{Available in apt?}
    
    Q2 -->|Yes| W1[Install via winget<br/>✅ Automated]
    Q2 -->|No| Q4{In Microsoft Store?}
    
    Q3 -->|Yes| L1[Install via apt<br/>✅ Automated]
    Q3 -->|No| Q5{Install script available?}
    
    Q4 -->|Yes| W2[Install from Store<br/>🔧 Semi-automated]
    Q4 -->|No| Q6{Hardware-specific?}
    
    Q5 -->|Yes| L2[Run install script<br/>✅ Automated]
    Q5 -->|No| L3[Manual download<br/>📥 Manual]
    
    Q6 -->|Yes| W3[Download from vendor<br/>📥 Manual]
    Q6 -->|No| W4[Search for package<br/>❓ Investigation needed]
    
    style W1 fill:#9f9,stroke:#333
    style L1 fill:#9f9,stroke:#333
    style L2 fill:#9f9,stroke:#333
    style W2 fill:#ff9,stroke:#333
    style W3 fill:#f99,stroke:#333
    style W4 fill:#f9f,stroke:#333
    style L3 fill:#f99,stroke:#333
```

## Package Management Flow

```mermaid
sequenceDiagram
    participant User
    participant Chezmoi
    participant Winget
    participant Apt
    participant Scripts
    participant System
    
    User->>Chezmoi: chezmoi init --apply
    
    Note over Chezmoi: Phase 1: Windows Bootstrap
    Chezmoi->>Scripts: run_once_before_windows-001-install-dependencies.ps1
    Scripts->>Winget: Install 60+ packages
    Winget->>System: Install applications
    Scripts->>Scripts: run_once_before_windows-002-configure-dependencies.ps1
    Scripts->>System: Configure WSL2
    Scripts->>Scripts: run_once_before_windows-003-install-fonts.ps1
    Scripts->>System: Install fonts
    
    Note over Chezmoi: Phase 2: WSL Bootstrap
    User->>System: wsl (enter WSL)
    User->>Chezmoi: chezmoi init --apply (in WSL)
    Chezmoi->>Scripts: run_once_before_linux-001-install-dependencies.sh
    Scripts->>Apt: Install apt packages
    Apt->>System: Install system tools
    Scripts->>Scripts: Install Oh My Zsh
    Scripts->>Scripts: Install version managers
    Scripts->>Scripts: Install development tools
    Scripts->>System: Configure environment
    
    Note over System: Environment Ready
```

## Validation Flow

```mermaid
graph TD
    START[Installation Complete] --> V1{Windows Validation}
    
    V1 --> V1A[Check PowerShell 7]
    V1 --> V1B[Check winget packages]
    V1 --> V1C[Check fonts]
    V1 --> V1D[Check drivers]
    
    V1A & V1B & V1C & V1D --> V2{WSL Validation}
    
    V2 --> V2A[Check Zsh]
    V2 --> V2B[Check kubectl]
    V2 --> V2C[Check terraform]
    V2 --> V2D[Check version managers]
    
    V2A & V2B & V2C & V2D --> V3{Config Validation}
    
    V3 --> V3A[Check Git config]
    V3 --> V3B[Check SSH keys]
    V3 --> V3C[Check 1Password]
    V3 --> V3D[Check chezmoi]
    
    V3A & V3B & V3C & V3D --> V4{App Validation}
    
    V4 --> V4A[Check JetBrains IDEs]
    V4 --> V4B[Check Docker]
    V4 --> V4C[Check Communication apps]
    
    V4A & V4B & V4C --> END[✅ Fully Validated]
    
    style START fill:#9ff,stroke:#333
    style END fill:#9f9,stroke:#333,stroke-width:3px
```

---

## Legend

- **✅ Automated**: Fully automated via chezmoi scripts
- **🔧 Semi-automated**: Requires minimal user interaction
- **📥 Manual**: Requires manual download and installation
- **❓ Investigation needed**: Package availability unclear
- **⚠️ Known issue**: Has documented installation problems

---

## Quick Reference

### Installation Command Paths

1. **Windows Features**: PowerShell (Admin) → `dism.exe`
2. **Prerequisites**: PowerShell → `winget install`
3. **Windows Bootstrap**: PowerShell → `chezmoi init --apply`
4. **WSL Setup**: PowerShell → `wsl --install`
5. **WSL Bootstrap**: Bash (WSL) → `chezmoi init --apply`
6. **Manual Steps**: Windows UI / Microsoft Store

### Time Estimates by Phase

| Phase | Active Time | Wait Time | Total |
|-------|-------------|-----------|-------|
| Phase 1-2 | 5 min | 10 min | 15 min |
| Phase 3 | 2 min | 30 min | 32 min |
| Phase 4-5 | 5 min | 90 min | 95 min |
| Phase 6 | 45 min | 5 min | 50 min |
| **Total** | **~1 hour** | **~2 hours** | **~3 hours** |

### Automation Percentage by Category

| Category | Automated | Manual | Total |
|----------|-----------|--------|-------|
| Development Tools | 90% | 10% | 100% |
| System Utilities | 95% | 5% | 100% |
| Office Utilities | 70% | 30% | 100% |
| Gaming Platforms | 80% | 20% | 100% |
| Hardware/Drivers | 20% | 80% | 100% |
| Communication | 60% | 40% | 100% |
| **Overall** | **70%** | **30%** | **100%** |

---

## Related Documents

- [INSTALLATION_CHECKLIST.md](INSTALLATION_CHECKLIST.md) - Comprehensive installation guide
- [QUICK_START_GUIDE.md](QUICK_START_GUIDE.md) - Fast-track installation
- [README.md](../README.md) - Repository overview
