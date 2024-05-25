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
$SSH_PORT = if ($envVariables['SSH_PORT']) { $envVariables['SSH_PORT'] } else { "3022" }
$DOTFILES_REPO = $envVariables['DOTFILES_REPO']

write-host "Setting WSL 1 $DistroName"
# as root
wsl -d $DistroName -- bash -c "if [ -z `"`$(ls -d /home/$USER 2> /dev/null)`" ]; then adduser --disabled-password --gecos '' $USER; fi && if [ -z `"`$(ls /etc/sudoers.d/$USER 2> /dev/null)`" ]; then echo 'Setting NOPASSWD' && echo $USER' ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/$USER ; fi
if [ -z `"`$(grep '^default=$USER' /etc/wsl.conf 2> /dev/null)`" ];then echo Makeing $USER default && echo '[user]' >> /etc/wsl.conf && echo `"default=$USER`" >> /etc/wsl.conf ; fi
apt update &&
apt install -y git openssh-server &&
sed -i -E 's,^#?Port.*$,Port $SSH_PORT,' /etc/ssh/sshd_config &&
echo All done
"
if (-not $LASTEXITCODE) {
  # restart to use default user
  wsl --terminate $DistroName
  # as ruser
  wsl -d $DistroName -- bash -c "sudo service ssh start &&
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -q -N '' &&
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


## ----------
# set ssh config
#
mkdir $env:USERPROFILE\.ssh -Force | out-null
if ((Test-Path $env:USERPROFILE\.ssh\config -PathType Leaf) -and (Select-String -Path $env:USERPROFILE\.ssh\config -Pattern "\b$DistroName\b" -CaseSensitive)) {
  echo "$DistroName config found"
} else {
  echo "$DistroName config not found, creating one"
  Write-Output -n @"

Host $DistroName
  HostName 127.0.0.1
  Port $SSH_PORT
  User $USER


"@ | out-file -encoding ascii -append -filepath $env:USERPROFILE\.ssh\config
}


## -----------
# set Defender exclusion
#


$wslpath = get-ChildItem $env:LOCALAPPDATA\Packages -directory | Where-Object {$_.Name -cmatch "$DistroName"} | % {$_.fullname}
#$excluded = Run-Elevated {
#	$(Get-MpPreference).ExclusionPath
#}
#$exclusionsToAdd = ((Compare-Object $wslPaths $currentExclusions) | Where-Object SideIndicator -eq "<=").InputObject
$dirs = @"
\bin
\sbin
\usr\bin
\usr\sbin
\usr\local\bin
\usr\local\go\bin
"@


$wslpath | foreach-object {
  $localstate = "$_\LocalState"
  $scr = [scriptblock]::Create(@"
    Add-MpPreference -ExclusionPath '$localstate'
    Write-Output 'Added_exclusion_for_$localstate'
    `$dirs='$dirs'
    `$rootfs = '$localstate' + '\rootfs'
    `$dirs.split('`r`n') | ForEach-Object {
        `$exclusion = `$rootfs + `$_ + '\*'
        Add-MpPreference -ExclusionProcess `$exclusion
	echo `"Added_exclusion_process_for_`$exclusion`"
    }
"@)
  Run-Elevated $scr

}


## ---------------
# Set Dotfiles

if ($DOTFILES_REPO) {
  $local:split = $DOTFILES_REPO.split('#')
  $local:repo = $split[0]
  $local:branch = $split[1]
  ssh $DistroName "bash -c `"cd &&
  if [ ! -d `"dotfiles`" ]; then
if [ -z `"$branch`" ]; then git clone $repo;
else git clone -b $branch $repo; fi
fi
  cd dotfiles &&
  ./init.sh
`""
}

