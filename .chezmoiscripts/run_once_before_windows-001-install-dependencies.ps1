$installedPackages = winget list --source winget

function Is-PackageInstalled
{
    param (
        [string]$packageName
    )
    return $installedPackages -like "*$packageName*"
}

function Install-Package-List
{
    param (
        [string[]]$packageList
    )

    foreach ($package in $packageList)
    {
        if (-not (Is-PackageInstalled $package))
        {
            winget install $package
            Write-Host "$package installed successfully..."
        }
        else
        {
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
    "Microsoft.WindowsTerminal",    # My default terminal
    "OffSec.KaliLinux"              # Kali Linux (my default WSL distro)
)
Install-Package-List $requirements
# =========================================================================================================
# Hardware
$hardware = @(
    "Asus.ArmouryCrate",            # TODO: it's never found. Always asking to install
    "Brother.FullDriver",
    "CPUID.CPU-Z.ROG",
    "FinalWire.AIDA64.Extreme",
    "Logitech.GHUB",
    "PerformanceTest"
)
Install-Package-List $hardware
# Hardware for Desktop
#$hardwareDesktop = @(
#    "Asus.GPUTweak"               # (just for RTX 4090)
#)
#Install-Package-List $hardwareDesktop
# =========================================================================================================
# Utilities
$utilities = @(
    "Adobe.Acrobat.Reader.64-bit",
    "CharlesMilette.TranslucentTB"
    "EaseUS.PartitionMaster",
    "GIMP.GIMP",
    "Google.ChromeRemoteDesktopHost",
    "Grammarly.Grammarly",
    "Microsoft.OneDrive",
    "Notepad++.Notepad++",
    "PDFLabs.PDFtk.Free"
    "Piriform.CCleaner",
    "Piriform.Recuva",
    "RevoUninstaller.RevoUninstallerPro",
    "Spotify.Spotify"               # TODO: error when installing (code 29)
)
Install-Package-List $utilities
# Utilities for Desktop
#$utilitiesDesktop = @(
#    "CyberPowerSystems.PowerPanel.Personal" # (just for Desktop)
#)
#Install-Package-List $utilitiesDesktop
# =========================================================================================================
# Communication
$communication = @(
    "SlackTechnologies.Slack",
    "Discord.Discord",
    "Zoom.Zoom.EXE"
)
Install-Package-List $communication
# =========================================================================================================
# Development
$development = @(
    "Docker.DockerDesktop",
    "ExpressVPN.ExpressVPN",
    "GoLang.Go",
    "JetBrains.Toolbox",
    "Microsoft.AzureStorageExplorer",
    "Microsoft.VisualStudio.2022.Community",
    "Mirantis.Lens",
    "OpenVPNTechnologies.OpenVPNConnect",
    "Postman.Postman",
    "jqlang.jq"
)
Install-Package-List $development
# =========================================================================================================
# Gaming
$gaming = @(
    "Blizzard.BattleNet",               # TODO: asking for a path and never installs
    "ElectronicArts.EADesktop",
    "EpicGames.EpicGamesLauncher",
    "GOG.Galaxy",
    "Ubisoft.Connect"                   # TODO: the hash is not matching, Windows prevents the installation
    "Valve.Steam"
)
Install-Package-List $gaming
# =========================================================================================================
# Refresh the PATH environment variable
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
