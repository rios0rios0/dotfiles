# Configures what the installer put on the machine: Kali in WSL, and the drive WSL's disks live on.
#
# Kali is installed and made the default distribution where it is missing, and WSL is updated where
# it is not. Then, when kali-linux or Docker Desktop's disks are on the system drive and another
# internal drive has room for them, the script asks whether to move them to <drive>:\wsl, and moves
# them on a yes (see AGENTS.md, "WSL Disks Off the System Drive"). Nothing about the move fails the
# apply: every step that goes wrong is a WARN, and leaves what it was moving where it was. A
# `run_once_` script, so it asks on a fresh machine's first apply, and again only when it changes.
#
# Dot-sourcing the script, as `make test ONLY=configure-dependencies-windows` does, stops before
# anything runs, with the functions defined.

$prefix = "wsl-move"

# Buses a disk can be unplugged from. Their volumes report DriveType Fixed all the same -- an
# external USB disk on alien-a51 does -- and WSL cannot start a distribution whose disk is gone. A
# mounted VHD (File Backed Virtual) and iSCSI keep their data in another file or on another machine.
$removableBusTypes = @("USB", "1394", "SD", "MMC", "File Backed Virtual", "iSCSI")

# Free space the target keeps after the move, so the disks do not fill it the moment they land.
$wslMoveHeadroom = 10GB

# The drive letter of a Windows path, without its colon, or nothing for a UNC path. WSL registers
# some distributions under the \\?\ prefix: Docker Desktop's is \\?\C:\Users\...\Docker\wsl\main.
function Get-PathDrive {
    param([string]$Path)

    if ($Path -match '^(\\\\\?\\)?([A-Za-z]):') {
        return $Matches[2].ToUpperInvariant()
    }
    return ""
}

function Format-Size {
    param([long]$Bytes)

    return "{0:N1} GB" -f ($Bytes / 1GB)
}

# The WSL distributions registered for this user, each with the folder its disk is in. WSL keeps
# them under this key; `wsl.exe --list` says nothing of where they are.
function Get-WslDistro {
    Get-ChildItem -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction SilentlyContinue |
        Get-ItemProperty -ErrorAction SilentlyContinue |
        Where-Object { $_.DistributionName -and $_.BasePath } |
        ForEach-Object {
            [pscustomobject]@{
                Name     = $_.DistributionName
                BasePath = $_.BasePath -replace '^\\\\\?\\', ''
                VhdName  = $(if ($_.VhdFileName) { $_.VhdFileName } else { "ext4.vhdx" })
            }
        }
}

# Every lettered volume on a fixed disk, with its file system, its free space and the bus of the
# disk it is on.
function Get-WslVolume {
    Get-Volume | Where-Object { $_.DriveLetter -and "$($_.DriveType)" -eq "Fixed" } | ForEach-Object {
        $letter = "$($_.DriveLetter)"
        try {
            $busType = "$((Get-Partition -DriveLetter $letter -ErrorAction Stop | Get-Disk -ErrorAction Stop).BusType)"
        }
        catch {
            # A volume whose disk Windows does not name, one on a dynamic disk for instance, is judged
            # by its file system and free space alone.
            $busType = "Unknown"
        }
        [pscustomobject]@{
            DriveLetter = $letter
            FileSystem  = "$($_.FileSystem)"
            Free        = [long]$_.SizeRemaining
            BusType     = $busType
        }
    }
}

# The size of a disk file, or $null when there is none.
function Get-DiskLength {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($item -and -not $item.PSIsContainer) {
        return [long]$item.Length
    }
    return $null
}

# Docker Desktop's WSL data folder: CustomWslDistroDir in its settings ("Disk image location" in
# Settings > Resources > Advanced), or %LOCALAPPDATA%\Docker\wsl until that is set. It holds the
# docker-desktop distribution, main\ext4.vhdx (about 100 MB), and disk\docker_data.vhdx, the disk
# every image, container and volume is on (28 GB on alien-a51). That disk is no distribution, so no
# `wsl` command moves it: Docker Desktop attaches it from this folder when it starts. $null when the
# settings are not valid JSON, since the folder is unknown then.
function Get-DockerWslDataDir {
    param([string]$SettingsPath, [string]$DefaultDir)

    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        return $DefaultDir
    }
    try {
        $text = [System.IO.File]::ReadAllText($SettingsPath)
        $settings = $null
        if ($text.Trim()) {
            $settings = $text | ConvertFrom-Json -ErrorAction Stop
        }
    }
    catch {
        Write-Host "[$prefix] WARN: $SettingsPath is not valid JSON, so where Docker Desktop keeps its disks is unknown: $_"
        return $null
    }
    if ($settings -and $settings.CustomWslDistroDir) {
        return [string]$settings.CustomWslDistroDir
    }
    return $DefaultDir
}

