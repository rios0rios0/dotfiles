# Exercises how PowerShell 7 gets its profile on Windows. Windows Terminal's PowerShell profile
# (AppData/Local/Packages/Microsoft.WindowsTerminal_+/LocalState/settings.json) starts pwsh with a
# command line that dot-sources ~/.config/powershell/profile.ps1, which chezmoi deploys from
# dot_config/powershell/profile.ps1. That command runs here in a child pwsh whose home is a scratch
# folder holding the profile: with a stub oh-my-posh, the init gets the theme's path and what it
# prints lands in the session's own scope; without one, the session starts with no error. Runs
# under pwsh on Linux, where $HOME follows the HOME variable.

$repo = Join-Path $PSScriptRoot "../../.."
$settingsPath = Join-Path $repo "AppData/Local/Packages/Microsoft.WindowsTerminal_+/LocalState/settings.json"
$profileSource = Join-Path $repo "dot_config/powershell/profile.ps1"
$pwsh = (Get-Process -Id $PID).Path
$script:failures = 0

Write-Host "[test-powershell-profile-windows] testing PowerShell 7's profile from Windows Terminal..."

$root = Join-Path ([System.IO.Path]::GetTempPath()) "pwsh-profile-test-$([guid]::NewGuid())"

$terminalProfile = (Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json).profiles.list |
    Where-Object { $_.source -eq "Windows.Terminal.PowershellCore" }
$commandLine = [string]$terminalProfile.commandline

function Invoke-TestCase {
    param([string]$Description, [scriptblock]$Body)

    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path (Join-Path $root ".config/powershell") -Force | Out-Null
    Copy-Item -LiteralPath $profileSource -Destination (Join-Path $root ".config/powershell/profile.ps1")
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

# Runs what Windows Terminal hands to -Command in a child pwsh whose home is the scratch folder,
# between $Prelude and $Probe, and returns everything the session printed.
function Invoke-TerminalCommand {
    param([string]$Prelude, [string]$Probe)

    $command = [regex]::Match($commandLine, '-Command "(.*)"$').Groups[1].Value
    $savedHome = $env:HOME
    try {
        $env:HOME = $root
        $session = (@($Prelude, $command, $Probe) | Where-Object { $_ }) -join "; "
        (& $pwsh -NoProfile -NonInteractive -Command $session 2>&1 | ForEach-Object { "$_" }) -join "`n"
    }
    finally {
        $env:HOME = $savedHome
    }
}

Invoke-TestCase "starts pwsh through its alias, keeps the session open, and dot-sources the profile" {
    Assert-That ($commandLine -ceq 'pwsh.exe -NoExit -Command ". $HOME/.config/powershell/profile.ps1"') "command line: $commandLine"
}

Invoke-TestCase "runs Oh My Posh's init with the theme, in the session's own scope" {
    $output = Invoke-TerminalCommand -Prelude 'function oh-my-posh { "`$ompInit = ''$($args -join '' '')''" }' -Probe '"init=$ompInit"'
    $theme = Join-Path $root ".oh-my-posh.json"
    Assert-That ($output -ceq "init=init pwsh --config $theme") "printed: $output"
}

Invoke-TestCase "starts the session with no error where Oh My Posh is not installed" {
    $output = Invoke-TerminalCommand -Probe '"started"'
    Assert-That ($output -ceq "started") "printed: $output"
}

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue

if ($script:failures -gt 0) {
    exit 1
}
Write-Host "[test-powershell-profile-windows] all PowerShell profile tests passed"
exit 0
