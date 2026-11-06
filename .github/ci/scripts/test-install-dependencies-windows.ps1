# Exercises .chezmoiscripts/run_once_before_windows-001-install-dependencies.ps1.tmpl. A
# package counts as installed only when winget lists it under its exact ID and source, and
# a failed install is reported -- never announced as a success, which is how Spotify's
# refusal to install (exit code 29) used to read "installed successfully". Armoury Crate,
# which winget cannot find, goes by its MSIX and the switch ASUS's tool parses, and
# PowerPanel Business by its service, after a silent install from a pinned download.
#
# `winget` and the Windows-only commands are stubbed, so this runs under pwsh on any OS and
# installs nothing. The template's actions only choose the device that gets PowerPanel,
# which test-template-render covers, so they are dropped here, as `make lint` drops them.

$template = Join-Path $PSScriptRoot "../../../.chezmoiscripts/run_once_before_windows-001-install-dependencies.ps1.tmpl"
$script:failures = 0

Write-Host "[test-install-dependencies-windows] testing the Windows dependency installer..."

# State that the stub reads and writes, reset before every case. Keys are
# "<source>:<id>"; every call is recorded as "<verb> <source>:<id> <exact|inexact>", and what
# `--override` hands the installer is kept apart.
$script:installed = @{}
$script:installExitCodes = @{}
$script:calls = @()
$script:overrides = @{}

# PowerShell resolves a function before an application of the same name, so the
# code under test calls this stub instead of the real winget.
function winget {
    $id = $args[[array]::IndexOf($args, "--id") + 1]
    $source = $args[[array]::IndexOf($args, "--source") + 1]
    $key = "${source}:$id"
    $script:calls += "$($args[0]) $key $(if ($args -contains '--exact') { 'exact' } else { 'inexact' })"
    if ($args -contains "--override") { $script:overrides[$key] = $args[[array]::IndexOf($args, "--override") + 1] }
    if ($args[0] -eq "list") {
        $global:LASTEXITCODE = if ($script:installed.ContainsKey($key)) { 0 } else { -1978335212 }
        return
    }
    $code = if ($script:installExitCodes.ContainsKey($key)) { $script:installExitCodes[$key] } else { 0 }
    if ($code -eq 0) { $script:installed[$key] = $true }
    $global:LASTEXITCODE = $code
}

# Defines the functions without installing the real lists.
$scriptUnderTest = Join-Path ([System.IO.Path]::GetTempPath()) "install-dependencies-$([guid]::NewGuid()).ps1"
(Get-Content -Raw -LiteralPath $template) -replace '(?m)^\{\{.*\}\}\r?\n', '' |
    Set-Content -LiteralPath $scriptUnderTest -NoNewline
. $scriptUnderTest
$script:callsWhileLoading = @($script:calls)
Remove-Item -LiteralPath $scriptUnderTest

# The real one, kept for its own case: running it would need a UAC prompt.
$script:elevatedInstaller = (Get-Command Invoke-ElevatedInstaller).ScriptBlock.ToString()

# PowerShell resolves a function before a cmdlet of the same name, and these come after the
# script is loaded to take the place of its own. Their state is reset before every case.
$script:appxPackages = @()
$script:services = @()
$script:serviceChecks = 0
$script:serviceWithInstaller = $false
$script:serviceAtCheck = 0
$script:download = $null
$script:downloadError = $null
$script:started = $null
$script:startError = $null

function Test-AppxPackage {
    param([string]$Name)

    return $script:appxPackages -contains $Name
}

# Counts every look at the service, so that a case can have it appear partway through the wait.
function Test-Service {
    param([string]$Name)

    $script:serviceChecks++
    if ($script:serviceChecks -eq $script:serviceAtCheck) { $script:services += $Name }
    return $script:services -contains $Name
}

# The real one needs a signed file and the network. The download lands in the case's own folder.
function Save-VerifiedDownload {
    param([string]$Uri, [string]$Sha256, [string]$Signer)

    $script:download = @{ Uri = $Uri; Sha256 = $Sha256; Signer = $Signer }
    if ($script:downloadError) { throw $script:downloadError }
    $path = Join-Path $script:workspace ([System.IO.Path]::GetFileName($Uri))
    Set-Content -LiteralPath $path -Value "installer"
    return $path
}

# Records how the installer starts and the answers it finds beside it, byte for byte, since
# they are a Java properties file: a byte order mark would hide the first key.
function Invoke-ElevatedInstaller {
    param([string]$Path, [string]$Arguments)

    if ($script:startError) { throw $script:startError }
    $script:started = @{
        Path      = $Path
        Arguments = $Arguments
        Answers   = [System.IO.File]::ReadAllBytes([System.IO.Path]::ChangeExtension($Path, ".varfile"))
    }
    if ($script:serviceWithInstaller) { $script:services += "PowerPanel Business Service" }
}

