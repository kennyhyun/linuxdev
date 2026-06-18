# Install WSL2 distro from local tar/tar.gz file (offline)
# Usage: .\scripts\wsl\install-distro-local.ps1 -ImagePath C:\path\to\distro.tar.gz
# Usage: .\scripts\wsl\install-distro-local.ps1 -ImagePath D:\usb\linuxdev-x64.tar -DistroName Linuxdev

param(
    [Parameter(Mandatory)][string]$ImagePath,
    [string]$DistroName = $script:DefaultDistroName,
    [string]$DistroDir  = $script:DefaultDistroDir
)

. "$PSScriptRoot\..\common\wsl-utils.ps1"

if (-not (Test-Path $ImagePath)) { Write-Error "File not found: $ImagePath"; exit 1 }

if (Test-WslDistroExists $DistroName) {
    Write-Host "$DistroName already installed."
    exit 0
}

New-Item -ItemType Directory -Force -Path $DistroDir | Out-Null
Write-Host "Importing $DistroName from $ImagePath ..."
wsl --import $DistroName $DistroDir $ImagePath
if ($LASTEXITCODE -ne 0) { Write-Error "wsl --import failed"; exit 1 }

Install-BootstrapMessage $DistroName
