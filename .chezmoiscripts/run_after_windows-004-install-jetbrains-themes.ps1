# Fans out the staged JetBrains themes under $HOME\.local\share\jetbrains-themes\ into
# every detected JetBrains IDE config directory at $env:APPDATA\JetBrains\<Product><Version>\.
# Idempotent: safe to run on every chezmoi apply.

$prefix = "jetbrains-themes"
$staging = Join-Path -Path $HOME -ChildPath ".local\share\jetbrains-themes"
$jbRoot = Join-Path -Path $env:APPDATA -ChildPath "JetBrains"

if (-not (Test-Path -Path $staging -PathType Container)) {
    Write-Host "[$prefix] staging dir $staging missing, skipping"
    exit 0
}

if (-not (Test-Path -Path $jbRoot -PathType Container)) {
    Write-Host "[$prefix] no JetBrains IDE config found at $jbRoot, skipping"
    exit 0
}

$ideDirs = Get-ChildItem -Path $jbRoot -Directory -ErrorAction SilentlyContinue

if (-not $ideDirs) {
    Write-Host "[$prefix] no IDE versions under $jbRoot, skipping"
    exit 0
}

function Copy-Into {
    param(
        [string]$Src,
        [string]$DestDir
    )
    if (-not (Test-Path -Path $DestDir)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }
    Copy-Item -Path $Src -Destination $DestDir -Force
    Write-Host "[$prefix] copied $(Split-Path -Leaf $Src) -> $DestDir"
}

$colorsSrc = Join-Path -Path $staging -ChildPath "colors"
$codestylesSrc = Join-Path -Path $staging -ChildPath "codestyles"

foreach ($ide in $ideDirs) {
    $idePath = $ide.FullName

    # color schemes: <IDE>\colors\
    if (Test-Path -Path $colorsSrc) {
        Get-ChildItem -Path $colorsSrc -Filter "*.icls" -File -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Into -Src $_.FullName -DestDir (Join-Path $idePath "colors")
        }
    }

    # code styles: <IDE>\codestyles\
    if (Test-Path -Path $codestylesSrc) {
        Get-ChildItem -Path $codestylesSrc -Filter "*.xml" -File -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Into -Src $_.FullName -DestDir (Join-Path $idePath "codestyles")
        }
    }

    # Material Theme UI plugin custom themes: <IDE>\materialCustomThemes\
    Get-ChildItem -Path $staging -Filter "*.xml" -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Into -Src $_.FullName -DestDir (Join-Path $idePath "materialCustomThemes")
    }
}