# The volume to move WSL's disks to: a lettered volume other than the system drive, NTFS or ReFS
# (WSL grants its VM access to a disk through the file's ACL, which FAT and exFAT do not have), on a
# disk that cannot be unplugged, with room for what moves plus the headroom; of those, the one with
# the most free space. It need not have more free space than the system drive: getting WSL off it
# is the point, and alien-a51's data drive D:, which holds kali-linux by choice, had less than C:
# (650 GB against 664 GB). The question shows both.
function Select-WslTargetVolume {
    param([object[]]$Volume, [string]$SystemDrive, [long]$Bytes)

    $Volume |
        Where-Object {
            $_.DriveLetter -ne $SystemDrive -and
            @("NTFS", "ReFS") -contains $_.FileSystem -and
            $removableBusTypes -notcontains $_.BusType -and
            $_.Free -ge ($Bytes + $wslMoveHeadroom)
        } |
        Sort-Object -Property Free -Descending |
        Select-Object -First 1
}

# What moves where. kali-linux and Docker Desktop's disks move only from the system drive: kali-linux
# to <drive>:\wsl\kali-linux, and Docker Desktop's data folder to <drive>:\wsl\docker-desktop, with
# its distribution in main\ under it, where Docker Desktop keeps it beside disk\. A target folder
# that already holds a disk -- a previous install's, after Windows was reinstalled -- is never
# written over: that part stays, with a note.
function Get-WslMovePlan {
    param(
        [object[]]$Distro,
        [string]$DockerDataDir,
        [object[]]$Volume,
        [string]$SystemDrive
    )

    $plan = [pscustomobject]@{
        Kali        = $null
        KaliMissing = $false
        Docker      = $null
        Target      = $null
        Root        = $null
        SystemFree  = $null
        Notes       = @()
    }

    $kali = $Distro | Where-Object { $_.Name -eq "kali-linux" } | Select-Object -First 1
    $plan.KaliMissing = -not $kali
    if ($kali -and (Get-PathDrive $kali.BasePath) -eq $SystemDrive) {
        $plan.Kali = [pscustomobject]@{
            From  = $kali.BasePath
            To    = $null
            Disk  = $kali.VhdName
            Bytes = [long](Get-DiskLength "$($kali.BasePath)\$($kali.VhdName)")
        }
    }

    if ($DockerDataDir -and (Get-PathDrive $DockerDataDir) -eq $SystemDrive) {
        $dockerDistro = $Distro | Where-Object { $_.Name -eq "docker-desktop" } | Select-Object -First 1
        $moveDistro = [bool]($dockerDistro -and (Get-PathDrive $dockerDistro.BasePath) -eq $SystemDrive)
        $distroBytes = $null
        if ($moveDistro) {
            $distroBytes = Get-DiskLength "$($dockerDistro.BasePath)\$($dockerDistro.VhdName)"
        }
        $dataBytes = Get-DiskLength "$DockerDataDir\disk\docker_data.vhdx"
        $plan.Docker = [pscustomobject]@{
            From         = $DockerDataDir
            To           = $null
            MoveDistro   = $moveDistro
            MoveDataDisk = $null -ne $dataBytes
            DataBytes    = [long]$dataBytes
            Bytes        = [long]$distroBytes + [long]$dataBytes
        }
    }
    if (-not $plan.Kali -and -not $plan.Docker) {
        return $plan
    }

    $bytes = [long]0
    if ($plan.Kali) { $bytes += $plan.Kali.Bytes }
    if ($plan.Docker) { $bytes += $plan.Docker.Bytes }
    $system = $Volume | Where-Object { $_.DriveLetter -eq $SystemDrive } | Select-Object -First 1
    if ($system) { $plan.SystemFree = $system.Free }
    $plan.Target = Select-WslTargetVolume -Volume $Volume -SystemDrive $SystemDrive -Bytes $bytes
    if (-not $plan.Target) {
        return $plan
    }
    $plan.Root = "$($plan.Target.DriveLetter):\wsl"

    if ($plan.Kali) {
        $to = "$($plan.Root)\kali-linux"
        if ($null -ne (Get-DiskLength "$to\$($plan.Kali.Disk)")) {
            $plan.Notes += "WARN: $to already holds $($plan.Kali.Disk), a previous install's perhaps, so kali-linux stays in $($plan.Kali.From); move that disk away first, or register it in place of this one with wsl --import-in-place"
            $plan.Kali = $null
        }
        else {
            $plan.Kali.To = $to
        }
    }
    if ($plan.Docker) {
        $to = "$($plan.Root)\docker-desktop"
        if ($null -ne (Get-DiskLength "$to\disk\docker_data.vhdx") -or $null -ne (Get-DiskLength "$to\main\ext4.vhdx")) {
            $plan.Notes += "WARN: $to already holds Docker Desktop disks, a previous install's perhaps, so Docker Desktop's stay in $($plan.Docker.From); move those away first"
            $plan.Docker = $null
        }
        else {
            $plan.Docker.To = $to
        }
    }
    return $plan
}

