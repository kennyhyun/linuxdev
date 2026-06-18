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
    [string]$localImage
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
    } else {
        Write-Host "  Enabling $feature ..."
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction SilentlyContinue
        if ($result -and $result.RestartNeeded) { $rebootNeeded = $true }
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
# Reboot if needed
# =============================================
if ($rebootNeeded) {
    Write-Host ""
    Write-Host "NOTICE: Reboot required to complete WSL2 feature activation."
    Write-Host "After rebooting, run: setup.ps1 -wsl"
    if (-not $noConfirm) {
        $ans = Read-Host "Reboot now? [y/N]"
        if ($ans -match '^[Yy]') { Restart-Computer -Force }
    }
    exit 0
}

# =============================================
# Distro install
# =============================================
if ($importDistro -or (-not $noConfirm)) {
    Write-Host ""
    Write-Host "Install WSL2 distro?"
    Write-Host "  [1] Skip"
    Write-Host "  [2] Microsoft Store (Debian)"
    Write-Host "  [3] GitHub Releases (linuxdev custom)"
    Write-Host "  [4] Local file (offline)"
    $choice = if ($importDistro) { "3" } elseif ($localImage) { "4" } else { Read-Host "Enter choice [1]" }

    switch ($choice.Trim()) {
        "2" { & "$PSScriptRoot\..\wsl\install-distro-store.ps1" }
        "3" { & "$PSScriptRoot\..\wsl\install-distro-github.ps1" }
        "4" {
            $img = if ($localImage) { $localImage } else { Read-Host "Path to .tar or .tar.gz" }
            & "$PSScriptRoot\..\wsl\install-distro-local.ps1" -ImagePath $img
        }
        default { Write-Host "Skipped. Run install-distro-*.ps1 later." }
    }
}