# Prints a case's outcome under the suite's prefix. Write-Host belongs in a Show- function, as
# PSScriptAnalyzer's PSAvoidUsingWriteHost puts it, so Invoke-TestCase leaves the printing here.
function Show-TestResult {
    param([string]$Message)

    Write-Host "[test-install-dependencies-windows] $Message"
}

function Invoke-TestCase {
    param([string]$Description, [scriptblock]$Body)

    $script:installed = @{}
    $script:installExitCodes = @{}
    $script:calls = @()
    $script:overrides = @{}
    $script:failed = @()
    $script:appxPackages = @()
    $script:services = @()
    $script:serviceChecks = 0
    $script:serviceWithInstaller = $false
    $script:serviceAtCheck = 0
    $script:download = $null
    $script:downloadError = $null
    $script:started = $null
    $script:startError = $null
    $script:workspace = Join-Path ([System.IO.Path]::GetTempPath()) "install-dependencies-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $script:workspace | Out-Null
    try {
        & $Body
        Show-TestResult "PASS: $Description"
    }
    catch {
        Show-TestResult "FAIL: $Description -- $_"
        $script:failures++
    }
    finally {
        Remove-Item -LiteralPath $script:workspace -Recurse -Force
    }
}

# Runs the list and returns each line the installer printed, errors included.
# Out-String is avoided on purpose: Windows PowerShell 5.1 wraps its output at the
# host width, which would split a message across lines.
function Get-InstallOutput {
    param([string[]]$PackageList)

    (Install-PackageList $PackageList 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
}

# The same for the installers that have a function of their own. PowerPanel's wait for its
# service does not sleep here: its last case would otherwise take the five minutes it allows.
function Get-ArmouryCrateOutput {
    (Install-ArmouryCrate 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
}

function Get-PowerPanelOutput {
    (Install-PowerPanelBusiness -PollSeconds 0 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
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

Invoke-TestCase "Armoury Crate is skipped where the app's package is registered" {
    # given
    $script:appxPackages = @("B9ECED6F.ArmouryCrate")

    # when
    $output = Get-ArmouryCrateOutput

    # then
    Assert-That ($script:calls.Count -eq 0) "winget was called: $($script:calls -join ' | ')"
    Assert-That ($output -match "\[armoury-crate\] already installed") "the skip was not reported: $output"
}

Invoke-TestCase "Armoury Crate runs ASUS's tool with the switch it parses, and never asks winget what is installed" {
    # given nothing installed

    # when
    Get-ArmouryCrateOutput | Out-Null

    # then
    Assert-That (($script:calls -join "|") -eq "install winget:Asus.ArmouryCrate exact") "unexpected calls: $($script:calls -join ' | ')"
    Assert-That ($script:overrides["winget:Asus.ArmouryCrate"] -ceq "-silent") "the tool got '$($script:overrides["winget:Asus.ArmouryCrate"])', and it reads only a dash-led switch"
    Assert-That ($script:failed.Count -eq 0) "a success was recorded as a failure"
}

Invoke-TestCase "Armoury Crate does not claim the app is there when the tool has only handed over to ASUS's service" {
    # given a tool that exits 0, with the app not registered yet

    # when
    $output = Get-ArmouryCrateOutput

    # then
    Assert-That ($output -match "in the background") "the hand-over was not reported: $output"
    Assert-That ($output -notmatch "installed successfully") "a hand-over was announced as an install: $output"
}

Invoke-TestCase "Armoury Crate reports a tool that winget could not run" {
    # given a hash mismatch, as when ASUS replaces the ZIP behind its unversioned URL
    $script:installExitCodes["winget:Asus.ArmouryCrate"] = -1978335215

    # when
    $output = Get-ArmouryCrateOutput

    # then
    Assert-That ($output -match "WARN: not installed \(winget exit code -1978335215\)") "the failure was not reported: $output"
    Assert-That (($script:failed -join ",") -eq "Armoury Crate") "failures recorded: $($script:failed -join ',')"
}

Invoke-TestCase "PowerPanel is skipped where its service exists" {
    # given
    $script:services = @("PowerPanel Business Service")

    # when
    $output = Get-PowerPanelOutput

    # then
    Assert-That ($null -eq $script:download) "it downloaded the installer"
    Assert-That ($null -eq $script:started) "it started the installer"
    Assert-That ($output -match "\[powerpanel\] already installed") "the skip was not reported: $output"
}

Invoke-TestCase "PowerPanel downloads the pinned installer signed by CyberPower" {
    # given
    $script:serviceWithInstaller = $true

    # when
    Get-PowerPanelOutput | Out-Null

    # then
    Assert-That ($script:download.Uri -eq "https://dl4jz3rbrsfum.cloudfront.net/software/PPB_Windows_v4.12.4.exe") "downloaded $($script:download.Uri)"
    Assert-That ($script:download.Signer -eq "Cyber Power Systems, Inc.") "signer: $($script:download.Signer)"
    Assert-That ($script:download.Sha256 -match "^[0-9a-f]{64}$") "not a SHA-256: $($script:download.Sha256)"
}

Invoke-TestCase "PowerPanel runs a silent, elevated install of the Local module" {
    # given
    $script:serviceWithInstaller = $true

    # when
    $output = Get-PowerPanelOutput

    # then
    $answers = [System.Text.Encoding]::ASCII.GetString($script:started.Answers).Trim()
    Assert-That ($script:started.Answers[0] -eq [byte][char]"i") "the answer file starts with byte $($script:started.Answers[0]), not its first key"
    Assert-That ($answers -ceq "installModule=local") "answers: $answers"
    Assert-That ($script:started.Arguments -ceq "-q") "arguments: $($script:started.Arguments)"
    Assert-That ($output -match "\[powerpanel\] installed 4\.12\.4") "the install was not reported: $output"
    Assert-That ($output -match "http://localhost:3052/local") "the first login was not pointed out: $output"
    Assert-That ($script:failed.Count -eq 0) "a success was recorded as a failure"
}

Invoke-TestCase "an elevated installer runs as administrator and is waited for alone, within a limit" {
    # given the function as the script defines it

    # when nothing else: it would raise a UAC prompt

    # then
    Assert-That ($script:elevatedInstaller -match "-Verb RunAs") "not elevated: $($script:elevatedInstaller)"
    Assert-That ($script:elevatedInstaller -notmatch "-Wait\b") "-Wait also waits for whatever the installer leaves running"
    Assert-That ($script:elevatedInstaller -match "\.WaitForExit\(\d+\)") "not waited for within a limit: $($script:elevatedInstaller)"
}

Invoke-TestCase "PowerPanel removes the installer and its answers afterwards" {
    # given
    $script:serviceWithInstaller = $true

    # when
    Get-PowerPanelOutput | Out-Null

    # then
    $left = @(Get-ChildItem -LiteralPath $script:workspace -Force)
    Assert-That ($left.Count -eq 0) "left behind: $($left.Name -join ', ')"
}

Invoke-TestCase "PowerPanel waits for a service that appears after the launcher returned" {
    # given a launcher that returns before the install is done
    $script:serviceAtCheck = 4

    # when
    $output = Get-PowerPanelOutput

    # then
    Assert-That ($script:serviceChecks -eq 4) "looked at the service $($script:serviceChecks) times"
    Assert-That ($output -match "\[powerpanel\] installed 4\.12\.4") "the install was not reported: $output"
    Assert-That ($script:failed.Count -eq 0) "a success was recorded as a failure"
}

Invoke-TestCase "PowerPanel gives up on a service that never appears, and says so" {
    # given an installer that returns and installs nothing

    # when
    $output = Get-PowerPanelOutput

    # then
    Assert-That ($script:serviceChecks -eq 62) "looked at the service $($script:serviceChecks) times: once before the download, and 61 times over five minutes"
    Assert-That ($output -match "\[powerpanel\] WARN: not installed: the service 'PowerPanel Business Service' did not appear") "the failure was not reported: $output"
    Assert-That ($output -notmatch "installed 4\.12\.4") "a failure was announced as a success: $output"
    Assert-That (($script:failed -join ",") -eq "PowerPanel Business") "failures recorded: $($script:failed -join ',')"
}

Invoke-TestCase "PowerPanel reports a download that fails or does not verify, and starts nothing" {
    # given
    $script:downloadError = "SHA-256 mismatch"

    # when
    $output = Get-PowerPanelOutput

    # then
    Assert-That ($null -eq $script:started) "it started an unverified installer"
    Assert-That ($output -match "\[powerpanel\] WARN: not installed: SHA-256 mismatch") "the failure was not reported: $output"
    Assert-That (($script:failed -join ",") -eq "PowerPanel Business") "failures recorded: $($script:failed -join ',')"
}

Invoke-TestCase "PowerPanel reports a declined elevation, without waiting, and removes the download" {
    # given the UAC prompt answered with no
    $script:startError = "The operation was canceled by the user."

    # when
    $output = Get-PowerPanelOutput

    # then
    $left = @(Get-ChildItem -LiteralPath $script:workspace -Force)
    Assert-That ($output -match "\[powerpanel\] WARN: not installed: The operation was canceled") "the failure was not reported: $output"
    Assert-That ($script:serviceChecks -eq 1) "waited for a service whose installer never started"
    Assert-That ($left.Count -eq 0) "left behind: $($left.Name -join ', ')"
    Assert-That (($script:failed -join ",") -eq "PowerPanel Business") "failures recorded: $($script:failed -join ',')"
}

if ($script:failures -gt 0) {
    exit 1
}
Write-Host "[test-install-dependencies-windows] all Windows dependency installer tests passed"
