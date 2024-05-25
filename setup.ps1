$ErrorActionPreference = "Stop"
$DistroName = "Debian"

# Function to run a script with elevated privileges and capture the output
function Run-Elevated {
    param (
        [string]$scriptBlock
    )
    $tempFile = [System.IO.Path]::GetTempFileName()
    Start-Process powershell -WindowStyle Minimized -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"& { $scriptBlock } *>> $tempFile`"" -Verb RunAs -Wait
    cat $tempFile
    rm $tempFile
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
$scr = [scriptblock]::Create("((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux)).State")
$wslStatus = Run-Elevated $scr
#$wslStatus = "Enabled"
if ($wslStatus -match "Enabled") {
    Write-Host "WSL is already enabled."
} else {
    Write-Host "WSL is not enabled. Enabling WSL..."
    Run-Elevated "Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux"
    Write-Host "WSL enabled. Please restart your computer and run the script again."
    exit
}
wsl --update # install kernel update package if not exist

$wslList = ($(wsl --list) -split "\r?\n" | Select-Object -Skip 1) -join "`n" -replace "`0", ""
if ($wslList -match "$DistroName" -or $wslList -match "DistroName") {
    Write-Host "$DistroName is already installed."
} else {
    # Set the default WSL version to 1
    wsl --set-default-version 1
    Write-Host "Installing $DistroName..."
    $process = Start-Process -FilePath "wsl" -ArgumentList "--install -d $DistroName" -WindowStyle Minimized -PassThru
    #-NoNewWindow -PassThru
    #-WindowStyle Minimized -PassThru
    do {
        write-host "waiting for $DistroName"
        Start-Sleep -Seconds 1
        $wslList = wsl --list --verbose | Select-String -Pattern "$DistroName"
	$wslList = ($(wsl --list) -split "\r?\n" | Select-Object -Skip 1) -join "`n" -replace "`0", ""
    } while (-not($wslList -match "$DistroName"))
    write-host "Stopping for now"
    wsl --terminate $DistroName
    Stop-Process -Name "$DistroName" -Force
}


## ---------------
# Set PASSWD, sshd
#
$USER = if ($envVariables['USER']) { $envVariables['USER'] } else { "admin" }
$DOTFILES_REPO = $envVariables['DOTFILES_REPO']

write-host "Setting WSL 1 $DistroName"
# as root
wsl -d $DistroName -- bash -c "if [ -z `"`$(ls -d /home/$USER 2> /dev/null)`" ]; then adduser --disabled-password --gecos '' $USER; fi && if [ -z `"`$(ls /etc/sudoers.d/$USER 2> /dev/null)`" ]; then echo 'Setting NOPASSWD' && echo $USER' ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/$USER ; fi
if [ -z `"`$(grep '^default=$USER' /etc/wsl.conf 2> /dev/null)`" ];then echo Makeing $USER default && echo '[user]' >> /etc/wsl.conf && echo `"default=$USER`" >> /etc/wsl.conf ; fi
apt update &&
apt install -y git openssh-server &&
sed -i -E 's,^#?Port.*$,Port 3022,' /etc/ssh/sshd_config &&
echo All done
"
if (-not $LASTEXITCODE) {
  # restart to use default user
  wsl --terminate $DistroName
  # as ruser
  wsl -d $DistroName -- bash -c "ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -q -N '' &&
echo Created ssh key &&
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys &&
echo ---------------- &&
cat ~/.ssh/id_rsa.pub &&
echo ----------------
"
}

# setup scheduler task for start sshd
$taskName = "Start WSL sshd"
$existingScheduler = Get-ScheduledTask -TaskName $taskName -Erroraction silentlycontinue
if (-not $existingScheduler) {
  Start-Process powershell -WindowStyle Minimized -ArgumentList "-ExecutionPolicy Bypass -file `"$PSScriptRoot\registerStartupTask.ps1`" `"$taskName`" `"wsl bash -c 'sudo /usr/sbin/service ssh start'`"" -Verb RunAs -Wait 
  Get-ScheduledTask -TaskName $taskName #-Erroraction silentlycontinue
}


## ---------------
# Set sshd


#wsl --set-default-version 2

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