# Runs a program and returns its exit code, printing its output under the prefix. Every wsl.exe
# call goes through Invoke-Wsl and every docker call through Invoke-DockerDesktop, so the tests
# replace both and nothing reaches the real programs.
function Invoke-Program {
    param([string]$Name, [string[]]$Arguments)

    if (-not (Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Host "[$prefix] WARN: $Name is not on PATH"
        return 127
    }
    $output = & $Name @Arguments 2>&1
    $code = $LASTEXITCODE
    $output | Where-Object { "$_".Trim() } | ForEach-Object { Write-Host "[$prefix] $_" }
    return $code
}

# WSL_UTF8 makes wsl.exe write UTF-8: captured, its UTF-16 reads with a NUL between characters.
function Invoke-Wsl {
    $env:WSL_UTF8 = "1"
    return Invoke-Program -Name "wsl.exe" -Arguments $args
}

function Invoke-DockerDesktop {
    return Invoke-Program -Name "docker" -Arguments (@("desktop") + $args)
}

# True while Docker Desktop runs: its window or its backend.
function Test-DockerDesktopRunning {
    return [bool](Get-Process -Name "Docker Desktop", "com.docker.backend" -ErrorAction SilentlyContinue)
}

# True when there is a terminal to ask on: chezmoi hands its scripts its own stdin.
function Test-InteractiveInput {
    return -not [Console]::IsInputRedirected
}

function Read-WslMoveAnswer {
    param([string]$Question)

    return (Read-Host -Prompt $Question) -match '^\s*y(es)?\s*$'
}

# A copy written by an elevated apply belongs to BUILTIN\Administrators, and WSL grants its VM
# access to a disk while impersonating the user, who may then change no ACL on it: WSL makes the
# user the owner of every disk it creates or moves for that reason (WslCoreFilesystem.cpp,
# LxssUserSession.cpp). This does the same for Docker's data disk.
function Restore-DiskOwner {
    param([string]$Path)

    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = Get-Acl -LiteralPath $Path
    if ($acl.GetOwner([System.Security.Principal.SecurityIdentifier]) -ne $user) {
        $acl.SetOwner($user)
        Set-Acl -LiteralPath $Path -AclObject $acl
    }
}

# Copies a disk to another volume, and returns only once the copy is on that drive, as
# MOVEFILE_WRITE_THROUGH does for WSL's own move: the caller deletes the original next. The guard
# handle shares the disk with readers only, so the copy cannot start while anything writes to it,
# and nothing can start writing until the copy is done. A copy that fails is deleted.
function Copy-DiskFile {
    param([string]$Source, [string]$Destination)

    $guard = [System.IO.File]::Open($Source, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop
        $stream = [System.IO.File]::Open($Destination, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
        try { $stream.Flush($true) } finally { $stream.Dispose() }
        Restore-DiskOwner -Path $Destination
    }
    catch {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        throw
    }
    finally {
        $guard.Dispose()
    }
}

# Sets CustomWslDistroDir in Docker Desktop's settings, keeping every other key, and creates the
# folder. Docker Desktop reads it when it starts, as it reads what modify_settings-store.json merges
# into the same file. Written as UTF-8 without a BOM, as Docker Desktop writes it: Windows
# PowerShell 5.1's Set-Content -Encoding UTF8 would add one. Invalid JSON is left as it is.
function Write-DockerWslDataDir {
    param([string]$Path, [string]$Directory)

    $settings = New-Object -TypeName PSObject
    if (Test-Path -LiteralPath $Path) {
        $text = [System.IO.File]::ReadAllText($Path)
        if ($text.Trim()) {
            $settings = $text | ConvertFrom-Json -ErrorAction Stop
        }
    }
    $settings | Add-Member -NotePropertyName "CustomWslDistroDir" -NotePropertyValue $Directory -Force
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $json = $settings | ConvertTo-Json -Depth 32
    [System.IO.File]::WriteAllText($Path, $json, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
}

# Moves Docker Desktop's disks to the plan's folder, the data disk first: it is copied, the setting
# that points Docker Desktop at the copy is written, and only then is the original deleted, so a
# failure at any step leaves Docker Desktop with a whole disk where its setting says. The
# distribution moves last, and stays where it is when that fails: Docker Desktop finds it by name.
# A Docker Desktop that never started has no disks yet, and gets the setting alone, so that its
# first start creates them there.
function Move-DockerDesktopDisk {
    param([object]$Docker, [string]$SettingsPath)

    $source = Join-Path (Join-Path $Docker.From "disk") "docker_data.vhdx"
    $destination = Join-Path (Join-Path $Docker.To "disk") "docker_data.vhdx"
    try {
        if ($Docker.MoveDataDisk) {
            Write-Host "[$prefix] copying Docker Desktop's data disk ($(Format-Size $Docker.DataBytes)) to $destination..."
            Copy-DiskFile -Source $source -Destination $destination
        }
        Write-DockerWslDataDir -Path $SettingsPath -Directory $Docker.To
    }
    catch {
        if ($Docker.MoveDataDisk) {
            Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        }
        Write-Host "[$prefix] WARN: Docker Desktop's disks stay in $($Docker.From): $_"
        return
    }
    if ($Docker.MoveDataDisk) {
        Remove-Item -LiteralPath $source -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $source) {
            Write-Host "[$prefix] WARN: the old data disk, $source, could not be deleted; Docker Desktop no longer uses it"
        }
    }
    if ($Docker.MoveDistro) {
        $main = Join-Path $Docker.To "main"
        Write-Host "[$prefix] moving docker-desktop to $main..."
        $code = Invoke-Wsl --manage docker-desktop --move $main
        if ($code -ne 0) {
            Write-Host "[$prefix] WARN: docker-desktop stays where it is (wsl exited with $code); Docker Desktop finds it by name"
        }
    }
    Write-Host "[$prefix] Docker Desktop keeps its disks in $($Docker.To) from its next start"
}

# Moves what the plan names. Docker Desktop is stopped first when it runs, and started again after.
# WSL is shut down when Docker's disks move, which releases the data disk however Docker Desktop
# attached it; when only kali-linux moves, only it is stopped: `wsl --manage --move` refuses a
# running distribution.
function Invoke-WslMovePlan {
    param([object]$Plan, [string]$SettingsPath)

    $docker = $Plan.Docker
    $restartDocker = $false
    if ($docker -and (Test-DockerDesktopRunning)) {
        Write-Host "[$prefix] stopping Docker Desktop..."
        $code = Invoke-DockerDesktop stop --timeout 300
        if ($code -eq 0) {
            $restartDocker = $true
        }
        else {
            Write-Host "[$prefix] WARN: Docker Desktop did not stop (exit code $code), so its disks stay in $($docker.From)"
            $docker = $null
        }
    }

    if ($docker -and ($docker.MoveDistro -or $docker.MoveDataDisk)) {
        Write-Host "[$prefix] shutting WSL down..."
        $code = Invoke-Wsl --shutdown
        if ($code -ne 0) {
            Write-Host "[$prefix] WARN: WSL did not shut down (wsl exited with $code), so nothing moves"
            $docker = $null
            $Plan.Kali = $null
        }
    }
    elseif ($Plan.Kali) {
        $null = Invoke-Wsl --terminate kali-linux
    }

    if ($Plan.Kali) {
        Write-Host "[$prefix] moving kali-linux to $($Plan.Kali.To)..."
        $code = Invoke-Wsl --manage kali-linux --move $Plan.Kali.To
        if ($code -eq 0) {
            $code = Invoke-Wsl --set-default kali-linux
            if ($code -ne 0) {
                Write-Host "[$prefix] WARN: kali-linux moved, but is not the default distribution (wsl exited with $code)"
            }
        }
        else {
            Write-Host "[$prefix] WARN: kali-linux stays in $($Plan.Kali.From) (wsl exited with $code)"
        }
    }
    if ($docker) {
        Move-DockerDesktopDisk -Docker $docker -SettingsPath $SettingsPath
    }
    if ($restartDocker) {
        Write-Host "[$prefix] starting Docker Desktop again..."
        $code = Invoke-DockerDesktop start --detach
        if ($code -ne 0) {
            Write-Host "[$prefix] WARN: Docker Desktop did not start (exit code $code); start it yourself"
        }
    }
}

# How to move them by hand, for a "no" or a run without a terminal: run_once_ does not ask again.
function Show-WslMoveCommand {
    param([object]$Plan)

    if ($Plan.Kali) {
        Write-Host "[$prefix]   wsl --terminate kali-linux; wsl --manage kali-linux --move $($Plan.Kali.To); wsl --set-default kali-linux"
    }
    if ($Plan.Docker) {
        Write-Host "[$prefix]   Docker Desktop's data: Settings > Resources > Advanced > Disk image location, in Docker Desktop"
    }
}

# Says what of WSL's is on the system drive and where it could go, asks whether to move it, and
# moves it on a yes. Without a terminal to ask on, it asks nothing and prints the commands instead.
function Request-WslMove {
    param([string]$SystemDrive, [string]$SettingsPath, [string]$DockerDefaultDir)

    $dockerDataDir = Get-DockerWslDataDir -SettingsPath $SettingsPath -DefaultDir $DockerDefaultDir
    $plan = Get-WslMovePlan -Distro @(Get-WslDistro) -DockerDataDir $dockerDataDir -Volume @(Get-WslVolume) -SystemDrive $SystemDrive
    foreach ($note in $plan.Notes) {
        Write-Host "[$prefix] $note"
    }

    $items = @()
    if ($plan.Kali) {
        $items += "kali-linux ($(Format-Size $plan.Kali.Bytes))"
    }
    if ($plan.Docker -and ($plan.Docker.MoveDistro -or $plan.Docker.MoveDataDisk)) {
        $items += "Docker Desktop's data ($(Format-Size $plan.Docker.Bytes))"
    }
    elseif ($plan.Docker) {
        $items += "Docker Desktop's data (none yet: its first start creates it)"
    }
    if (-not $items) {
        if (-not $plan.Notes) {
            Write-Host "[$prefix] none of WSL's disks is on the system drive, ${SystemDrive}:"
        }
        return
    }

    $systemFree = ""
    if ($null -ne $plan.SystemFree) {
        $systemFree = " ($(Format-Size $plan.SystemFree) free)"
    }
    $what = $items -join " and "
    if (-not $plan.Target) {
        Write-Host "[$prefix] no other internal NTFS or ReFS drive has room for what WSL keeps on the system drive, ${SystemDrive}:${systemFree}: $what"
        return
    }
    Write-Host "[$prefix] on the system drive, ${SystemDrive}:${systemFree}: $what"

    $them = $(if ($items.Count -gt 1) { "them" } else { "it" })
    $stops = ""
    if ($plan.Docker -and ($plan.Docker.MoveDistro -or $plan.Docker.MoveDataDisk)) {
        $stops = " Docker Desktop and WSL stop during the move."
    }
    elseif ($plan.Kali) {
        $stops = " kali-linux stops during the move."
    }
    $question = "[$prefix] Move $them to $($plan.Root) ($(Format-Size $plan.Target.Free) free)?$stops [y/N]"

    if (-not (Test-InteractiveInput)) {
        Write-Host "[$prefix] no terminal to ask on; to move $them yourself:"
        Show-WslMoveCommand -Plan $plan
        return
    }
    if (-not (Read-WslMoveAnswer -Question $question)) {
        Write-Host "[$prefix] nothing moved; to move $them later:"
        Show-WslMoveCommand -Plan $plan
        return
    }

    Invoke-WslMovePlan -Plan $plan -SettingsPath $SettingsPath
    if ($plan.KaliMissing) {
        Write-Host "[$prefix] kali-linux is not installed yet (WSL may be waiting for the reboot it asked for); once it is: wsl --manage kali-linux --move $($plan.Root)\kali-linux"
    }
}

if ($MyInvocation.InvocationName -eq ".") { return }

$distroList = & wsl.exe -l -q
$kaliFound = $false

foreach ($distro in $distroList) {
    if ($distro.Trim().ToLower() -eq "kali-linux") {
        $kaliFound = $true
        break
    }
}

if ($kaliFound) {
    Write-Host "Kali Linux is installed. Updating WSL..."
    wsl.exe --update
} else {
    Write-Host "Kali Linux is NOT installed. Installing Kali Linux distro..."
    wsl.exe --install -d kali-linux

    Write-Host "Setting Kali Linux as the default distro..."
    wsl.exe --setdefault kali-linux
}

# Never fails the apply: the move is optional, and a run_once_ script that exits non-zero stops
# the apply before any file is written.
try {
    Request-WslMove -SystemDrive (Get-PathDrive $env:SystemDrive) `
        -SettingsPath (Join-Path $env:APPDATA "Docker\settings-store.json") `
        -DockerDefaultDir (Join-Path $env:LOCALAPPDATA "Docker\wsl")
}
catch {
    Write-Host "[$prefix] WARN: WSL's disks were not moved: $_"
}
