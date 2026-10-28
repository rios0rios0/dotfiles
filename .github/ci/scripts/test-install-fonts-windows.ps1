# Exercises .chezmoiscripts/run_before_windows-003-install-fonts.ps1, which installs the fonts for
# the current user before every apply. A missing family is downloaded and installed into the user's
# fonts folder under its decoded file name; a family installed for the user or for the machine is
# left alone without downloading anything; and a failed download only warns, since the next apply
# retries it -- the run_once_ version needed administrator rights, exited 0 without them, and was
# never run again.
#
# Save-Download, Get-NerdFontsVersion and Register-Font are replaced after the script is
# dot-sourced, so this runs under pwsh on any OS, downloads nothing, and writes no registry value.

$scriptUnderTest = Join-Path $PSScriptRoot "../../../.chezmoiscripts/run_before_windows-003-install-fonts.ps1"
$script:failures = 0

Write-Host "[test-install-fonts-windows] testing the Windows font install..."

$root = Join-Path ([System.IO.Path]::GetTempPath()) "fonts-test-$([guid]::NewGuid())"
$userFonts = Join-Path $root "user"
$systemFonts = Join-Path $root "system"

# Defines the functions without installing anything.
. $scriptUnderTest

# Release zips shaped like Nerd Fonts', one per family, and one that holds no font at all.
$zips = Join-Path $root "zips"
foreach ($zip in @(
        @{ Name = "FiraCode.zip"; Fonts = @("FiraCodeNerdFont-Regular.ttf", "FiraCodeNerdFontMono-Bold.ttf") },
        @{ Name = "Meslo.zip"; Fonts = @("MesloLGSNerdFont-Regular.ttf", "MesloLGMNerdFontMono-Italic.ttf", "MesloLGLDZNerdFontPropo-Bold.ttf") },
        @{ Name = "Empty.zip"; Fonts = @("README.md") })) {
    $content = Join-Path $root "content-$($zip.Name)"
    New-Item -ItemType Directory -Path $content -Force | Out-Null
    foreach ($font in $zip.Fonts) { Set-Content -LiteralPath (Join-Path $content $font) -Value "font" }
    New-Item -ItemType Directory -Path $zips -Force | Out-Null
    Compress-Archive -Path (Join-Path $content "*") -DestinationPath (Join-Path $zips $zip.Name) -Force
}

# Defined after the dot-source, these replace the script's own functions of the same names.
function Get-NerdFontsVersion {
    $script:apiCalls++
    if ($script:apiFails) { throw "GitHub API unavailable" }
    return "v9.9.9"
}

function Save-Download {
    param([string]$Uri, [string]$Path)

    $script:downloads += , $Uri
    $name = [System.IO.Path]::GetFileName($Uri)
    if ($name -like "*.zip") {
        $source = if ($script:emptyZip) { "Empty.zip" } else { $name }
        Copy-Item -LiteralPath (Join-Path $zips $source) -Destination $Path
    }
    else { Set-Content -LiteralPath $Path -Value "font" }
}

function Register-Font {
    param([string]$Path, [string]$Name)

    $script:registered += , "$Name=$Path"
}

# Prints a case's outcome under the suite's prefix. Write-Host belongs in a Show- function, as
# PSScriptAnalyzer's PSAvoidUsingWriteHost puts it, so Invoke-TestCase leaves the printing here.
function Show-TestResult {
    param([string]$Message)

    Write-Host "[test-install-fonts-windows] $Message"
}

function Invoke-TestCase {
    param([string]$Description, [scriptblock]$Body)

    $script:apiCalls = 0
    $script:apiFails = $false
    $script:emptyZip = $false
    $script:downloads = @()
    $script:registered = @()
    Remove-Item -LiteralPath $userFonts, $systemFonts -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $systemFonts -Force | Out-Null
    try {
        & $Body
        Show-TestResult "PASS: $Description"
    }
    catch {
        Show-TestResult "FAIL: $Description -- $_"
        $script:failures++
    }
}

# Runs the install and returns every line it printed.
function Get-InstallOutput {
    (Invoke-FontInstall -UserFolder $userFonts -SystemFolder $systemFonts 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
}

function Assert-That {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) { throw $Message }
}

