# Exercises the WSL disk move in .chezmoiscripts/run_once_before_windows-002-configure-dependencies.ps1.
# Where kali-linux and Docker Desktop's disks go: the internal NTFS or ReFS drive other than the
# system drive with the most free space, never a USB one, never over a disk already there. That
# nothing moves without a terminal or without a yes. And the move: kali-linux through wsl, Docker
# Desktop's data disk copied, pointed at and only then deleted, its distribution moved last, Docker
# Desktop stopped and started again around it, and every failure leaving things where they were.
#
# wsl and docker are replaced after the script is dot-sourced, as are the registry, volume and
# file-size lookups, so this runs under pwsh on any OS and moves no WSL distribution; the file
# operations work in a scratch folder.

$scriptUnderTest = Join-Path $PSScriptRoot "../../../.chezmoiscripts/run_once_before_windows-002-configure-dependencies.ps1"
$script:failures = 0

Write-Host "[test-configure-dependencies-windows] testing the WSL disk move..."

# The real wsl.exe or docker must never run from here, and a function wins over a program of the
# same name: a call the replacements below miss fails its case instead of reaching WSL.
function wsl.exe { throw "the real wsl.exe was called: $args" }
function wsl { throw "the real wsl was called: $args" }
function docker { throw "the real docker was called: $args" }

# Defines the functions without running anything.
. $scriptUnderTest

# Defined after the dot-source, these replace the script's own functions of the same names. Every
# wsl and docker call is recorded as its command line, and exits with the code $script:exitCodes
# names for that line, 0 otherwise.
function Invoke-Wsl {
    $call = "wsl $($args -join ' ')"
    $script:calls += $call
    if ($script:exitCodes.ContainsKey($call)) { return $script:exitCodes[$call] }
    return 0
}

function Invoke-DockerDesktop {
    $call = "docker desktop $($args -join ' ')"
    $script:calls += $call
    if ($script:exitCodes.ContainsKey($call)) { return $script:exitCodes[$call] }
    return 0
}

function Test-DockerDesktopRunning { return $script:dockerRunning }
function Get-WslDistro { return $script:distros }
function Get-WslVolume { return $script:volumes }
function Test-InteractiveInput { return $script:interactive }

function Get-DiskLength {
    param([string]$Path)

    if ($script:disks.ContainsKey($Path)) { return [long]$script:disks[$Path] }
    return $null
}

function Read-WslMoveAnswer {
    param([string]$Question)

    $script:questions += $Question
    return $script:answer
}

# Get-Acl works on Windows alone; the owner it would set is recorded instead.
function Restore-DiskOwner {
    param([string]$Path)

    $script:owned += $Path
}

# alien-a51's drives as they were on 2026-11-02, with its external USB disk given more room than any
# of them: an unpluggable disk is never chosen, however much room it has.
$laptopVolumes = @(
    [pscustomobject]@{ DriveLetter = "C"; FileSystem = "NTFS"; Free = 664GB; BusType = "NVMe" },
    [pscustomobject]@{ DriveLetter = "D"; FileSystem = "NTFS"; Free = 650GB; BusType = "NVMe" },
    [pscustomobject]@{ DriveLetter = "E"; FileSystem = "NTFS"; Free = 476GB; BusType = "NVMe" },
    [pscustomobject]@{ DriveLetter = "F"; FileSystem = "NTFS"; Free = 900GB; BusType = "USB" }
)
$kaliDir = "C:\Users\me\AppData\Local\wsl\{917815ac-20e9-42b2-84fc-8c1acfb50441}"
$dockerDir = "C:\Users\me\AppData\Local\Docker\wsl"
$kaliOnC = [pscustomobject]@{ Name = "kali-linux"; BasePath = $kaliDir; VhdName = "ext4.vhdx" }
$kaliOnD = [pscustomobject]@{ Name = "kali-linux"; BasePath = "D:\wsl\kali-linux"; VhdName = "ext4.vhdx" }
$dockerDistro = [pscustomobject]@{ Name = "docker-desktop"; BasePath = "$dockerDir\main"; VhdName = "ext4.vhdx" }
$laptopDisks = @{
    "$kaliDir\ext4.vhdx"               = 2GB
    "$dockerDir\main\ext4.vhdx"        = 100MB
    "$dockerDir\disk\docker_data.vhdx" = 30GB
}

