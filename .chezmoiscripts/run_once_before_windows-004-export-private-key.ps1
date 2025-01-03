# define the path to the .ssh folder
$sshFolderPath = "$HOME\.ssh"

# ensure the ".ssh" folder exists
if (-Not (Test-Path -Path $sshFolderPath)) {
    New-Item -ItemType Directory -Path $sshFolderPath
}

# check if the key already exists
if (-Not (Test-Path "$sshFolderPath\chezmoi")) {
    Write-Host "Creating Chezmoi encryption key at: `"$sshFolderPath\chezmoi`"..."
    op read "op://personal/Chezmoi Key/private key" | Set-Content "$sshFolderPath\chezmoi"
}
