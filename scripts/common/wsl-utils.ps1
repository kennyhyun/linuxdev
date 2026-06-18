# Common WSL2 utility functions
# Usage: . "$PSScriptRoot\..\common\wsl-utils.ps1"

$script:DefaultDistroName = "Linuxdev"
$script:DefaultDistroDir  = "$env:USERPROFILE\linuxdev\distro"
$script:DefaultVhdxPath   = "$script:DefaultDistroDir\ext4.vhdx"
$script:GithubRepo        = "kennyhyun/linuxdev"

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Get-WslDistros {
    # Returns list of installed distro names (handles UTF-16LE null bytes)
    return (wsl --list --quiet 2>$null) -replace "`0", "" |
           Where-Object { $_.Trim() -ne "" } |
           ForEach-Object { $_.Trim() }
}

function Test-WslDistroExists {
    param([string]$Name)
    return (Get-WslDistros) -contains $Name
}

function Install-BootstrapMessage {
    param([string]$DistroName)
    Write-Host ""
    Write-Host "Distro '$DistroName' installed."
    Write-Host ""
    Write-Host "NEXT STEPS:"
    Write-Host "  1. Run setup-disks.ps1 to create data disks:"
    Write-Host "       .\scripts\wsl\setup-disks.ps1 -DistroName $DistroName"
    Write-Host "  2. Run bootstrap-wsl.sh inside WSL:"
    Write-Host "       wsl -d $DistroName -u root -- bash /mnt/c/Users/$env:USERNAME/linuxdev/bootstrap-wsl.sh"
}
