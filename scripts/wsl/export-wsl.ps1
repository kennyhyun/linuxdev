# Export WSL distro as tar.gz for GitHub Release
# Usage (PowerShell, from linuxdev dir):
#   .\scripts\wsl\export-wsl.ps1
#   .\scripts\wsl\export-wsl.ps1 -DistroName Debian -Tag v0.0.3 -Upload
#
# Requires: 7-Zip, GitHub CLI (gh) authenticated for upload

param(
    [string]$DistroName = "Debian",
    [string]$Tag        = "v$(Get-Date -Format yyyyMMdd)",
    [string]$OutputDir  = "$PSScriptRoot\..\..\exports",
    [switch]$Upload
)

$ErrorActionPreference = "Stop"
$OutputDir = (Resolve-Path $OutputDir -ErrorAction SilentlyContinue) ??
             (New-Item -ItemType Directory -Force -Path $OutputDir).FullName
$Date      = Get-Date -Format "yyyyMMdd"
$Arch      = if ([System.Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
$BaseName  = "linuxdev-$Arch-$Date"
$TarPath   = "$OutputDir\$BaseName.tar"
$GzPath    = "$TarPath.gz"

Write-Host "========================================"
Write-Host " Linuxdev WSL Export"
Write-Host " Distro : $DistroName"
Write-Host " Output : $OutputDir\$BaseName.*"
Write-Host " Tag    : $Tag"
Write-Host "========================================"

# Confirm distro exists
$distros = wsl --list --quiet 2>$null
if (-not ($distros | Where-Object { $_ -match "^$DistroName" })) {
    Write-Error "Distro '$DistroName' not found. Run: wsl --list"
    exit 1
}

# Terminate distro before export (clean state)
Write-Host "Terminating $DistroName for clean export..."
wsl --terminate $DistroName 2>$null
Start-Sleep -Seconds 2

# Export to tar
Write-Host "Exporting $DistroName to $TarPath ..."
wsl --export $DistroName $TarPath
if ($LASTEXITCODE -ne 0) {
    Write-Error "wsl --export failed"
    exit 1
}

$tarSize = [math]::Round((Get-Item $TarPath).Length / 1GB, 2)
Write-Host "Exported: $tarSize GB"

# Compress with 7z (split into 256MB volumes)
if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
    Write-Error "7-Zip not found. Install with: winget install 7zip.7zip"
    exit 1
}

Write-Host "Compressing with 7-Zip (256MB splits)..."
$VolumeSize = "268435456"  # 256MB
Push-Location $OutputDir
7z a -t7z "-v${VolumeSize}b" -mx=9 "$BaseName.7z" "$BaseName.tar"
if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Error "7-Zip compression failed"
    exit 1
}
Pop-Location

# Verify archive
Write-Host "Verifying archive..."
7z t "$OutputDir\$BaseName.7z.001"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Archive verification failed"
    exit 1
}

# Remove uncompressed tar after successful compression
Remove-Item $TarPath -Force
Write-Host "Removed uncompressed tar"

# Generate checksums
Write-Host "Generating checksums..."
Push-Location $OutputDir
$sha256File = "$BaseName.sha256"
Get-ChildItem -Filter "$BaseName.7z.*" | ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    "$hash  $($_.Name)" | Add-Content $sha256File
}
Pop-Location

# Summary
Write-Host ""
Write-Host "========================================"
Write-Host " Export complete"
Get-ChildItem $OutputDir -Filter "$BaseName*" | ForEach-Object {
    $size = [math]::Round($_.Length / 1MB, 1)
    Write-Host "  $($_.Name)  ($size MB)"
}
Write-Host "========================================"

# Upload to GitHub Release
if ($Upload) {
    Write-Host ""
    Write-Host "Creating GitHub Release $Tag ..."

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI not found. Install with: winget install GitHub.cli"
        exit 1
    }

    $archiveFiles = Get-ChildItem $OutputDir -Filter "$BaseName.7z.*"
    $sha256 = "$OutputDir\$BaseName.sha256"

    $notes = "Linuxdev WSL2 x64 distro ($Date).`n`n" +
             "## Install`n" +
             "See README for setup instructions or run install.ps1`n`n" +
             "## Extract`n" +
             "``7z x $BaseName.7z.001``"

    gh release create $Tag @($archiveFiles.FullName) $sha256 `
        --repo "kennyhyun/linuxdev" `
        --title "Linuxdev $Tag (x64 WSL2)" `
        --notes $notes

    Write-Host "GitHub Release $Tag created."
    Write-Host "View: gh release view $Tag --web"
}
