# Install WSL2 distro from Microsoft Store, then run post-install
# Usage: .\scripts\wsl\install-distro-store.ps1 [-Distro Debian] [-DefaultUser linuxdev]

param(
    [string]$Distro = "Debian",
    [string]$DefaultUser = "linuxdev",
    [switch]$SkipPostInstall
)

. "$PSScriptRoot\..\common\wsl-utils.ps1"

if (Test-WslDistroExists $Distro) {
    Write-Host "$Distro already installed."
} else {
    Write-Host "Installing $Distro from Microsoft Store..."
    wsl --install -d $Distro --no-launch
    if ($LASTEXITCODE -ne 0) { Write-Error "wsl --install failed"; exit 1 }
    Write-Host "$Distro installed."
}

if (-not $SkipPostInstall) {
    & "$PSScriptRoot\post-install.ps1" -DistroName $Distro -DefaultUser $DefaultUser
}
