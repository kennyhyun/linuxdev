# Install WSL2 distro from GitHub Releases (kennyhyun/linuxdev)
# Usage: .\scripts\wsl\install-distro-github.ps1 [-DistroName Linuxdev]

param(
    [string]$DistroName = $script:DefaultDistroName,
    [string]$DistroDir  = $script:DefaultDistroDir
)

. "$PSScriptRoot\..\common\wsl-utils.ps1"

if (Test-WslDistroExists $DistroName) {
    Write-Host "$DistroName already installed."
    exit 0
}

New-Item -ItemType Directory -Force -Path $DistroDir | Out-Null

# Fetch latest release
Write-Host "Fetching latest release from $script:GithubRepo ..."
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$script:GithubRepo/releases/latest" -UseBasicParsing
} catch {
    Write-Error "Could not fetch release: $_"; exit 1
}
Write-Host "Latest release: $($release.tag_name)"

# Find x64 tar assets (tar or tar.gz)
$tarAssets = $release.assets | Where-Object { $_.name -match "x64.*\.(tar|tar\.gz|7z)" }
if (-not $tarAssets) {
    Write-Host "No x64 release found. Available:"
    $release.assets | ForEach-Object { Write-Host "  $($_.name)" }
    Write-Error "No x64 distro release available yet."
    exit 1
}

# Download
foreach ($asset in $tarAssets) {
    $outFile = "$DistroDir\$($asset.name)"
    if (Test-Path $outFile) {
        Write-Host "  $($asset.name) already exists, skipping"
    } else {
        $sizeMB = [math]::Round($asset.size / 1MB, 1)
        Write-Host "  Downloading $($asset.name) ($sizeMB MB)..."
        Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $outFile
    }
}

# Extract if 7z
$firstVol = Get-ChildItem $DistroDir -Filter "*.7z.001" | Select-Object -First 1
if ($firstVol) {
    Write-Host "Extracting $($firstVol.Name)..."
    & 7z x $firstVol.FullName "-o$DistroDir" -y
    if ($LASTEXITCODE -ne 0) { Write-Error "Extraction failed"; exit 1 }
}

# Import
$tarFile = Get-ChildItem $DistroDir -Filter "*.tar*" | Where-Object { $_.Extension -ne ".7z" } | Select-Object -First 1
if (-not $tarFile) { Write-Error "No tar file found in $DistroDir"; exit 1 }

Write-Host "Importing $DistroName from $($tarFile.Name)..."
wsl --import $DistroName $DistroDir $tarFile.FullName
if ($LASTEXITCODE -ne 0) { Write-Error "wsl --import failed"; exit 1 }

Install-BootstrapMessage $DistroName
