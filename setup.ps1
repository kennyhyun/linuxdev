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
If ($args.Contains("-noshortcut")) {
  $noShortcut = 1
}
If ($args.Contains("-noautostart")) {
  $noAutostart = 1
}
# -distroname <name>: name to register the Store distro under (default: linuxdev)
$distroName = ""
for ($i = 0; $i -lt $args.Count - 1; $i++) {
  if ("$($args[$i])" -ieq "-distroname") { $distroName = "$($args[$i + 1])" }
}
# -dockerdisk <size>: docker.vhdx size, e.g. 64G / 64GB / 64 (GB). Written to the
# per-distro env file ~/.linuxdev/<distroname>/.env (WSL backend only).
$dockerDiskGB = $null
for ($i = 0; $i -lt $args.Count; $i++) {
  if ("$($args[$i])" -ieq "-dockerdisk") {
    $raw = if ($i + 1 -lt $args.Count) { "$($args[$i + 1])" } else { "" }
    # PowerShell turns a bare 64GB argument into the number 68719476736 (bytes)
    if ($raw -match '^\s*(\d+)\s*(g|gb)?\s*$') {
      $n = [long]$matches[1]
      if ($n -ge 1GB -and ($n % 1GB) -eq 0) { $n = [long]($n / 1GB) }
      if ($n -ge 1 -and $n -le 65536) { $dockerDiskGB = [int]$n }
    }
    if ($null -eq $dockerDiskGB) {
      Write-Error "Invalid -dockerdisk value '$raw' (use e.g. 64G, 64GB or 64)"
      exit 1
    }
  }
}

# Legacy flags - keep for backward compat
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
Write-Host "================================================"

# Did the user pass any meaningful option?
$hasOptions = $args.Count -gt 0

if (-not $hasOptions) {
  # No options: show full usage + examples
  Write-Host " Common tools: git, windows terminal (always, unless skipped)"
  Write-Host " VM backend:   wsl2 / virtualbox+vagrant / none (selectable)"
  Write-Host ""
  Write-Host " Options:"
  Write-Host "   -wsl          set up WSL2 backend (recommended for Win11)"
  Write-Host "   -vagrant      set up VirtualBox + Vagrant backend (legacy)"
  Write-Host "   -novm         minimal: common tools only, skip VM backend"
  Write-Host "   -nodevtools   skip Windows Terminal"
  Write-Host "   -nogit        skip Git install"
  Write-Host "   -vscode       also install VSCode"
  Write-Host "   -importdistro install the WSL2 distro automatically"
  Write-Host "   -distroname <name>  name for the WSL distro (default: linuxdev). Settings: ~/.linuxdev/<name>/.env"
  Write-Host "   -dockerdisk <size>  docker disk size, e.g. 64G (default 120G)"
  Write-Host "   -noshortcut   don't create the desktop shortcut (htop in the distro)"
  Write-Host "   -noautostart  don't register the logon task (disk attach + keep-alive)"
  Write-Host "   -noconfirm    non-interactive (use .env / defaults, no prompts)"
  Write-Host ""
  Write-Host " Examples:"
  Write-Host "   .\setup.ps1 -wsl                          WSL2, interactive (recommended)"
  Write-Host "   .\setup.ps1 -wsl -noconfirm               WSL2, non-interactive (Store distro, .env defaults)"
  Write-Host "   .\setup.ps1 -wsl -importdistro            WSL2 + custom distro from GitHub Releases"
  Write-Host "   .\setup.ps1 -wsl -distroname dev2 -dockerdisk 64G   distro 'dev2', 64G docker disk (~/.linuxdev/dev2/.env)"
  Write-Host "   .\setup.ps1 -vagrant                      VirtualBox + Vagrant (legacy)"
  Write-Host "   .\setup.ps1 -novm -nodevtools -noconfirm  minimal: tools only"
  Write-Host "================================================"
} else {
  # Options given: explain what the current invocation will do
  Write-Host " This run will:"
  if ($noGit)     { Write-Host "   - skip Git install" }       else { Write-Host "   - install/verify Git" }
  if ($noTerminal){ Write-Host "   - skip Windows Terminal" }   else { Write-Host "   - install/verify Windows Terminal" }
  if ($withVsCode){ Write-Host "   - install VSCode" }
  switch ($vmBackend) {
    "wsl"     { Write-Host "   - set up WSL2 backend" ;
                if ($importDistro) { Write-Host "       + install the WSL2 distro (GitHub Releases)" }
                elseif ($noConfirm) { Write-Host "       + non-interactive: Store distro + .env defaults" }
                else { Write-Host "       + interactive: choose distro + enter .env values" } }
    "vagrant" { Write-Host "   - set up VirtualBox + Vagrant backend (disables Hyper-V)" }
    "none"    { Write-Host "   - skip VM backend setup (tools only)" }
    default   { Write-Host "   - prompt for VM backend (none/wsl2/vagrant)" }
  }
  if ($noConfirm) { Write-Host "   - run non-interactively (no prompts)" }
  Write-Host "================================================"
  Write-Host " Run with no options to see all flags and examples."
  Write-Host "================================================"
}
if (-not $noConfirm) {
  Read-Host -Prompt "Press Enter to continue or Ctrl+C to stop"
}

# Default env file: repo .env (used by the Vagrant backend, and as the template that
# seeds the per-distro file ~/.linuxdev/<distroname>/.env for the WSL backend).
$envPath = "$PSScriptRoot\.env"

