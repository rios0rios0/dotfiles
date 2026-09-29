# Exercises .chezmoiscripts/run_onchange_after_windows-005-remove-dependencies.ps1.
# That script uninstalls packages unattended, so a removal that leaves its target
# behind must be reported, never counted as removed -- the same contract the Linux
# and Android library is held to by test-remove-dependencies.sh.
#
# `winget` and `npm` are stubbed, so this runs under pwsh on any OS and never
# touches a real package.

$scriptUnderTest = Join-Path $PSScriptRoot "../../../.chezmoiscripts/run_onchange_after_windows-005-remove-dependencies.ps1"
$script:failures = 0

Write-Host "[test-remove-dependencies-windows] testing the Windows dependency removal script..."

# Package state that the stubs read and write, reset before every case.
$script:installed = @{}
$script:uninstallRemoves = $true
$script:uninstallExitCode = 0

# PowerShell resolves a function before an application of the same name, so the
# handlers under test call these stubs instead of the real tools.
function winget {
    $id = $args[[array]::IndexOf($args, "--id") + 1]
    if ($args[0] -eq "uninstall" -and $script:uninstallRemoves) { $script:installed.Remove($id) }
    if ($args[0] -eq "list" -and $script:installed.ContainsKey($id)) { "Name Id Version"; "Example $id 1.0" }
    $global:LASTEXITCODE = if ($args[0] -eq "uninstall") { $script:uninstallExitCode } else { 0 }
}

function npm {
    $package = $args[-1]
    if ($args[0] -eq "uninstall" -and $script:uninstallRemoves) { $script:installed.Remove($package) }
    $global:LASTEXITCODE = if ($args[0] -eq "ls") { [int](-not $script:installed.ContainsKey($package)) } else { $script:uninstallExitCode }
}

# Defines the handlers and Invoke-TombstoneList without applying the real list.
. $scriptUnderTest

function Invoke-TestCase {
    param([string]$Description, [scriptblock]$Body)

    $script:removed = 0
    $script:installed = @{}
    $script:uninstallRemoves = $true
    $script:uninstallExitCode = 0
    try {
        & $Body
        Write-Host "[test-remove-dependencies-windows] PASS: $Description"
    }
    catch {
        Write-Host "[test-remove-dependencies-windows] FAIL: $Description -- $_"
        $script:failures++
    }
}

# Applies the tombstones and returns each line the script printed, errors
# included. Out-String is avoided on purpose: Windows PowerShell 5.1 wraps its
# output at the host width, which would split a message across lines.
function Get-TombstoneOutput {
    param([string[]]$Tombstones)

    (Invoke-TombstoneList $Tombstones 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
}

function Assert-That {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) { throw $Message }
}

Invoke-TestCase "counts a winget package that is gone after its uninstall" {
    # given
    $script:installed["Example.Clean"] = $true

    # when
    $output = Get-TombstoneOutput "winget:Example.Clean"

    # then
    Assert-That (-not $script:installed.ContainsKey("Example.Clean")) "winget uninstall was never called"
    Assert-That ($output -match "removed 1 leftover dependency entries") "the removal was not counted: $output"
    Assert-That ($output -notmatch "WARN") "unexpected warning: $output"
}

Invoke-TestCase "reports a winget package that survives its uninstall instead of counting it" {
    # given: the uninstaller fails, as a per-machine MSI does without elevation
    $script:installed["Example.Stuck"] = $true
    $script:uninstallRemoves = $false
    $script:uninstallExitCode = 1

    # when
    $output = Get-TombstoneOutput "winget:Example.Stuck"

    # then
    Assert-That ($output -match "failed to remove 'Example.Stuck' via 'winget': still installed after winget uninstall \(exit code 1\)") "the failure was not reported: $output"
    Assert-That ($output -notmatch "leftover dependency entries") "the failure was counted as a removal: $output"
}

Invoke-TestCase "reports a winget uninstall that exits 0 without removing the package" {
    # given
    $script:installed["Example.Silent"] = $true
    $script:uninstallRemoves = $false

    # when
    $output = Get-TombstoneOutput "winget:Example.Silent"

    # then
    Assert-That ($output -match "failed to remove 'Example.Silent' via 'winget'") "the no-op uninstall was not reported: $output"
    Assert-That ($output -notmatch "leftover dependency entries") "the no-op uninstall was counted as a removal: $output"
}

Invoke-TestCase "counts a winget package that is gone although the uninstaller exited non-zero" {
    # given
    $script:installed["Example.Restart"] = $true
    $script:uninstallExitCode = 1

    # when
    $output = Get-TombstoneOutput "winget:Example.Restart"

    # then
    Assert-That ($output -match "removed 1 leftover dependency entries") "the removal was not counted: $output"
    Assert-That ($output -notmatch "WARN") "unexpected warning: $output"
}

Invoke-TestCase "reports an npm package that survives its uninstall instead of counting it" {
    # given
    $script:installed["@example/stuck"] = $true
    $script:uninstallRemoves = $false
    $script:uninstallExitCode = 1

    # when
    $output = Get-TombstoneOutput "npm_global:@example/stuck"

    # then
    Assert-That ($output -match "failed to remove '@example/stuck' via 'npm_global': still installed after npm uninstall \(exit code 1\)") "the failure was not reported: $output"
    Assert-That ($output -notmatch "leftover dependency entries") "the failure was counted as a removal: $output"
}

Invoke-TestCase "stays silent when every target is already absent" {
    # given
    $absent = Join-Path $HOME ".remove-deps-test-absent-$([guid]::NewGuid())"

    # when
    $output = Get-TombstoneOutput @("winget:Example.Absent", "npm_global:@example/absent", "path:$absent")

    # then
    Assert-That ([string]::IsNullOrWhiteSpace($output)) "a clean machine produced output: $output"
}

# A directory that is not writable keeps its entries, but only for a user other
# than root, and only where chmod exists; Windows would need an ACL instead.
if ($PSVersionTable.PSEdition -eq "Core" -and -not $IsWindows -and (id -u) -ne "0") {
    Invoke-TestCase "reports a path that survives Remove-Item instead of counting it" {
        # given
        $stuck = Join-Path $HOME ".remove-deps-test-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $stuck | Out-Null
        New-Item -ItemType File -Path (Join-Path $stuck "locked") | Out-Null
        chmod 0555 $stuck

        try {
            # when
            $output = Get-TombstoneOutput "path:$stuck"

            # then
            Assert-That (Test-Path -LiteralPath $stuck) "the fixture was removed after all"
            Assert-That ($output -match "failed to remove '.+' via 'path': still present after Remove-Item") "the failure was not reported: $output"
            Assert-That ($output -notmatch "leftover dependency entries") "the failure was counted as a removal: $output"
        }
        finally {
            chmod 0755 $stuck
            Remove-Item -LiteralPath $stuck -Recurse -Force
        }
    }
}

if ($script:failures -gt 0) {
    exit 1
}
Write-Host "[test-remove-dependencies-windows] all Windows dependency removal tests passed"