function Get-UserFont {
    param([string]$Name)

    Test-Path -LiteralPath (Join-Path $userFonts $Name)
}

Invoke-TestCase "installs every family for the user when none is installed" {
    $output = Get-InstallOutput
    Assert-That (Get-UserFont "MesloLGS NF Regular.ttf") "MesloLGS NF Regular.ttf is missing (or kept its %20): $(Get-ChildItem $userFonts -Name)"
    Assert-That (Get-UserFont "MesloLGS NF Bold Italic.ttf") "MesloLGS NF Bold Italic.ttf is missing"
    Assert-That (Get-UserFont "FiraCodeNerdFontMono-Bold.ttf") "the FiraCode zip was not installed"
    Assert-That (Get-UserFont "MesloLGLDZNerdFontPropo-Bold.ttf") "the Meslo zip was not installed"
    Assert-That ($script:registered.Count -eq 9) "registered $($script:registered.Count) fonts: $($script:registered -join '; ')"
    Assert-That ($script:registered -contains "MesloLGS NF Regular (TrueType)=$(Join-Path $userFonts 'MesloLGS NF Regular.ttf')") "the registration does not name the installed file: $($script:registered -join '; ')"
    Assert-That ($script:apiCalls -eq 1) "the release was resolved $($script:apiCalls) times"
    Assert-That (@($script:downloads | Where-Object { $_ -like "*/download/v9.9.9/*" }).Count -eq 2) "the zips do not come from the resolved release: $($script:downloads -join '; ')"
    Assert-That ($output -notmatch "WARN") "warned: $output"
    Assert-That ($output -match "installing MesloLGS NF\.\.\." -and $output -match "installed MesloLGS NF \(4 files\)") "the install is not reported: $output"
}

Invoke-TestCase "downloads nothing while every family is installed" {
    New-Item -ItemType Directory -Path $userFonts -Force | Out-Null
    foreach ($font in @("MesloLGS NF Regular.ttf", "FiraCodeNerdFont-Regular.ttf", "MesloLGSNerdFont-Regular.ttf")) {
        Set-Content -LiteralPath (Join-Path $userFonts $font) -Value "font"
    }
    $output = Get-InstallOutput
    Assert-That ($script:downloads.Count -eq 0 -and $script:apiCalls -eq 0) "downloaded: $($script:downloads -join '; ')"
    Assert-That ($script:registered.Count -eq 0) "registered: $($script:registered -join '; ')"
    Assert-That (([regex]::Matches($output, "is already installed, skipping")).Count -eq 3) "expected three already-installed lines: $output"
}

Invoke-TestCase "counts a family installed for the machine" {
    Set-Content -LiteralPath (Join-Path $systemFonts "MesloLGS NF Regular.ttf") -Value "font"
    Get-InstallOutput | Out-Null
    Assert-That (@($script:downloads | Where-Object { $_ -like "*powerlevel10k-media*" }).Count -eq 0) "MesloLGS NF was downloaded although the machine has it"
    Assert-That (@($script:downloads | Where-Object { $_ -like "*.zip" }).Count -eq 2) "the missing Nerd Fonts were not downloaded"
}

Invoke-TestCase "installs MesloLGS NF and only warns when the Nerd Fonts release cannot be resolved" {
    $script:apiFails = $true
    $output = Get-InstallOutput
    Assert-That (Get-UserFont "MesloLGS NF Regular.ttf") "MesloLGS NF was not installed"
    Assert-That (@($script:downloads | Where-Object { $_ -like "*.zip" }).Count -eq 0) "a zip was downloaded without a release"
    Assert-That (([regex]::Matches($output, "WARN: .* was not installed")).Count -eq 2) "expected two warnings: $output"
}

Invoke-TestCase "warns about a download that holds no font" {
    $script:emptyZip = $true
    $output = Get-InstallOutput
    Assert-That ($output -match "WARN: FiraCode Nerd Font was not installed: no .ttf file") "no warning for the empty zip: $output"
    Assert-That (Get-UserFont "MesloLGS NF Regular.ttf") "MesloLGS NF was not installed beside it"
}

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue

if ($script:failures -gt 0) {
    exit 1
}
Write-Host "[test-install-fonts-windows] all Windows font install tests passed"
exit 0
