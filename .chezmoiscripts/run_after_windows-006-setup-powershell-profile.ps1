# Makes PowerShell 7 start with Oh My Posh and the ~/.oh-my-posh.json theme chezmoi deploys: one
# managed block in its all-hosts profile, Documents\PowerShell\profile.ps1. Documents is found
# through Windows' known folder, because OneDrive can move it (to "OneDrive - <org>\Documents"),
# so no fixed path under $HOME reaches it. Everything outside the block is the user's and stays.
#
# PowerShell 7 only: Windows PowerShell 5.1 runs no profile under its default execution policy
# (Restricted), and changing that policy is the user's call, not an apply's.
#
# A `run_after_` script: it runs on every apply, after the theme is written, says when the block is
# already in place, and writes only when the block is missing or differs. A failure warns, and the
# next apply retries it. -DocumentsFolder exists for test-powershell-profile-windows.ps1.

param([string]$DocumentsFolder = [Environment]::GetFolderPath("MyDocuments"))

$prefix = "powershell-profile"
$begin = "# >>> rios0rios0/dotfiles: oh-my-posh >>>"
$end = "# <<< rios0rios0/dotfiles: oh-my-posh <<<"
$block = @(
    $begin,
    "# Written by chezmoi (run_after_windows-006-setup-powershell-profile.ps1); what is between these markers is replaced.",
    'if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {',
    '    oh-my-posh init pwsh --config "$HOME\.oh-my-posh.json" | Invoke-Expression',
    '}',
    $end
) -join "`r`n"

# Puts the block into the profile and says what it did: "unchanged", "updated" or "added".
function Install-OhMyPoshBlock {
    param([string]$ProfilePath)

    $current = ""
    if (Test-Path -LiteralPath $ProfilePath) {
        $current = [string](Get-Content -LiteralPath $ProfilePath -Raw)
    }
    $pattern = "(?s)" + [regex]::Escape($begin) + ".*?" + [regex]::Escape($end)
    $found = [regex]::Match($current, $pattern)
    if ($found.Success -and $found.Value -eq $block) {
        return "unchanged"
    }
    if ($found.Success) {
        # Spliced by position: a replacement string would read the `$` in the block as a group.
        $updated = $current.Substring(0, $found.Index) + $block + $current.Substring($found.Index + $found.Length)
        $status = "updated"
    }
    else {
        $separator = if (-not $current) { "" } elseif ($current.EndsWith("`n")) { "`r`n" } else { "`r`n`r`n" }
        $updated = $current + $separator + $block + "`r`n"
        $status = "added"
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $ProfilePath) -Force | Out-Null
    Set-Content -LiteralPath $ProfilePath -Value $updated -NoNewline -Encoding UTF8
    return $status
}

# Dot-sourcing the script, as `make test-powershell-profile-windows` does, stops here with the
# function defined; running it sets up the profile.
if ($MyInvocation.InvocationName -eq ".") { return }

if (-not $DocumentsFolder) {
    Write-Host "[$prefix] WARN: Windows reports no Documents folder, so there is no PowerShell profile to set up"
    exit 0
}
$profilePath = Join-Path $DocumentsFolder "PowerShell\profile.ps1"
try {
    switch (Install-OhMyPoshBlock -ProfilePath $profilePath) {
        "unchanged" { Write-Host "[$prefix] Oh My Posh is already set up in $profilePath" }
        "updated" { Write-Host "[$prefix] updated the Oh My Posh block in $profilePath" }
        default { Write-Host "[$prefix] set up Oh My Posh in $profilePath; new PowerShell 7 sessions start with it" }
    }
}
catch {
    Write-Host "[$prefix] WARN: could not set up Oh My Posh in ${profilePath}: $_; the next apply tries again"
}
