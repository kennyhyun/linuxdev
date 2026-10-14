#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Register a Windows Task Scheduler job that wakes the WSL2 distro at logon/boot,
    so the GitLab Runner inside it comes online automatically.

.DESCRIPTION
    WSL2 shuts a distro down when it has no running sessions. The runner's
    systemd service (installed by install-runner.sh) only starts once the distro
    is running. This task starts the distro at user logon (and optionally system
    startup), which triggers systemd, which starts the runner.

    The task runs:  wsl.exe -d <DistroName> -- /bin/true
    which boots the distro (firing wsl.conf [boot] + systemd) without opening a shell.

.PARAMETER DistroName
    Name of the WSL distro to wake (e.g. "Linuxdev"). Required.

.PARAMETER TaskName
    Scheduler task name. Default: "LinuxdevWSLRunnerAutostart".

.PARAMETER AtStartup
    Also trigger at system startup (runs as SYSTEM, before any user logs on).
    Useful for an always-on runner host. Requires the distro to be usable
    without a logged-in user.

.PARAMETER Remove
    Remove the scheduled task instead of creating it.

.EXAMPLE
    .\register-autostart.ps1 -DistroName Linuxdev

.EXAMPLE
    .\register-autostart.ps1 -DistroName Linuxdev -AtStartup

.EXAMPLE
    .\register-autostart.ps1 -DistroName Linuxdev -Remove
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DistroName,

    [string]$TaskName = "LinuxdevWSLRunnerAutostart",

    [switch]$AtStartup,

    [int]$DelaySeconds = 30,

    [switch]$Remove
)

$ErrorActionPreference = "Stop"

if ($Remove) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed scheduled task '$TaskName'."
    } else {
        Write-Host "No scheduled task named '$TaskName' found."
    }
    return
}

# Verify the distro exists (wsl --list is UTF-16; normalise)
$distros = (wsl.exe --list --quiet) -replace "`0", "" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($distros -notcontains $DistroName) {
    Write-Warning "Distro '$DistroName' not found in: $($distros -join ', ')"
    Write-Warning "Register anyway (it will no-op until the distro exists)."
}

# The action: boot the distro quietly. /bin/true returns immediately but the
# distro stays up (systemd keeps running) and the runner service starts.
$wslPath = "$env:SystemRoot\System32\wsl.exe"
$action = New-ScheduledTaskAction -Execute $wslPath `
    -Argument "-d $DistroName -- /bin/true"

$triggers = @()
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn
$startupTrigger = $null
if ($AtStartup) { $startupTrigger = New-ScheduledTaskTrigger -AtStartup }

# Right after a COLD boot, WSL/vmms and the vhdx mounts are not ready yet, so a
# trigger that fires too early wakes the distro but it fails to stabilise
# (reported success, but STATE=Stopped). A short delay lets WSL warm up.
# (Verified: manual/warm starts work immediately; only boot-time is affected.)
if ($DelaySeconds -gt 0) {
    $iso = "PT${DelaySeconds}S"
    $logonTrigger.Delay = $iso
    $triggers += $logonTrigger
    if ($startupTrigger) { $startupTrigger.Delay = $iso; $triggers += $startupTrigger }
} else {
    $triggers += $logonTrigger
    if ($startupTrigger) { $triggers += $startupTrigger }
}

# WSL distros are registered PER-USER, so the task MUST run as the interactive
# user -- SYSTEM cannot see or start the distro. (Running as SYSTEM fails with
# LastTaskResult=0xFFFFFFFF and the distro stays Stopped.)
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal -UserId $currentUser `
    -LogonType Interactive -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host "Task '$TaskName' already exists - updating it."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask -TaskName $TaskName `
    -Action $action `
    -Trigger $triggers `
    -Principal $principal `
    -Settings $settings `
    -Description "Wake WSL distro '$DistroName' at logon so the GitLab Runner service starts." | Out-Null

$triggerLabel = "logon"
if ($AtStartup) { $triggerLabel = "logon + startup" }

Write-Host "================================================"
Write-Host " Registered scheduled task '$TaskName'"
Write-Host "   action:   wsl.exe -d $DistroName -- /bin/true"
Write-Host "   runs as:  $currentUser (interactive)"
Write-Host "   triggers: $triggerLabel"
if ($AtStartup) {
    Write-Host ""
    Write-Host " NOTE: WSL needs a user context, so this task runs as $currentUser."
    Write-Host "       The 'startup' trigger only fires once that user is logged on."
    Write-Host "       For a headless runner host, enable Windows auto-logon."
}
Write-Host ""
Write-Host " Test now:  Start-ScheduledTask -TaskName $TaskName"
Write-Host " Verify:    wsl.exe -d $DistroName -- gitlab-runner status"
Write-Host " Remove:    .\scripts\wsl\register-autostart.ps1 -DistroName $DistroName -Remove"
Write-Host "================================================"
