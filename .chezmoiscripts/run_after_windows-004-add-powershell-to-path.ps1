# Puts PowerShell 7's folder on the user's PATH when no folder on PATH holds pwsh.exe. Windows
# Terminal's PowerShell profile starts `pwsh.exe` by name (see "PowerShell Profile (Oh My Posh)" in
# AGENTS.md), and only PATH resolves that name: with PowerShell 7's folder on neither the machine's
# nor the user's PATH, the profile fails to open with error 2147942402 (0x80070002), "The system
# cannot find the file specified", although PowerShell 7 is installed.
#
# A `run_after_` script, not `run_once_`: it runs on every apply, so a PATH that an installer or an
# update rewrites without the folder is put right by the next apply. It writes the user's PATH,
# under HKCU, which needs no administrator rights, and leaves the machine's alone. A failure only
# warns, since the next apply tries again.
#
# The registry reads, the write and the broadcast after it are functions of their own, for
# test-powershell-path-windows.ps1, which dot-sources this file and replaces them; chezmoi passes
# no argument.

param(
    [string]$DefaultFolder = $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles "PowerShell\7" })
)

$prefix = "pwsh-path"

# A scope's PATH, "Machine" or "User", as the registry holds it -- its variables unexpanded -- and
# the value's kind; an empty REG_EXPAND_SZ, the kind Windows gives PATH, when there is none.
function Get-PathValue {
    param([string]$Scope)

    $key = if ($Scope -eq "Machine") {
        [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Control\Session Manager\Environment")
    }
    else {
        [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment")
    }
    $pathValue = @{ Value = ""; Kind = "ExpandString" }
    if ($null -eq $key) { return $pathValue }
    try {
        $value = $key.GetValue("Path", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -ne $value) {
            $pathValue = @{ Value = [string]$value; Kind = [string]$key.GetValueKind("Path") }
        }
    }
    finally {
        $key.Close()
    }
    return $pathValue
}

# Writes the user's PATH as a value of the given kind. [Environment]::SetEnvironmentVariable would
# write REG_SZ with every variable expanded, so %USERPROFILE% and the like would stop following
# their variables for good.
function Write-UserPath {
    param([string]$Value, [string]$Kind)

    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("Environment")
    try {
        $key.SetValue("Path", $Value, [Microsoft.Win32.RegistryValueKind]$Kind)
    }
    finally {
        $key.Close()
    }
}

# Tells the running programs that the environment changed, as the Environment Variables dialog does,
# so that Explorer, which starts Windows Terminal, reads the new PATH without a sign-out.
function Send-EnvironmentChange {
    if (-not ("Dotfiles.EnvironmentChange" -as [type])) {
        Add-Type -Namespace Dotfiles -Name EnvironmentChange -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);'
    }
    $result = [UIntPtr]::Zero
    # HWND_BROADCAST and WM_SETTINGCHANGE; SMTO_ABORTIFHUNG skips a hung window instead of waiting
    # on it, and any other window gets five seconds at most.
    [void][Dotfiles.EnvironmentChange]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result)
}

# PowerShell 7's installations as its installer records them, each with its version and the folder
# that holds its pwsh.exe.
function Get-PowerShellInstallation {
    Get-ChildItem -LiteralPath "HKLM:\SOFTWARE\Microsoft\PowerShellCore\InstalledVersions" -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath } |
        Where-Object { $_.InstallLocation } |
        ForEach-Object { [pscustomobject]@{ Version = [string]$_.SemanticVersion; Folder = [string]$_.InstallLocation } }
}

