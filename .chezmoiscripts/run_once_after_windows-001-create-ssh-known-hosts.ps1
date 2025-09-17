# define the path to the .ssh folder
$sshFolderPath = "$HOME\.ssh"
$knownHostsPath = "$sshFolderPath\known_hosts"

# ensure the .ssh folder exists
if (-Not (Test-Path -Path $sshFolderPath)) {
    New-Item -ItemType Directory -Path $sshFolderPath
}

New-Item $knownHostsPath -Type File -Force

# Function to safely run ssh-keyscan with timeout and error handling
function Add-SSHKnownHost {
    param(
        [string]$hostname,
        [string]$knownHostsFile,
        [int]$timeoutSeconds = 10
    )
    
    Write-Host "Adding SSH host key for: $hostname"
    try {
        # Use ssh-keyscan.exe explicitly to avoid WSL interoperability issues
        # Add timeout and handle potential hanging
        $process = Start-Process -FilePath "ssh-keyscan.exe" -ArgumentList @("-T", $timeoutSeconds, $hostname) -RedirectStandardOutput "temp_$hostname.txt" -RedirectStandardError "temp_${hostname}_error.txt" -NoNewWindow -Wait -PassThru
        
        if ($process.ExitCode -eq 0 -and (Test-Path "temp_$hostname.txt")) {
            $content = Get-Content "temp_$hostname.txt" -Raw
            if ($content -and $content.Trim() -ne "") {
                Add-Content -Path $knownHostsFile -Value $content.Trim()
                Write-Host "✓ Successfully added SSH host key for: $hostname"
            } else {
                Write-Warning "⚠ No valid host key received for: $hostname"
            }
        } else {
            $errorContent = ""
            if (Test-Path "temp_${hostname}_error.txt") {
                $errorContent = Get-Content "temp_${hostname}_error.txt" -Raw
            }
            Write-Warning "✗ Failed to get SSH host key for: $hostname. Error: $errorContent"
        }
        
        # Clean up temporary files
        Remove-Item "temp_$hostname.txt" -ErrorAction SilentlyContinue
        Remove-Item "temp_${hostname}_error.txt" -ErrorAction SilentlyContinue
        
    } catch {
        Write-Warning "✗ Exception occurred while processing $hostname : $($_.Exception.Message)"
    }
}

# Add SSH host keys for common Git providers
Add-SSHKnownHost -hostname "github.com" -knownHostsFile $knownHostsPath
Add-SSHKnownHost -hostname "gitlab.com" -knownHostsFile $knownHostsPath  
Add-SSHKnownHost -hostname "ssh.dev.azure.com" -knownHostsFile $knownHostsPath

# Get Bitbucket SSH keys via web scraping as fallback
Write-Host "Adding Bitbucket SSH host keys via web scraping..."
try {
    $bitbucket = Invoke-WebRequest -Uri "https://bitbucket.org/site/ssh" -TimeoutSec 30 | Select-Object -ExpandProperty Content
    if ($bitbucket -and $bitbucket.Trim() -ne "") {
        Add-Content -Path $knownHostsPath -Value $bitbucket
        Write-Host "✓ Successfully added Bitbucket SSH host keys"
    } else {
        Write-Warning "⚠ No content received from Bitbucket SSH endpoint"
    }
} catch {
    Write-Warning "✗ Failed to get Bitbucket SSH keys: $($_.Exception.Message)"
}

Write-Host "SSH known_hosts setup completed. File location: $knownHostsPath"
