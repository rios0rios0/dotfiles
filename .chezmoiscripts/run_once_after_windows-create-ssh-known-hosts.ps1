# define the path to the .ssh folder
$sshFolderPath = "$HOME\.ssh"
$knownHostsPath = "$sshFolderPath\known_hosts"

# ensure the .ssh folder exists
if (-Not (Test-Path -Path $sshFolderPath)) {
    New-Item -ItemType Directory -Path $sshFolderPath
}

New-Item $knownHostsPath -Type File -Force
ssh-keyscan github.com | Out-File -Append -FilePath $knownHostsPath
ssh-keyscan gitlab.com | Out-File -Append -FilePath $knownHostsPath
ssh-keyscan ssh.dev.azure.com | Out-File -Append -FilePath $knownHostsPath
$bitbucket = Invoke-WebRequest -Uri "https://bitbucket.org/site/ssh" | Select-Object -ExpandProperty Content
Add-Content -Path $knownHostsPath -Value $bitbucket
