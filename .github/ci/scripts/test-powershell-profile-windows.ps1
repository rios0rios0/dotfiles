# Exercises .chezmoiscripts/run_after_windows-006-setup-powershell-profile.ps1, which puts the
# block that starts Oh My Posh into PowerShell 7's profile on every apply. A missing profile is
# created with the block; an existing one keeps everything outside it; a current block is left as
# it is and reported as already set up; an outdated one is replaced in place. Runs under pwsh on any
# OS, against a scratch Documents folder.

$scriptUnderTest = Join-Path $PSScriptRoot "../../../.chezmoiscripts/run_after_windows-006-setup-powershell-profile.ps1"
$script:failures = 0

Write-Host "[test-powershell-profile-windows] testing the PowerShell profile setup..."

$root = Join-Path ([System.IO.Path]::GetTempPath()) "pwsh-profile-test-$([guid]::NewGuid())"

# Defines Install-OhMyPoshBlock without touching any profile.
. $scriptUnderTest

function Invoke-TestCase {
    param([string]$Description, [scriptblock]$Body)

    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    try {
        & $Body
        Write-Host "[test-powershell-profile-windows] PASS: $Description"
    }
    catch {
        Write-Host "[test-powershell-profile-windows] FAIL: $Description -- $_"
        $script:failures++
    }
}

function Assert-That {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) { throw $Message }
}

function Get-BlockCount {
    param([string]$Text)

    ([regex]::Matches($Text, [regex]::Escape($begin))).Count
}

# Runs the script itself against the scratch Documents folder and returns what it printed.
function Invoke-Setup {
    (& $scriptUnderTest -DocumentsFolder $root 6>&1 | ForEach-Object { "$_" }) -join "`n"
}

$profilePath = Join-Path $root "PowerShell\profile.ps1"

Invoke-TestCase "creates PowerShell 7's profile with the block, and says so" {
    $output = Invoke-Setup
    Assert-That (Test-Path -LiteralPath $profilePath) "no profile at $profilePath"
    $text = Get-Content -LiteralPath $profilePath -Raw
    Assert-That ((Get-BlockCount $text) -eq 1) "expected one block: $text"
    Assert-That ($text -match [regex]::Escape('oh-my-posh init pwsh --config "$HOME\.oh-my-posh.json" | Invoke-Expression')) "the init line is missing: $text"
    Assert-That ($output -match "set up Oh My Posh in") "printed: $output"
}

Invoke-TestCase "reports the block as already set up and leaves the file alone" {
    Invoke-Setup | Out-Null
    $before = Get-Content -LiteralPath $profilePath -Raw
    $output = Invoke-Setup
    Assert-That ((Get-Content -LiteralPath $profilePath -Raw) -ceq $before) "the profile changed"
    Assert-That ($output -match "Oh My Posh is already set up in") "printed: $output"
}

Invoke-TestCase "keeps the user's own profile and appends the block after it" {
    New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath) -Force | Out-Null
    Set-Content -LiteralPath $profilePath -Value "Set-Alias ll Get-ChildItem" -NoNewline
    $status = Install-OhMyPoshBlock -ProfilePath $profilePath
    $text = Get-Content -LiteralPath $profilePath -Raw
    Assert-That ($status -eq "added") "status $status"
    Assert-That ($text.StartsWith("Set-Alias ll Get-ChildItem`r`n`r`n")) "the user's line was not kept first: $text"
    Assert-That ((Get-BlockCount $text) -eq 1) "expected one block: $text"
}

Invoke-TestCase "replaces an outdated block in place, keeping what surrounds it" {
    New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath) -Force | Out-Null
    Set-Content -LiteralPath $profilePath -NoNewline -Value ("before`r`n$begin`r`nold line`r`n$end`r`nafter`r`n")
    $status = Install-OhMyPoshBlock -ProfilePath $profilePath
    $text = Get-Content -LiteralPath $profilePath -Raw
    Assert-That ($status -eq "updated") "status $status"
    Assert-That ($text.StartsWith("before`r`n") -and $text.EndsWith("`r`nafter`r`n")) "the surrounding lines changed: $text"
    Assert-That ($text -notmatch "old line" -and (Get-BlockCount $text) -eq 1) "the old block survived: $text"
    Assert-That ((Install-OhMyPoshBlock -ProfilePath $profilePath) -eq "unchanged") "the replaced block is not stable"
}

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue

if ($script:failures -gt 0) {
    exit 1
}
Write-Host "[test-powershell-profile-windows] all PowerShell profile tests passed"
exit 0
