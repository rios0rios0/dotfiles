# Removes dependencies that this repository used to install on Windows but no
# longer declares in run_once_before_windows-001-install-dependencies.ps1.
#
# Deleting a package from the installer only stops NEW machines from getting the
# tool -- machines that already ran it keep the tool forever. chezmoi has no
# concept of packages (it only knows about scripts), so uninstallation has to be
# explicit. See `.docs/dependency-lifecycle.md`.
#
# This is a `run_onchange_` script: chezmoi re-runs it whenever the tombstone list
# below changes, and every handler is idempotent, so it is a silent no-op once a
# machine is clean.

$prefix = "remove-deps"
$script:removed = 0

# =========================================================================================================
# Removal strategies. Each handler takes the target as its only argument, returns
# without acting when the target is already absent, and logs only when it actually
# removes something.

# Uninstall a winget package by its exact package ID.
function Remove-WingetPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Target)

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return }

    $listed = winget list --id $Target --exact --accept-source-agreements 2>$null | Out-String
    if ($listed -notmatch [regex]::Escape($Target)) { return }

    if ($PSCmdlet.ShouldProcess($Target, "Uninstall winget package")) {
        Write-Host "[$prefix] removing winget package: $Target"
        winget uninstall --id $Target --exact --accept-source-agreements | Out-Null
        $script:removed++
    }
}

# Uninstall a globally installed npm package.
function Remove-NpmGlobalPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Target)

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { return }

    npm ls -g --depth=0 $Target 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return }

    if ($PSCmdlet.ShouldProcess($Target, "Uninstall npm global package")) {
        Write-Host "[$prefix] removing npm global package: $Target"
        npm uninstall -g $Target | Out-Null
        $script:removed++
    }
}

# Delete a file or directory left behind by an installer.
function Remove-TargetPath {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Target)

    if (-not (Test-Path -LiteralPath $Target)) { return }

    # Safety rail: this runs unattended on every tombstone change, so it must
    # never delete outside the user profile directory.
    $userHome = [System.IO.Path]::GetFullPath($HOME)
    $resolved = [System.IO.Path]::GetFullPath($Target)
    if (-not $resolved.StartsWith($userHome + [System.IO.Path]::DirectorySeparatorChar)) {
        Write-Host "[$prefix] WARN: refusing to remove '$Target' (outside `$HOME)"
        return
    }

    if ($PSCmdlet.ShouldProcess($Target, "Remove path")) {
        Write-Host "[$prefix] removing path: $Target"
        # -Confirm:$false so the outer ShouldProcess is the only decision point.
        Remove-Item -LiteralPath $Target -Recurse -Force -Confirm:$false
        $script:removed++
    }
}

# Strategy name -> handler function.
$removalHandlers = @{
    "npm_global" = "Remove-NpmGlobalPackage"
    "path"       = "Remove-TargetPath"
    "winget"     = "Remove-WingetPackage"
}

# =========================================================================================================
# Tombstone list, format "<strategy>:<target>". Add one group per removal, newest
# first, and reference the commit that dropped the installer so the entry can be
# retired once every machine has converged.
$tombstones = @(
    # Cursor and Gemini CLI -- removed in 601cbeb (2026-07-21)
    "winget:Anysphere.Cursor",
    "npm_global:@google/gemini-cli"
)

foreach ($tombstone in $tombstones) {
    $strategy, $target = $tombstone -split ":", 2

    if (-not $removalHandlers.ContainsKey($strategy)) {
        Write-Host "[$prefix] WARN: unknown removal strategy '$strategy' for '$target', skipping"
        continue
    }

    # A single failed removal must never abort `chezmoi apply`.
    try {
        & $removalHandlers[$strategy] $target
    }
    catch {
        Write-Host "[$prefix] WARN: failed to remove '$target' via '$strategy': $_"
    }
}

if ($script:removed -gt 0) {
    Write-Host "[$prefix] removed $($script:removed) leftover dependency entries"
}
