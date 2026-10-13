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
$triggers += New-ScheduledTaskTrigger -AtLogOn
if ($AtStartup) {
    $triggers += New-ScheduledTaskTrigger -AtStartup
}

# Run with highest privileges. At logon use the interactive user; at startup
# fall back to SYSTEM so it fires before anyone logs in.
if ($AtStartup) {
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
        -LogonType ServiceAccount -RunLevel Highest
} else {
    $principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
        -LogonType Interactive -RunLevel Highest
}

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
if ($AtStartup) { $triggerLabel = "logon + startup (SYSTEM)" }

Write-Host "================================================"
Write-Host " Registered scheduled task '$TaskName'"
Write-Host "   action:   wsl.exe -d $DistroName -- /bin/true"
Write-Host "   triggers: $triggerLabel"
Write-Host ""
Write-Host " Test now:  Start-ScheduledTask -TaskName $TaskName"
Write-Host " Verify:    wsl.exe -d $DistroName -- gitlab-runner status"
Write-Host " Remove:    .\register-autostart.ps1 -DistroName $DistroName -Remove"
Write-Host "================================================"
