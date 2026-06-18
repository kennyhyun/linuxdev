param(
    [switch]$importDistro,
    [switch]$noConfirm,
    [string]$localImage   # Path to local tar.gz/tar for offline install
)

. "$PSScriptRoot\..\common\installer-utils.ps1"

$DistroName = "Linuxdev"
$DistroDir  = "$env:USERPROFILE\linuxdev\distro"
$VhdxPath   = "$DistroDir\ext4.vhdx"
$GithubRepo = "kennyhyun/linuxdev"

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# =============================================
# Enable WSL2 Windows Features
# =============================================
Write-Host "---------------------------------------"
Write-Host "Enabling WSL2 Windows features..."

$features = @(
    "Microsoft-Windows-Subsystem-Linux",
    "VirtualMachinePlatform",
    "HypervisorPlatform"
)

$rebootNeeded = $false
foreach ($feature in $features) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue).State
    if ($state -eq "Enabled") {
        Write-Host "  $feature already enabled"
    } else {
        Write-Host "  Enabling $feature ..."
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction SilentlyContinue
        if ($result -and $result.RestartNeeded) { $rebootNeeded = $true }
    }
}

# Set WSL default version to 2
try {
    wsl --set-default-version 2 2>$null
    Write-Host "  WSL default version set to 2"
} catch {}

# =============================================
# Install 7-Zip
# =============================================
Write-Host "---------------------------------------"
Write-Host "Checking 7-Zip..."
if (Get-Command 7z -ErrorAction SilentlyContinue) {
    Write-Host "7-Zip already installed"
} else {
    Write-Host "Installing 7-Zip via winget..."
    try {
        winget install --id 7zip.7zip -e --silent --accept-package-agreements --accept-source-agreements
        Refresh-Path
        Write-Host "7-Zip installed"
    } catch {
        Write-Host "winget failed, trying direct download..."
        $sevenZipUrl = "https://7-zip.org/a/7z2408-x64.exe"
        $sevenZipInstaller = "$env:TEMP\7zip-installer.exe"
        Invoke-WebRequest -UseBasicParsing -Uri $sevenZipUrl -OutFile $sevenZipInstaller
        Start-Process -FilePath $sevenZipInstaller -ArgumentList "/S" -Wait
        Refresh-Path
        Write-Host "7-Zip installed"
    }
}

