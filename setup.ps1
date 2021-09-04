$ErrorActionPreference = "Stop"

Write-Host ==================================
Write-Host Note: This will turn off WSL2
Write-Host   and upgrade exsting softwares like
Write-Host   git, vscode, windows terminal,
Write-Host   virtualbox, vagrant
Write-Host ==================================
Read-Host -Prompt "Press any key to continue or ^C to stop"

# Disable hyper-v
Write-Host ---------------------------------------
Write-Host  Disabling Hypervisor Platform
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

# Install terminal
Write-Host ---------------------------------------
$installed_terminal_version = (Get-AppxPackage -Name *WindowsTerminal).Version
$terminal_url = "https://api.github.com/repos/microsoft/terminal/releases/latest"
$terminal_asset = Invoke-RestMethod -Method Get -Uri $terminal_url | % assets | where name -like "*msixbundle"
$terminal_installer = "$env:temp\$($terminal_asset.name)"
Write-Host $terminal_asset.name
if ($installed_terminal_version -And $terminal_asset.name -match $installed_terminal_version) {
  Write-Host already installed
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
Write-Host ---------------------------------------
Try {
  $installed_vscode_version = code --version| select-object -First 1
} catch {}
#Write-Host VS Code version: $installed_vscode_version

$vscode_url = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user"
$vscode_installer_url = [System.Uri](Invoke-WebRequest -UseBasicParsing -Method Head -MaximumRedirection 0 -Uri $vscode_url -ErrorAction SilentlyContinue).Headers.Location

#Write-Host VS Code installer url: $vscode_installer_url
$vscode_installer_filename = $vscode_installer_url.Segments[-1]
$vscode_installer_version = echo $vscode_installer_filename| %{$_.split('-')[-1]} | %{$_.SubString(0, $_.IndexOf('.exe'))}
#Write-Host $vscode_installer_filename, $vscode_installer_version

$vscode_installer = "$env:temp\$($vscode_installer_filename)"
Write-Host VS Code $vscode_installer_version
if ($installed_vscode_version -And $vscode_installer_version -match $installed_vscode_version) {
  Write-Host already installed
} else {
  # download installer unless exists
  if (Test-Path($vscode_installer)) {
    Write-Host Found $vscode_installer, skip downloading
  } Else {
    Write-Host Downloading $vscode_installer_url
    Invoke-WebRequest -UseBasicParsing -Uri $vscode_installer_url -OutFile $vscode_installer
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
Write-Host ---------------------------------------
Try {
  $installed_git_version = git --version | %{$_.split(' ')[-1]} | %{$_.SubString(0, $_.IndexOf('.windows'))}
} catch {}
$git_url = "https://api.github.com/repos/git-for-windows/git/releases/latest"
$git_asset = Invoke-RestMethod -Method Get -Uri $git_url | % assets | where name -like "*64-bit.exe"
$git_installer = "$env:temp\$($git_asset.name)"

Write-Host $git_asset.name
if ($installed_git_version -And $git_asset.name -match $installed_git_version) {
  Write-Host already installed
} Else {
  # download installer unless exists
  $installer = "$env:temp\$($git_asset.name)"
  if (Test-Path($installer)) {
    Write-Host Found $installer, skip downloading
  } Else {
    Invoke-WebRequest -UseBasicParsing -Uri $git_asset.browser_download_url -OutFile $installer
  }
  # install git
  $git_install_inf = "$PSScriptRoot\git.inf"
  $install_args = "/SP- /SILENT /SUPPRESSMSGBOXES /NOCANCEL /NORESTART /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /LOADINF=""$git_install_inf"""
  Write-Host Installing $installer, $install_args
  Start-Process -FilePath $installer -ArgumentList $install_args -Wait
  Write-Host Installed Git.
}

######################
# Install virtual box
Write-Host ---------------------------------------
$vbox_path = "$Env:Programfiles\Oracle\VirtualBox"
$vbox_manage = "$vbox_path\VBoxManage"
Try {
  $installed_vbox_version = (& $vbox_manage --version)
} catch {}
#Write-Host VBox version: $installed_vbox_version
$vbox_url = "https://www.virtualbox.org/wiki/Downloads"
$vbox_link = (Invoke-WebRequest -UseBasicParsing -Uri $vbox_url).Links | Where-Object {$_.href -like "*Win.exe"}
$vbox_installer_url = [System.Uri]$vbox_link.href
#Write-Host VBox installer url: $vbox_installer_url
$vbox_installer_filename = $vbox_installer_url.Segments[-1]
$vbox_installer_version = echo $vbox_installer_filename | %{$_.SubString($_.IndexOf('-')+1)} | %{$_.SubString(0, $_.IndexOf('-Win'))}
$vbox_installer = "$env:temp\$($vbox_installer_filename)"
#Write-Host $vbox_installer_version, $installed_vbox_version
Write-Host VirtualBox $vbox_installer_version
if ($installed_vbox_version -And $installed_vbox_version -match $vbox_installer_version.split('-')[1] ) {
  Write-Host already installed
} else {
  # download installer unless exists
  if (Test-Path($vbox_installer)) {
    Write-Host Found $vbox_installer, skip downloading
  } Else {
    Write-Host Downloading $vbox_installer_url
    Invoke-WebRequest -UseBasicParsing -Uri $vbox_installer_url -OutFile $vbox_installer
  }
  # Install vbox
  Write-Host Installing $vbox_installer_filename
  Try {
    Start-Process -Wait -FilePath $vbox_installer -Argument "--silent --ignore-reboot" -PassThru
  } catch {
    Write-Host $_
  }
  Write-Host Installed VirtualBox.
}

######################
# Install vagrant
Write-Host ---------------------------------------
Try {
  $installed_vagrant_version = vagrant --version | %{$_.split(' ')[1]}
} catch {}
#Write-Host Vagrant version: $installed_vagrant_version
$vagrant_url = "https://www.vagrantup.com/downloads"
$vagrant_link = (Invoke-WebRequest -UseBasicParsing -Uri $vagrant_url).Links | Where-Object {$_.href -like "*64.msi"}
$vagrant_installer_url = [System.Uri]$vagrant_link.href
$vagrant_installer_filename = $vagrant_installer_url.Segments[-1]
$vagrant_installer_version = echo $vagrant_installer_filename | %{$_.Split('_')[1]}
$vagrant_installer = "$env:temp\$($vagrant_installer_filename)"
Write-Host Vagrant $vagrant_installer_version
if ($installed_vagrant_version -And $installed_vagrant_version -match $vagrant_installer_version ) {
  Write-Host already installed
} else {
  # download installer unless exists
  if (Test-Path($vagrant_installer)) {
    Write-Host Found $vagrant_installer, skip downloading
  } Else {
    Write-Host Downloading $vagrant_installer_url
    Invoke-WebRequest -UseBasicParsing -Uri $vagrant_installer_url -OutFile $vagrant_installer
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

Write-Host ==================================
Write-Host Done. Please continue to bootstrap

if ($virtualization_enabled -ne "Yes") {
  Write-Host Virtualization is not enabled, please follow this link and try to enable
  Write-Host https://www.smarthomebeginner.com/enable-hardware-virtualization-vt-x-amd-v/
}
