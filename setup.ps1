$ErrorActionPreference = "Stop"

######################
# Disable hyper-v
#
bcdedit /set hypervisorlaunchtype off
Try {
  Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Hypervisor -All -NoRestart
} Catch {
  Write-Host hyper-v not found
}
  Disable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -NoRestart
Try {
  Disable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
  Disable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -NoRestart
} Catch {
  Write-Host hypervisor platform not found
}
bcdedit /set hypervisorlaunchtype off
$virtualization_enabled = systeminfo |select-string "Virtualization Enabled"|out-string|%{$_.SubString($_.IndexOf(': ')+1).trim()}

Write-Host Virtualization support: $virtualization_enabled

######################
# Install terminal
#
$installed_terminal_version = (Get-AppxPackage -Name *WindowsTerminal).Version
$terminal_url = "https://api.github.com/repos/microsoft/terminal/releases/latest"
$terminal_asset = Invoke-RestMethod -Method Get -Uri $terminal_url | % assets | where name -like "*msixbundle"
$terminal_installer = "$env:temp\$($terminal_asset.name)"
if ($terminal_asset.name -match $installed_terminal_version) {
  Write-Host Windows Terminal $installed_terminal_version already installed
} else {

  # download installer unless exists
  if (Test-Path($terminal_installer)) {
    Write-Host Found $terminal_installer, skip downloading
  } Else {
    Write-Host Downloading $terminal_asset.browser_download_url
    Invoke-WebRequest -UseBasicParsing -Uri $terminal_asset.browser_download_url -OutFile $terminal_installer
  }
  
  # Install terminal
  Write-Host Installing $terminal_asset.name
  Try {
    Add-AppPackage -path $terminal_installer
  } catch {
    Write-Host $_
  }
  Write-Host Installed Windows Terminal.
}

######################
# Install vscode
#
try {
  $installed_vscode_version = code --version| select-object -First 1
} catch {
  Write-Host $_
}
Write-Host VS Code version: $installed_vscode_version

$vscode_url = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user"
$vscode_installer_url = [System.Uri](Invoke-WebRequest -Method Head -MaximumRedirection 0 -Uri $vscode_url -ErrorAction SilentlyContinue).Headers.Location

Write-Host VS Code installer url: $vscode_installer_url
$vscode_installer_filename = $vscode_installer_url.Segments[-1]
$vscode_installer_version = echo $vscode_installer_filename| %{$_.split('-')[-1]} | %{$_.SubString(0, $_.IndexOf('.exe'))}
Write-Host $vscode_installer_filename, $vscode_installer_version

$vscode_installer = "$env:temp\$($vscode_installer_filename)"
if ($vscode_installer_version -match $installed_vscode_version) {
  Write-Host VS Code $installed_vscode_version already installed
} else {

  # download installer unless exists
  if (Test-Path($vscode_installer)) {
    Write-Host Found $vscode_installer, skip downloading
  } Else {
    Write-Host Downloading $vscode_installer_url
    Invoke-WebRequest -Uri $vscode_installer_url -OutFile $vscode_installer
  }

  # Install vs code
  Write-Host Installing $vscode_installer_filename
  Try {
    Start-Process -Wait -FilePath $vscode_installer -Argument "/SILENT /NORESTART /MERGETASKS=!runcode" -PassThru
  } catch {
    Write-Host $_
  }
  Write-Host Installed VS Code.
}


######################
# run installer if git-bash not found
#
$git_install_inf = "$PSScriptRoot\git.inf"
$git_path = Get-Content $git_install_inf | Select-String "Dir" | Out-String | %{$_.trim()} | % { $_.Substring(4) }
$git_bash = "$git_path\git-bash.exe"
$install_args = "/SP- /SILENT /SUPPRESSMSGBOXES /NOCANCEL /NORESTART /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /LOADINF=""$git_install_inf"""
if (Test-Path($git_bash)) {
  Write-Host Found $git_bash
} Else {
  # get latest download url for git-for-windows 64-bit exe
  $git_url = "https://api.github.com/repos/git-for-windows/git/releases/latest"
  $asset = Invoke-RestMethod -Method Get -Uri $git_url | % assets | where name -like "*64-bit.exe"
  
  # download installer unless exists
  $installer = "$env:temp\$($asset.name)"
  if (Test-Path($installer)) {
    Write-Host Found $installer, skip downloading
  } Else {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installer
  }

  Write-Host Start installing $installer, $install_args
  Start-Process -FilePath $installer -ArgumentList $install_args -Wait
  Write-Host Done
}

