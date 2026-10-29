# Writes ~\.local\bin\op-retry.cmd, the shim chezmoi runs 1Password's CLI through on Windows
# (onePassword.command in .chezmoi.yaml.tmpl). 1Password for Windows removes the pipe op connects to
# for about 0.9 s after every CLI call, and an op started in that gap exits at once with "cannot
# connect to 1Password app, make sure it is running" -- the app is running, its pipe is just not
# back yet. chezmoi runs `op account list` and then `op signin` back to back, so every apply failed
# at its first 1Password template; the shim retries exactly that failure, a second after it. WSL's
# ~/.local/bin/op wrapper (run_once_before_linux-001-create-op-wrapper.sh) does the same there.
#
# A batch file, because chezmoi can only execute a program or a batch file, and cmd.exe hands
# op.exe's stdout to chezmoi untouched, where a PowerShell shim would decode and re-encode it. It is
# not on PATH, so op in a terminal still runs op.exe itself. A `run_before_` script rather than a
# managed file: templates call op before chezmoi writes any file, so the shim has to exist by then,
# and one that went missing or was edited is put back by the next apply.
#
# The folder is a parameter for test-op-wrapper-windows.ps1, which dot-sources this file; chezmoi
# passes nothing.

param(
    [string]$BinFolder = (Join-Path ([System.Environment]::GetFolderPath("UserProfile")) ".local\bin")
)

$prefix = "op-wrapper"

# cmd.exe parses %* again: safe for what chezmoi passes (item names, op:// references and flags,
# which Go quotes when they hold a space), not for an unquoted argument holding & | < > or %.
$shim = @'
@echo off
rem Written by run_before_windows-000-create-op-wrapper.ps1 from rios0rios0/dotfiles before every
rem chezmoi apply; chezmoi runs 1Password's CLI through it. 1Password for Windows removes the pipe op
rem connects to for about 0.9 s after every CLI call, and an op started in that gap exits at once
rem with "cannot connect to 1Password app, make sure it is running", so retry exactly that failure.
setlocal EnableExtensions DisableDelayedExpansion
set "OP_RETRY_ERR=%TEMP%\op-retry-%RANDOM%%RANDOM%.err"
set /a OP_RETRY_ATTEMPT=1
:attempt
op.exe %* 2>"%OP_RETRY_ERR%"
set "OP_RETRY_RC=%ERRORLEVEL%"
if "%OP_RETRY_RC%"=="0" goto done
if %OP_RETRY_ATTEMPT% geq 4 goto done
findstr /c:"cannot connect to 1Password app" "%OP_RETRY_ERR%" >nul || goto done
set /a OP_RETRY_ATTEMPT+=1
rem ping waits a second between its two echoes; timeout.exe refuses to run when stdin is redirected
ping -n 2 127.0.0.1 >nul
goto attempt
:done
type "%OP_RETRY_ERR%" >&2
del "%OP_RETRY_ERR%" >nul 2>&1
exit /b %OP_RETRY_RC%
'@

# The here-string takes this file's line endings, which a checkout may have turned into LF; batch
# labels need CRLF, so the lines are joined again.
$shimContent = (($shim -split "`r?`n") -join "`r`n") + "`r`n"

# Writes the shim into the folder unless the one there is already current. Throws when it cannot.
function Install-OpRetryShim {
    param([string]$Folder)

    $path = Join-Path $Folder "op-retry.cmd"
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and ([System.IO.File]::ReadAllText($path) -ceq $shimContent)) {
        Write-Host "[$prefix] $path is already in place"
        return
    }
    New-Item -ItemType Directory -Path $Folder -Force -ErrorAction Stop | Out-Null
    # ASCII without a byte order mark: cmd.exe would read a BOM as part of the first command.
    [System.IO.File]::WriteAllText($path, $shimContent, [System.Text.Encoding]::ASCII)
    Write-Host "[$prefix] wrote $path, which retries an op call the 1Password app turned away"
}

# Dot-sourcing the script, as `make test-op-wrapper-windows` does, stops here with the functions
# defined; running it writes the shim.
if ($MyInvocation.InvocationName -eq ".") { return }

# Without the shim, every 1Password template fails, so a shim that cannot be written stops the apply.
try {
    Install-OpRetryShim -Folder $BinFolder
}
catch {
    Write-Host "[$prefix] ERROR: could not write op-retry.cmd into ${BinFolder}: $_"
    exit 1
}
