# PowerShell 7's profile on Windows. PowerShell reads its own profile only from the Documents
# folder Windows reports, which OneDrive can move and Controlled Folder Access guards, so chezmoi
# keeps this one in the user folder instead, and Windows Terminal's PowerShell profile dot-sources
# it: `pwsh.exe -NoExit -Command ". $HOME/.config/powershell/profile.ps1"`. A PowerShell started
# anywhere else skips it. See "PowerShell Profile (Oh My Posh)" in the dotfiles' CLAUDE.md.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'oh-my-posh init prints the script that sets up the prompt')]
param()

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config (Join-Path $HOME '.oh-my-posh.json') | Invoke-Expression
}