# Prints a case's outcome under the suite's prefix. Write-Host belongs in a Show- function, as
# PSScriptAnalyzer's PSAvoidUsingWriteHost puts it, so Invoke-TestCase leaves the printing here.
function Show-TestResult {
    param([string]$Message)

    Write-Host "[test-configure-dependencies-windows] $Message"
}

function Invoke-TestCase {
    param([string]$Description, [scriptblock]$Body)

    $script:calls = @()
    $script:exitCodes = @{}
    $script:dockerRunning = $false
    $script:distros = @()
    $script:volumes = @()
    $script:disks = @{}
    $script:interactive = $true
    $script:answer = $false
    $script:questions = @()
    $script:owned = @()
    $script:movedPlan = $null
    $script:scratch = Join-Path ([System.IO.Path]::GetTempPath()) "wsl-move-test-$([System.Guid]::NewGuid())"
    New-Item -ItemType Directory -Path $script:scratch -Force | Out-Null
    try {
        & $Body
        Show-TestResult "PASS: $Description"
    }
    catch {
        Show-TestResult "FAIL: $Description -- $_"
        $script:failures++
    }
    finally {
        Remove-Item -LiteralPath $script:scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Runs a command and returns each line it printed, errors included. Out-String is avoided on
# purpose: Windows PowerShell 5.1 wraps its output at the host width.
function Get-Output {
    param([scriptblock]$Command)

    (& $Command 6>&1 2>&1 | ForEach-Object { "$_" }) -join "`n"
}

function Assert-That {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) { throw $Message }
}

# A Docker Desktop data folder in the scratch folder, holding a data disk, and its settings file.
function Get-TestDocker {
    param([switch]$WithDisks)

    $from = Join-Path $script:scratch "c-docker-wsl"
    $to = Join-Path $script:scratch "d-wsl-docker-desktop"
    if ($WithDisks) {
        New-Item -ItemType Directory -Path (Join-Path $from "disk") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path (Join-Path $from "disk") "docker_data.vhdx") -Value "images, containers and volumes" -NoNewline
    }
    $settings = Join-Path (Join-Path $script:scratch "roaming-docker") "settings-store.json"
    New-Item -ItemType Directory -Path (Split-Path -Parent $settings) -Force | Out-Null
    Set-Content -LiteralPath $settings -Value '{"AutoStart":true,"IntegratedWslDistros":["kali-linux"],"SettingsVersion":48}' -NoNewline
    return [pscustomobject]@{
        Settings = $settings
        Plan     = [pscustomobject]@{
            From         = $from
            To           = $to
            MoveDistro   = [bool]$WithDisks
            MoveDataDisk = [bool]$WithDisks
            DataBytes    = 30GB
            Bytes        = 30GB + 100MB
        }
    }
}

function Get-TestPlan {
    param([object]$Kali, [object]$Docker)

    return [pscustomobject]@{ Kali = $Kali; KaliMissing = $false; Docker = $Docker; Root = "D:\wsl"; Notes = @() }
}

$kaliMove = [pscustomobject]@{ From = $kaliDir; To = "D:\wsl\kali-linux"; Disk = "ext4.vhdx"; Bytes = 2GB }

Invoke-TestCase "dot-sourcing the script defines its functions without running anything" {
    # given the script dot-sourced above, with a wsl and a docker that throw when called

    # when nothing else ran

    # then
    Assert-That ([bool](Get-Command Request-WslMove -ErrorAction SilentlyContinue)) "Request-WslMove is not defined"
    Assert-That ([bool](Get-Command Invoke-WslMovePlan -ErrorAction SilentlyContinue)) "Invoke-WslMovePlan is not defined"
}

Invoke-TestCase "reads the drive letter of plain, \\?\ and UNC paths" {
    # given
    $paths = @("C:\Users\me", "d:\wsl", "\\?\C:\Users\me\AppData\Local\Docker\wsl\main", "\\server\share\wsl")

    # when
    $drives = $paths | ForEach-Object { Get-PathDrive $_ }

    # then
    Assert-That (($drives -join ",") -eq "C,D,C,") "drives: $($drives -join ',')"
}

