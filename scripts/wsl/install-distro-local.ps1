# Install WSL2 distro from local tar/tar.gz (offline), then run post-install
# Usage: .\scripts\wsl\install-distro-local.ps1 -ImagePath C:\path\to\distro.tar.gz
# Usage: .\scripts\wsl\install-distro-local.ps1 -ImagePath D:\linuxdev.tar -DistroName Linuxdev

param(
    [Parameter(Mandatory)][string]$ImagePath,
    [string]$DistroName  = "Linuxdev",
    [string]$DistroDir   = "$env:USERPROFILE\linuxdev\distro",
    [string]$DefaultUser = "linuxdev",
    [switch]$SkipPostInstall
)

. "$PSScriptRoot\..\common\wsl-utils.ps1"

if (-not (Test-Path $ImagePath)) { Write-Error "File not found: $ImagePath"; exit 1 }

if (-not (Test-WslDistroExists $DistroName)) {
    New-Item -ItemType Directory -Force -Path $DistroDir | Out-Null
    Write-Host "Importing $DistroName from $ImagePath ..."
    wsl --import $DistroName $DistroDir $ImagePath
    if ($LASTEXITCODE -ne 0) { Write-Error "wsl --import failed"; exit 1 }
    Write-Host "$DistroName installed."
} else {
    Write-Host "$DistroName already installed."
}

if (-not $SkipPostInstall) {
    & "$PSScriptRoot\post-install.ps1" -DistroName $DistroName -DefaultUser $DefaultUser
}
