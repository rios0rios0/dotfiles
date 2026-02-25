# define the path to the .ssh folder
$sshFolderPath = "$HOME\.ssh"
$knownHostsPath = "$sshFolderPath\known_hosts"

# ensure the .ssh folder exists
if (-Not (Test-Path -Path $sshFolderPath)) {
    New-Item -ItemType Directory -Path $sshFolderPath
}

New-Item $knownHostsPath -Type File -Force

# use SSH with StrictHostKeyChecking=accept-new to automatically add host keys without prompting
# the connection will fail authentication (no key loaded yet) but host keys will be saved to known_hosts
# this avoids the freeze that occurs when ssh.exe is called via git from WSL and encounters an unknown host
$gitHosts = @("github.com", "gitlab.com", "ssh.dev.azure.com", "bitbucket.org")
foreach ($gitHost in $gitHosts) {
    ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10 -T "git@$gitHost" 2>&1 | Out-Null
}
