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
    [string]$EnvFile = "$PSScriptRoot\..\..\.env",
    [string]$DiskDir = "",   # default: %USERPROFILE%\.linuxdev\<DistroName>\disks
    [switch]$SkipDisks,
    [switch]$NoConfirm
)

. "$PSScriptRoot\..\common\wsl-utils.ps1"

if (-not $DiskDir) { $DiskDir = Get-LinuxdevDir $DistroName "disks" }

# Convert a Windows path (C:\Users\me\x) to a WSL path (/mnt/c/Users/me/x)
function ConvertTo-WslPath($winPath) {
    $full = $winPath
    try { $r = (Resolve-Path $winPath -ErrorAction Stop).Path; if ($r) { $full = $r } } catch {}
    if ($full -match '^([A-Za-z]):\\(.*)$') {
        return "/mnt/$($matches[1].ToLower())/$($matches[2] -replace '\\','/')"
    }
    return ($full -replace '\\','/')
}

# This repo's root as seen from WSL (the repo can live anywhere, not only
# C:\Users\<user>\linuxdev): scripts/wsl/post-install.ps1 -> ..\..
$wslRoot = ConvertTo-WslPath (Resolve-Path "$PSScriptRoot\..\..").Path

# Resolve default user: .env WSL_USERNAME wins over the -DefaultUser default
if (Test-Path $EnvFile) {
    foreach ($line in Get-Content $EnvFile) {
        if ($line -match '^\s*WSL_USERNAME\s*=\s*(.+?)\s*$') { $DefaultUser = $matches[1].Trim() }
    }
}
$envUnc = ConvertTo-WslPath $EnvFile

# Random user password lives at %USERPROFILE%\.linuxdev\<DistroName>\password
# (bootstrap-wsl.sh generates it on first user creation, reuses it otherwise).
$passFile = Join-Path (Get-LinuxdevDir $DistroName) "password"
New-Item -ItemType Directory -Force -Path (Split-Path $passFile) | Out-Null
$passUnc = ConvertTo-WslPath $passFile

Write-Host "========================================"
Write-Host " Post-install: $DistroName"
Write-Host " Default user: $DefaultUser"
Write-Host "========================================"

# =============================================
# Step 0: Wait for the distro to be ready
# =============================================
# A freshly `wsl --install --no-launch`ed distro is registered but not yet
# initialized; `wsl -d <d>` fails with WSL_E_DISTRO_NOT_FOUND until first boot.
Write-Host ""
Write-Host "Waiting for $DistroName to be ready..."
$ready = $false
for ($i = 1; $i -le 30; $i++) {
    wsl -d $DistroName -u root -- /bin/true 2>$null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ready) {
    Write-Error "$DistroName did not become ready. Try: wsl -d $DistroName (to finish init), then re-run post-install.ps1"
    exit 1
}
Write-Host "$DistroName is ready."

# =============================================
# Step 1: Run bootstrap-wsl.sh inside WSL
# =============================================
Write-Host ""
Write-Host "Running bootstrap-wsl.sh inside WSL..."
Write-Host "  (installs packages, creates user '$DefaultUser' @ UID 1000, systemd, rootfs-ro)"

wsl -d $DistroName -u root -- bash "$wslRoot/bootstrap-wsl.sh" --noninteractive --envfile "$envUnc" --passfile "$passUnc" --user $DefaultUser --name $DistroName
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: bootstrap-wsl.sh returned $LASTEXITCODE - check output above"
}

# Restrict the password file to the current user (drvfs ignores chmod).
if (Test-Path $passFile) {
    icacls $passFile /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
    Write-Host "  Password for '$DefaultUser' saved to $passFile"
}

# =============================================
# Step 2: Restart WSL to apply wsl.conf
# =============================================
Write-Host ""
Write-Host "Restarting WSL to apply wsl.conf..."
wsl --terminate $DistroName 2>$null
Start-Sleep -Seconds 2

# =============================================
# Step 3: Setup data disks (A1: data + docker). This creates the volumes,
# seeds /var + /home onto the data volume, and leaves the next
# boot to the systemd .mount units.
# =============================================
if (-not $SkipDisks) {
    Write-Host ""
    Write-Host "Setting up data disks (A1: data + docker)..."
    if ($NoConfirm) {
        & "$PSScriptRoot\setup-disks.ps1" -DistroName $DistroName -DiskDir $DiskDir -EnvFile $EnvFile -NoConfirm
    } else {
        & "$PSScriptRoot\setup-disks.ps1" -DistroName $DistroName -DiskDir $DiskDir -EnvFile $EnvFile
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: setup-disks.ps1 returned errors - check output above"
    }
} else {
    Write-Host "Skipping disk setup (-SkipDisks)"
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
Write-Host " On next Windows boot, the autostart task attaches the vhdx and the"
Write-Host " systemd .mount units mount /var, /home, /var/lib/docker."
Write-Host "========================================"
