# Install WSL2 distro from GitHub Releases (kennyhyun/linuxdev), then run post-install
# Usage: .\scripts\wsl\install-distro-github.ps1 [-DistroName Linuxdev] [-DefaultUser linuxdev]

param(
    [string]$DistroName  = "Linuxdev",
    [string]$DistroDir   = "$env:USERPROFILE\linuxdev\distro",
    [string]$DefaultUser = "linuxdev",
    [switch]$SkipPostInstall
)

. "$PSScriptRoot\..\common\wsl-utils.ps1"

if (-not (Test-WslDistroExists $DistroName)) {
    New-Item -ItemType Directory -Force -Path $DistroDir | Out-Null

    Write-Host "Fetching latest release from $script:GithubRepo ..."
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$script:GithubRepo/releases/latest" -UseBasicParsing
    } catch { Write-Error "Could not fetch release: $_"; exit 1 }
    Write-Host "Latest release: $($release.tag_name)"

    $tarAssets = $release.assets | Where-Object { $_.name -match "x64.*\.(tar|tar\.gz|7z)" }
    if (-not $tarAssets) {
        Write-Host "No x64 release found. Available:"
        $release.assets | ForEach-Object { Write-Host "  $($_.name)" }
        Write-Error "No x64 distro release available."; exit 1
    }

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

    $firstVol = Get-ChildItem $DistroDir -Filter "*.7z.001" | Select-Object -First 1
    if ($firstVol) {
        Write-Host "Extracting $($firstVol.Name)..."
        & 7z x $firstVol.FullName "-o$DistroDir" -y
        if ($LASTEXITCODE -ne 0) { Write-Error "Extraction failed"; exit 1 }
    }

    $tarFile = Get-ChildItem $DistroDir -Include "*.tar","*.tar.gz" -Recurse | Select-Object -First 1
    if (-not $tarFile) { Write-Error "No tar file found in $DistroDir"; exit 1 }

    Write-Host "Importing $DistroName..."
    wsl --import $DistroName $DistroDir $tarFile.FullName
    if ($LASTEXITCODE -ne 0) { Write-Error "wsl --import failed"; exit 1 }
    Write-Host "$DistroName installed."
} else {
    Write-Host "$DistroName already installed."
}

if (-not $SkipPostInstall) {
    & "$PSScriptRoot\post-install.ps1" -DistroName $DistroName -DefaultUser $DefaultUser
}
