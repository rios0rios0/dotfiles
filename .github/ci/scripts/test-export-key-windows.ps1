# Exercises .chezmoiscripts/run_before_windows-004-export-private-key.ps1.tmpl, which puts the
# chezmoi age key at ~\.ssh\chezmoi before every apply. A key that matches is left alone without
# reaching 1Password; a missing or older one is fetched; and a read that fails, or returns some
# other key, fails the apply without touching the file -- the run_once_ version reported such a
# read as success and was never run again.
#
# `op` is stubbed, so this runs under pwsh on any OS and never reaches 1Password. The template's
# two actions are rendered here the way chezmoi's squote would render them.

$template = Join-Path $PSScriptRoot "../../../.chezmoiscripts/run_before_windows-004-export-private-key.ps1.tmpl"
$script:failures = 0

Write-Host "[test-export-key-windows] testing the Windows key export..."

$recipient = "age1testrecipient"
$reference = "op://Private/chezmoi.age/private key"
$goodKey = "# created: 2026-10-27T00:00:00Z`n# public key: $recipient`nAGE-SECRET-KEY-1TESTVALUE"
$otherKey = "# created: 2026-10-27T00:00:00Z`n# public key: age1someoneelse`nAGE-SECRET-KEY-1OTHERVALUE"
$sshKey = "-----BEGIN OPENSSH PRIVATE KEY-----`nAAAA`n-----END OPENSSH PRIVATE KEY-----`n"

$scriptUnderTest = Join-Path ([System.IO.Path]::GetTempPath()) "export-key-$([guid]::NewGuid()).ps1"
(Get-Content -Raw -LiteralPath $template).
    Replace('{{ .ageKeys.chezmoi.recipient | squote }}', "'$recipient'").
    Replace('{{ .ageKeys.chezmoi.privateKey | squote }}', "'$reference'") |
    Set-Content -LiteralPath $scriptUnderTest -NoNewline

# PowerShell resolves a function before an application of the same name, so the script under
# test calls this stub instead of the real CLI. The script runs in a scope of its own, so the
# stub keeps its state in members of one object, which it finds by walking up from the call.
$opState = @{ Calls = [System.Collections.Generic.List[string]]::new(); Output = $goodKey; ExitCode = 0 }

function op {
    $opState.Calls.Add($args -join " ")
    $global:LASTEXITCODE = $opState.ExitCode
    if ($opState.ExitCode -eq 0) { $opState.Output -split "`n" }
}

# Prints a case's outcome under the suite's prefix. Write-Host belongs in a Show- function, as
# PSScriptAnalyzer's PSAvoidUsingWriteHost puts it, so Invoke-TestCase leaves the printing here.
function Show-TestResult {
    param([string]$Message)

    Write-Host "[test-export-key-windows] $Message"
}

function Invoke-TestCase {
    param([string]$Description, [scriptblock]$Body)

    $opState.Calls.Clear()
    $opState.Output = $goodKey
    $opState.ExitCode = 0
    $script:sshFolder = Join-Path ([System.IO.Path]::GetTempPath()) "export-key-ssh-$([guid]::NewGuid())"
    try {
        & $Body
        Show-TestResult "PASS: $Description"
    }
    catch {
        Show-TestResult "FAIL: $Description -- $_"
        $script:failures++
    }
    finally {
        Remove-Item -LiteralPath $script:sshFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Runs the script against the case's folder and returns its exit code. A run that ends without
# `exit` leaves LASTEXITCODE as it was, so it starts at 0.
function Invoke-Export {
    $global:LASTEXITCODE = 0
    & $scriptUnderTest -SshFolder $script:sshFolder *> $null
    return $global:LASTEXITCODE
}

function Write-KeyFile {
    param([string]$Content)

    New-Item -ItemType Directory -Path $script:sshFolder -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $script:sshFolder "chezmoi") -Value $Content -NoNewline
}

function Get-KeyFile {
    $path = Join-Path $script:sshFolder "chezmoi"
    if (Test-Path -LiteralPath $path) { return Get-Content -Raw -LiteralPath $path }
    return $null
}

function Assert-That {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) { throw $Message }
}

Invoke-TestCase "fetches the key when there is none, from the personal account" {
    $exitCode = Invoke-Export
    Assert-That ($exitCode -eq 0) "exit code $exitCode"
    Assert-That ((Get-KeyFile) -ceq $goodKey) "the file does not hold the key: $(Get-KeyFile)"
    Assert-That ($opState.Calls.Count -eq 1) "op was called $($opState.Calls.Count) times"
    Assert-That ($opState.Calls[0] -match [regex]::Escape("$reference --account my")) "op was called with: $($opState.Calls[0])"
}

Invoke-TestCase "leaves a matching key alone without reaching 1Password" {
    Write-KeyFile $goodKey
    $exitCode = Invoke-Export
    Assert-That ($exitCode -eq 0) "exit code $exitCode"
    Assert-That ($opState.Calls.Count -eq 0) "op was called: $($opState.Calls -join '; ')"
}

Invoke-TestCase "replaces an older key, as the SSH key this repository used before" {
    Write-KeyFile $sshKey
    $exitCode = Invoke-Export
    Assert-That ($exitCode -eq 0) "exit code $exitCode"
    Assert-That ((Get-KeyFile) -ceq $goodKey) "the older key was not replaced"
}

Invoke-TestCase "fails without touching the file when op fails" {
    Write-KeyFile $sshKey
    $opState.ExitCode = 1
    $exitCode = Invoke-Export
    Assert-That ($exitCode -eq 1) "exit code $exitCode"
    Assert-That ((Get-KeyFile) -ceq $sshKey) "the file was changed"
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $script:sshFolder "chezmoi.tmp"))) "a staged file was left behind"
}

Invoke-TestCase "refuses a key for another recipient" {
    $opState.Output = $otherKey
    $exitCode = Invoke-Export
    Assert-That ($exitCode -eq 1) "exit code $exitCode"
    Assert-That ($null -eq (Get-KeyFile)) "the wrong key was written"
}

Remove-Item -LiteralPath $scriptUnderTest -Force

if ($script:failures -gt 0) {
    exit 1
}
Write-Host "[test-export-key-windows] all Windows key export tests passed"
exit 0
