# Install WSL2 distro from Microsoft Store, then run post-install.
# The Store distro is installed under a custom name (default: linuxdev) using
# 'wsl --install --name' (requires WSL >= 2.4; run 'wsl --update' if missing).
#
# Usage: .\scripts\wsl\install-distro-store.ps1 [-Distro Debian] [-DistroName linuxdev] [-DefaultUser linuxdev]
#
#   -Distro      Store distro to install (source image).
#   -DistroName  Name to register it under in WSL. If it equals -Distro, the
#                Store distro is installed under its own name.

param(
    [string]$Distro = "Debian",
    [string]$DistroName = "linuxdev",
    [string]$DefaultUser = "linuxdev",
    [string]$DistroDir = "",   # default: %USERPROFILE%\.linuxdev\<DistroName>\distro
    [string]$EnvFile = "$PSScriptRoot\..\..\.env",
    [switch]$SkipPostInstall
)

. "$PSScriptRoot\..\common\wsl-utils.ps1"

if (-not $DistroDir) { $DistroDir = Get-LinuxdevDir $DistroName "distro" }

if (-not $DistroName) { $DistroName = "linuxdev" }
if ($DistroName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    Write-Error "Invalid distro name '$DistroName' (use letters, digits, '.', '_', '-')"
    exit 1
}

if (Test-WslDistroExists $DistroName) {
    Write-Host "$DistroName already installed."
} elseif ($DistroName -ieq $Distro) {
    # Same name as the Store distro: plain install.
    Write-Host "Installing $Distro from Microsoft Store..."
    wsl --install -d $Distro --no-launch
    if ($LASTEXITCODE -ne 0) { Write-Error "wsl --install failed"; exit 1 }
    Write-Host "$Distro installed."
} else {
    # Different name: fresh Store image registered directly under the new name.
    New-Item -ItemType Directory -Force -Path $DistroDir | Out-Null
    Write-Host "Installing $Distro from Microsoft Store as '$DistroName' ..."
    wsl --install -d $Distro --name $DistroName --location $DistroDir --no-launch
    if ($LASTEXITCODE -ne 0 -or -not (Test-WslDistroExists $DistroName)) {
        Write-Error "'wsl --install --name' failed. It requires WSL >= 2.4 -- run 'wsl --update' and retry."
        exit 1
    }
    Write-Host "$DistroName installed."
}

if (-not $SkipPostInstall) {
    & "$PSScriptRoot\post-install.ps1" -DistroName $DistroName -DefaultUser $DefaultUser -EnvFile $EnvFile
}
