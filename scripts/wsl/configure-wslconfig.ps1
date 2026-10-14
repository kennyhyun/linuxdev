# Generate/update %USERPROFILE%\.wslconfig from .env values.
#
# Called by setup.ps1 (WSL2 branch). NOTE: .wslconfig is GLOBAL -- it affects
# ALL WSL2 distros for the current Windows user, not just Linuxdev.
#
# .env keys consumed:
#   MEMORY           -> [wsl2]        memory=<MEMORY>MB
#   CPUS             -> [wsl2]        processors=<CPUS>
#   WSL_SWAP         -> [wsl2]        swap=<WSL_SWAP>MB   (0 = omit)
#   WSL_AUTO_RECLAIM -> [experimental] autoMemoryReclaim=<value>  (gradual|dropcache|disabled)
#
# IMPORTANT: autoMemoryReclaim lives under [experimental], NOT [wsl2].
# Putting it under [wsl2] makes WSL warn: Unknown key 'wsl2.autoMemoryReclaim'.
#
# Usage:
#   .\scripts\wsl\configure-wslconfig.ps1 [-EnvFile <path>]
param(
    [string]$EnvFile = "$PSScriptRoot\..\..\.env"
)
$ErrorActionPreference = "Stop"

# --- read .env (KEY=VALUE lines) ---
$envVars = @{}
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $envVars[$matches[1]] = $matches[2].Trim()
        }
    }
} else {
    Write-Host "No .env found at $EnvFile -- writing defaults."
}

# --- build [wsl2] section ---
$wsl2 = @("[wsl2]")
if ($envVars.MEMORY) { $wsl2 += "memory=$($envVars.MEMORY)MB" }
if ($envVars.CPUS)   { $wsl2 += "processors=$($envVars.CPUS)" }
if ($envVars.WSL_SWAP -and $envVars.WSL_SWAP -ne "0") { $wsl2 += "swap=$($envVars.WSL_SWAP)MB" }

# NOTE: keeping the distro alive is handled by scripts/wsl/register-autostart.ps1
# (a hidden VBS 'sleep infinity' session), NOT by vmIdleTimeout/instanceIdleTimeout.
# Those keys are ignored on several WSL builds (e.g. 3.0.3 warns "Unknown key"),
# so they are intentionally NOT written here.

# --- build [experimental] section ---
$experimental = @()
if ($envVars.WSL_AUTO_RECLAIM -and $envVars.WSL_AUTO_RECLAIM -ne "disabled") {
    $experimental += "autoMemoryReclaim=$($envVars.WSL_AUTO_RECLAIM)"
}

$wslconfig = "$env:USERPROFILE\.wslconfig"

# --- preserve sections we do NOT manage (keep everything except [wsl2] and
#     [experimental], which this script owns) ---
$kept = @()
if (Test-Path $wslconfig) {
    Copy-Item $wslconfig "$wslconfig.bak" -Force
    Write-Host "Backed up existing .wslconfig -> $wslconfig.bak"
    $skip = $false
    foreach ($line in Get-Content $wslconfig) {
        if ($line -match '^\s*\[(wsl2|experimental)\]\s*$') { $skip = $true;  continue }
        elseif ($line -match '^\s*\[.+\]\s*$')              { $skip = $false }
        if (-not $skip) { $kept += $line }
    }
}

# --- assemble ---
$out = @()
$out += $wsl2
if ($experimental.Count -gt 0) { $out += ""; $out += "[experimental]"; $out += $experimental }
# trim leading blank lines from kept, then append
$keptTrimmed = @($kept) | Where-Object { $_ -ne "" -or $true }  # keep as-is
if ($kept.Count -gt 0) { $out += ""; $out += $kept }

Set-Content -Path $wslconfig -Value $out -Encoding ASCII
Write-Host "Wrote $wslconfig :"
$wsl2         | ForEach-Object { Write-Host "  $_" }
if ($experimental.Count -gt 0) { Write-Host "  [experimental]"; $experimental | ForEach-Object { Write-Host "  $_" } }
Write-Host ""
Write-Host "NOTE: .wslconfig is GLOBAL (all WSL2 distros). Apply with: wsl --shutdown"
