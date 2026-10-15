# setup-disks.ps1 -- set up the A1 WSL2 data layout (data + docker volumes).
#
# Layout (2 volumes; /home/linuxbrew lives inside the data volume):
#   data.vhdx   -> /mnt/data  (bind /mnt/data/var -> /var, /mnt/data/home -> /home)
#   docker.vhdx -> /var/lib/docker
#
# Behaviour:
#   - If data.vhdx already exists:
#       * interactive -> ask: use existing / overwrite / abort
#       * -NoConfirm  -> ERROR and stop (never silently overwrite data)
#   - Otherwise: create data.vhdx + docker.vhdx (max = *_SIZE_GB), attach, then
#     run setup-disks.sh which formats the volumes,
#     and ALWAYS seeds the current rootfs /var + /home into the data volume
#     (rsync) before emptying the rootfs dirs.
#
# Sizes come from .env (DATA_SIZE_GB / DOCKER_SIZE_GB = vhdx size, default 64).
# Disk types come from .env, per disk (default: docker=fixed, data=expandable):
#   DOCKER_VHDX_TYPE / DATA_VHDX_TYPE  (fixed | expandable)
#   VHDX_TYPE                          (optional: applies to any disk without its own key)
#   fixed       -- full size is allocated on disk up front. Creation takes a
#                  while (zero-fill) but avoids runtime growth stalls /
#                  fragmentation and guarantees the space.
#   expandable  -- dynamic; starts small and grows as data is written
#                  ("dynamic" is accepted as an alias).
#
# Usage (Admin PowerShell):
#   .\scripts\wsl\setup-disks.ps1 -DistroName Debian
#   .\scripts\wsl\setup-disks.ps1 -DistroName Debian -NoConfirm
#   .\scripts\wsl\setup-disks.ps1 -DistroName Debian -Force    # overwrite existing

param(
    [string]$DistroName = "Debian",
    [string]$DiskDir    = "$env:USERPROFILE\linuxdev\disks",
    [string]$EnvFile    = "$env:USERPROFILE\linuxdev\.env",
    [switch]$Force,
    [switch]$NoConfirm,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# --- admin check ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Run as Administrator"
    exit 1
}

# --- read a size from .env, default fallback ---
function Get-EnvSizeGB {
    param([string]$Key, [int]$Default)
    if (Test-Path $EnvFile) {
        foreach ($line in Get-Content $EnvFile) {
            if ($line -match "^\s*$Key\s*=\s*(\d+)\s*$") { return [int]$matches[1] }
        }
    }
    return $Default
}

$DataSizeGB   = Get-EnvSizeGB "DATA_SIZE_GB"   64
$DockerSizeGB = Get-EnvSizeGB "DOCKER_SIZE_GB" 64

# --- read a vhdx type from .env: fixed | expandable ---
# Precedence: <Key> (DATA_VHDX_TYPE / DOCKER_VHDX_TYPE) > VHDX_TYPE > $Default
function Get-EnvRaw {
    param([string]$Key)
    $val = ""
    if (Test-Path $EnvFile) {
        foreach ($line in Get-Content $EnvFile) {
            if ($line -match "^\s*$Key\s*=\s*([A-Za-z]*)\s*(#.*)?$") { $val = $matches[1].ToLower() }
        }
    }
    return $val
}
function Get-EnvVhdxType {
    param([string]$Key, [string]$Default)
    $val = Get-EnvRaw $Key
    if (-not $val) { $val = Get-EnvRaw "VHDX_TYPE" }
    if (-not $val) { $val = $Default }
    switch ($val) {
        "fixed"      { return "fixed" }
        "expandable" { return "expandable" }
        "dynamic"    { return "expandable" }
        default      { Write-Error "Invalid vhdx type '$val' for $Key/VHDX_TYPE in $EnvFile (use fixed or expandable)"; exit 1 }
    }
}
# Defaults: docker.vhdx fixed (heavy writes, big), data.vhdx expandable (/var, /home)
$DataType   = Get-EnvVhdxType "DATA_VHDX_TYPE"   "expandable"
$DockerType = Get-EnvVhdxType "DOCKER_VHDX_TYPE" "fixed"

$dataVhdx   = Join-Path $DiskDir "data.vhdx"
$dockerVhdx = Join-Path $DiskDir "docker.vhdx"

New-Item -ItemType Directory -Force -Path $DiskDir | Out-Null

Write-Host "========================================"
Write-Host " Linuxdev WSL2 disk setup (A1: data + docker)"
Write-Host " Distro : $DistroName"
Write-Host " DiskDir: $DiskDir"
Write-Host " data   : ${DataSizeGB}G ($DataType)"
Write-Host " docker : ${DockerSizeGB}G ($DockerType)"
if ($WhatIf) { Write-Host " MODE   : DRY RUN (no changes)" }
Write-Host "========================================"

# =====================================================================
# Existence guard: never silently clobber existing data volumes.
# =====================================================================
if (Test-Path $dataVhdx) {
    if ($Force) {
        Write-Host "-Force: discarding existing data.vhdx / docker.vhdx"
    } elseif ($NoConfirm) {
        Write-Error "data.vhdx already exists ($dataVhdx) and -NoConfirm was given. Refusing to overwrite. Re-run with -Force to overwrite, or remove the file manually."
        exit 1
    } else {
        Write-Host ""
        Write-Host "data.vhdx already exists: $dataVhdx"
        Write-Host "  [U] Use existing disks as-is (do nothing)"
        Write-Host "  [O] Overwrite (DELETE and recreate -- data on these volumes is lost)"
        Write-Host "  [A] Abort"
        $ans = Read-Host "Choose U/O/A"
        switch ($ans.ToUpper()) {
            "U" { Write-Host "Using existing disks. Nothing to do."; return }
            "O" { $Force = $true }
            default { Write-Host "Aborted."; return }
        }
    }

    if ($Force -and -not $WhatIf) {
        wsl --terminate $DistroName 2>$null
        Start-Sleep -Seconds 2
        foreach ($v in @($dataVhdx, $dockerVhdx)) {
            if (Test-Path $v) {
                wsl --unmount $v 2>$null | Out-Null
                Remove-Item -LiteralPath $v -Force
                Write-Host "   removed: $v"
            }
        }
    }
}