######################
# Install virtual box
#
$vbox_path = "$Env:Programfiles\Oracle\VirtualBox"
$vbox_manage = "$vbox_path\VBoxManage"
try {
  $installed_vbox_version = (& $vbox_manage --version)
} catch {
  Write-Host $_
}
Write-Host VBox version: $installed_vbox_version

$vbox_url = "https://www.virtualbox.org/wiki/Downloads"
$vbox_link = (Invoke-WebRequest -Uri $vbox_url).Links | Where-Object {$_.href -like "*Win.exe"}

$vbox_installer_url = [System.Uri]$vbox_link.href

#Write-Host VBox installer url: $vbox_installer_url
$vbox_installer_filename = $vbox_installer_url.Segments[-1]
$vbox_installer_version = echo $vbox_installer_filename | %{$_.SubString($_.IndexOf('-')+1)} | %{$_.SubString(0, $_.IndexOf('-Win'))}

$vbox_installer = "$env:temp\$($vbox_installer_filename)"
#Write-Host $vbox_installer_version, $installed_vbox_version
if ($installed_vbox_version -match $vbox_installer_version.split('-')[1] ) {
  Write-Host VBox $vbox_installer_version already installed
} else {

  # download installer unless exists
  if (Test-Path($vbox_installer)) {
    Write-Host Found $vbox_installer, skip downloading
  } Else {
    Write-Host Downloading $vbox_installer_url
    Invoke-WebRequest -Uri $vbox_installer_url -OutFile $vbox_installer
  }

  # Install vbox
  Write-Host Installing $vbox_installer_filename
  Try {
    Start-Process -Wait -FilePath $vbox_installer -Argument "--silent --ignore-reboot" -PassThru
  } catch {
    Write-Host $_
  }
  Write-Host Installed VBox.
}

######################
# Install vagrant
#
try {
  $installed_vagrant_version = vagrant --version|%{$_.split(' ')[1]}
} catch {
  Write-Host $_
}
Write-Host Vagrant version: $installed_vagrant_version
$vagrant_url = "https://www.vagrantup.com/downloads"
$vagrant_link = (Invoke-WebRequest -Uri $vagrant_url).Links | Where-Object {$_.href -like "*64.msi"}
$vagrant_installer_url = [System.Uri]$vagrant_link.href
$vagrant_installer_filename = $vagrant_installer_url.Segments[-1]
$vagrant_installer_version = echo $vagrant_installer_filename | %{$_.Split('_')[1]}
$vagrant_installer = "$env:temp\$($vagrant_installer_filename)"
if ($installed_vagrant_version -match $vagrant_installer_version ) {
  Write-Host Vagrant $vagrant_installer_version already installed
} else {

  # download installer unless exists
  if (Test-Path($vagrant_installer)) {
    Write-Host Found $vagrant_installer, skip downloading
  } Else {
    Write-Host Downloading $vagrant_installer_url
    Invoke-WebRequest -Uri $vagrant_installer_url -OutFile $vagrant_installer
  }
  # Install vagrant
  Write-Host Installing $vagrant_installer_filename
  Try {
    Start-Process -Wait -FilePath $vagrant_installer -Argument "/passive /norestart" -PassThru
  } catch {
    Write-Host $_
  }
  Write-Host Installed Vagrant.
}

if ($virtualization_enabled -ne "Yes") {
  Write-Host Virtualization is not enabled, please follow this link and try to enable
}
