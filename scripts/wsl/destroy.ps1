# Destroy WSL2 distro and all associated vhdx data disks
# DESTRUCTIVE - asks for confirmation with distro name
#
# Usage: .\scripts\wsl\destroy.ps1
# Usage: .\scripts\wsl\destroy.ps1 -DistroName Debian -DiskDir C:\custom\path

param(
    [string]$DistroName = "",
    [string]$DiskDir    = "$env:USERPROFILE\linuxdev\disks",
    [string]$DistroDir  = "$env:USERPROFILE\linuxdev\distro",
    [switch]$Volumes    # Also delete vhdx data disks (home/docker/brew)
)

. "$PSScriptRoot\..\common\wsl-utils.ps1"

# List installed distros
$distros = Get-WslDistros
if ($distros.Count -eq 0) {
    Write-Host "No WSL distros installed."
    exit 0
}

Write-Host "Installed distros:"
$distros | ForEach-Object { Write-Host "  $_" }
Write-Host ""

# Confirm distro name
if (-not $DistroName) {
    $DistroName = Read-Host "Enter distro name to destroy (or Enter to cancel)"
    if (-not $DistroName) {
        Write-Host "Cancelled."
        exit 0
    }
}

if (-not (Test-WslDistroExists $DistroName)) {
    Write-Error "Distro '$DistroName' not found."
    exit 1
}

# Final confirmation
Write-Host ""
Write-Host "WARNING: This will permanently delete:"
Write-Host "  - WSL distro: $DistroName"
Write-Host "  - Distro dir: $DistroDir"
if ($Volumes) {
    Write-Host "  - Disk files in: $DiskDir  (--Volumes specified)"
} else {
    Write-Host "  - Disk files: KEPT (use -Volumes to also delete)"
}
Write-Host ""
$confirm = Read-Host "Type the distro name again to confirm"
if ($confirm -ne $DistroName) {
    Write-Host "Cancelled (name did not match)."
    exit 0
}

# Terminate
Write-Host ""
Write-Host "Terminating $DistroName..."
wsl --terminate $DistroName 2>$null
Start-Sleep -Seconds 2

# Detach disks
$disks = @("home.vhdx", "docker.vhdx", "brew.vhdx")
foreach ($disk in $disks) {
    $path = "$DiskDir\$disk"
    if (Test-Path $path) {
        Write-Host "Detaching $disk..."
        wsl --unmount $path 2>$null
    }
}

# Unregister distro
Write-Host "Unregistering $DistroName..."
wsl --unregister $DistroName
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: wsl --unregister returned error (may already be gone)"
}

# Delete vhdx disk files (only with -Volumes)
if ($Volumes) {
    if (Test-Path $DiskDir) {
        Write-Host "Deleting disk files in $DiskDir..."
        foreach ($disk in $disks) {
            $path = "$DiskDir\$disk"
            if (Test-Path $path) {
                Remove-Item $path -Force
                Write-Host "  Deleted: $disk"
            }
        }
    }
} else {
    Write-Host "Disk files kept in $DiskDir (re-use with -AttachOnly on next install)"
}

# Delete distro dir (ext4.vhdx for custom imports)
if (Test-Path $DistroDir) {
    Write-Host "Deleting distro dir $DistroDir..."
    Remove-Item $DistroDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Done. '$DistroName' has been destroyed."
if ($Volumes) {
    Write-Host "All data disks deleted."
} else {
    Write-Host "Data disks preserved in $DiskDir"
    Write-Host "To reuse: install-distro-store.ps1 then setup-disks.ps1 -AttachOnly"
}
Write-Host "Run install-distro-store.ps1 (or other) to start fresh."
