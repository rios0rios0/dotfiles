# Retrieve installed packages in JSON format and extract their IDs.
$installedPackageData = winget export --output allPackages.json # TODO: error here
$installedPackageIds  = $installedPackageData | ForEach-Object { $_.Id }

function Is-PackageInstalled {
    param (
        [string]$packageId
    )
    # Check if the array of installed package IDs contains the specific package ID.
    return $installedPackageIds -contains $packageId
}

function Install-PackageList {
    param (
        [string[]]$packageList
    )

    foreach ($package in $packageList) {
        if (-not (Is-PackageInstalled -packageId $package)) {
            # Install the package using its exact ID.
            winget install --id $package --source winget --accept-package-agreements --accept-source-agreements
            Write-Host "$package installed successfully..."
        }
        else {
            Write-Host "$package is already installed..."
        }
    }
}

# =========================================================================================================
# Requirements for this repository to work properly
$requirements = @(
    "AgileBits.1Password",
    "AgileBits.1Password.CLI",
    "FiloSottile.age",              # Age for encryption
    "Git.Git",                      # TODO: it's needed to install manually to avoid OpenSSH of installing and check ASLR issues options
    "JanDeDobbeleer.OhMyPosh",      # Oh My Posh
    "Microsoft.PowerShell"
    "Microsoft.WSL",                # Windows Subsystem for Linux
    "Microsoft.WindowsTerminal"     # My default terminal
)
Install-PackageList $requirements
# =========================================================================================================
# Hardware
$hardware = @(
    #"Asus.ArmouryCrate",            # TODO: it's never found. Always asking to install
    "Brother.FullDriver",
    "CPUID.CPU-Z.ROG",
    "FinalWire.AIDA64.Extreme",
    "Logitech.GHUB",
    "PerformanceTest"
)
Install-PackageList $hardware
# Hardware for Desktop
#$hardwareDesktop = @(
#    "Asus.GPUTweak"               # (just for RTX 4090)
#)
#Install-PackageList $hardwareDesktop
# =========================================================================================================
# Utilities
$utilities = @(
    "Adobe.Acrobat.Reader.64-bit",
    "CharlesMilette.TranslucentTB",
    "EaseUS.PartitionMaster",
    "GIMP.GIMP",
    "Google.ChromeRemoteDesktopHost",
    "Grammarly.Grammarly",
    "Microsoft.OneDrive",
    "Notepad++.Notepad++",
    "PDFLabs.PDFtk.Free",
    "Piriform.CCleaner",
    "Piriform.Recuva",
    "RevoUninstaller.RevoUninstallerPro",
    "Spotify.Spotify",
    "Oracle.VirtualBox"
)
Install-PackageList $utilities
# Utilities for Desktop
#$utilitiesDesktop = @(
#    "CyberPowerSystems.PowerPanel.Personal" # (just for Desktop)
#)
#Install-PackageList $utilitiesDesktop
# =========================================================================================================
# Communication
$communication = @(
    "SlackTechnologies.Slack",
    "Discord.Discord",
    "Zoom.Zoom.EXE"
)
Install-PackageList $communication
# =========================================================================================================
# Development
$development = @(
    "Anysphere.Cursor",
    "Anthropic.ClaudeCode",
    "CoreyButler.NVMforWindows",
    "Docker.DockerDesktop",
    "ExpressVPN.ExpressVPN",
    "GitHub.cli",
    "GoLang.Go",
    "JetBrains.Toolbox",
    "Microsoft.AzureStorageExplorer",
    "Microsoft.VisualStudio.2022.Community",
    "Mirantis.Lens",
    "OpenVPNTechnologies.OpenVPNConnect",
    "Postman.Postman",
    "BurntSushi.ripgrep.MSVC",
    "jqlang.jq",
    "sharkdp.bat"
)
Install-PackageList $development
# =========================================================================================================
# Gaming
$gaming = @(
    #"Blizzard.BattleNet",               # TODO: asking for a path and never installs
    "ElectronicArts.EADesktop",
    "EpicGames.EpicGamesLauncher",
    "GOG.Galaxy",
    #"Ubisoft.Connect"                   # TODO: the hash is not matching, Windows prevents the installation
    "Valve.Steam"
)
Install-PackageList $gaming
# =========================================================================================================
# Refresh the PATH environment variable
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
# =========================================================================================================
# npm-based CLIs (requires NVM for Windows to be installed and a Node.js version active)
# https://github.com/google-gemini/gemini-cli
npm install -g @google/gemini-cli
