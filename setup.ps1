$ErrorActionPreference = "Stop"
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "Please run as an administrator"
  exit 109
}

# --- Argument parsing ---
If ($args.Contains("-noconfirm")) {
  $noConfirm = 1
}
If ($args.Contains("-nodevtools")) {
  $noTerminal = 1
}
If ($args.Contains("-nogit")) {
  $noGit = 1
}
If ($args.Contains("-noterminal")) {
  $noTerminal = 1
}
If ($args.Contains("-vscode")) {
  $withVsCode = 1
}
If ($args.Contains("-wsl")) {
  $vmBackend = "wsl"
}
If ($args.Contains("-vagrant")) {
  $vmBackend = "vagrant"
}
If ($args.Contains("-novm")) {
  $vmBackend = "none"
}
If ($args.Contains("-importdistro")) {
  $importDistro = 1
}

# Legacy flags — keep for backward compat
If ($args.Contains("-novagrant")) {
  $noVagrant = 1
}
If ($args.Contains("-novirtualbox")) {
  $noVirtualBox = 1
}
If ($args.Contains("-withvagrantmanager")) {
  $withVagrantManager = 1
}
If ($args.Contains("-withosconfig")) {
  $withOsConfig = 1
}
If ($args.Contains("-nohyperv")) {
  $noHyperv = 1
}

$OsVersion = (Get-WmiObject -class Win32_OperatingSystem).Caption
$OsArchBit = (Get-WMIObject Win32_Processor).AddressWidth
$OsArch = if ($OsArchBit -ne 32) { "x64" } else { "x86" }
$OsBuildNumber = (Get-WmiObject -class Win32_OperatingSystem).BuildNumber
if ($OsBuildNumber -lt 19041) {
  Write-Error "Windows Build number should be at least 19041"
  exit 101
}

Write-Host "================================================"
Write-Host " Linuxdev Setup"
Write-Host " Common: git, windows terminal"
Write-Host " VM backend: selectable (wsl2 / virtualbox+vagrant / none)"
Write-Host "================================================"
if (-not $noConfirm) {
  Read-Host -Prompt "Press Enter to continue or Ctrl+C to stop"
}

# Load .env if present
$envfile = [ordered]@{}
$envfileContent = Get-Content "$PSScriptRoot\.env" -ErrorAction SilentlyContinue
if ($envfileContent) {
  $envfileContent | ForEach-Object {
    $key, $value = $_.split("=")
    if ($key) { $envfile[$key] = $value }
  }
}

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

if ($withOsConfig) {
  & "$PSScriptRoot\scripts\basic-config.ps1"
}

# =============================================
# Common tools (always installed)
# =============================================
Write-Host ""
Write-Host "======= Common Tools ======="

If (-Not $noTerminal) {
  & "$PSScriptRoot\scripts\installers\install-terminal.ps1" -OsVersion $OsVersion
}

If (-Not $noGit) {
  & "$PSScriptRoot\scripts\installers\install-git.ps1" -OsArchBit $OsArchBit
}

If ($withVsCode) {
  & "$PSScriptRoot\scripts\installers\install-vscode.ps1"
}

# =============================================
# VM Backend selection
# =============================================
Write-Host ""
if (-not $vmBackend) {
  Write-Host "Which VM backend do you want to set up?"
  Write-Host "  [1] None (skip)"
  Write-Host "  [2] WSL2  (recommended for Windows 11)"
  Write-Host "  [3] VirtualBox + Vagrant  (legacy)"
  Write-Host ""
  $choice = Read-Host "Enter choice [1]"
  switch ($choice.Trim()) {
    "2" { $vmBackend = "wsl" }
    "3" { $vmBackend = "vagrant" }
    default { $vmBackend = "none" }
  }
}

switch ($vmBackend) {

  "wsl" {
    Write-Host ""
    Write-Host "======= WSL2 Setup ======="
    & "$PSScriptRoot\scripts\installers\install-wsl2.ps1" `
        -importDistro:([bool]$importDistro) `
        -noConfirm:([bool]$noConfirm)
  }

  "vagrant" {
    Write-Host ""
    Write-Host "======= VirtualBox + Vagrant Setup ======="

    # VirtualBox needs Hyper-V disabled
    if (-not $noHyperv) {
      Write-Host "Disabling Hyper-V for VirtualBox compatibility..."
      try {
        function disable-optional-feature {
          param ($featureName)
          $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName
          if ($feature) {
            if ($feature.State -eq "Disabled") {
              Write-Host "  $featureName already disabled"
            } else {
              Disable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart
            }
          } else {
            Write-Host "  $featureName not found"
          }
        }
        disable-optional-feature -featureName Microsoft-Hyper-V-Hypervisor
        disable-optional-feature -featureName VirtualMachinePlatform
        disable-optional-feature -featureName HypervisorPlatform
        Start-Process -Wait -PassThru powershell -Verb runAs -ArgumentList 'bcdedit /set hypervisorlaunchtype off'
      } catch {
        Write-Host $_
        exit 102
      }
    }

    $virtualization_enabled = systeminfo | Select-String "Virtualization Enabled" |
      Out-String | ForEach-Object { $_.SubString($_.IndexOf(': ') + 1).Trim() }
    Write-Host "Virtualization support: $virtualization_enabled"

    If ($withVagrantManager) {
      & "$PSScriptRoot\scripts\installers\install-vagrant-manager.ps1"
    }
    If (-Not $noVirtualBox) {
      & "$PSScriptRoot\scripts\installers\install-virtualbox.ps1" -envfile $envfile -OsArchBit $OsArchBit
    }
    If (-Not $noVagrant) {
      & "$PSScriptRoot\scripts\installers\install-vagrant.ps1" -envfile $envfile -OsArchBit $OsArchBit
    }

    if ($virtualization_enabled -ne "Yes") {
      Write-Host "Virtualization is not enabled. Please follow:"
      Write-Host "https://www.smarthomebeginner.com/enable-hardware-virtualization-vt-x-amd-v/"
      exit 108
    }
  }

  default {
    Write-Host "Skipping VM backend setup."
  }
}

Write-Host ""
Write-Host "================================================"
Write-Host " Done. Please continue to bootstrap."
Write-Host "================================================"
