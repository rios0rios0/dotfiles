$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$downloadDir = "$env:TEMP\DownloadedFonts"

# Create temporary download directory
New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

# List of font ZIP URLs from the GitHub repository
$fontUrls = @(
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/FiraCode.zip"
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/Meslo.zip"
)

foreach ($url in $fontUrls) {
    # Determine ZIP file name and paths
    $zipFileName = Split-Path $url -Leaf
    $zipPath = Join-Path $downloadDir $zipFileName

    # Remove existing ZIP file if it exists
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }

    Write-Host "Downloading $url..."
    Invoke-WebRequest -Uri $url -OutFile $zipPath

    # Create an extraction folder based on the ZIP file name
    $extractPath = Join-Path $downloadDir ([System.IO.Path]::GetFileNameWithoutExtension($zipFileName))
    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force
    }

    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    Write-Host "Copying fonts from $extractPath to $fontDir..."
    Get-ChildItem -Path $extractPath -Recurse -Include *.ttf, *.otf | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $fontDir -Force
    }

    # Clean up: remove the ZIP file and its extraction folder
    Remove-Item $zipPath -Force
    Remove-Item $extractPath -Recurse -Force
}

# Register the fonts by refreshing the font cache
Write-Host "Installing fonts..."
Start-Sleep -Seconds 2
$Shell = New-Object -ComObject Shell.Application
$FontFolder = $Shell.Namespace(0x14)  # Windows Fonts folder
Get-ChildItem -Path $fontDir -Filter "*.ttf","*.otf" | ForEach-Object {
    $FontFolder.CopyHere($_.FullName)
}

Write-Host "Fonts installed successfully!"
