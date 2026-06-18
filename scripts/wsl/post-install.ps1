# Post-install setup for WSL2 distro
# Called automatically after any install-distro-*.ps1
# - Runs bootstrap-wsl.sh inside WSL (user, visudo, wsl.conf, rootfs-ro)
# - Creates and attaches data disks (setup-disks.ps1)
# - Mounts disks inside WSL (mount-disks.sh)
#
# Usage: .\scripts\wsl\post-install.ps1 -DistroName Debian

param(
    [string]$DistroName = "Linuxdev",
    [string]$DefaultUser = "linuxdev",
    [string]$DiskDir = "$env:USERPROFILE\linuxdev\disks",
    [switch]$SkipDisks,
    [switch]$SkipBrew
)

. "$PSScriptRoot\..\common\wsl-utils.ps1"

$linuxdevRoot = "$env:USERPROFILE\linuxdev"
# Windows path -> WSL mount path
$wslRoot = "/mnt/c/Users/$env:USERNAME/linuxdev"

Write-Host "========================================"
Write-Host " Post-install: $DistroName"
Write-Host " Default user: $DefaultUser"
Write-Host "========================================"

# =============================================
# Step 1: Run bootstrap-wsl.sh inside WSL
# =============================================
Write-Host ""
Write-Host "Running bootstrap-wsl.sh inside WSL..."
Write-Host "  (installs packages, creates user '$DefaultUser', sets up wsl.conf + rootfs-ro)"

wsl -d $DistroName -u root -- bash "$wslRoot/bootstrap-wsl.sh" --user $DefaultUser
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: bootstrap-wsl.sh returned $LASTEXITCODE - check output above"
}

# =============================================
# Step 2: Restart WSL to apply wsl.conf
# =============================================
Write-Host ""
Write-Host "Restarting WSL to apply wsl.conf..."
wsl --terminate $DistroName 2>$null
Start-Sleep -Seconds 2

# =============================================
# Step 3: Setup data disks
# =============================================
if (-not $SkipDisks) {
    Write-Host ""
    Write-Host "Setting up data disks..."
    if ($SkipBrew) {
        & "$PSScriptRoot\setup-disks.ps1" -DistroName $DistroName -DiskDir $DiskDir -SkipBrew
    } else {
        & "$PSScriptRoot\setup-disks.ps1" -DistroName $DistroName -DiskDir $DiskDir
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: setup-disks.ps1 returned errors - check output above"
    }
} else {
    Write-Host "Skipping disk setup (-SkipDisks)"
}

# =============================================
# Step 4: Format disks (if not already formatted)
# =============================================
Write-Host ""
Write-Host "Formatting unformatted disks (skips already-formatted)..."
wsl -d $DistroName -u root -- bash "$wslRoot/scripts/wsl/format-disks.sh"
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: format-disks.sh returned errors"
}

# =============================================
# Step 5: Mount disks inside WSL
# =============================================
Write-Host ""
Write-Host "Mounting disks inside WSL..."
wsl -d $DistroName -u root -- bash "$wslRoot/scripts/wsl/mount-disks.sh"
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: mount-disks.sh returned errors"
}

# =============================================
# Done
# =============================================
Write-Host ""
Write-Host "========================================"
Write-Host " Post-install complete."
Write-Host ""
Write-Host " Start WSL:"
Write-Host "   wsl -d $DistroName"
Write-Host ""
Write-Host " Install dotfiles (inside WSL as $DefaultUser):"
Write-Host "   git clone https://github.com/kennyhyun/dotfiles.git ~/dotfiles"
Write-Host "   PRODUCTION=1 bash ~/dotfiles/scripts/linux.sh linuxdev"
Write-Host ""
Write-Host " On next Windows boot, attach disks first:"
Write-Host "   .\scripts\wsl\attach-disks.ps1"
Write-Host "   wsl -d $DistroName"
Write-Host "========================================"
