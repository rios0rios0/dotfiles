# Exercises .chezmoiscripts/run_after_windows-004-add-powershell-to-path.ps1, which puts PowerShell
# 7's folder on the user's PATH on every apply when no folder on PATH holds pwsh.exe: Windows
# Terminal's PowerShell profile starts `pwsh.exe` by name, and failed with error 0x80070002 while
# the folder was on neither PATH. Nothing is written while either PATH leads to pwsh.exe, the Store
# build's alias included; otherwise the folder the installer recorded -- a stable version's before a
# preview's, the newest first -- or Program Files' default joins the end of the user's PATH, whose
# entries, unexpanded variables and kind stay as they were. No PowerShell 7, a failed write and a
# failed broadcast only warn.
#
# Get-PathValue, Write-UserPath, Send-EnvironmentChange and Get-PowerShellInstallation are replaced
# after the script is dot-sourced, so this runs under pwsh on any OS and touches no registry.

$scriptUnderTest = Join-Path $PSScriptRoot "../../../.chezmoiscripts/run_after_windows-004-add-powershell-to-path.ps1"
$script:failures = 0

Write-Host "[test-powershell-path-windows] testing PowerShell 7's PATH entry..."

$root = Join-Path ([System.IO.Path]::GetTempPath()) "pwsh-path-test-$([guid]::NewGuid())"
# A variable the PATH values below name unexpanded, as a real one names %USERPROFILE%.
$env:PWSH_PATH_TEST_ROOT = $root

# Defines the functions without touching PATH.
. $scriptUnderTest

# Folders shaped like the ones PATH names: PowerShell 7's stable, preview and older installations,
# Program Files' default and the Store build's alias folder, each with a pwsh.exe, and a folder
# with other programs only.
$stable = Join-Path $root "PowerShell/7"
$preview = Join-Path $root "PowerShell/7-preview"
$older = Join-Path $root "PowerShell/6"
$programFiles = Join-Path $root "ProgramFiles/PowerShell/7"
$windowsApps = Join-Path $root "WindowsApps"
$system = Join-Path $root "System32"
foreach ($folder in @($stable, $preview, $older, $programFiles, $windowsApps)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $folder "pwsh.exe") -Value "pwsh"
}
New-Item -ItemType Directory -Path $system -Force | Out-Null
Set-Content -LiteralPath (Join-Path $system "cmd.exe") -Value "cmd"

# Defined after the dot-source, these replace the script's own functions of the same names.
function Get-PathValue {
    param([string]$Scope)

    return $script:pathValues[$Scope]
}

function Write-UserPath {
    param([string]$Value, [string]$Kind)

    if ($script:writeFails) { throw "access denied" }
    $script:writes += , @{ Value = $Value; Kind = $Kind }
}

function Send-EnvironmentChange {
    $script:broadcasts++
    if ($script:broadcastFails) { throw "no window answered" }
}

function Get-PowerShellInstallation {
    return $script:installations
}

# Prints a case's outcome under the suite's prefix. Write-Host belongs in a Show- function, as
# PSScriptAnalyzer's PSAvoidUsingWriteHost puts it, so Invoke-TestCase leaves the printing here.
function Show-TestResult {
    param([string]$Message)

    Write-Host "[test-powershell-path-windows] $Message"
}

