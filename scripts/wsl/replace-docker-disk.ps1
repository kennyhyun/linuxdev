#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Replace docker.vhdx with a new, empty FIXED-size disk (docker data is lost).

.DESCRIPTION
    Keeps the old disk as docker.vhdx.bak, creates a new fixed-size docker.vhdx,
    formats it as ext4 with the label "linuxdev-docker" (the label the
    var-lib-docker.mount unit looks for), then restarts via reboot.ps1.

    data.vhdx (/var, /home) is NOT touched.
    Docker images, containers and the build cache are discarded -- the first
    builds afterwards run cold and base images are pulled again.
    Any job running on this machine's GitLab runner is killed.

    Run as the SAME Windows user that installed the distro (admin PowerShell).
    The old disk is kept as .bak; delete it yourself once everything works.
    To roll back: Move-Item docker.vhdx.bak docker.vhdx, then run reboot.ps1.

.PARAMETER DistroName
    WSL distro name. Required.

.PARAMETER SizeGB
    New disk size in GB (fixed, allocated up front). Default: 120.

.PARAMETER DiskDir
    Folder containing docker.vhdx. Default: %USERPROFILE%\.linuxdev\<DistroName>\disks

.PARAMETER TaskName
    Keep-alive scheduled task. Default: LinuxdevWSLKeepAlive-<DistroName>.

.EXAMPLE
    .\scripts\wsl\replace-docker-disk.ps1 -DistroName Debian
.EXAMPLE
    .\scripts\wsl\replace-docker-disk.ps1 -DistroName Debian -SizeGB 150
#>
param(
    [Parameter(Mandatory = $true)][string]$DistroName,
    [int]$SizeGB      = 120,
    [string]$DiskDir  = "",   # default: %USERPROFILE%\.linuxdev\<DistroName>\disks
    [string]$TaskName = ""   # default: LinuxdevWSLKeepAlive-<DistroName>
)
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\common\wsl-utils.ps1"
if (-not $DiskDir) { $DiskDir = Get-LinuxdevDir $DistroName "disks" }
if (-not $TaskName) { $TaskName = "LinuxdevWSLKeepAlive-$DistroName" }

$docker = Join-Path $DiskDir "docker.vhdx"
$bak    = "$docker.bak"
if (-not (Test-Path $docker)) { throw "docker.vhdx not found: $docker" }
if (Test-Path $bak)           { throw "$bak already exists. Remove or rename it first." }

# fixed disk allocates everything up front
$drive = (Split-Path -Qualifier $DiskDir).TrimEnd(':')
$free  = [math]::Floor((Get-PSDrive $drive).Free / 1GB)
if ($free -lt $SizeGB) { throw "Need ${SizeGB}G free on ${drive}:, have ${free}G" }

# 1) stop services gracefully, stop the keep-alive task, stop the distro
Write-Host ">> Stopping services, task and distro"
wsl -d $DistroName -u root -- systemctl stop gitlab-runner docker docker.socket 2>$null
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
wsl --terminate $DistroName 2>$null
Start-Sleep -Seconds 3
wsl --unmount $docker 2>$null | Out-Null

# 2) keep the old disk as .bak, create the new fixed disk
Write-Host ">> Creating new fixed docker.vhdx [${SizeGB}G] (old disk kept as $bak)"
Move-Item $docker $bak
$tmp = Join-Path $env:TEMP "replace-docker-disk.txt"
"create vdisk file=`"$docker`" maximum=$($SizeGB * 1024) type=fixed" | Set-Content $tmp -Encoding ASCII
diskpart /s $tmp | Out-Null
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
if (-not (Test-Path $docker)) {
    Move-Item $bak $docker
    throw "diskpart failed; the old disk was restored."
}

# 3) attach the new disk inside a live session and format it with the label
Write-Host ">> Formatting the new disk (label: linuxdev-docker)"
$job = Start-Job { wsl -d $args[0] -u root -- sleep 600 } -ArgumentList $DistroName
try {
    Start-Sleep -Seconds 3
    $before = @(wsl -d $DistroName -u root -- bash -c "lsblk -dnro NAME")
    wsl --mount --vhd $docker --bare | Out-Null
    Start-Sleep -Seconds 2
    $after  = @(wsl -d $DistroName -u root -- bash -c "lsblk -dnro NAME")
    $new    = @($after | Where-Object { $before -notcontains $_ })
    if ($new.Count -ne 1) { throw "Expected exactly 1 new block device, found: $($new -join ',')" }
    $dev  = "/dev/$($new[0])"
    $type = (wsl -d $DistroName -u root -- bash -c "blkid -o value -s TYPE $dev") -join ""
    if ($type) { throw "$dev already has a filesystem ($type); refusing to format." }
    wsl -d $DistroName -u root -- mkfs.ext4 -q -L linuxdev-docker -F $dev
    if ($LASTEXITCODE -ne 0) { throw "mkfs.ext4 failed" }
    Write-Host "   formatted $dev as ext4 [linuxdev-docker]"
} finally {
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -ErrorAction SilentlyContinue
    wsl --unmount $docker 2>$null | Out-Null
}

# 4) restart through the normal path (re-attaches disks, mounts by label)
Write-Host ">> Restarting via reboot.ps1"
& "$PSScriptRoot\reboot.ps1" -DistroName $DistroName -TaskName $TaskName -DiskDir $DiskDir
wsl -d $DistroName -u root -- bash -c "df -h /var/lib/docker; systemctl is-active docker gitlab-runner"
Write-Host ""
Write-Host "If everything works, delete the old disk: Remove-Item `"$bak`""