# =============================================
# Install GitHub CLI
# =============================================
Write-Host "---------------------------------------"
Write-Host "Checking GitHub CLI..."
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Host "GitHub CLI already installed: $(gh --version | Select-Object -First 1)"
} else {
    Write-Host "Installing GitHub CLI via winget..."
    try {
        winget install --id GitHub.cli -e --silent --accept-package-agreements --accept-source-agreements
        Refresh-Path
        Write-Host "GitHub CLI installed"
    } catch {
        Write-Host "winget failed, trying GitHub API..."
        $OsArchBit = (Get-WMIObject Win32_Processor).AddressWidth
        $pattern = if ($OsArchBit -eq 32) { "*windows_386.msi" } else { "*windows_amd64.msi" }
        $ghAsset = get_github_release_url `
            -url "https://api.github.com/repos/cli/cli/releases/latest" `
            -pattern $pattern
        $ghInstaller = download_from_installer_url -url $ghAsset.url -filename $ghAsset.name
        Start-Process msiexec -ArgumentList "/i `"$ghInstaller`" /quiet /norestart" -Wait
        Refresh-Path
        Write-Host "GitHub CLI installed"
    }
}

# =============================================
# Reboot notice
# =============================================
if ($rebootNeeded) {
    Write-Host ""
    Write-Host "NOTICE: A reboot is required to complete WSL2 feature activation."
    Write-Host "After rebooting, run: setup.ps1 -wsl"
    if (-not $noConfirm) {
        $ans = Read-Host "Reboot now? [y/N]"
        if ($ans -match '^[Yy]') {
            Restart-Computer -Force
        }
    }
    exit 0
}

# =============================================
# Import Linuxdev distro
# =============================================

# Check if already imported
$existingDistro = wsl --list --quiet 2>$null | Where-Object { $_ -match "^$DistroName" }
if ($existingDistro) {
    Write-Host ""
    Write-Host "$DistroName distro already installed."
    exit 0
}

if (-not $importDistro -and -not $noConfirm -and -not $localImage) {
    Write-Host ""
    Write-Host "Install Linuxdev WSL2 distro now?"
    Write-Host "  [1] Skip (install later)"
    Write-Host "  [2] Download from GitHub Releases (internet required, several GB)"
    Write-Host "  [3] Install from Microsoft Store Debian (internet required)"
    Write-Host "  [4] Use local image file (offline)"
    $choice = Read-Host "Enter choice [1]"
    switch ($choice.Trim()) {
        "2" { $importDistro = $true }
        "3" { $useStore = $true }
        "4" {
            $localImage = Read-Host "Path to .tar or .tar.gz file"
            if (-not (Test-Path $localImage)) {
                Write-Error "File not found: $localImage"
                exit 1
            }
        }
        default {
            Write-Host "Skipped. Run 'setup.ps1 -wsl -importdistro' later."
            exit 0
        }
    }
}

# Option 3: Microsoft Store install
if ($useStore) {
    Write-Host "Installing Debian from Microsoft Store..."
    wsl --install -d Debian
    Write-Host ""
    Write-Host "Debian installed. After setup, run bootstrap-wsl.sh inside WSL:"
    Write-Host "  bash /mnt/c/Users/$env:USERNAME/linuxdev/bootstrap-wsl.sh"
    exit 0
}

# Option 4: Local image
if ($localImage) {
    Write-Host "Installing from local image: $localImage"
    New-Item -ItemType Directory -Force -Path $DistroDir | Out-Null
    wsl --import $DistroName $DistroDir $localImage
    if ($LASTEXITCODE -ne 0) {
        Write-Error "wsl --import failed"
        exit 1
    }
    Write-Host ""
    Write-Host "Linuxdev distro installed from local image."
    Write-Host "Run: wsl -d $DistroName"
    exit 0
}

Write-Host "---------------------------------------"
Write-Host "Downloading Linuxdev distro from GitHub Releases..."
New-Item -ItemType Directory -Force -Path $DistroDir | Out-Null

# Use GitHub API directly — no auth needed for public repos
$apiUrl = "https://api.github.com/repos/$GithubRepo/releases/latest"
Write-Host "Fetching latest release info from $GithubRepo ..."
try {
    $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
} catch {
    Write-Error "Could not fetch release info: $_"
    exit 1
}
$tag = $release.tag_name
Write-Host "Latest release: $tag"

# Find x64 vhdx assets (prefer vhdx, fall back to any arch if no x64)
$assets = $release.assets
$vhdxAssets = $assets | Where-Object { $_.name -match "x64.*vhdx.*7z" }
if (-not $vhdxAssets) {
    # No x64 vhdx yet — inform user and exit gracefully
    Write-Host ""
    Write-Host "No x64 vhdx release found. Available assets:"
    $assets | ForEach-Object { Write-Host "  $($_.name)" }
    Write-Host ""
    Write-Host "The current release only has arm64 qcow2 images (for macOS QEMU)."
    Write-Host "An x64 vhdx release is needed for WSL2 import."
    Write-Host "Skipping distro install. Check back later for a new release."
    exit 0
}
$sha256Asset = $assets | Where-Object { $_.name -match "x64.*sha256" } | Select-Object -First 1

# Download split volumes
Write-Host "Downloading $($vhdxAssets.Count) archive volume(s)..."
foreach ($asset in $vhdxAssets) {
    $outFile = "$DistroDir\$($asset.name)"
    if (Test-Path $outFile) {
        Write-Host "  $($asset.name) already exists, skipping"
    } else {
        Write-Host "  Downloading $($asset.name) ($([math]::Round($asset.size/1MB, 1)) MB)..."
        Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $outFile
    }
}

# Download checksum
$sha256File = $null
if ($sha256Asset) {
    $sha256Path = "$DistroDir\$($sha256Asset.name)"
    Invoke-WebRequest -UseBasicParsing -Uri $sha256Asset.browser_download_url -OutFile $sha256Path
    $sha256File = Get-Item $sha256Path
}

$firstVol = Get-ChildItem $DistroDir -Filter "*x64*.vhdx.7z.001" | Sort-Object Name | Select-Object -First 1
if (-not $firstVol) {
    $firstVol = Get-ChildItem $DistroDir -Filter "*x64*.vhdx.7z" | Sort-Object Name | Select-Object -First 1
}
if (-not $firstVol) {
    Write-Error "No vhdx archive found in $DistroDir after download"
    exit 1
}

# Verify checksum
if ($sha256File) {
    Write-Host "Verifying checksum..."
    $expected = (Get-Content $sha256File.FullName |
                 Where-Object { $_ -match [regex]::Escape($firstVol.Name) } |
                 ForEach-Object { $_.Split()[0] })
    if ($expected) {
        $actual = (Get-FileHash $firstVol.FullName -Algorithm SHA256).Hash.ToLower()
        if ($actual -eq $expected.ToLower()) {
            Write-Host "Checksum OK"
        } else {
            Write-Error "Checksum mismatch on $($firstVol.Name). Download may be corrupted."
            exit 1
        }
    } else {
        Write-Host "Checksum entry not found for $($firstVol.Name), skipping verification"
    }
}

# Extract
Write-Host "Extracting $($firstVol.Name) ..."
& 7z x $firstVol.FullName "-o$DistroDir" -y
if ($LASTEXITCODE -ne 0) {
    Write-Error "Extraction failed"
    exit 1
}

# Find extracted vhdx
$vhdx = Get-ChildItem $DistroDir -Filter "*.vhdx" | Select-Object -First 1
if (-not $vhdx) {
    Write-Error "No .vhdx file found after extraction in $DistroDir"
    exit 1
}

# Move to standard path if needed
if ($vhdx.FullName -ne $VhdxPath) {
    Move-Item $vhdx.FullName $VhdxPath -Force
}

# Import
Write-Host "Importing $DistroName from $VhdxPath ..."
wsl --import-in-place $DistroName $VhdxPath
if ($LASTEXITCODE -ne 0) {
    Write-Error "wsl --import-in-place failed. Requires Windows 11 + WSL 0.67+"
    exit 1
}

Write-Host ""
Write-Host "Linuxdev WSL2 distro installed successfully."
Write-Host "Run: wsl -d $DistroName"
