# Generate/update %USERPROFILE%\.wslconfig [wsl2] section from .env values.
#
# Called by setup.ps1 (WSL2 branch). NOTE: .wslconfig is GLOBAL -- it affects
# ALL WSL2 distros for the current Windows user, not just Linuxdev.
#
# .env keys consumed:
#   MEMORY           -> [wsl2] memory=<MEMORY>MB
#   CPUS             -> [wsl2] processors=<CPUS>
#   WSL_SWAP         -> [wsl2] swap=<WSL_SWAP>MB   (0 = omit)
#   WSL_AUTO_RECLAIM -> [wsl2] autoMemoryReclaim=<value>   (gradual|dropcache|disabled)
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
if ($envVars.WSL_AUTO_RECLAIM) { $wsl2 += "autoMemoryReclaim=$($envVars.WSL_AUTO_RECLAIM)" }

$wslconfig = "$env:USERPROFILE\.wslconfig"

# --- preserve any non-[wsl2] sections already present ---
$kept = @()
if (Test-Path $wslconfig) {
    Copy-Item $wslconfig "$wslconfig.bak" -Force
    Write-Host "Backed up existing .wslconfig -> $wslconfig.bak"
    $inWsl2 = $false
    foreach ($line in Get-Content $wslconfig) {
        if ($line -match '^\s*\[wsl2\]\s*$')   { $inWsl2 = $true;  continue }
        elseif ($line -match '^\s*\[.+\]\s*$') { $inWsl2 = $false }
        if (-not $inWsl2) { $kept += $line }
    }
}

$out = $wsl2
if ($kept.Count -gt 0) { $out += ""; $out += $kept }

Set-Content -Path $wslconfig -Value $out -Encoding ASCII
Write-Host "Wrote $wslconfig :"
$wsl2 | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "NOTE: .wslconfig is GLOBAL (all WSL2 distros). Apply with: wsl --shutdown"
