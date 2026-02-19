# This script installs MesloLGS NF, Meslo Nerd Font, and FiraCode Nerd Font on Windows.
# The same fonts are installed on Linux/Android via run_once_before_install-fonts.sh.

# Ensure the script is run as Administrator.
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator"))
{
    Write-Warning "This script must be run as Administrator to install fonts."
    exit
}

# Create a temporary working directory for downloads and extraction.
$temporaryDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $temporaryDir -Force | Out-Null

# Function to add font registry entry.
function Add-FontRegistryEntry
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$FontFileName, # e.g. MeslogNS-Regular.ttf
        [Parameter(Mandatory = $true)]
        [string]$FontDisplayName # e.g. "MeslogNS Regular (TrueType)"
    )

    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    Write-Host "Adding registry entry: [$FontDisplayName] = $FontFileName"
    # Create or update the registry entry.
    Set-ItemProperty -Path $regPath -Name $FontDisplayName -Value $FontFileName -ErrorAction SilentlyContinue
}

# Function to install a .ttf font file.
function Install-Font
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$FontPath   # Full path to the .ttf file downloaded or extracted.
    )

    $fontFileName = [System.IO.Path]::GetFileName($FontPath)
    $fontsFolder = Join-Path $env:WINDIR "Fonts"
    $destination = Join-Path $fontsFolder $fontFileName

    if (Test-Path $destination)
    {
        Write-Host "Font '$fontFileName' already exists in the Fonts folder. Skipping copy."
    }
    else
    {
        Write-Host "Copying '$fontFileName' to the Fonts folder..."
        Copy-Item -Path $FontPath -Destination $destination -Force
    }

    # Use file name (without extension) and append " (TrueType)" for the registry display name.
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fontFileName)
    $displayName = "$baseName (TrueType)"
    Add-FontRegistryEntry -FontFileName $fontFileName -FontDisplayName $displayName

    Write-Host "Installed font: $fontFileName"
}

# Resolve the latest Nerd Fonts release tag (https://github.com/ryanoasis/nerd-fonts)
$nerdFontsRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest"
$nerdFontsVersion = $nerdFontsRelease.tag_name
Write-Host "Resolved Nerd Fonts version: $nerdFontsVersion"

$nerdFontsBaseUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/$nerdFontsVersion"
$mesloBaseUrl = "https://github.com/romkatv/powerlevel10k-media/raw/master"

# Font URLs: Nerd Font patched FiraCode and Meslo, plus MesloLGS NF for Powerlevel10k.
$Urls = @(
    "$nerdFontsBaseUrl/FiraCode.zip"
    "$nerdFontsBaseUrl/Meslo.zip"
    "$mesloBaseUrl/MesloLGS%20NF%20Regular.ttf"
    "$mesloBaseUrl/MesloLGS%20NF%20Bold.ttf"
    "$mesloBaseUrl/MesloLGS%20NF%20Italic.ttf"
    "$mesloBaseUrl/MesloLGS%20NF%20Bold%20Italic.ttf"
)

foreach ($url in $Urls)
{
    Write-Host "Processing URL:" $url

    # Check if the URL seems to point to a ZIP file.
    if ($url -match "\.zip($|\?)")
    {
        $zipFileName = [System.IO.Path]::GetFileName($url)
        $zipFilePath = Join-Path $temporaryDir $zipFileName

        Write-Host "Downloading ZIP file:" $zipFileName
        Invoke-WebRequest -Uri $url -OutFile $zipFilePath

        # Extract the ZIP file into a folder.
        $extractDir = Join-Path $temporaryDir ([System.IO.Path]::GetFileNameWithoutExtension($zipFileName))
        Write-Host "Extracting ZIP file to:" $extractDir
        Expand-Archive -LiteralPath $zipFilePath -DestinationPath $extractDir -Force

        # Recursively find all .ttf files in the extracted content.
        $ttfFiles = Get-ChildItem -Path $extractDir -Filter "*.ttf" -Recurse
        foreach ($ttf in $ttfFiles)
        {
            Install-Font -FontPath $ttf.FullName
        }
    }
    # Check if the URL points directly to a .ttf file.
    elseif ($url -match "\.ttf($|\?)")
    {
        $ttfFileName = [System.IO.Path]::GetFileName($url)
        $ttfFilePath = Join-Path $temporaryDir $ttfFileName

        Write-Host "Downloading TTF file:" $ttfFileName
        Invoke-WebRequest -Uri $url -OutFile $ttfFilePath

        Install-Font -FontPath $ttfFilePath
    }
    else
    {
        Write-Warning "The URL '$url' does not appear to be a ZIP or .ttf file. Skipping."
    }
}

# Clean up the temporary directory.
Remove-Item -Path $temporaryDir -Recurse -Force
Write-Host "Font installation complete. You might need to restart your application to see the new fonts."
