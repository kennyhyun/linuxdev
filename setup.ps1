$ErrorActionPreference = "Stop"

# Function to run a script with elevated privileges and capture the output
function Run-Elevated {
    param (
        [string]$scriptBlock
    )
    $tempFile = [System.IO.Path]::GetTempFileName()
    $command = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"& { $scriptBlock } | Out-File -FilePath '$tempFile'`""
    Start-Process powershell -ArgumentList $command -Verb RunAs -Wait
    Get-Content -Path $tempFile
}


$envFilePath = ".env"
$envContent = Get-Content -Path $envFilePath
$envVariables = @{}
foreach ($line in $envContent) {
    if ($line -match '^(?<key>[^=]+)=(?<value>.+)$') {
        $envVariables[$Matches['key']] = $Matches['value']
    }
}


# Check if WSL is enabled
$script = {
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    if ($wslFeature.State -ne "Enabled") {
        Write-Output "WSL is not enabled."
    } else {
        Write-Output "WSL is enabled."
    }
}
$wslStatus = Run-Elevated $script
if ($wslStatus -contains "WSL is not enabled.") {
    Write-Host "WSL is not enabled. Enabling WSL..."
    Run-Elevated "Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux"
    Write-Host "WSL enabled. Please restart your computer and run the script again."
    exit
} else {
    Write-Host "WSL is already enabled."
}
wsl --update # install kernel update package if not exist

$wslList = wsl -l -v
if ($wslList -match "Debian" -or $wslList -match "Debian") {
    Write-Host "Debian is already installed."
} else {
    # Set the default WSL version to 1
    wsl --set-default-version 1
    Write-Host "Installing Debian..."
    $process = Start-Process -FilePath "wsl" -ArgumentList "--install -d Debian" -WindowStyle Minimized -PassThru
    #-NoNewWindow -PassThru
    #-WindowStyle Minimized -PassThru
    do {
        write-host "waiting for Debian"
        Start-Sleep -Seconds 1
        $wslList = wsl --list --verbose | Select-String -Pattern "Debian"
	$wslList = ($(wsl --list) -split "\r?\n" | Select-Object -Skip 1) -join "`n" -replace "`0", ""
    } while (-not($wslList -match "Debian"))
write-host "Stopping for now"
wsl --terminate Debian
Stop-Process -Name "Debian" -Force

$USER = if ($envVariables['USER']) { $envVariables['USER'] } else { "admin" }
$DOTFILES_REPO = $envVariables['DOTFILES_REPO']
wsl -d Debian -- bash -c "adduser --disabled-password --gecos '' $USER && echo `"[user]\ndefault=$USER`" >> /etc/wsl.conf"
wsl -d Debian -- bash -c "apt update &&
apt install -y git openssh-server &&
sed -i -E 's,^#?Port.*$,Port 2022,' /etc/ssh/sshd_config
service ssh restart
"
wsl --terminate Debian
wsl -d Debuan -- bash -c "sudo sh -c `"echo \`"${USER} ALL=(root) NOPASSWD: /usr/sbin/service ssh start\`" >/etc/sudoers.d/service-ssh-start`""

}

wsl --set-default-version 2

## Define variables
#$customDistroName = "UbuntuWsl1"
#$installPath = "$env:LOCALAPPDATA\Packages\$customDistroName"
#$tarGzPath = "$env:TEMP\ubuntu.tar.gz"
#
## Get the latest Ubuntu WSL image download link
#Write-Output "Fetching the latest Ubuntu WSL image link..."
#$wslImageLink = Get-LatestUbuntuWSLLink
#Write-Output "Latest Ubuntu WSL image link: $wslImageLink"
#
## Download the latest Ubuntu WSL image
#Write-Output "Downloading the latest Ubuntu WSL image..."
#Invoke-WebRequest -Uri $wslImageLink -OutFile $tarGzPath
#
## Create installation directory if it doesn't exist
#if (-Not (Test-Path $installPath)) {
#    New-Item -ItemType Directory -Path $installPath | Out-Null
#}
#
## Import the downloaded root filesystem as a custom WSL distro
#Write-Output "Importing Ubuntu as $customDistroName..."
#wsl --import $customDistroName $installPath $tarGzPath --version 1
#
## Clean up the downloaded tar.gz file
#Remove-Item $tarGzPath
#
## Verify installation
#$wslList = wsl --list --verbose
#if ($wslList -match $customDistroName) {
#    Write-Output "$customDistroName installation successful."
#} else {
#    Write-Output "$customDistroName installation failed."
#    exit 1
#}
#
## Initialize Terraform
#Write-Output "Initializing Terraform..."
#terraform init
#
#Write-Output "Script completed successfully."