# Load env file if present
$envfile = [ordered]@{}
$envfileContent = Get-Content $envPath -ErrorAction SilentlyContinue
if ($envfileContent) {
  $envfileContent | ForEach-Object {
    $key, $value = $_.split("=")
    if ($key) { $envfile[$key] = $value }
  }
}

# Set KEY=VALUE in an env file (replace the line if present, else append; creates the file)
function Set-EnvValue($path, $key, $value) {
  $lines = @()
  if (Test-Path $path) { $lines = @(Get-Content $path) }
  $found = $false
  $out = @(foreach ($l in $lines) {
    if ($l -match "^\s*$([regex]::Escape($key))\s*=") { $found = $true; "$key=$value" } else { $l }
  })
  if (-not $found) { $out += "$key=$value" }
  Set-Content -Path $path -Value $out
  $script:envfile[$key] = "$value"
}

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

# Ensure .gitattributes line endings are respected (override autocrlf=input)
$repoConfig = git -C $PSScriptRoot config core.autocrlf 2>$null
if ($repoConfig -ne "false") {
    git -C $PSScriptRoot config core.autocrlf false
    git -C $PSScriptRoot rm --cached -r . 2>$null | Out-Null
    git -C $PSScriptRoot reset --hard HEAD 2>$null | Out-Null
}

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

if ($null -ne $dockerDiskGB -and $vmBackend -ne "wsl") {
  Write-Warning "-dockerdisk only applies to the WSL backend (-wsl); ignored."
}

switch ($vmBackend) {

  "wsl" {
    Write-Host ""
    Write-Host "======= WSL2 Setup ======="

    # --- Interactive .env collection (ask only if empty; save to .env) ---
    # To change saved values later, edit or delete .env (or rename it) and re-run.
    # --- per-distro env file: ~/.linuxdev/<distroname>/.env ---
    # Created on first use, seeded from the repo .env (common defaults) if present.
    # From here on this file is the one read/written and passed to every script.
    . "$PSScriptRoot\scripts\common\wsl-utils.ps1"
    if (-not $distroName) {
      if ($noConfirm) {
        $distroName = "linuxdev"
      } else {
        $in = Read-Host "Distro name [linuxdev]"
        $distroName = if ([string]::IsNullOrWhiteSpace($in)) { "linuxdev" } else { $in.Trim() }
      }
    }
    if ($distroName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
      Write-Error "Invalid distro name '$distroName' (use letters, digits, '.', '_', '-')"
      exit 1
    }
    $distroHome = Get-LinuxdevDir $distroName
    $envPath = Join-Path $distroHome ".env"
    New-Item -ItemType Directory -Force -Path $distroHome | Out-Null
    if (-not (Test-Path $envPath)) {
      if (Test-Path "$PSScriptRoot\.env") {
        Copy-Item "$PSScriptRoot\.env" $envPath
        Write-Host "Created $envPath (copied from repo .env)"
      } else {
        New-Item -ItemType File -Path $envPath | Out-Null
        Write-Host "Created $envPath"
      }
    }
    Write-Host "Using env file: $envPath"
    $envfile = [ordered]@{}
    Get-Content $envPath -ErrorAction SilentlyContinue | ForEach-Object {
      $key, $value = $_.split("=")
      if ($key) { $envfile[$key] = $value }
    }
    Set-EnvValue $envPath "WSL_DISTRO_NAME" $distroName
    if ($null -ne $dockerDiskGB) {
      Set-EnvValue $envPath "DOCKER_SIZE_GB" $dockerDiskGB
      Write-Host "  DOCKER_SIZE_GB=$dockerDiskGB"
    }
    function Get-OrAsk($key, $prompt, $default) {
      $cur = $envfile[$key]
      if ($cur) { return $cur }
      if ($noConfirm) {
        $val = $default
      } else {
        $in = Read-Host "$prompt [$default]"
        $val = if ([string]::IsNullOrWhiteSpace($in)) { $default } else { $in.Trim() }
      }
      Add-Content $envPath "$key=$val"
      $envfile[$key] = $val
      return $val
    }
    Get-OrAsk "WSL_USERNAME"     "Default Linux username (UID 1000)"                "linuxdev"  | Out-Null
    Get-OrAsk "WSL_CONTAINER_RUNTIME" "Container runtime (docker/microk8s/both/none)" "docker"   | Out-Null
    Get-OrAsk "MEMORY"           "WSL2 memory limit in MB (global)"                 "4096"      | Out-Null
    Get-OrAsk "CPUS"             "WSL2 CPU count (global)"                          "4"         | Out-Null
    Get-OrAsk "WSL_AUTO_RECLAIM" "Memory auto-reclaim (gradual/dropcache/disabled)" "gradual"   | Out-Null
    Get-OrAsk "WSL_SWAP"         "WSL2 swap in MB (0 to disable)"                   "0"         | Out-Null
    Get-OrAsk "DOTFILES_REPO"    "Dotfiles repo URL (blank to skip)"                ""          | Out-Null

    # --- Host-global .wslconfig from .env (memory/cpu/reclaim/swap) ---
    & "$PSScriptRoot\scripts\wsl\configure-wslconfig.ps1" -EnvFile $envPath

    & "$PSScriptRoot\scripts\installers\install-wsl2.ps1" `
        -importDistro:([bool]$importDistro) `
        -noConfirm:([bool]$noConfirm) `
        -noShortcut:([bool]$noShortcut) `
        -noAutostart:([bool]$noAutostart) `
        -distroName $distroName `
        -envFile $envPath
    if ($LASTEXITCODE -eq 2) {
        # install-wsl2 signalled "reboot required" -- stop here, do not print "Done".
        exit 2
    }
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