Invoke-TestCase "plans kali-linux and Docker Desktop's disks from the system drive to the roomiest internal drive" {
    # given alien-a51's drives, with kali-linux and Docker Desktop on C:
    $script:disks = $laptopDisks

    # when
    $plan = Get-WslMovePlan -Distro @($kaliOnC, $dockerDistro) -DockerDataDir $dockerDir -Volume $laptopVolumes -SystemDrive "C"

    # then
    Assert-That ($plan.Target.DriveLetter -eq "D") "target: $($plan.Target.DriveLetter), not D (F: is USB, C: is the system drive)"
    Assert-That ($plan.Root -eq "D:\wsl") "root: $($plan.Root)"
    Assert-That ($plan.Kali.To -eq "D:\wsl\kali-linux") "kali-linux goes to $($plan.Kali.To)"
    Assert-That ($plan.Kali.Bytes -eq 2GB) "kali-linux's size: $($plan.Kali.Bytes)"
    Assert-That ($plan.Docker.To -eq "D:\wsl\docker-desktop") "Docker Desktop's data goes to $($plan.Docker.To)"
    Assert-That ($plan.Docker.MoveDistro -and $plan.Docker.MoveDataDisk) "Docker Desktop's disks are not both planned"
    Assert-That ($plan.Docker.Bytes -eq (30GB + 100MB)) "Docker Desktop's size: $($plan.Docker.Bytes)"
    Assert-That ($plan.SystemFree -eq 664GB) "the system drive's free space: $($plan.SystemFree)"
    Assert-That ($plan.Notes.Count -eq 0) "notes: $($plan.Notes -join ' | ')"
}

Invoke-TestCase "leaves a distribution that is already off the system drive alone" {
    # given kali-linux on D:, as on alien-a51, and Docker Desktop on C:
    $script:disks = $laptopDisks

    # when
    $plan = Get-WslMovePlan -Distro @($kaliOnD, $dockerDistro) -DockerDataDir $dockerDir -Volume $laptopVolumes -SystemDrive "C"

    # then
    Assert-That ($null -eq $plan.Kali) "kali-linux on D: was planned to move"
    Assert-That (-not $plan.KaliMissing) "kali-linux on D: counted as missing"
    Assert-That ($plan.Docker.To -eq "D:\wsl\docker-desktop") "Docker Desktop's data goes to $($plan.Docker.To)"
}

Invoke-TestCase "plans only the location for a Docker Desktop that never started" {
    # given a fresh machine: kali-linux just installed, Docker Desktop installed but never started
    $script:disks = @{ "$kaliDir\ext4.vhdx" = 1GB }

    # when
    $plan = Get-WslMovePlan -Distro @($kaliOnC) -DockerDataDir $dockerDir -Volume $laptopVolumes -SystemDrive "C"

    # then
    Assert-That ($plan.Docker.To -eq "D:\wsl\docker-desktop") "Docker Desktop's data goes to $($plan.Docker.To)"
    Assert-That (-not $plan.Docker.MoveDistro -and -not $plan.Docker.MoveDataDisk) "disks that do not exist were planned to move"
    Assert-That ($plan.Kali.To -eq "D:\wsl\kali-linux") "kali-linux goes to $($plan.Kali.To)"
}

Invoke-TestCase "plans nothing when nothing of WSL's is on the system drive" {
    # given kali-linux on D: and Docker Desktop's data folder set to D:
    $script:disks = $laptopDisks

    # when
    $plan = Get-WslMovePlan -Distro @($kaliOnD) -DockerDataDir "D:\wsl\docker-desktop" -Volume $laptopVolumes -SystemDrive "C"

    # then
    Assert-That ($null -eq $plan.Kali -and $null -eq $plan.Docker) "something was planned"
    Assert-That ($null -eq $plan.Target) "a target was chosen for nothing"
}

Invoke-TestCase "finds no target among FAT, exFAT and unpluggable drives" {
    # given
    $script:disks = $laptopDisks
    $volumes = @(
        [pscustomobject]@{ DriveLetter = "C"; FileSystem = "NTFS"; Free = 600GB; BusType = "NVMe" },
        [pscustomobject]@{ DriveLetter = "D"; FileSystem = "exFAT"; Free = 900GB; BusType = "SATA" },
        [pscustomobject]@{ DriveLetter = "E"; FileSystem = "FAT32"; Free = 900GB; BusType = "SATA" },
        [pscustomobject]@{ DriveLetter = "F"; FileSystem = "NTFS"; Free = 900GB; BusType = "SD" }
    )

    # when
    $plan = Get-WslMovePlan -Distro @($kaliOnC) -DockerDataDir $dockerDir -Volume $volumes -SystemDrive "C"

    # then
    Assert-That ($null -eq $plan.Target) "chose $($plan.Target.DriveLetter):"
    Assert-That ($null -ne $plan.Kali) "kali-linux dropped out of a plan that has no target"
}

