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
# =========================================================================================================
nvm install --lts # TODO: in the first execution it's giving error because nvm is not recognized as cmdlet
# =========================================================================================================
