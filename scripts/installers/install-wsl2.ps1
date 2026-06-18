param(
    [switch]$importDistro,
    [switch]$noConfirm
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

if (-not $importDistro -and -not $noConfirm) {
    Write-Host ""
    Write-Host "Install Linuxdev WSL2 distro now?"
    Write-Host "  This downloads the vhdx image from GitHub Releases (several GB)."
    $answer = Read-Host "Continue? [y/N]"
    if ($answer -notmatch '^[Yy]') {
        Write-Host "Skipped. Run 'setup.ps1 -wsl -importdistro' later."
        exit 0
    }
}

Write-Host "---------------------------------------"
Write-Host "Downloading Linuxdev distro from GitHub Releases..."
New-Item -ItemType Directory -Force -Path $DistroDir | Out-Null

# Check gh auth
$ghAuth = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "GitHub CLI is not authenticated. Please login first:"
    Write-Host "  gh auth login"
    Write-Host "Then run: setup.ps1 -wsl -importdistro"
    exit 1
}

# Get latest release tag
$latestRelease = gh release list --repo $GithubRepo --limit 1 --json tagName |
                 ConvertFrom-Json
if (-not $latestRelease) {
    Write-Error "Could not fetch release info from $GithubRepo"
    exit 1
}
$tag = $latestRelease[0].tagName
Write-Host "Latest release: $tag"

# Download vhdx split volumes + checksum
Write-Host "Downloading assets..."
gh release download $tag `
    --repo $GithubRepo `
    --pattern "*x64*.vhdx.7z*" `
    --pattern "*x64*.sha256" `
    --dir $DistroDir

# Verify checksum (basic)
$sha256File = Get-ChildItem $DistroDir -Filter "*x64*.sha256" | Select-Object -First 1
$firstVol   = Get-ChildItem $DistroDir -Filter "*x64*.vhdx.7z.001" | Select-Object -First 1

if (-not $firstVol) {
    # Might be a single volume
    $firstVol = Get-ChildItem $DistroDir -Filter "*x64*.vhdx.7z" | Select-Object -First 1
}

if (-not $firstVol) {
    Write-Error "No vhdx archive found in $DistroDir"
    exit 1
}

if ($sha256File) {
    Write-Host "Verifying checksum..."
    Push-Location $DistroDir
    $expected = (Get-Content $sha256File.FullName | Where-Object { $_ -match $firstVol.Name } | ForEach-Object { $_.Split()[0] })
    if ($expected) {
        $actual = (Get-FileHash $firstVol.FullName -Algorithm SHA256).Hash.ToLower()
        if ($actual -eq $expected.ToLower()) {
            Write-Host "Checksum OK"
        } else {
            Write-Error "Checksum mismatch. Download may be corrupted."
            Pop-Location
            exit 1
        }
    }
    Pop-Location
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
