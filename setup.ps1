$ErrorActionPreference = "Stop"
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "Please run as an administrator"
  exit 109
}

If ($args.Contains("-noconfirm")) {
  $noConfirm=1
}
If ($args.Contains("-nodevtools") -or $args.Contains("-production")) {
  $noDevTools=1
}

If ($args.Contains("-nogit")) {
  $noGit=1
}

If ($args.Contains("-novscode")) {
  $noVsCode=1
}

If ($args.Contains("-noterminal")) {
  $noTerminal=1
}

If ($args.Contains("-novagrant")) {
  $noVagrant=1
}

If ($args.Contains("-novirtualbox")) {
  $noVirtualBox=1
}

If ($args.Contains("-withvagrantmanager")) {
  $withVagrantManager=1
}

If ($args.Contains("-withosconfig")) {
  $withOsConfig=1
}

If ($args.Contains("-nohyperv")) {
  $noHyperv=1
}

if ($noDevTools) {
  $noVsCode=1
  $noTerminal=1
}

$OsVersion = (Get-WmiObject -class Win32_OperatingSystem).Caption
$OsArchBit = (Get-WMIObject Win32_Processor).AddressWidth
$OsArch = "x86"
if ($OsArchBit -ne 32) {
  $OsArch = "x64"
}
$OsBuildNumber = (Get-WmiObject -class Win32_OperatingSystem).BuildNumber
if ($OsBuildNumber -lt 19041) {
  write-error "Windows Build number should be at least 19041"
  exit 101
}

Write-Host "==================================
Note: This will turn off WSL2
  and upgrade exsting softwares like
  git, vscode, windows terminal,
  virtualbox, vagrant
=================================="
if (-not $noConfirm) {
Read-Host -Prompt "Press any key to continue or ^C to stop"
}

# read .env
$envfileContent = Get-Content $PSScriptRoot\.env -ErrorAction continue
$envfile=[ordered]@{}
$envfileContent|ForEach-Object{
  $key, $value = $_.split("=")
  if ($key) {
    $envfile[$key]=$value
  }
}

# apply path
$machine_path = [Environment]::GetEnvironmentVariables("Machine")['Path']
$user_path = [Environment]::GetEnvironmentVariables("User")['Path']
$env:Path = "$machine_path;$user_path"

if ($withOsConfig) {
  & "$PSScriptRoot\scripts\basic-config.ps1"
}

if (-not $noHyperv) {
# Disable hyper-v
Write-Host ---------------------------------------
Write-Host " Disabling Hypervisor Platform"

try {
function disable-optional-feature {
  param ($featureName)
  $feature = Get-WindowsOptionalFeature -online -FeatureName $featureName
  if ($feature) {
    if ($feature.State -eq "Disabled") {
      write-host $featureName is already disabled
    } else {
      Disable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart
    }
  } else {
    write-host $featureName was not found
  }
}

disable-optional-feature -featureName Microsoft-Hyper-V-Hypervisor
disable-optional-feature -featureName VirtualMachinePlatform
disable-optional-feature -featureName HypervisorPlatform

Start-Process -Wait -PassThru powershell -Verb runAs -ArgumentList 'bcdedit /set hypervisorlaunchtype off'

} catch {
  $_
  exit 102
}

}

$virtualization_enabled = systeminfo |select-string "Virtualization Enabled"|out-string|ForEach-Object{$_.SubString($_.IndexOf(': ')+1).trim()}
Write-Host Virtualization support: $virtualization_enabled



If (-Not $noTerminal) {
  & "$PSScriptRoot\scripts\installers\install-terminal.ps1" -OsVersion $OsVersion
}

If ($withVagrantManager) {
  & "$PSScriptRoot\scripts\installers\install-vagrant-manager.ps1"
}

If (-Not $noVsCode) {
  & "$PSScriptRoot\scripts\installers\install-vscode.ps1"
}

If (-Not $noGit) {
  & "$PSScriptRoot\scripts\installers\install-git.ps1" -OsArchBit $OsArchBit
}

If (-Not $noVirtualBox) {
  & "$PSScriptRoot\scripts\installers\install-virtualbox.ps1" -envfile $envfile -OsArchBit $OsArchBit
}

If (-Not $noVagrant) {
  & "$PSScriptRoot\scripts\installers\install-vagrant.ps1" -envfile $envfile -OsArchBit $OsArchBit
}

Write-Host ==================================

if ($virtualization_enabled -ne "Yes") {
  Write-Host "Virtualization is not enabled, please follow this link and try to enable"
  Write-Host "https://www.smarthomebeginner.com/enable-hardware-virtualization-vt-x-amd-v/"
  exit 108
} else {
  Write-Host "Done. Please continue to bootstrap"
}