Invoke-TestCase "needs room for what moves plus the headroom" {
    # given 32.1 GB to move: D: has room for it, but not 10 GB more; E: has both
    $script:disks = $laptopDisks
    $volumes = @(
        [pscustomobject]@{ DriveLetter = "C"; FileSystem = "NTFS"; Free = 40GB; BusType = "NVMe" },
        [pscustomobject]@{ DriveLetter = "D"; FileSystem = "NTFS"; Free = 35GB; BusType = "NVMe" },
        [pscustomobject]@{ DriveLetter = "E"; FileSystem = "ReFS"; Free = 45GB; BusType = "SATA" }
    )

    # when
    $plan = Get-WslMovePlan -Distro @($kaliOnC, $dockerDistro) -DockerDataDir $dockerDir -Volume $volumes -SystemDrive "C"

    # then
    Assert-That ($plan.Target.DriveLetter -eq "E") "chose $($plan.Target.DriveLetter):"
}

Invoke-TestCase "never writes over a disk already in a target folder" {
    # given a previous install's disks in D:\wsl, as after Windows was reinstalled
    $script:disks = $laptopDisks.Clone()
    $script:disks["D:\wsl\kali-linux\ext4.vhdx"] = 113GB
    $script:disks["D:\wsl\docker-desktop\disk\docker_data.vhdx"] = 28GB

    # when
    $plan = Get-WslMovePlan -Distro @($kaliOnC, $dockerDistro) -DockerDataDir $dockerDir -Volume $laptopVolumes -SystemDrive "C"

    # then
    Assert-That ($null -eq $plan.Kali) "kali-linux was planned over D:\wsl\kali-linux\ext4.vhdx"
    Assert-That ($null -eq $plan.Docker) "Docker Desktop was planned over D:\wsl\docker-desktop"
    Assert-That ($plan.Notes.Count -eq 2) "notes: $($plan.Notes -join ' | ')"
    Assert-That (($plan.Notes -join "`n") -match "WARN: D:\\wsl\\kali-linux already holds ext4\.vhdx") "notes: $($plan.Notes -join ' | ')"
    Assert-That (($plan.Notes -join "`n") -match "WARN: D:\\wsl\\docker-desktop already holds Docker Desktop disks") "notes: $($plan.Notes -join ' | ')"
}

Invoke-TestCase "reads Docker Desktop's data folder from its settings, or the default" {
    # given
    $settings = Join-Path $script:scratch "settings-store.json"
    $default = "C:\Users\me\AppData\Local\Docker\wsl"

    # when
    $missing = Get-DockerWslDataDir -SettingsPath $settings -DefaultDir $default
    Set-Content -LiteralPath $settings -Value '{"AutoStart":true}' -NoNewline
    $unset = Get-DockerWslDataDir -SettingsPath $settings -DefaultDir $default
    Set-Content -LiteralPath $settings -Value '{"CustomWslDistroDir":"D:\\wsl\\docker-desktop"}' -NoNewline
    $custom = Get-DockerWslDataDir -SettingsPath $settings -DefaultDir $default
    Set-Content -LiteralPath $settings -Value '{"AutoStart":' -NoNewline
    $output = Get-Output { $script:invalid = Get-DockerWslDataDir -SettingsPath $settings -DefaultDir $default }

    # then
    Assert-That ($missing -eq $default) "no settings file: $missing"
    Assert-That ($unset -eq $default) "no CustomWslDistroDir: $unset"
    Assert-That ($custom -eq "D:\wsl\docker-desktop") "CustomWslDistroDir: $custom"
    Assert-That ($null -eq $script:invalid) "invalid JSON: $($script:invalid)"
    Assert-That ($output -match "WARN: .* is not valid JSON") "the invalid JSON was not reported: $output"
}

Invoke-TestCase "says so and asks nothing when nothing of WSL's is on the system drive" {
    # given
    $script:distros = @($kaliOnD)
    $script:volumes = $laptopVolumes
    $settings = Join-Path $script:scratch "settings-store.json"
    Set-Content -LiteralPath $settings -Value '{"CustomWslDistroDir":"D:\\wsl\\docker-desktop"}' -NoNewline

    # when
    $output = Get-Output { Request-WslMove -SystemDrive "C" -SettingsPath $settings -DockerDefaultDir $dockerDir }

    # then
    Assert-That ($output -match "none of WSL's disks is on the system drive, C:") "not reported: $output"
    Assert-That ($script:questions.Count -eq 0) "asked: $($script:questions -join ' | ')"
    Assert-That ($script:calls.Count -eq 0) "calls: $($script:calls -join ' | ')"
}

