#Requires -RunAsAdministrator
# One-click bootstrap for Linuxdev
# Usage (Admin PowerShell):
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   irm https://raw.githubusercontent.com/kennyhyun/linuxdev/feature/wsl2-custom-distro/install.ps1 | iex
$ErrorActionPreference = "Stop"

$RepoUrl   = "https://github.com/kennyhyun/linuxdev.git"
$Branch    = "feature/wsl2-custom-distro"
$InstallDir = "$env:USERPROFILE\linuxdev"

Write-Host "================================================"
Write-Host " Linuxdev Bootstrap"
Write-Host "================================================"

# Refresh PATH helper (needed after silent installs)
function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# --- Step 1: Install Git if not present ---
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing Git for Windows..."

    $OsArchBit = (Get-WMIObject Win32_Processor).AddressWidth
    $pattern   = if ($OsArchBit -eq 32) { "*32-bit.exe" } else { "*64-bit.exe" }

    # Fetch latest release asset URL from GitHub API
    $releaseApi = "https://api.github.com/repos/git-for-windows/git/releases/latest"
    $asset = Invoke-RestMethod -Uri $releaseApi |
             ForEach-Object assets |
             Where-Object name -like $pattern |
             Select-Object -First 1

    if (-not $asset) {
        Write-Error "Could not find Git installer for $OsArchBit-bit Windows"
        exit 1
    }

    $gitInstaller = "$env:TEMP\$($asset.name)"
    if (-not (Test-Path $gitInstaller)) {
        Write-Host "Downloading $($asset.name) ..."
        Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $gitInstaller
    }

    # Silent install — minimal options, adds git+bash to PATH
    $installArgs = "/SP- /SILENT /NOCANCEL /NORESTART /COMPONENTS=ext,ext\shellhere,gitlfs,assoc,assoc_sh /PathOption=Cmd /BashTerminalOption=ConHost /CRLFOption=LFOnly /DefaultBranchOption=main"
    Write-Host "Installing Git..."
    Start-Process -FilePath $gitInstaller -ArgumentList $installArgs -Wait
    Refresh-Path
    Write-Host "Git installed: $(git --version)"
} else {
    Write-Host "Git already installed: $(git --version)"
}

# --- Step 2: Clone or update repo ---
if (Test-Path "$InstallDir\.git") {
    Write-Host "Repo already exists at $InstallDir — pulling latest..."
    Push-Location $InstallDir
    git pull
    Pop-Location
} else {
    Write-Host "Cloning linuxdev to $InstallDir ..."
    git clone -b $Branch $RepoUrl $InstallDir
}

# --- Step 3: Run setup.ps1, forwarding any args ---
Write-Host ""
Write-Host "Running setup.ps1..."
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& "$InstallDir\setup.ps1" @args
