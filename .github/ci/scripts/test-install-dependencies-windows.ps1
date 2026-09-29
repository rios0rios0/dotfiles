# Exercises Install-PackageList in
# .chezmoiscripts/run_once_before_windows-001-install-dependencies.ps1. A package
# counts as installed only when winget lists it under its exact ID and source, and
# a failed install is reported -- never announced as a success, which is how
# Spotify's refusal to install (exit code 29) used to read "installed successfully".
#
# `winget` is stubbed, so this runs under pwsh on any OS and installs nothing.

$scriptUnderTest = Join-Path $PSScriptRoot "../../../.chezmoiscripts/run_once_before_windows-001-install-dependencies.ps1"
$script:failures = 0

Write-Host "[test-install-dependencies-windows] testing the Windows dependency installer..."

# State that the stub reads and writes, reset before every case. Keys are
# "<source>:<id>"; every call is recorded as "<verb> <source>:<id> <exact|inexact>".
$script:installed = @{}
$script:installExitCodes = @{}
$script:calls = @()

# PowerShell resolves a function before an application of the same name, so the
# code under test calls this stub instead of the real winget.
function winget {
    $id = $args[[array]::IndexOf($args, "--id") + 1]
    $source = $args[[array]::IndexOf($args, "--source") + 1]
    $key = "${source}:$id"
    $script:calls += "$($args[0]) $key $(if ($args -contains '--exact') { 'exact' } else { 'inexact' })"
    if ($args[0] -eq "list") {
        $global:LASTEXITCODE = if ($script:installed.ContainsKey($key)) { 0 } else { -1978335212 }
        return
    }
    $code = if ($script:installExitCodes.ContainsKey($key)) { $script:installExitCodes[$key] } else { 0 }
    if ($code -eq 0) { $script:installed[$key] = $true }
    $global:LASTEXITCODE = $code
}

# Defines the functions without installing the real lists.
. $scriptUnderTest
$script:callsWhileLoading = @($script:calls)

function Invoke-TestCase {
    param([string]$Description, [scriptblock]$Body)

    $script:installed = @{}
    $script:installExitCodes = @{}
    $script:calls = @()
    $script:failed = @()
    try {
        & $Body
        Write-Host "[test-install-dependencies-windows] PASS: $Description"
    }
    catch {
        Write-Host "[test-install-dependencies-windows] FAIL: $Description -- $_"
        $script:failures++
    }
}

# Runs the list and returns each line the installer printed, errors included.
# Out-String is avoided on purpose: Windows PowerShell 5.1 wraps its output at the
# host width, which would split a message across lines.
function Get-InstallOutput {
    param([string[]]$PackageList)

    (Install-PackageList $PackageList 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
}

function Assert-That {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) { throw $Message }
}

Invoke-TestCase "dot-sourcing the script defines its functions without installing anything" {
    # given the script dot-sourced above

    # when nothing else ran

    # then
    Assert-That ($script:callsWhileLoading.Count -eq 0) "loading called winget $($script:callsWhileLoading.Count) times"
    Assert-That ([bool](Get-Command Install-PackageList -ErrorAction SilentlyContinue)) "Install-PackageList is not defined"
}

Invoke-TestCase "skips a package that winget lists under its exact ID" {
    # given
    $script:installed["winget:GIMP.GIMP"] = $true

    # when
    $output = Get-InstallOutput "GIMP.GIMP"

    # then
    Assert-That (($script:calls -join "|") -eq "list winget:GIMP.GIMP exact") "unexpected calls: $($script:calls -join ' | ')"
    Assert-That ($output -match "GIMP.GIMP is already installed") "the skip was not reported: $output"
}

Invoke-TestCase "installs a missing package by its exact ID and reports success" {
    # given nothing installed

    # when
    $output = Get-InstallOutput "Git.Git"

    # then
    Assert-That (($script:calls -join "|") -eq "list winget:Git.Git exact|install winget:Git.Git exact") "unexpected calls: $($script:calls -join ' | ')"
    Assert-That ($output -match "Git.Git installed successfully") "the success was not reported: $output"
    Assert-That ($script:failed.Count -eq 0) "a success was recorded as a failure"
}

Invoke-TestCase "reports a failed install instead of announcing success" {
    # given an installer that refuses, as Spotify's does beside its Store edition
    $script:installExitCodes["winget:Spotify.Spotify"] = -1978335226

    # when
    $output = Get-InstallOutput "Spotify.Spotify"

    # then
    Assert-That ($output -match "WARN: Spotify.Spotify was not installed \(winget exit code -1978335226\)") "the failure was not reported: $output"
    Assert-That ($output -notmatch "installed successfully") "a failure was announced as a success: $output"
    Assert-That (($script:failed -join ",") -eq "Spotify.Spotify") "the failure was not recorded: $($script:failed -join ',')"
}

Invoke-TestCase "looks up and installs an msstore entry in the Microsoft Store source" {
    # given nothing installed

    # when
    $output = Get-InstallOutput "msstore:9NCBCSZSJRSB"

    # then
    Assert-That (($script:calls -join "|") -eq "list msstore:9NCBCSZSJRSB exact|install msstore:9NCBCSZSJRSB exact") "unexpected calls: $($script:calls -join ' | ')"
    Assert-That ($output -match "9NCBCSZSJRSB installed successfully") "the success was not reported: $output"
}

Invoke-TestCase "skips an msstore entry that the Store source lists as installed" {
    # given the Store edition already installed, as on a machine that has it
    $script:installed["msstore:9NCBCSZSJRSB"] = $true

    # when
    $output = Get-InstallOutput "msstore:9NCBCSZSJRSB"

    # then
    Assert-That (($script:calls -join "|") -eq "list msstore:9NCBCSZSJRSB exact") "unexpected calls: $($script:calls -join ' | ')"
    Assert-That ($output -match "9NCBCSZSJRSB is already installed") "the skip was not reported: $output"
}

Invoke-TestCase "keeps going after a failure and records every package that failed" {
    # given two refusals around an install that works
    $script:installExitCodes["winget:A.A"] = 1
    $script:installExitCodes["winget:C.C"] = 2

    # when
    $output = Get-InstallOutput @("A.A", "B.B", "C.C")

    # then
    Assert-That ($output -match "B.B installed successfully") "the list stopped at the first failure: $output"
    Assert-That (($script:failed -join ",") -eq "A.A,C.C") "failures recorded: $($script:failed -join ',')"
}

if ($script:failures -gt 0) {
    exit 1
}
Write-Host "[test-install-dependencies-windows] all Windows dependency installer tests passed"
