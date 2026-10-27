# Installs MesloLGS NF -- Powerlevel10k's font, the face Windows Terminal's profiles name -- and the
# FiraCode and Meslo Nerd Fonts for the current user: into %LOCALAPPDATA%\Microsoft\Windows\Fonts,
# registered under HKCU, which Windows 10 1809 and later load without administrator rights. Linux
# and Android get the same fonts through .chezmoitemplates/lib-install-fonts.sh.
#
# A `run_before_` script, not `run_once_`: it runs on every apply and returns at once while each
# family is installed, for this user or for the machine, so a font that is missing is installed
# on the next apply. The `run_once_` version copied into $env:WINDIR\Fonts, which needs an
# elevated shell; without one it warned and exited 0, chezmoi recorded it as done, and Windows
# Terminal opened with "MesloLGS NF" not found from then on. A failed download only warns now,
# since the next apply retries it anyway.
#
# The folders are parameters for test-install-fonts-windows.ps1, which dot-sources this file;
# chezmoi passes nothing.

param(
    [string]$UserFontsFolder = $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts" }),
    [string]$SystemFontsFolder = $(if ($env:WINDIR) { Join-Path $env:WINDIR "Fonts" })
)

$prefix = "fonts"
$fontsKey = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
$mesloBaseUrl = "https://github.com/romkatv/powerlevel10k-media/raw/master"

# Each family counts as installed when a file matching Pattern is in either folder. The Nerd
# Fonts zips name many variants, so their patterns are wildcards rather than one file name.
$fontFamilies = @(
    @{ Name = "MesloLGS NF"; Pattern = "MesloLGS NF *.ttf"; Files = @(
            "$mesloBaseUrl/MesloLGS%20NF%20Regular.ttf",
            "$mesloBaseUrl/MesloLGS%20NF%20Bold.ttf",
            "$mesloBaseUrl/MesloLGS%20NF%20Italic.ttf",
            "$mesloBaseUrl/MesloLGS%20NF%20Bold%20Italic.ttf") },
    @{ Name = "FiraCode Nerd Font"; Pattern = "FiraCodeNerdFont*.ttf"; NerdFontsAsset = "FiraCode.zip" },
    @{ Name = "Meslo Nerd Font"; Pattern = "MesloLG*NerdFont*.ttf"; NerdFontsAsset = "Meslo.zip" }
)

# Downloads a URL to a file, and resolves the newest Nerd Fonts release tag (e.g. v3.4.0): each a
# function of its own, so that test-install-fonts-windows.ps1 can replace them.
function Save-Download {
    param([string]$Uri, [string]$Path)

    Invoke-WebRequest -Uri $Uri -OutFile $Path -UseBasicParsing
}

function Get-NerdFontsVersion {
    (Invoke-RestMethod -Uri "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest").tag_name
}

# True when a font file matching the pattern is in one of the folders.
function Test-FontFamily {
    param([string]$Pattern, [string[]]$Folders)

    foreach ($folder in $Folders) {
        if ($folder -and (Test-Path -LiteralPath $folder) -and (Get-ChildItem -LiteralPath $folder -Filter $Pattern -File -ErrorAction SilentlyContinue)) {
            return $true
        }
    }
    return $false
}

# Registers an installed font file for this user and loads it into the session, so an application
# started afterwards finds it without signing out. Only the registry value is needed for good.
function Register-Font {
    param([string]$Path, [string]$Name)

    if (-not (Test-Path -LiteralPath $fontsKey)) {
        # Never New-Item -Force here: on an existing key it would recreate it, dropping every
        # other font registered under it.
        New-Item -Path $fontsKey | Out-Null
    }
    Set-ItemProperty -LiteralPath $fontsKey -Name $Name -Value $Path
    if (-not ("Dotfiles.FontSession" -as [type])) {
        Add-Type -Namespace Dotfiles -Name FontSession -MemberDefinition '[DllImport("gdi32.dll", CharSet = CharSet.Unicode)] public static extern int AddFontResource(string fileName);'
    }
    [void][Dotfiles.FontSession]::AddFontResource($Path)
}

# Copies one font file into the fonts folder, under its decoded name, and registers it.
function Install-FontFile {
    param([string]$Path, [string]$FontsFolder)

    $name = [System.Uri]::UnescapeDataString([System.IO.Path]::GetFileName($Path))
    $destination = Join-Path $FontsFolder $name
    Copy-Item -LiteralPath $Path -Destination $destination -Force
    Register-Font -Path $destination -Name "$([System.IO.Path]::GetFileNameWithoutExtension($name)) (TrueType)"
}

# Downloads a family into the work directory and installs every .ttf it holds.
function Install-FontFamily {
    param([hashtable]$Family, [string]$NerdFontsVersion, [string]$WorkDir, [string]$FontsFolder)

    $urls = if ($Family.NerdFontsAsset) {
        @("https://github.com/ryanoasis/nerd-fonts/releases/download/$NerdFontsVersion/$($Family.NerdFontsAsset)")
    }
    else { $Family.Files }

    $installed = 0
    foreach ($url in $urls) {
        $download = Join-Path $WorkDir ([System.Uri]::UnescapeDataString([System.IO.Path]::GetFileName($url)))
        Save-Download -Uri $url -Path $download
        $fonts = if ($download -like "*.zip") {
            $extracted = Join-Path $WorkDir ([System.IO.Path]::GetFileNameWithoutExtension($download))
            Expand-Archive -LiteralPath $download -DestinationPath $extracted -Force
            Get-ChildItem -LiteralPath $extracted -Filter "*.ttf" -File -Recurse
        }
        else { Get-Item -LiteralPath $download }
        foreach ($font in $fonts) {
            Install-FontFile -Path $font.FullName -FontsFolder $FontsFolder
            $installed++
        }
    }
    if ($installed -eq 0) { throw "no .ttf file in the download" }
    Write-Host "[$prefix] installed $($Family.Name) ($installed files)"
}

# Installs every family missing from both folders into the user's; each one that fails only warns.
function Invoke-FontInstall {
    param([string]$UserFolder, [string]$SystemFolder)

    $missing = @($fontFamilies | Where-Object { -not (Test-FontFamily -Pattern $_.Pattern -Folders @($UserFolder, $SystemFolder)) })
    if ($missing.Count -eq 0) { return }

    if (-not $UserFolder) {
        Write-Host "[$prefix] WARN: LOCALAPPDATA is not set, so there is no user fonts folder to install into"
        return
    }
    New-Item -ItemType Directory -Path $UserFolder -Force | Out-Null
    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) "fonts-$([System.Guid]::NewGuid())"
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    # Windows PowerShell 5.1 redraws the progress bar for every chunk, which slows downloads by an
    # order of magnitude.
    $ProgressPreference = "SilentlyContinue"
    try {
        $nerdFontsVersion = $null
        foreach ($family in $missing) {
            try {
                if ($family.NerdFontsAsset -and -not $nerdFontsVersion) {
                    $nerdFontsVersion = Get-NerdFontsVersion
                }
                Install-FontFamily -Family $family -NerdFontsVersion $nerdFontsVersion -WorkDir $workDir -FontsFolder $UserFolder
            }
            catch {
                Write-Host "[$prefix] WARN: $($family.Name) was not installed: $_; the next apply tries again"
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Dot-sourcing the script, as `make test-install-fonts-windows` does, stops here with the
# functions defined; running it installs what is missing.
if ($MyInvocation.InvocationName -eq ".") { return }

Invoke-FontInstall -UserFolder $UserFontsFolder -SystemFolder $SystemFontsFolder
