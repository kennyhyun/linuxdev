# Setup additional WSL2 data disks (home, docker, brew)
# Creates vhdx files, attaches to WSL2, formats, and labels them.
#
# Usage (Admin PowerShell):
#   .\scripts\wsl\setup-disks.ps1
#   .\scripts\wsl\setup-disks.ps1 -DistroName Linuxdev -HomeSizeGB 30 -DockerSizeGB 60
#   .\scripts\wsl\setup-disks.ps1 -SkipBrew        # no brew disk
#   .\scripts\wsl\setup-disks.ps1 -AttachOnly      # attach existing vhdx (no format)
#
# Disk layout:
#   home.vhdx   -> /home             label: linuxdev-home
#   docker.vhdx -> /var/lib/docker   label: linuxdev-docker
#   brew.vhdx   -> /home/linuxbrew   label: linuxdev-brew

param(
    [string]$DistroName   = "Linuxdev",
    [string]$DiskDir      = "$env:USERPROFILE\linuxdev\disks",
    [int]$HomeSizeGB      = 20,
    [int]$DockerSizeGB    = 50,
    [int]$BrewSizeGB      = 10,
    [switch]$SkipBrew,
    [switch]$AttachOnly
)

$ErrorActionPreference = "Stop"

# Check admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run as Administrator"
    exit 1
}

# Check WSL distro exists
$distros = (wsl --list --quiet 2>$null) -replace "`0", "" | Where-Object { $_ -ne "" }
if (-not ($distros | Where-Object { $_.Trim() -eq $DistroName })) {
    Write-Host "Available distros:"
    $distros | ForEach-Object { Write-Host "  '$_'" }
    Write-Error "Distro '$DistroName' not found. Run: wsl --list"
    exit 1
}

New-Item -ItemType Directory -Force -Path $DiskDir | Out-Null

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

# Helper: create vhdx if not exists
function Ensure-Vhdx {
    param([string]$Path, [int]$SizeGB, [string]$Label)
    $fileName = [System.IO.Path]::GetFileName($Path)
    if (Test-Path $Path) {
        Write-Host "  $fileName already exists - skipping create"
    } else {
        $sizeBytes = [long]$SizeGB * 1GB
        $sizeInfo = $SizeGB.ToString() + "GB dynamic"
        Write-Host "  Creating $fileName [$sizeInfo]..."
        New-VHD -Path $Path -SizeBytes $sizeBytes -Dynamic | Out-Null
        Write-Host "  Created: $Path"
    }
}

# Helper: attach vhdx to WSL, format if needed, mount to path
function Setup-WslDisk {
    param(
        [string]$VhdxPath,
        [string]$MountPoint,
        [string]$Label,
        [bool]$Format
    )

    $vhdxName = [System.IO.Path]::GetFileName($VhdxPath)
    Write-Host ""
    Write-Host "--- $vhdxName -> $MountPoint ---"

    # Attach VHD to WSL
    Write-Host "  Attaching $vhdxName to WSL..."
    wsl --mount --vhd $VhdxPath --bare
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to attach $VhdxPath"
        return
    }
    Start-Sleep -Milliseconds 500

    # Find the new /dev/sdX device inside WSL (freshly attached = no label yet)
    $devPath = wsl -d $DistroName -- bash -c @'
        lsblk -rno NAME,SIZE | while read name size; do
            dev="/dev/$name"
            label=$(blkid -o value -s LABEL "$dev" 2>/dev/null || true)
            if [ -z "$label" ] && [ ! -b "${dev}1" ] && lsblk -no TYPE "$dev" 2>/dev/null | grep -q disk; then
                echo "$dev"
                break
            fi
        done
'@ 2>$null

    if (-not $devPath) {
        # Already formatted - find by label
        $devPath = wsl -d $DistroName -- bash -c "blkid -L '$Label' 2>/dev/null || true" 2>$null
    }

    if (-not $devPath) {
        Write-Host "  WARNING: Could not find device for $vhdxName - attach manually"
        return
    }

    $devPath = $devPath.Trim()
    Write-Host "  Device: $devPath"

    # Format if requested (first time setup)
    if ($Format) {
        Write-Host "  Formatting $devPath as ext4 [label: $Label]..."
        wsl -d $DistroName -u root -- bash -c "mkfs.ext4 -L '$Label' -F '$devPath'"
        Write-Host "  Formatted: $devPath"
    }

    # Mount
    wsl -d $DistroName -u root -- bash -c "mkdir -p '$MountPoint' && mount '$devPath' '$MountPoint'"
    Write-Host "  Mounted: $devPath -> $MountPoint"
    Write-Host "  Done: $vhdxName"
}

# =============================================
# Disk definitions
# =============================================
$disks = @(
    @{ File = "home.vhdx";   SizeGB = $HomeSizeGB;   Mount = "/home";            Label = "linuxdev-home" },
    @{ File = "docker.vhdx"; SizeGB = $DockerSizeGB; Mount = "/var/lib/docker";  Label = "linuxdev-docker" }
)
if (-not $SkipBrew) {
    $disks += @{ File = "brew.vhdx"; SizeGB = $BrewSizeGB; Mount = "/home/linuxbrew"; Label = "linuxdev-brew" }
}

$modeStr = if ($AttachOnly) { "attach only" } else { "create + format + mount" }
Write-Host "========================================"
Write-Host " Linuxdev WSL2 Disk Setup"
Write-Host " Distro : $DistroName"
Write-Host " DiskDir: $DiskDir"
Write-Host " Mode   : $modeStr"
Write-Host "========================================"

# =============================================
# Create vhdx files
# =============================================
if (-not $AttachOnly) {
    Write-Host ""
    Write-Host "Creating vhdx files..."
    foreach ($disk in $disks) {
        Ensure-Vhdx -Path "$DiskDir\$($disk.File)" -SizeGB $disk.SizeGB -Label $disk.Label
    }
}

# =============================================
# Terminate distro, attach disks, restart
# =============================================
Write-Host ""
Write-Host "Terminating $DistroName for clean disk attach..."
wsl --terminate $DistroName 2>$null
Start-Sleep -Seconds 2

Write-Host "Starting $DistroName..."
$job = Start-Job { wsl -d $args[0] -- sleep 30 } -ArgumentList $DistroName
Start-Sleep -Seconds 3

foreach ($disk in $disks) {
    $vhdxPath = "$DiskDir\$($disk.File)"
    $shouldFormat = -not $AttachOnly
    Setup-WslDisk `
        -VhdxPath $vhdxPath `
        -MountPoint $disk.Mount `
        -Label $disk.Label `
        -Format $shouldFormat
}

Stop-Job $job -ErrorAction SilentlyContinue
Remove-Job $job -ErrorAction SilentlyContinue

# Verify
Write-Host ""
Write-Host "Verifying labels..."
wsl -d $DistroName -u root -- bash -c 'blkid -o list 2>/dev/null | grep linuxdev && echo OK || echo "(none yet)"'

Write-Host ""
Write-Host "========================================"
Write-Host " Disk setup complete."
Write-Host ""
Write-Host " Disks auto-mount on boot via wsl-boot.sh + mount-disks.sh"
Write-Host " NOTE: wsl --mount must run before WSL starts (see attach-disks.ps1)"
Write-Host ""
Write-Host " To attach on Windows startup:"
foreach ($disk in $disks) {
    $diskPath = "$DiskDir\$($disk.File)"
    Write-Host "   wsl --mount --vhd '$diskPath' --bare"
}
Write-Host ""
Write-Host " Or run: .\scripts\wsl\attach-disks.ps1"
Write-Host "========================================"