function Invoke-TestCase {
    param([string]$Description, [scriptblock]$Body)

    # A machine's PATH and a user's, the user's with an unexpanded variable, an empty entry and a
    # trailing separator; neither leads to pwsh.exe. The installer recorded the stable version.
    $script:pathValues = @{
        Machine = @{ Value = "$system;$(Join-Path $root 'Docker')\"; Kind = "ExpandString" }
        User    = @{ Value = "%PWSH_PATH_TEST_ROOT%/bin;;$(Join-Path $root 'Links');"; Kind = "ExpandString" }
    }
    $script:installations = @([pscustomobject]@{ Version = "7.6.10"; Folder = $stable })
    $script:writes = @()
    $script:broadcasts = 0
    $script:writeFails = $false
    $script:broadcastFails = $false
    try {
        & $Body
        Show-TestResult "PASS: $Description"
    }
    catch {
        Show-TestResult "FAIL: $Description -- $_"
        $script:failures++
    }
}

# Runs the script's work and returns every line it printed.
function Get-PathOutput {
    param([string]$DefaultFolder = $programFiles)

    (Invoke-PowerShellPath -DefaultFolder $DefaultFolder 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
}

function Assert-That {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) { throw $Message }
}

# The one value written to the user's PATH, after checking that exactly one was.
function Get-OnlyWrite {
    Assert-That ($script:writes.Count -eq 1) "expected one write to the user's PATH, got $($script:writes.Count)"
    return $script:writes[0]
}

Invoke-TestCase "adds the installed folder to the end of the user's PATH, keeping its entries and kind" {
    $output = Get-PathOutput
    $written = Get-OnlyWrite
    Assert-That ($written.Value -ceq "%PWSH_PATH_TEST_ROOT%/bin;;$(Join-Path $root 'Links');$stable") "wrote: $($written.Value)"
    Assert-That ($written.Kind -eq "ExpandString") "wrote a $($written.Kind) value"
    Assert-That ($script:broadcasts -eq 1) "broadcast $($script:broadcasts) times"
    Assert-That ($output -match "added .* to the user's PATH; restart Windows Terminal") "the addition is not reported: $output"
    Assert-That ($output -notmatch "WARN") "warned: $output"
}

Invoke-TestCase "writes nothing while the machine's PATH holds pwsh.exe, a trailing backslash and all" {
    $script:pathValues.Machine.Value = "$system;$stable\"
    $output = Get-PathOutput
    Assert-That ($script:writes.Count -eq 0 -and $script:broadcasts -eq 0) "wrote: $($script:writes.Value -join '; ')"
    Assert-That ($output -match [regex]::Escape("PowerShell 7 is already on PATH ($stable), skipping")) "printed: $output"
}

Invoke-TestCase "counts the Store build's alias on the user's PATH, its variable expanded" {
    $script:pathValues.User.Value = "%PWSH_PATH_TEST_ROOT%/WindowsApps;%PWSH_PATH_TEST_ROOT%/bin"
    $script:installations = @()
    $output = Get-PathOutput
    Assert-That ($script:writes.Count -eq 0) "wrote: $($script:writes.Value -join '; ')"
    Assert-That ($output -match "already on PATH \(.*WindowsApps\), skipping") "printed: $output"
}

Invoke-TestCase "counts no variable in a REG_SZ PATH, which Windows leaves unexpanded" {
    $script:pathValues.User = @{ Value = "%PWSH_PATH_TEST_ROOT%/WindowsApps"; Kind = "String" }
    Get-PathOutput | Out-Null
    $written = Get-OnlyWrite
    Assert-That ($written.Value -ceq "%PWSH_PATH_TEST_ROOT%/WindowsApps;$stable") "wrote: $($written.Value)"
    Assert-That ($written.Kind -eq "String") "wrote a $($written.Kind) value over a REG_SZ one"
}

Invoke-TestCase "prefers the newest stable installation to a preview and an older one" {
    $script:installations = @(
        [pscustomobject]@{ Version = "7.7.0-preview.2"; Folder = $preview },
        [pscustomobject]@{ Version = "6.2.7"; Folder = $older },
        [pscustomobject]@{ Version = "7.6.10"; Folder = $stable })
    Get-PathOutput | Out-Null
    Assert-That ((Get-OnlyWrite).Value.EndsWith(";$stable")) "wrote: $($script:writes.Value -join '; ')"

    $script:writes = @()
    $script:installations = @([pscustomobject]@{ Version = "7.7.0-preview.2"; Folder = $preview })
    Get-PathOutput | Out-Null
    Assert-That ((Get-OnlyWrite).Value.EndsWith(";$preview")) "a preview alone was not taken: $($script:writes.Value -join '; ')"
}

Invoke-TestCase "falls back to Program Files' folder when no recorded folder holds pwsh.exe" {
    $script:installations = @([pscustomobject]@{ Version = "7.6.10"; Folder = (Join-Path $root "Uninstalled") })
    Get-PathOutput | Out-Null
    Assert-That ((Get-OnlyWrite).Value.EndsWith(";$programFiles")) "wrote: $($script:writes.Value -join '; ')"
}

Invoke-TestCase "starts an empty user PATH with the folder alone" {
    $script:pathValues.User = @{ Value = ""; Kind = "ExpandString" }
    Get-PathOutput | Out-Null
    $written = Get-OnlyWrite
    Assert-That ($written.Value -ceq $stable -and $written.Kind -eq "ExpandString") "wrote a $($written.Kind) value: $($written.Value)"
}

Invoke-TestCase "warns and writes nothing when PowerShell 7 is not installed" {
    $script:installations = @()
    $output = Get-PathOutput -DefaultFolder (Join-Path $root "Missing")
    Assert-That ($script:writes.Count -eq 0 -and $script:broadcasts -eq 0) "wrote: $($script:writes.Value -join '; ')"
    Assert-That ($output -match "WARN: PowerShell 7 is not installed") "printed: $output"
}

Invoke-TestCase "only warns when the write fails, and tells no program" {
    $script:writeFails = $true
    $output = Get-PathOutput
    Assert-That ($script:broadcasts -eq 0) "broadcast after a failed write"
    Assert-That ($output -match "WARN: .* was not added to the user's PATH: access denied; the next apply tries again") "printed: $output"
}

Invoke-TestCase "keeps the PATH it wrote and only warns when the broadcast fails" {
    $script:broadcastFails = $true
    $output = Get-PathOutput
    Get-OnlyWrite | Out-Null
    Assert-That ($output -match "WARN: added .* but running programs were not told \(no window answered\); sign out and back in") "printed: $output"
}

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath Env:PWSH_PATH_TEST_ROOT -ErrorAction SilentlyContinue

if ($script:failures -gt 0) {
    exit 1
}
Write-Host "[test-powershell-path-windows] all PowerShell 7 PATH tests passed"
exit 0
