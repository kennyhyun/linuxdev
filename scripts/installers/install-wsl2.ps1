# Enable WSL2 Windows features and install required tools (7-Zip, GitHub CLI)
# Distro installation is handled separately:
#   .\scripts\wsl\install-distro-store.ps1    (Microsoft Store)
#   .\scripts\wsl\install-distro-github.ps1   (GitHub Releases)
#   .\scripts\wsl\install-distro-local.ps1    (local file, offline)
#
# Usage: called from setup.ps1 -wsl

param(
    [switch]$importDistro,
    [switch]$noConfirm,
    [string]$localImage,
    [string]$envFile = "$PSScriptRoot\..\..\.env"
)

. "$PSScriptRoot\..\common\installer-utils.ps1"
. "$PSScriptRoot\..\common\wsl-utils.ps1"

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# =============================================
# Enable WSL2 Windows Features
# =============================================
Write-Host "---------------------------------------"
Write-Host "Enabling WSL2 Windows features..."

$features = @(
    "Microsoft-Windows-Subsystem-Linux",
    "VirtualMachinePlatform",
    "HypervisorPlatform"
)

$rebootNeeded = $false
foreach ($feature in $features) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue).State
    if ($state -eq "Enabled") {
        Write-Host "  $feature already enabled"
    } elseif ($state -eq "EnablePending") {
        # Already enabled in a previous run but not yet rebooted.
        Write-Host "  $feature enabled but pending reboot"
        $rebootNeeded = $true
    } else {
        Write-Host "  Enabling $feature ..."
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction SilentlyContinue
        # A feature that was NOT already enabled requires a reboot to take effect.
        # Do not rely solely on $result.RestartNeeded -- it is unreliable here.
        $rebootNeeded = $true
    }
}

try { wsl --set-default-version 2 2>$null; Write-Host "  WSL default version: 2" } catch {}

# =============================================
# Install 7-Zip
# =============================================
Write-Host "---------------------------------------"
Write-Host "Checking 7-Zip..."
if (Get-Command 7z -ErrorAction SilentlyContinue) {
    Write-Host "7-Zip already installed"
} else {
    Write-Host "Installing 7-Zip via winget..."
    try {
        winget install --id 7zip.7zip -e --silent --accept-package-agreements --accept-source-agreements
        Refresh-Path
    } catch {
        $url = "https://7-zip.org/a/7z2408-x64.exe"
        $installer = "$env:TEMP\7zip-installer.exe"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $installer
        Start-Process -FilePath $installer -ArgumentList "/S" -Wait
        Refresh-Path
    }
    Write-Host "7-Zip installed"
}