# The folders a PATH value names, as Windows searches them: quotes and a trailing backslash dropped,
# empty entries skipped, and variables expanded only in a REG_EXPAND_SZ value, the one kind Windows
# expands.
function Get-PathFolder {
    param([string]$Value, [switch]$Expand)

    foreach ($entry in ($Value -split ";")) {
        $folder = $entry.Trim().Trim('"')
        if ($Expand) { $folder = [Environment]::ExpandEnvironmentVariables($folder) }
        $folder = $folder.TrimEnd("\")
        if ($folder) { $folder }
    }
}

# True when the folder holds pwsh.exe: PowerShell 7 itself, or the Store build's alias.
function Test-PowerShellFolder {
    param([string]$Folder)

    if (-not $Folder) { return $false }
    try {
        return Test-Path -LiteralPath (Join-Path $Folder "pwsh.exe") -PathType Leaf
    }
    catch {
        # A PATH entry that is no valid path, such as one holding a character no path may.
        return $false
    }
}

# A version PowerShell's installer records, such as 7.6.10 or 7.7.0-preview.2, as a [version] to
# sort by, without its prerelease label; 0.0 when it is not one.
function ConvertTo-PowerShellVersion {
    param([string]$Text)

    $version = $null
    if ([version]::TryParse(($Text -replace "-.*$", ""), [ref]$version)) { return $version }
    return [version]"0.0"
}

# The folder to put on PATH: of the folders PowerShell 7's installer recorded, a stable version's
# before a preview's and the newest first, then the default folder -- the first that holds pwsh.exe.
function Find-PowerShellFolder {
    param([string]$DefaultFolder)

    $recorded = @(Get-PowerShellInstallation | Sort-Object -Property @(
            @{ Expression = { $_.Version -like "*-*" } },
            @{ Expression = { ConvertTo-PowerShellVersion -Text $_.Version }; Descending = $true }
        ))
    foreach ($folder in @($recorded | ForEach-Object { $_.Folder }) + @($DefaultFolder)) {
        if (Test-PowerShellFolder -Folder $folder) {
            return $folder.TrimEnd("\")
        }
    }
    return $null
}

# Adds PowerShell 7's folder to the end of the user's PATH unless a folder on the machine's or the
# user's PATH already holds pwsh.exe: the installer's folder, or the Store build's alias in
# %LOCALAPPDATA%\Microsoft\WindowsApps. Every other entry stays as it was, variables unexpanded.
function Invoke-PowerShellPath {
    param([string]$DefaultFolder)

    $machinePath = Get-PathValue -Scope "Machine"
    $userPath = Get-PathValue -Scope "User"
    $folders = @(Get-PathFolder -Value $machinePath.Value -Expand:($machinePath.Kind -eq "ExpandString")) +
        @(Get-PathFolder -Value $userPath.Value -Expand:($userPath.Kind -eq "ExpandString"))
    foreach ($folder in $folders) {
        if (Test-PowerShellFolder -Folder $folder) {
            Write-Host "[$prefix] PowerShell 7 is already on PATH ($folder), skipping"
            return
        }
    }

    $powerShellFolder = Find-PowerShellFolder -DefaultFolder $DefaultFolder
    if (-not $powerShellFolder) {
        Write-Host "[$prefix] WARN: PowerShell 7 is not installed, so Windows Terminal's PowerShell profile cannot start; the Windows installer installs it (Microsoft.PowerShell)"
        return
    }

    $entries = $userPath.Value.TrimEnd(";")
    $newValue = if ($entries) { "$entries;$powerShellFolder" } else { $powerShellFolder }
    try {
        Write-UserPath -Value $newValue -Kind $userPath.Kind
    }
    catch {
        Write-Host "[$prefix] WARN: $powerShellFolder was not added to the user's PATH: $_; the next apply tries again"
        return
    }
    try {
        Send-EnvironmentChange
        Write-Host "[$prefix] added $powerShellFolder to the user's PATH; restart Windows Terminal for its PowerShell profile to find pwsh.exe"
    }
    catch {
        Write-Host "[$prefix] WARN: added $powerShellFolder to the user's PATH, but running programs were not told ($_); sign out and back in for Windows Terminal to see it"
    }
}

# Dot-sourcing the script, as `make test ONLY=powershell-path-windows` does, stops here with the
# functions defined; running it puts PowerShell 7 on PATH when it is missing.
if ($MyInvocation.InvocationName -eq ".") { return }

Invoke-PowerShellPath -DefaultFolder $DefaultFolder
