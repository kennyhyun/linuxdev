# migrate-disks.ps1 -- one-time migration to the A1 disk layout (rsync method).
#
# WHAT THIS DOES (run ONCE on a machine whose data still lives on the rootfs):
#   1. Terminates the distro for a clean start.
#   2. Creates THREE fresh empty vhdx: data.vhdx, docker.vhdx, brew.vhdx.
#   3. Boots a temp session, attaches them, and runs migrate-disks.sh which:
#        - formats data(linuxdev-data), docker(linuxdev-docker), brew(linuxdev-brew)
#        - stops docker, rsync's /var (minus /var/lib/docker) and /home onto the
#          data volume, then empties the rootfs /var and /home (keeps the dirs)
#        - discards docker data (fresh empty docker.vhdx)
#   4. Terminates so the next boot's .mount units take over.
#
# After this, systemd .mount units (installed by bootstrap-wsl.sh) mount:
#   data.vhdx   -> /mnt/data   (then bind /mnt/data/var -> /var, .../home -> /home)
#   docker.vhdx -> /var/lib/docker
#   brew.vhdx   -> /home/linuxbrew
#
# Sizes come from .env (DATA_SIZE_GB / DOCKER_SIZE_GB / BREW_SIZE_GB), default 64.
#
# Usage (Admin PowerShell):
#   .\scripts\wsl\migrate-disks.ps1 -DistroName Debian
#   .\scripts\wsl\migrate-disks.ps1 -DistroName Debian -WhatIf   # dry run

param(
    [string]$DistroName = "Debian",
    [string]$DiskDir    = "$env:USERPROFILE\linuxdev\disks",
    [string]$EnvFile    = "$env:USERPROFILE\linuxdev\.env",
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# --- admin check ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run as Administrator"
    exit 1
}

# --- read a size from .env, default 64 ---
function Get-EnvSizeGB {
    param([string]$Key, [int]$Default = 64)
    if (Test-Path $EnvFile) {
        foreach ($line in Get-Content $EnvFile) {
            if ($line -match "^\s*$Key\s*=\s*(\d+)\s*$") { return [int]$matches[1] }
        }
    }
    return $Default
}

$DataSizeGB   = Get-EnvSizeGB "DATA_SIZE_GB"   64
$DockerSizeGB = Get-EnvSizeGB "DOCKER_SIZE_GB" 64
$BrewSizeGB   = Get-EnvSizeGB "BREW_SIZE_GB"   64

$dataVhdx   = Join-Path $DiskDir "data.vhdx"
$dockerVhdx = Join-Path $DiskDir "docker.vhdx"
$brewVhdx   = Join-Path $DiskDir "brew.vhdx"

New-Item -ItemType Directory -Force -Path $DiskDir | Out-Null

Write-Host "========================================"
Write-Host " Linuxdev A1 disk migration (rsync)"
Write-Host " Distro : $DistroName"
Write-Host " DiskDir: $DiskDir"
Write-Host " Sizes  : data=${DataSizeGB}G docker=${DockerSizeGB}G brew=${BrewSizeGB}G"
if ($WhatIf) { Write-Host " MODE   : DRY RUN (no changes)" }
Write-Host "========================================"

if (Test-Path $dataVhdx) {
    Write-Error "data.vhdx already exists ($dataVhdx). Migration appears done. Aborting."
    exit 1
}

function Invoke-Step {
    param([string]$Desc, [scriptblock]$Action)
    Write-Host ""
    Write-Host ">> $Desc"
    if ($WhatIf) { Write-Host "   (dry run - skipped)"; return }
    & $Action
}

# --- diskpart helper to create an empty expandable vhdx ---
function New-EmptyVhdx {
    param([string]$Path, [int]$SizeGB)
    $sizeMB = [long]$SizeGB * 1024
    $script = "create vdisk file=`"$Path`" maximum=$sizeMB type=expandable"
    $tmp = "$env:TEMP\linuxdev-mig-create.txt"
    $script | Set-Content $tmp -Encoding ASCII
    diskpart /s $tmp | Out-Null
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $Path)) { Write-Error "diskpart failed to create $Path" }
}

# =====================================================================
# Step 1: terminate the distro for a clean start
# =====================================================================
Invoke-Step "Terminating $DistroName" {
    wsl --terminate $DistroName 2>$null
    Start-Sleep -Seconds 2
}

# =====================================================================
# Step 2: create empty data/docker/brew vhdx
# =====================================================================
Invoke-Step "Creating data.vhdx [${DataSizeGB}G]" {
    New-EmptyVhdx -Path $dataVhdx -SizeGB $DataSizeGB
    Write-Host "   created: $dataVhdx"
}
Invoke-Step "Creating docker.vhdx [${DockerSizeGB}G]" {
    New-EmptyVhdx -Path $dockerVhdx -SizeGB $DockerSizeGB
    Write-Host "   created: $dockerVhdx"
}
Invoke-Step "Creating brew.vhdx [${BrewSizeGB}G] (if missing)" {
    if (Test-Path $brewVhdx) { Write-Host "   exists, skipping" }
    else { New-EmptyVhdx -Path $brewVhdx -SizeGB $BrewSizeGB; Write-Host "   created: $brewVhdx" }
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "Dry run complete. Re-run without -WhatIf to apply."
    return
}

# =====================================================================
# Step 3: boot a temp session, attach the new disks, run migrate-disks.sh
# =====================================================================
Write-Host ""
Write-Host ">> Processing volumes inside $DistroName ..."

$job = Start-Job { wsl -d $args[0] -u root -- sleep 300 } -ArgumentList $DistroName
Start-Sleep -Seconds 3

foreach ($v in @($dataVhdx, $dockerVhdx, $brewVhdx)) {
    if (Test-Path $v) { wsl --mount --vhd $v --bare 2>&1 | Out-Null; Start-Sleep -Milliseconds 500 }
}

$wslRepo = (wsl -d $DistroName -u root -- bash -c "echo /mnt/c/Users/$env:USERNAME/linuxdev" 2>$null).Trim()
wsl -d $DistroName -u root -- bash "$wslRepo/scripts/wsl/migrate-disks.sh" `
    --data-label linuxdev-data `
    --docker-label linuxdev-docker `
    --brew-label linuxdev-brew
$rc = $LASTEXITCODE

Stop-Job $job -ErrorAction SilentlyContinue
Remove-Job $job -ErrorAction SilentlyContinue

if ($rc -ne 0) {
    Write-Error "In-distro migration (migrate-disks.sh) failed with code $rc. Review output above."
    exit 1
}

# =====================================================================
# Step 4: terminate so the next boot uses the new .mount units
# =====================================================================
wsl --terminate $DistroName 2>$null

Write-Host ""
Write-Host "========================================"
Write-Host " Migration complete."
Write-Host ""
Write-Host " Next:"
Write-Host "   1. Ensure bootstrap-wsl.sh has installed the .mount units and"
Write-Host "      register-autostart.ps1 attaches the vhdx at logon."
Write-Host "   2. Reboot Windows (or run the autostart task) and verify:"
Write-Host "        wsl -d $DistroName -u root -- findmnt /var /home /var/lib/docker"
Write-Host "      Each should be on a separate device, not /dev/sdd[...]."
Write-Host "========================================"
