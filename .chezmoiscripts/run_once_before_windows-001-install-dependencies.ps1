$prefix = "install-deps"
$script:failed = @()

# True when winget lists the package as installed under exactly this ID and source.
# `winget export` is no substitute: it leaves out packages that are installed -- it
# omitted GIMP, Codex, yq, ShellCheck, the Copilot CLI and the EA app on the machine
# this was found on -- so every run went back to installing them again.
function Test-PackageInstalled {
    param (
        [string]$Id,
        [string]$Source
    )

    winget list --id $Id --exact --source $Source --accept-source-agreements --disable-interactivity 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

# Install each package that is not installed yet. An entry is a winget ID, or
# "<source>:<id>" for another winget source, e.g. "msstore:<id>" for a Store app.
function Install-PackageList {
    param (
        [string[]]$packageList
    )

    foreach ($entry in $packageList) {
        $source, $id = if ($entry.Contains(":")) { $entry -split ":", 2 } else { "winget", $entry }

        if (Test-PackageInstalled -Id $id -Source $source) {
            Write-Host "[$prefix] $id is already installed..."
            continue
        }

        winget install --id $id --exact --source $source --accept-package-agreements --accept-source-agreements
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            Write-Host "[$prefix] $id installed successfully..."
        }
        else {
            Write-Host "[$prefix] WARN: $id was not installed (winget exit code $exitCode)"
            $script:failed += $id
        }
    }
}

# Download a release asset and return its path only when it is exactly the pinned
# file AND validly signed by the expected publisher. The hash pins the bytes; the
# signer check means a wrong pin still cannot let in a binary someone else signed.
function Save-VerifiedDownload {
    param (
        [string]$Uri,
        [string]$Sha256,
        [string]$Signer
    )

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetFileName($Uri))
    # Windows PowerShell 5.1 redraws the progress bar for every chunk, which slows
    # the download by an order of magnitude.
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -Uri $Uri -OutFile $path -UseBasicParsing

    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    $signedBy = if ($signature.SignerCertificate) { $signature.SignerCertificate.GetNameInfo("SimpleName", $false) }
    if ($actual -ne $Sha256) {
        Remove-Item -LiteralPath $path -Force
        throw "SHA-256 mismatch for $Uri (expected $Sha256, got $actual)"
    }
    if ($signature.Status -ne "Valid" -or $signedBy -ne $Signer) {
        Remove-Item -LiteralPath $path -Force
        throw "$Uri is not validly signed by $Signer (signature: $($signature.Status), signed by: '$signedBy')"
    }
    return $path
}

# RustDesk is not in winget: its publisher had every version removed in 2026-03,
# after the package was falsely flagged as malware and could not be allowlisted
# again (microsoft/winget-pkgs#352094). It comes from the GitHub release instead,
# pinned to one MSI. To bump it, copy the new MSI's `digest` from
# https://api.github.com/repos/rustdesk/rustdesk/releases/latest -- the signer
# check still refuses anything that RustDesk (PURSLANE) did not sign.
function Install-RustDesk {
    $version = "1.4.9"
    $sha256 = "c87d2f4cef2a5acd6003b6507dcfbf5d5168a256db082cd90b54d35193224aaa"

    # Both installers register the display name "RustDesk" (the .exe under the key
    # "RustDesk", the MSI under its product code), so a manual install counts too.
    $installed = Get-ItemProperty -Path @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    ) -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq "RustDesk" }
    if ($installed) {
        Write-Host "[rustdesk] already installed..."
        return
    }

    try {
        $msi = Save-VerifiedDownload -Signer "PURSLANE" -Sha256 $sha256 `
            -Uri "https://github.com/rustdesk/rustdesk/releases/download/$version/rustdesk-$version-x86_64.msi"
    }
    catch {
        Write-Host "[rustdesk] WARN: not installed: $_"
        $script:failed += "RustDesk"
        return
    }

    # A per-machine MSI that registers a service. /passive (not /qn) lets Windows
    # Installer raise a UAC prompt when the apply is not already elevated.
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msi`" /passive /norestart" -Wait -PassThru
    Remove-Item -LiteralPath $msi -Force
    # 3010: installed, and a restart finishes it.
    if ($process.ExitCode -in 0, 3010) {
        Write-Host "[rustdesk] installed $version"
    }
    else {
        Write-Host "[rustdesk] WARN: msiexec exited with $($process.ExitCode), RustDesk is not installed"
        $script:failed += "RustDesk"
    }
}

# Dot-sourcing the script, as `make test-install-dependencies-windows` does, stops
# here with the functions defined; running it installs the lists below.
if ($MyInvocation.InvocationName -eq ".") { return }

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
    #"Brother.FullDriver",           # TODO: not in the winget source (Brother has only BRAdmin and iPrint&Scan there)
    "CPUID.CPU-Z.ROG",
    "FinalWire.AIDA64.Extreme",
    "Logitech.GHUB",
    "PassMark.PerformanceTest"
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
    "Grammarly.Grammarly",
    "Microsoft.OneDrive",
    "Notepad++.Notepad++",
    "PDFLabs.PDFtk.Free",
    "Piriform.CCleaner",
    "Piriform.Recuva",
    "RevoUninstaller.RevoUninstallerPro",
    "msstore:9NCBCSZSJRSB",             # Spotify, the Microsoft Store edition: the Spotify.Spotify installer refuses to run beside it (exit code 29)
    "Oracle.VirtualBox"
)
Install-PackageList $utilities
Install-RustDesk                    # not in winget, see the function
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
    "Anthropic.ClaudeCode",
    "CoreyButler.NVMforWindows",
    "Docker.DockerDesktop",
    "ExpressVPN.ExpressVPN",
    "GitHub.cli",
    "GitHub.Copilot",                   # agentic GitHub Copilot CLI (binary `copilot`)
    "GoLang.Go",
    "JetBrains.Toolbox",
    "Microsoft.Azure.StorageExplorer",
    "Microsoft.VisualStudio.2022.Community",
    "Mirantis.Lens",
    "OpenAI.Codex",                     # Codex CLI (binary `codex`); winget unpacks the portable release zip
    "OpenVPNTechnologies.OpenVPNConnect",
    "Postman.Postman",
    "BurntSushi.ripgrep.MSVC",
    "jqlang.jq",
    "MikeFarah.yq",
    "sharkdp.bat",
    "koalaman.shellcheck"               # static analysis for shell scripts (used by `make lint`)
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
if ($script:failed) {
    Write-Host "[$prefix] WARN: $($script:failed.Count) packages were not installed: $($script:failed -join ', ')"
}
