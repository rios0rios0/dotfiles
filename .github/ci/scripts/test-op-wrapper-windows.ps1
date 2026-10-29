# Exercises .chezmoiscripts/run_before_windows-000-create-op-wrapper.ps1, which writes op-retry.cmd,
# the shim chezmoi runs 1Password's CLI through on Windows, before every apply. The shim is written
# with its folder when missing, as ASCII with CRLF line endings and no byte order mark -- cmd.exe
# would read a BOM as part of the first command, and batch labels need CRLF -- left alone while it
# is current, rewritten when it differs, and a shim that cannot be written throws. The batch file
# itself runs only on Windows, so the checks on its logic here are on its lines: op.exe gets the
# arguments as given, only op's "cannot connect to 1Password app" failure is retried, the attempts
# are bounded, and the shim exits with op's own code after passing on op's error output.

$scriptUnderTest = Join-Path $PSScriptRoot "../../../.chezmoiscripts/run_before_windows-000-create-op-wrapper.ps1"
$script:failures = 0

Write-Host "[test-op-wrapper-windows] testing the Windows op retry shim..."

$root = Join-Path ([System.IO.Path]::GetTempPath()) "op-wrapper-test-$([guid]::NewGuid())"
$bin = Join-Path $root "bin"
$shimPath = Join-Path $bin "op-retry.cmd"

# Defines the function without writing anything.
. $scriptUnderTest

# Prints a case's outcome under the suite's prefix. Write-Host belongs in a Show- function, as
# PSScriptAnalyzer's PSAvoidUsingWriteHost puts it, so Invoke-TestCase leaves the printing here.
function Show-TestResult {
    param([string]$Message)

    Write-Host "[test-op-wrapper-windows] $Message"
}

function Invoke-TestCase {
    param([string]$Description, [scriptblock]$Body)

    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    try {
        & $Body
        Show-TestResult "PASS: $Description"
    }
    catch {
        Show-TestResult "FAIL: $Description -- $_"
        $script:failures++
    }
}

# Writes the shim and returns every line the script printed.
function Get-InstallOutput {
    (Install-OpRetryShim -Folder $bin 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
}

function Assert-That {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) { throw $Message }
}

# True when the shim has a line that is exactly the given text, CRLF included.
function Test-ShimLine {
    param([string]$Line)

    ([System.IO.File]::ReadAllText($shimPath) -split "`n") -ccontains "$Line`r"
}

Invoke-TestCase "writes the shim, and its folder, when neither exists" {
    $output = Get-InstallOutput
    Assert-That (Test-Path -LiteralPath $shimPath -PathType Leaf) "no shim at $shimPath"
    Assert-That ($output -match "wrote .*op-retry\.cmd") "the write is not reported: $output"
}

Invoke-TestCase "writes ASCII with CRLF line endings and no byte order mark" {
    Get-InstallOutput | Out-Null
    $bytes = [System.IO.File]::ReadAllBytes($shimPath)
    Assert-That (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "the shim starts with a byte order mark"
    Assert-That (@($bytes | Where-Object { $_ -gt 0x7F }).Count -eq 0) "the shim holds bytes outside ASCII"
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    Assert-That ($text.StartsWith("@echo off`r`n")) "the shim does not start with @echo off and CRLF"
    Assert-That ($text.EndsWith("`r`n")) "the last line does not end in CRLF"
    Assert-That (([regex]::Matches($text, "(?<!`r)`n")).Count -eq 0) "a line ends in a bare LF"
}

Invoke-TestCase "retries only op's turned-away failure, a bounded number of times, and keeps op's exit code" {
    Get-InstallOutput | Out-Null
    Assert-That (Test-ShimLine 'op.exe %* 2>"%OP_RETRY_ERR%"') "op.exe is not run with the arguments as given"
    Assert-That (Test-ShimLine 'findstr /c:"cannot connect to 1Password app" "%OP_RETRY_ERR%" >nul || goto done') "the retry is not limited to the turned-away failure"
    Assert-That (Test-ShimLine 'if %OP_RETRY_ATTEMPT% geq 4 goto done') "the attempts are not bounded at four"
    Assert-That (Test-ShimLine 'ping -n 2 127.0.0.1 >nul') "the shim does not wait a second before a retry"
    Assert-That (Test-ShimLine 'type "%OP_RETRY_ERR%" >&2') "op's error output is not passed on"
    Assert-That (Test-ShimLine 'exit /b %OP_RETRY_RC%') "the shim does not exit with op's code"
}

Invoke-TestCase "leaves a current shim alone" {
    Get-InstallOutput | Out-Null
    $stamp = [datetime]::new(2000, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
    (Get-Item -LiteralPath $shimPath).LastWriteTimeUtc = $stamp
    $output = Get-InstallOutput
    Assert-That ((Get-Item -LiteralPath $shimPath).LastWriteTimeUtc -eq $stamp) "a current shim was written again"
    Assert-That ($output -match "op-retry\.cmd is already in place") "the current shim is not reported: $output"
}

Invoke-TestCase "rewrites a shim that differs" {
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    [System.IO.File]::WriteAllText($shimPath, "@echo off`r`nop.exe %*`r`n")
    $output = Get-InstallOutput
    Assert-That (Test-ShimLine 'findstr /c:"cannot connect to 1Password app" "%OP_RETRY_ERR%" >nul || goto done') "the old shim was kept"
    Assert-That ($output -match "wrote .*op-retry\.cmd") "the rewrite is not reported: $output"
}

Invoke-TestCase "throws when the shim cannot be written" {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    # A file where the folder should be, so neither the folder nor the shim can be created.
    Set-Content -LiteralPath $bin -Value "not a folder"
    $threw = $false
    try { Install-OpRetryShim -Folder $bin 6>$null }
    catch { $threw = $true }
    Assert-That $threw "a shim that could not be written did not throw"
}

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue

if ($script:failures -gt 0) {
    exit 1
}
Write-Host "[test-op-wrapper-windows] all Windows op retry shim tests passed"
exit 0