# =============================================
# Install GitHub CLI
# =============================================
Write-Host "---------------------------------------"
Write-Host "Checking GitHub CLI..."
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "GitHub CLI already installed: $(gh --version | Select-Object -First 1)"
} else {
    Write-Host "Installing GitHub CLI via winget..."
    try {
        winget install --id GitHub.cli -e --silent --accept-package-agreements --accept-source-agreements
        Refresh-Path
    } catch {
        $OsArchBit = (Get-WMIObject Win32_Processor).AddressWidth
        $pattern = if ($OsArchBit -eq 32) { "*windows_386.msi" } else { "*windows_amd64.msi" }
        $ghAsset = get_github_release_url -url "https://api.github.com/repos/cli/cli/releases/latest" -pattern $pattern
        $ghInstaller = download_from_installer_url -url $ghAsset.url -filename $ghAsset.name
        Start-Process msiexec -ArgumentList "/i `"$ghInstaller`" /quiet /norestart" -Wait
        Refresh-Path
    }
    Write-Host "GitHub CLI installed"
}
# =============================================
# Reboot gate -- must pass before any distro work
# =============================================
# WSL features only take effect after a reboot. 'wsl --status' is NOT reliable:
# before a reboot it still exits 0 and prints "Default Version", while telling
# you to enable the optional component. So we check three things:
#   (a) a feature we just enabled this run ($rebootNeeded)
#   (b) a Windows "pending reboot" registry flag
#   (c) wsl --status output asking to enable the component / WSL1 unsupported

function Test-PendingReboot {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($k in $keys) { if (Test-Path $k) { return $true } }
    $sm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    try {
        $pfro = (Get-ItemProperty -Path $sm -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
        if ($pfro) { return $true }
    } catch {}
    return $false
}

$statusText = ""
try { $statusText = (wsl --status 2>&1 | Out-String) } catch {}
$statusSaysEnable = $statusText -match 'enable the|optional component|not supported with your current'

if ($rebootNeeded -or (Test-PendingReboot) -or $statusSaysEnable) {
    Write-Host ""
    Write-Host "================================================"
    Write-Host " REBOOT REQUIRED"
    Write-Host " WSL2 features were enabled but are not active until you reboot."
    Write-Host ""
    Write-Host " 1. Reboot Windows."
    Write-Host " 2. Re-run:  .\setup.ps1 -wsl"
    Write-Host "================================================"
    if (-not $noConfirm) {
        $ans = Read-Host "Reboot now? [y/N]"
        if ($ans -match '^[Yy]') { Restart-Computer -Force }
    }
    # Do NOT continue to distro install -- WSL is not usable yet.
    exit 2
}
Write-Host "WSL is operational."

# =============================================
# Distro install
# =============================================
if ($importDistro -or $localImage -or (-not $noConfirm)) {
    Write-Host ""
    Write-Host "Install WSL2 distro?"
    Write-Host "  [1] Skip"
    Write-Host "  [2] Microsoft Store (Debian)"
    Write-Host "  [3] GitHub Releases (linuxdev custom)"
    Write-Host "  [4] Local file (offline)"
    # Non-interactive selection: -importdistro -> GitHub custom; -localImage -> local;
    # otherwise (plain -noConfirm) default to Store (Debian). Interactive: ask.
    $choice = if ($importDistro) { "3" }
              elseif ($localImage) { "4" }
              elseif ($noConfirm) { "2" }
              else { Read-Host "Enter choice [1]" }

    switch ($choice.Trim()) {
        "2" { & "$PSScriptRoot\..\wsl\install-distro-store.ps1"  -EnvFile $envFile; $installed = $true; $installedDistro = "Debian" }
        "3" { & "$PSScriptRoot\..\wsl\install-distro-github.ps1" -EnvFile $envFile; $installed = $true; $installedDistro = "Linuxdev" }
        "4" {
            $img = if ($localImage) { $localImage } else { Read-Host "Path to .tar or .tar.gz" }
            & "$PSScriptRoot\..\wsl\install-distro-local.ps1" -ImagePath $img -EnvFile $envFile
            $installed = $true; $installedDistro = "Linuxdev"
        }
        default { Write-Host "Skipped. Run install-distro-*.ps1 later." }
    }
    # NOTE: each install-distro-*.ps1 runs post-install.ps1, which waits for the
    # distro to be ready and then runs bootstrap-wsl.sh (--noninteractive --envfile).
    # Do not call bootstrap here -- that caused a double-run with the wrong distro name.

    # --- Expose WSL docker to Windows (only when a docker runtime was set up) ---
    if ($installed) {
        $runtime = "docker"
        if (Test-Path $envFile) {
            foreach ($line in Get-Content $envFile) {
                if ($line -match '^\s*WSL_CONTAINER_RUNTIME\s*=\s*(.+?)\s*$') { $runtime = $matches[1].Trim() }
            }
        }
        if ($runtime -eq "docker" -or $runtime -eq "both") {
            $distro = if ($installedDistro) { $installedDistro } else { $script:DefaultDistroName }
            Write-Host ""
            Write-Host "----- Docker: exposing WSL daemon to Windows -----"
            # Convert repo path to WSL mount path
            $repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
            $repoUnc  = if ($repoRoot -match '^([A-Za-z]):\\(.*)$') { "/mnt/$($matches[1].ToLower())/$($matches[2] -replace '\\','/')" } else { $repoRoot -replace '\\','/' }
            # 1) Ensure systemd/docker are live, then open localhost TCP inside WSL
            wsl --terminate $distro 2>$null
            Start-Sleep -Seconds 2
            wsl -d $distro -u root -- bash "$repoUnc/scripts/wsl/enable-docker-tcp.sh"
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "enable-docker-tcp.sh failed; skipping Windows docker CLI setup."
            } else {
                # 2) Install Windows docker CLI if missing + set DOCKER_HOST
                & "$PSScriptRoot\..\wsl\setup-docker-host.ps1"
            }
        }
    }
}

# =============================================
# Optional: GitLab Runner (CI) -- guidance only
# =============================================
# The runner is NOT installed here. It is an optional add-on for turning this
# machine into a CI runner host. The install lives inside the distro (bash) and
# the auto-start is a Windows scheduled task -- both are run on demand.
Write-Host ""
Write-Host "----- Optional: GitLab Runner (CI) -----"
Write-Host "To turn this WSL2 machine into a GitLab CI runner, run these AFTER the"
Write-Host "distro is installed and bootstrapped (bootstrap-wsl.sh sets up docker):"
Write-Host ""
Write-Host "  1) Install + register the runner (inside WSL, as root):"
Write-Host "       sudo bash scripts/wsl/install-runner.sh \"
Write-Host "         --url https://gitlab.imaginetoolbox.com \"
Write-Host "         --token <registration-token> \"
Write-Host "         --tags linux,localstack,runner --autostart"
Write-Host ""
Write-Host "  2) Auto-start the distro at Windows logon (admin PowerShell):"
Write-Host "       .\scripts\wsl\register-autostart.ps1 -DistroName <DistroName>"
Write-Host ""
Write-Host "  Skip both if you only need a local dev environment."
Write-Host "----------------------------------------"
