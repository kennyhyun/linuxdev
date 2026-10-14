#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Keep a WSL2 distro running in the background (no console window) at logon,
    so its systemd services (GitLab Runner, sshd, docker) stay available.

.DESCRIPTION
    WSL2 shuts a distro down shortly after the LAST session with an active
    console handle closes -- internal systemd daemons alone do NOT keep it up,
    and vmIdleTimeout/instanceIdleTimeout are ignored on some WSL builds.

    The reliable fix (per WSL issue #1511 and community guides) is to launch a
    PERSISTENT session (`sleep infinity`) that stays attached. A plain
    Start-Process -WindowStyle Hidden drops the console handle and the distro
    still dies; a VBS `WshShell.Run(cmd, 0, False)` hides the window but KEEPS
    the console handle, so the distro stays alive with no visible window.

    This script:
      1. Writes a VBS launcher (sleep infinity in the distro) to %LOCALAPPDATA%.
      2. Registers a logon scheduled task that runs it via wscript.exe.
    systemd (enabled in the distro) then auto-starts the runner/sshd/docker.

.PARAMETER DistroName
    WSL distro name (e.g. "Debian", "Linuxdev"). Required.

.PARAMETER TaskName
    Scheduled task name. Default: "LinuxdevWSLKeepAlive".

.PARAMETER Remove
    Remove the task and the VBS launcher.

.EXAMPLE
    .\register-autostart.ps1 -DistroName Debian
.EXAMPLE
    .\register-autostart.ps1 -DistroName Debian -Remove
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DistroName,

    [string]$TaskName = "LinuxdevWSLKeepAlive",

    [switch]$Remove
)

$ErrorActionPreference = "Stop"

$vbsPath = Join-Path $env:LOCALAPPDATA "linuxdev-wsl-keepalive.vbs"

if ($Remove) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed scheduled task '$TaskName'."
    } else {
        Write-Host "No scheduled task named '$TaskName' found."
    }
    if (Test-Path $vbsPath) { Remove-Item $vbsPath -Force; Write-Host "Removed $vbsPath." }
    return
}

# Verify the distro exists (wsl --list is UTF-16; normalise)
$distros = (wsl.exe --list --quiet) -replace "`0", "" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($distros -notcontains $DistroName) {
    Write-Warning "Distro '$DistroName' not found in: $($distros -join ', ')"
    Write-Warning "Registering anyway (no-op until the distro exists)."
}

# --- 1) Write the VBS keep-alive launcher ---
# Run(cmd, 0, False): 0 = hidden window (console handle kept alive, unlike
#   Start-Process -Hidden which drops it), False = don't wait.
# NOTE: pass "sleep infinity" directly (no 'sh -c') to avoid nested quotes
#   inside the VBS string, which caused "unexpected end of statement".
$wslCmd = "wsl.exe -d $DistroName -u root -- sleep infinity"
$vbs = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "$wslCmd", 0, False
"@
Set-Content -Path $vbsPath -Value $vbs -Encoding ASCII
Write-Host "Wrote keep-alive launcher: $vbsPath"

# --- 2) Register a logon scheduled task that runs the VBS via wscript ---
$action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$vbsPath`""
$trigger = New-ScheduledTaskTrigger -AtLogOn

# Per-user WSL -> run as the interactive user (NOT SYSTEM; SYSTEM cannot see the distro).
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0)   # 0 = no limit (persistent)

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "Task '$TaskName' already exists - updating it."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "Keep WSL distro '$DistroName' alive (hidden) so its services stay up." | Out-Null

Write-Host "================================================"
Write-Host " Registered scheduled task '$TaskName'"
Write-Host "   runs:     wscript.exe $vbsPath"
Write-Host "   which:    $wslCmd"
Write-Host "   runs as:  $currentUser (interactive, at logon)"
Write-Host ""
Write-Host " Test now:  Start-ScheduledTask -TaskName $TaskName"
Write-Host "            Start-Sleep 10; wsl -l --running"
Write-Host " Verify:    wsl -d $DistroName -- systemctl is-active gitlab-runner"
Write-Host " Remove:    .\scripts\wsl\register-autostart.ps1 -DistroName $DistroName -Remove"
Write-Host "================================================"
