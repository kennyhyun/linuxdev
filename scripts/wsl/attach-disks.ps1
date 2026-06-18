# Attach Linuxdev data disks to WSL2
# Run this before starting WSL, or add to Windows startup / Task Scheduler
#
# Usage:
#   .\scripts\wsl\attach-disks.ps1
#   .\scripts\wsl\attach-disks.ps1 -DiskDir D:\wsl-disks
#   .\scripts\wsl\attach-disks.ps1 -SkipBrew

param(
    [string]$DiskDir  = "$env:USERPROFILE\linuxdev\disks",
    [switch]$SkipBrew
)

$disks = @("home.vhdx", "docker.vhdx")
if (-not $SkipBrew) { $disks += "brew.vhdx" }

$anyFailed = $false

foreach ($disk in $disks) {
    $path = "$DiskDir\$disk"
    if (-not (Test-Path $path)) {
        Write-Host "SKIP: $path not found"
        continue
    }
    Write-Host "Attaching $disk ..."
    wsl --mount --vhd $path --bare 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK: $disk attached"
    } else {
        # May already be attached — not always an error
        Write-Host "  NOTE: $disk may already be attached (exit $LASTEXITCODE)"
    }
}

if (-not $anyFailed) {
    Write-Host ""
    Write-Host "Disks attached. Start WSL normally:"
    Write-Host "  wsl -d Linuxdev"
}