Invoke-TestCase "says so and asks nothing when no other drive has room" {
    # given
    $script:distros = @($kaliOnC)
    $script:volumes = @([pscustomobject]@{ DriveLetter = "C"; FileSystem = "NTFS"; Free = 200GB; BusType = "NVMe" })
    $script:disks = $laptopDisks

    # when
    $output = Get-Output { Request-WslMove -SystemDrive "C" -SettingsPath (Join-Path $script:scratch "none.json") -DockerDefaultDir $dockerDir }

    # then
    Assert-That ($output -match "no other internal NTFS or ReFS drive has room") "not reported: $output"
    Assert-That ($script:questions.Count -eq 0) "asked: $($script:questions -join ' | ')"
    Assert-That ($script:calls.Count -eq 0) "calls: $($script:calls -join ' | ')"
}

Invoke-TestCase "asks nothing without a terminal, and prints the commands instead" {
    # given
    $script:distros = @($kaliOnC, $dockerDistro)
    $script:volumes = $laptopVolumes
    $script:disks = $laptopDisks
    $script:interactive = $false

    # when
    $output = Get-Output { Request-WslMove -SystemDrive "C" -SettingsPath (Join-Path $script:scratch "none.json") -DockerDefaultDir $dockerDir }

    # then
    Assert-That ($script:questions.Count -eq 0) "asked without a terminal: $($script:questions -join ' | ')"
    Assert-That ($script:calls.Count -eq 0) "calls: $($script:calls -join ' | ')"
    Assert-That ($output -match "no terminal to ask on") "not reported: $output"
    Assert-That ($output -match [regex]::Escape("wsl --manage kali-linux --move D:\wsl\kali-linux")) "no command for kali-linux: $output"
    Assert-That ($output -match "Disk image location") "no route for Docker Desktop's data: $output"
}

Invoke-TestCase "moves nothing on a no, after one question naming the drives" {
    # given
    $script:distros = @($kaliOnC, $dockerDistro)
    $script:volumes = $laptopVolumes
    $script:disks = $laptopDisks
    $script:answer = $false

    # when
    $output = Get-Output { Request-WslMove -SystemDrive "C" -SettingsPath (Join-Path $script:scratch "none.json") -DockerDefaultDir $dockerDir }

    # then
    Assert-That ($script:questions.Count -eq 1) "asked $($script:questions.Count) times"
    Assert-That ($script:questions[0] -match "^\[wsl-move\] Move them to D:\\wsl \(650[.,]0 GB free\)\? Docker Desktop and WSL stop during the move\. \[y/N\]$") "question: $($script:questions[0])"
    Assert-That ($output -match "on the system drive, C: \(664[.,]0 GB free\): kali-linux \(2[.,]0 GB\) and Docker Desktop's data \(30[.,]1 GB\)") "what is on C: was not reported: $output"
    Assert-That ($script:calls.Count -eq 0) "calls: $($script:calls -join ' | ')"
    Assert-That ($output -match "nothing moved; to move them later") "the no was not reported: $output"
}

Invoke-TestCase "moves on a yes, and names the command for a kali-linux not installed yet" {
    # given a fresh machine where WSL waits for a reboot: no kali-linux, Docker Desktop never started
    $script:volumes = $laptopVolumes
    $script:answer = $true
    function Invoke-WslMovePlan {
        param([object]$Plan, [string]$SettingsPath)

        $script:movedPlan = $Plan
        $script:movedSettings = $SettingsPath
    }

    # when
    $output = Get-Output { Request-WslMove -SystemDrive "C" -SettingsPath (Join-Path $script:scratch "settings.json") -DockerDefaultDir $dockerDir }

    # then
    Assert-That ($script:questions[0] -match "Move it to D:\\wsl .*\? \[y/N\]$") "question: $($script:questions[0])"
    Assert-That ($script:movedPlan.Docker.To -eq "D:\wsl\docker-desktop") "moved: $($script:movedPlan.Docker.To)"
    Assert-That ($script:movedSettings -eq (Join-Path $script:scratch "settings.json")) "settings: $($script:movedSettings)"
    Assert-That ($output -match [regex]::Escape("once it is: wsl --manage kali-linux --move D:\wsl\kali-linux")) "no command for the missing kali-linux: $output"
}

