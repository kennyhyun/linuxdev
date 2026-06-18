# Install WSL2 distro from Microsoft Store
# Usage: .\scripts\wsl\install-distro-store.ps1 [-Distro Debian]

param([string]$Distro = "Debian")

. "$PSScriptRoot\..\common\wsl-utils.ps1"

if (Test-WslDistroExists $Distro) {
    Write-Host "$Distro already installed."
    exit 0
}

Write-Host "Installing $Distro from Microsoft Store..."
wsl --install -d $Distro
if ($LASTEXITCODE -ne 0) { Write-Error "wsl --install failed"; exit 1 }

Install-BootstrapMessage $Distro
