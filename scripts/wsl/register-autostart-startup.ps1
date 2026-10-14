<#
.SYNOPSIS
    Keep a WSL2 distro alive at logon WITHOUT admin rights, via the Startup folder.

.DESCRIPTION
    Alternative to register-autostart.ps1 (which uses Task Scheduler + admin).
    This writes a hidden VBS launcher and drops it in the per-user Startup
    folder, so it runs at logon with no admin and no console window.

    Why VBS: WSL keeps a distro alive only while a session with an ACTIVE
    console handle exists. `WshShell.Run(cmd, 0, False)` hides the window but
    keeps the handle (unlike Start-Process -Hidden, which drops it and the
    distro dies). The launched `sleep infinity` session persists, so systemd
    services (gitlab-runner, sshd, docker) stay up.

.PARAMETER DistroName
    WSL distro name (e.g. "Debian"). Required.

.PARAMETER Remove
    Remove the Startup entry and the VBS launcher.

.EXAMPLE
    .\register-autostart-startup.ps1 -DistroName Debian
.EXAMPLE
    .\register-autostart-startup.ps1 -DistroName Debian -Remove
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DistroName,

    [switch]$Remove
)
$ErrorActionPreference = "Stop"

$startupDir = [System.Environment]::GetFolderPath("Startup")
$vbsPath    = Join-Path $startupDir "linuxdev-wsl-keepalive.vbs"

if ($Remove) {
    if (Test-Path $vbsPath) { Remove-Item $vbsPath -Force; Write-Host "Removed $vbsPath." }
    else { Write-Host "No keep-alive VBS in Startup." }
    return
}

# Verify the distro exists (wsl --list is UTF-16; normalise)
$distros = (wsl.exe --list --quiet) -replace "`0", "" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($distros -notcontains $DistroName) {
    Write-Warning "Distro '$DistroName' not found in: $($distros -join ', ')"
    Write-Warning "Writing the launcher anyway (no-op until the distro exists)."
}

# NOTE: pass "sleep infinity" directly (no 'sh -c') to avoid nested quotes
# inside the VBS string.
$wslCmd = "wsl.exe -d $DistroName -u root -- sleep infinity"
$vbs = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "$wslCmd", 0, False
"@
Set-Content -Path $vbsPath -Value $vbs -Encoding ASCII

Write-Host "================================================"
Write-Host " WSL keep-alive installed in Startup (no admin)."
Write-Host "   file:  $vbsPath"
Write-Host "   runs:  $wslCmd  (hidden, at logon)"
Write-Host ""
Write-Host " Test now:  wscript.exe `"$vbsPath`" ; Start-Sleep 10 ; wsl -l --running"
Write-Host " Verify:    wsl -d $DistroName -- systemctl is-active gitlab-runner"
Write-Host " Remove:    .\scripts\wsl\register-autostart-startup.ps1 -DistroName $DistroName -Remove"
Write-Host "================================================"