Invoke-TestCase "moves kali-linux alone with wsl, stopping only it, and makes it the default" {
    # given
    $plan = Get-TestPlan -Kali $kaliMove

    # when
    $null = Get-Output { Invoke-WslMovePlan -Plan $plan -SettingsPath (Join-Path $script:scratch "none.json") }

    # then
    $expected = "wsl --terminate kali-linux|wsl --manage kali-linux --move D:\wsl\kali-linux|wsl --set-default kali-linux"
    Assert-That (($script:calls -join "|") -eq $expected) "calls: $($script:calls -join ' | ')"
}

Invoke-TestCase "leaves the default alone when kali-linux does not move" {
    # given
    $plan = Get-TestPlan -Kali $kaliMove
    $script:exitCodes["wsl --manage kali-linux --move D:\wsl\kali-linux"] = 1

    # when
    $output = Get-Output { Invoke-WslMovePlan -Plan $plan -SettingsPath (Join-Path $script:scratch "none.json") }

    # then
    Assert-That (($script:calls -join "|") -notmatch "set-default") "calls: $($script:calls -join ' | ')"
    Assert-That ($output -match "WARN: kali-linux stays in .* \(wsl exited with 1\)") "not reported: $output"
}

Invoke-TestCase "moves Docker Desktop's disks around a stop and a start of Docker Desktop" {
    # given Docker Desktop running, with its data disk on C:
    $script:dockerRunning = $true
    $docker = Get-TestDocker -WithDisks
    $plan = Get-TestPlan -Kali $kaliMove -Docker $docker.Plan
    $source = Join-Path (Join-Path $docker.Plan.From "disk") "docker_data.vhdx"
    $destination = Join-Path (Join-Path $docker.Plan.To "disk") "docker_data.vhdx"

    # when
    $output = Get-Output { Invoke-WslMovePlan -Plan $plan -SettingsPath $docker.Settings }

    # then
    $expected = @(
        "docker desktop stop --timeout 300",
        "wsl --shutdown",
        "wsl --manage kali-linux --move D:\wsl\kali-linux",
        "wsl --set-default kali-linux",
        "wsl --manage docker-desktop --move $(Join-Path $docker.Plan.To 'main')",
        "docker desktop start --detach"
    ) -join "|"
    Assert-That (($script:calls -join "|") -eq $expected) "calls: $($script:calls -join ' | ')"
    Assert-That ((Get-Content -LiteralPath $destination -Raw) -eq "images, containers and volumes") "the data disk was not copied whole"
    Assert-That (-not (Test-Path -LiteralPath $source)) "the old data disk is still there"
    Assert-That (($script:owned -join "|") -eq $destination) "owner restored on: $($script:owned -join ' | ')"
    $settings = Get-Content -LiteralPath $docker.Settings -Raw | ConvertFrom-Json
    Assert-That ($settings.CustomWslDistroDir -eq $docker.Plan.To) "CustomWslDistroDir: $($settings.CustomWslDistroDir)"
    Assert-That ($settings.AutoStart -eq $true -and $settings.SettingsVersion -eq 48 -and @($settings.IntegratedWslDistros) -contains "kali-linux") "Docker Desktop's other settings were not kept"
    $bytes = [System.IO.File]::ReadAllBytes($docker.Settings)
    Assert-That (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "the settings were written with a BOM"
    Assert-That ($output -match "Docker Desktop keeps its disks in") "the move was not reported: $output"
}

Invoke-TestCase "gives a Docker Desktop that never started only the location" {
    # given
    $docker = Get-TestDocker
    $plan = Get-TestPlan -Docker $docker.Plan

    # when
    $null = Get-Output { Invoke-WslMovePlan -Plan $plan -SettingsPath $docker.Settings }

    # then
    Assert-That ($script:calls.Count -eq 0) "calls: $($script:calls -join ' | ')"
    Assert-That (Test-Path -LiteralPath $docker.Plan.To) "the folder was not created"
    $settings = Get-Content -LiteralPath $docker.Settings -Raw | ConvertFrom-Json
    Assert-That ($settings.CustomWslDistroDir -eq $docker.Plan.To) "CustomWslDistroDir: $($settings.CustomWslDistroDir)"
}

Invoke-TestCase "keeps Docker Desktop's disks when Docker Desktop does not stop, and still moves kali-linux" {
    # given
    $script:dockerRunning = $true
    $script:exitCodes["docker desktop stop --timeout 300"] = 1
    $docker = Get-TestDocker -WithDisks
    $plan = Get-TestPlan -Kali $kaliMove -Docker $docker.Plan

    # when
    $output = Get-Output { Invoke-WslMovePlan -Plan $plan -SettingsPath $docker.Settings }

    # then
    $expected = "docker desktop stop --timeout 300|wsl --terminate kali-linux|wsl --manage kali-linux --move D:\wsl\kali-linux|wsl --set-default kali-linux"
    Assert-That (($script:calls -join "|") -eq $expected) "calls: $($script:calls -join ' | ')"
    Assert-That (Test-Path -LiteralPath (Join-Path (Join-Path $docker.Plan.From "disk") "docker_data.vhdx")) "the data disk moved"
    Assert-That (-not ((Get-Content -LiteralPath $docker.Settings -Raw) -match "CustomWslDistroDir")) "the location was set"
    Assert-That ($output -match "WARN: Docker Desktop did not stop") "not reported: $output"
}

Invoke-TestCase "moves nothing when WSL does not shut down, and starts Docker Desktop again" {
    # given
    $script:dockerRunning = $true
    $script:exitCodes["wsl --shutdown"] = 1
    $docker = Get-TestDocker -WithDisks
    $plan = Get-TestPlan -Kali $kaliMove -Docker $docker.Plan

    # when
    $output = Get-Output { Invoke-WslMovePlan -Plan $plan -SettingsPath $docker.Settings }

    # then
    $expected = "docker desktop stop --timeout 300|wsl --shutdown|docker desktop start --detach"
    Assert-That (($script:calls -join "|") -eq $expected) "calls: $($script:calls -join ' | ')"
    Assert-That (Test-Path -LiteralPath (Join-Path (Join-Path $docker.Plan.From "disk") "docker_data.vhdx")) "the data disk moved"
    Assert-That ($output -match "WARN: WSL did not shut down") "not reported: $output"
}

Invoke-TestCase "deletes the copy and keeps the data disk when the location cannot be written" {
    # given settings that are not JSON
    $docker = Get-TestDocker -WithDisks
    Set-Content -LiteralPath $docker.Settings -Value '{"AutoStart":' -NoNewline
    $plan = Get-TestPlan -Docker $docker.Plan

    # when
    $output = Get-Output { Invoke-WslMovePlan -Plan $plan -SettingsPath $docker.Settings }

    # then
    Assert-That (Test-Path -LiteralPath (Join-Path (Join-Path $docker.Plan.From "disk") "docker_data.vhdx")) "the data disk is gone"
    Assert-That (-not (Test-Path -LiteralPath (Join-Path (Join-Path $docker.Plan.To "disk") "docker_data.vhdx"))) "the copy was left behind"
    Assert-That ((Get-Content -LiteralPath $docker.Settings -Raw) -eq '{"AutoStart":') "the settings were rewritten"
    Assert-That (($script:calls -join "|") -eq "wsl --shutdown") "calls: $($script:calls -join ' | ')"
    Assert-That ($output -match "WARN: Docker Desktop's disks stay in") "not reported: $output"
}

Invoke-TestCase "keeps the data disk and the location when the copy fails" {
    # given a copy that fails, as on a drive that fills up
    $docker = Get-TestDocker -WithDisks
    $plan = Get-TestPlan -Docker $docker.Plan
    function Copy-DiskFile { throw "There is not enough space on the disk." }

    # when
    $output = Get-Output { Invoke-WslMovePlan -Plan $plan -SettingsPath $docker.Settings }

    # then
    Assert-That (Test-Path -LiteralPath (Join-Path (Join-Path $docker.Plan.From "disk") "docker_data.vhdx")) "the data disk is gone"
    Assert-That (-not ((Get-Content -LiteralPath $docker.Settings -Raw) -match "CustomWslDistroDir")) "the location was set"
    Assert-That (($script:calls -join "|") -eq "wsl --shutdown") "the distribution moved without its data: $($script:calls -join ' | ')"
    Assert-That ($output -match "WARN: Docker Desktop's disks stay in .*not enough space") "not reported: $output"
}

if ($script:failures -gt 0) {
    exit 1
}
Write-Host "[test-configure-dependencies-windows] all WSL disk move tests passed"
