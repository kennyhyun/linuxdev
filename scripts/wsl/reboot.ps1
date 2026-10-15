#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restart a WSL2 distro cleanly: stop the keep-alive task, terminate the
    distro, detach the data vhdx, then start the keep-alive task again (which
    re-attaches the vhdx, terminates once, and keeps the distro alive).

.DESCRIPTION
    Use this after `wsl --terminate`, after changing .wslconfig (-Shutdown), or
    whenever the distro died and the data volumes (/var, /home, /var/lib/docker)
    are not mounted.

    Must run as the SAME Windows user that installed the distro (WSL distros and
    the scheduled task are per-user). It cannot run as SYSTEM.

.PARAMETER DistroName
    WSL distro name. Auto-detected when exactly one distro is installed.

.PARAMETER TaskName
    Keep-alive scheduled task registered by register-autostart.ps1.
    Default: LinuxdevWSLKeepAlive.

.PARAMETER DiskDir
    Folder with data.vhdx / docker.vhdx. Default: %USERPROFILE%\linuxdev\disks

.PARAMETER Shutdown
    Use `wsl --shutdown` (stops the whole WSL2 VM, all distros) instead of
    terminating only this distro. Needed to apply .wslconfig changes.

.PARAMETER TimeoutSec
    How long to wait for the distro to come back. Default: 60.

.EXAMPLE
    .\scripts\wsl\reboot.ps1
.EXAMPLE
    .\scripts\wsl\reboot.ps1 -DistroName Debian -Shutdown
#>
param(
    [string]$DistroName = "",
    [string]$TaskName   = "LinuxdevWSLKeepAlive",
    [string]$DiskDir    = "$env:USERPROFILE\linuxdev\disks",
    [switch]$Shutdown,
    [int]$TimeoutSec    = 60
)

$ErrorActionPreference = "Stop"

# WSL refuses to run as SYSTEM, and a SYSTEM session would look at the wrong
# user's registry/profile anyway.
if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
    Write-Error "Running as SYSTEM is not supported by WSL. Run this as the user that owns the distro."
    exit 1
}

. "$PSScriptRoot\..\common\wsl-utils.ps1"

# --- resolve distro name ---
$distros = @(Get-WslDistros)
if (-not $DistroName) {
    if ($distros.Count -eq 1) {
        $DistroName = $distros[0]
        Write-Host "Auto-detected distro: $DistroName"
    } elseif ($distros.Count -eq 0) {
        Write-Error "No WSL distro installed."
        exit 1
    } else {
        Write-Error "Multiple distros installed ($($distros -join ', ')). Pass -DistroName <name>."
        exit 1
    }
} elseif ($distros -notcontains $DistroName) {
    Write-Error "Distro '$DistroName' not found (installed: $($distros -join ', '))."
    exit 1
}

# --- the keep-alive task must exist, otherwise nothing re-attaches the vhdx ---
if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
    Write-Error "Scheduled task '$TaskName' not found. Register it first: .\scripts\wsl\register-autostart.ps1 -DistroName $DistroName"
    exit 1
}

# --- 1) stop the keep-alive task (its 'sleep infinity' would hold the distro) ---
Write-Host ">> Stopping task '$TaskName'"
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

# --- 2) stop the distro / VM ---
if ($Shutdown) {
    Write-Host ">> wsl --shutdown"
    wsl --shutdown
} else {
    Write-Host ">> wsl --terminate $DistroName"
    wsl --terminate $DistroName 2>$null
}
Start-Sleep -Seconds 3

# --- 3) detach the data disks (ignore "not attached" errors) ---
foreach ($name in @("data.vhdx", "docker.vhdx")) {
    $path = Join-Path $DiskDir $name
    if (Test-Path $path) {
        Write-Host ">> wsl --unmount $path"
        wsl --unmount $path 2>$null | Out-Null
    }
}
Start-Sleep -Seconds 2

# --- 4) start the keep-alive task: attach vhdx -> terminate -> sleep infinity ---
Write-Host ">> Starting task '$TaskName'"
Start-ScheduledTask -TaskName $TaskName

# --- 5) wait for the distro to be running ---
function Test-DistroRunning {
    param([string]$Name)
    $prev = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [System.Text.Encoding]::Unicode } catch {}
    try { $raw = & wsl.exe --list --running --quiet 2>$null } finally {
        try { [Console]::OutputEncoding = $prev } catch {}
    }
    $lines = (($raw | Out-String) -replace "`0", "") -split "`r?`n" | ForEach-Object { $_.Trim() }
    return ($lines -contains $Name)
}

Write-Host ">> Waiting for '$DistroName' (up to ${TimeoutSec}s)"
$deadline = (Get-Date).AddSeconds($TimeoutSec)
$up = $false
while ((Get-Date) -lt $deadline) {
    if (Test-DistroRunning $DistroName) { $up = $true; break }
    Start-Sleep -Seconds 2
}

if (-not $up) {
    Write-Warning "'$DistroName' is not running after ${TimeoutSec}s."
    Write-Warning "Check: Get-ScheduledTaskInfo -TaskName $TaskName   (LastTaskResult)"
    exit 1
}

Write-Host ""
Write-Host "'$DistroName' is running. Mounts (data volumes should be separate devices):"
wsl -d $DistroName -u root -- findmnt /var /home /var/lib/docker
