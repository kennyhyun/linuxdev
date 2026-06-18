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
#   home.vhdx   → /home             label: linuxdev-home
#   docker.vhdx → /var/lib/docker   label: linuxdev-docker
#   brew.vhdx   → /home/linuxbrew   label: linuxdev-brew

param(
    [string]$DistroName   = "Linuxdev",
    [string]$DiskDir      = "$env:USERPROFILE\linuxdev\disks",
    [int]$HomeSizeGB      = 20,
    [int]$DockerSizeGB    = 50,
    [int]$BrewSizeGB      = 10,
    [switch]$SkipBrew,
    [switch]$AttachOnly   # Attach and mount existing disks without formatting
)

$ErrorActionPreference = "Stop"

# Check admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run as Administrator"
    exit 1
}

# Check WSL distro exists
$distros = wsl --list --quiet 2>$null
if (-not ($distros | Where-Object { $_ -match "^$DistroName" })) {
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
    if (Test-Path $Path) {
        Write-Host "  $([System.IO.Path]::GetFileName($Path)) already exists — skipping create"
    } else {
        Write-Host "  Creating $([System.IO.Path]::GetFileName($Path)) ($($SizeGB)GB dynamic)..."
        New-VHD -Path $Path -SizeBytes ([long]$SizeGB * 1GB) -Dynamic | Out-Null
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
    Write-Host "--- $vhdxName → $MountPoint ---"

    # Attach VHD to WSL
    Write-Host "  Attaching $vhdxName to WSL..."
    wsl --mount --vhd $VhdxPath --bare
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to attach $VhdxPath"
        return
    }
    Start-Sleep -Milliseconds 500

    # Find the new /dev/sdX device inside WSL
    $devPath = wsl -d $DistroName -- bash -c "
        lsblk -rno NAME,SIZE | while read name size; do
            dev=\"/dev/\$name\"
            label=\$(blkid -o value -s LABEL \"\$dev\" 2>/dev/null || true)
            if [ -z \"\$label\" ] && [ ! -b \"\${dev}1\" ] && lsblk -no TYPE \"\$dev\" 2>/dev/null | grep -q disk; then
                # No partition table, no label = freshly attached
                echo \"\$dev\"
                break
            fi
        done
    " 2>$null

    if (-not $devPath) {
        # Try finding by label if already formatted
        $devPath = wsl -d $DistroName -- bash -c "blkid -L '$Label' 2>/dev/null || true" 2>$null
    }

    if (-not $devPath) {
        Write-Host "  WARNING: Could not find device for $vhdxName — attach manually"
        return
    }

    $devPath = $devPath.Trim()
    Write-Host "  Device: $devPath"

    # Format if requested (first time)
    if ($Format) {
        Write-Host "  Formatting $devPath as ext4 with label '$Label'..."
        wsl -d $DistroName -u root -- bash -c "mkfs.ext4 -L '$Label' -F '$devPath'"
        Write-Host "  Formatted: $devPath"
    }

    # Create mount point and mount
    wsl -d $DistroName -u root -- bash -c "mkdir -p '$MountPoint' && mount '$devPath' '$MountPoint'"
    Write-Host "  Mounted: $devPath → $MountPoint"
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

Write-Host "========================================"
Write-Host " Linuxdev WSL2 Disk Setup"
Write-Host " Distro : $DistroName"
Write-Host " DiskDir: $DiskDir"
Write-Host " Mode   : $(if ($AttachOnly) { 'attach only' } else { 'create + format + mount' })"
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
# Terminate distro, setup disks, restart
# =============================================
Write-Host ""
Write-Host "Terminating $DistroName for clean disk attach..."
wsl --terminate $DistroName 2>$null
Start-Sleep -Seconds 2

Write-Host "Starting $DistroName..."
# Start distro in background
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

# =============================================
# Update wsl-boot.sh awareness
# =============================================
Write-Host ""
Write-Host "Verifying mount-disks.sh knows the labels..."
wsl -d $DistroName -u root -- bash -c "
    if command -v blkid >/dev/null; then
        echo 'Disk labels found:'
        blkid -o list 2>/dev/null | grep linuxdev || echo '  (none yet — reboot may be needed)'
    fi
"

Write-Host ""
Write-Host "========================================"
Write-Host " Disk setup complete."
Write-Host ""
Write-Host " Disks will auto-mount on boot via wsl-boot.sh + mount-disks.sh"
Write-Host " (wsl --mount is needed from PowerShell before WSL starts)"
Write-Host ""
Write-Host " To attach on Windows startup, add to Task Scheduler or startup script:"
foreach ($disk in $disks) {
    Write-Host "   wsl --mount --vhd `"$DiskDir\$($disk.File)`" --bare"
}
Write-Host ""
Write-Host " Or run manually before starting WSL:"
Write-Host "   .\scripts\wsl\attach-disks.ps1"
Write-Host "========================================"