function Invoke-Step {
    param([string]$Desc, [scriptblock]$Action)
    Write-Host ""
    Write-Host ">> $Desc"
    if ($WhatIf) { Write-Host "   (dry run - skipped)"; return }
    & $Action
}

# --- diskpart helper to create an empty vhdx (-Type: fixed | expandable) ---
function New-EmptyVhdx {
    param([string]$Path, [int]$SizeGB, [string]$Type)
    $sizeMB = [long]$SizeGB * 1024
    $script = "create vdisk file=`"$Path`" maximum=$sizeMB type=$Type"
    $tmp = "$env:TEMP\linuxdev-disk-create.txt"
    $script | Set-Content $tmp -Encoding ASCII
    diskpart /s $tmp | Out-Null
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $Path)) { Write-Error "diskpart failed to create $Path" }
}

# --- fixed disks allocate everything up front: make sure there is room ---
$needGB = 0
if ($DataType   -eq "fixed") { $needGB += $DataSizeGB }
if ($DockerType -eq "fixed") { $needGB += $DockerSizeGB }
if ($needGB -gt 0 -and -not $WhatIf) {
    $driveName = (Split-Path -Qualifier (Resolve-Path $DiskDir).Path).TrimEnd(':')
    $freeGB    = [math]::Floor((Get-PSDrive -Name $driveName).Free / 1GB)
    if ($freeGB -lt $needGB) {
        Write-Error "Not enough free space on ${driveName}: for fixed disks (need ${needGB}G, free ${freeGB}G). Lower the *_SIZE_GB or use expandable (DATA_VHDX_TYPE / DOCKER_VHDX_TYPE / VHDX_TYPE) in $EnvFile."
        exit 1
    }
    Write-Host "Fixed disks: allocating ${needGB}G up front (free on ${driveName}: ${freeGB}G). This can take several minutes."
}

# =====================================================================
# Step 1: terminate the distro for a clean start
# =====================================================================
Invoke-Step "Terminating $DistroName" {
    wsl --terminate $DistroName 2>$null
    Start-Sleep -Seconds 2
}

# =====================================================================
# Step 2: create empty data/docker vhdx (max cap)
# =====================================================================
Invoke-Step "Creating data.vhdx [${DataSizeGB}G, $DataType]" {
    New-EmptyVhdx -Path $dataVhdx -SizeGB $DataSizeGB -Type $DataType
    Write-Host "   created: $dataVhdx"
}
Invoke-Step "Creating docker.vhdx [${DockerSizeGB}G, $DockerType]" {
    New-EmptyVhdx -Path $dockerVhdx -SizeGB $DockerSizeGB -Type $DockerType
    Write-Host "   created: $dockerVhdx"
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "Dry run complete. Re-run without -WhatIf to apply."
    return
}

# =====================================================================
# Step 3: boot a temp session, attach the new disks, run setup-disks.sh
# =====================================================================
Write-Host ""
Write-Host ">> Formatting + seeding inside $DistroName ..."

$job = Start-Job { wsl -d $args[0] -u root -- sleep 600 } -ArgumentList $DistroName
Start-Sleep -Seconds 3

foreach ($v in @($dataVhdx, $dockerVhdx)) {
    if (Test-Path $v) { wsl --mount --vhd $v --bare 2>&1 | Out-Null; Start-Sleep -Milliseconds 500 }
}

$wslRepo = (wsl -d $DistroName -u root -- bash -c "echo /mnt/c/Users/$env:USERNAME/linuxdev" 2>$null).Trim()
$logStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$winLogDir = Join-Path $env:USERPROFILE "linuxdev\logs"
New-Item -ItemType Directory -Force -Path $winLogDir | Out-Null
$wslLogFile = "$wslRepo/logs/setup-disks-$logStamp.log"
Write-Host "   log: $winLogDir\setup-disks-$logStamp.log"
wsl -d $DistroName -u root -- bash "$wslRepo/scripts/wsl/setup-disks.sh" `
    --data-label linuxdev-data `
    --docker-label linuxdev-docker `
    --log-file $wslLogFile
$rc = $LASTEXITCODE

Stop-Job $job -ErrorAction SilentlyContinue
Remove-Job $job -ErrorAction SilentlyContinue

if ($rc -ne 0) {
    Write-Error "In-distro setup (setup-disks.sh) failed with code $rc. Review output above."
    exit 1
}

# =====================================================================
# Step 4: terminate so the next boot uses the new .mount units
# =====================================================================
wsl --terminate $DistroName 2>$null

Write-Host ""
Write-Host "========================================"
Write-Host " Disk setup complete."
Write-Host ""
Write-Host " Next:"
Write-Host "   1. Ensure bootstrap-wsl.sh installed the .mount units and"
Write-Host "      register-autostart.ps1 attaches the vhdx at logon."
Write-Host "   2. Reboot Windows (or run the autostart task) and verify:"
Write-Host "        wsl -d $DistroName -u root -- findmnt /var /home /var/lib/docker"
Write-Host "      Each should be on a separate device, not the rootfs."
Write-Host "========================================"
