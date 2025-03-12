$distro = "kali-linux"

# Get the list of WSL distributions with detailed info.
try {
    $wslList = wsl --list --verbose 2>&1
} catch {
    Write-Error "Error retrieving WSL distributions. Ensure that WSL is installed and configured."
    exit
}

$installed = $false
$defaultDistro = $null

foreach ($line in $wslList) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    # Skip header lines (e.g., "NAME  STATE  VERSION")
    if ($trimmed -match "NAME\s+STATE\s+VERSION") { continue }

    # Check for default distro (lines starting with '*')
    if ($trimmed.StartsWith('*')) {
        $parts = $trimmed.Substring(1).Trim().Split()
        if ($parts.Count -gt 0) {
            $defaultDistro = $parts[0]
        }
    }

    # Get distro name (remove any asterisk that marks it as default)
    $name = $trimmed.TrimStart('*').Trim().Split()[0]
    if ($name -eq $distro) {
        $installed = $true
    }
}

if (-not $installed) {
    Write-Host "$distro is not installed. Installing..."
    wsl --install $distro
} else {
    Write-Host "$distro is already installed."
}

if ($defaultDistro -ne $distro) {
    Write-Host "$distro is not the default distro. Setting it as default..."
    wsl --set-default $distro
} else {
    Write-Host "$distro is already the default distro."
}
