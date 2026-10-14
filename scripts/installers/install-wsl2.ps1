# Enable WSL2 Windows features and install required tools (7-Zip, GitHub CLI)
# Distro installation is handled separately:
#   .\scripts\wsl\install-distro-store.ps1    (Microsoft Store)
#   .\scripts\wsl\install-distro-github.ps1   (GitHub Releases)
#   .\scripts\wsl\install-distro-local.ps1    (local file, offline)
#
# Usage: called from setup.ps1 -wsl

param(
    [switch]$importDistro,
    [switch]$noConfirm,
    [string]$localImage,
    [string]$envFile = "$PSScriptRoot\..\..\.env"
)

. "$PSScriptRoot\..\common\installer-utils.ps1"
. "$PSScriptRoot\..\common\wsl-utils.ps1"

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

# Only these two are required for WSL2. HypervisorPlatform is optional: it is
# enabled if possible, but its state never forces a reboot (on some machines it
# cannot be enabled at all, which used to make every run demand a reboot).
$requiredFeatures = @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")

$rebootNeeded = $false      # a REQUIRED feature is not active yet
$optionalPending = @()
foreach ($feature in $features) {
    $required = $requiredFeatures -contains $feature
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue).State
    if ($state -eq "Enabled") {
        Write-Host "  $feature already enabled"
        continue
    }
    if ($state -ne "EnablePending") {
        Write-Host "  Enabling $feature ..."
        Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart -ErrorAction SilentlyContinue | Out-Null
        # Re-read the real state instead of assuming.
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction SilentlyContinue).State
    }
    Write-Host "  $feature state: $state"
    if ($state -ne "Enabled") {
        if ($required) { $rebootNeeded = $true } else { $optionalPending += "$feature($state)" }
    }
}

try { wsl --set-default-version 2 2>$null; Write-Host "  WSL default version: 2" } catch {}

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
    } catch {
        $url = "https://7-zip.org/a/7z2408-x64.exe"
        $installer = "$env:TEMP\7zip-installer.exe"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $installer
        Start-Process -FilePath $installer -ArgumentList "/S" -Wait
        Refresh-Path
    }
    Write-Host "7-Zip installed"
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
    } catch {
        $OsArchBit = (Get-WMIObject Win32_Processor).AddressWidth
        $pattern = if ($OsArchBit -eq 32) { "*windows_386.msi" } else { "*windows_amd64.msi" }
        $ghAsset = get_github_release_url -url "https://api.github.com/repos/cli/cli/releases/latest" -pattern $pattern
        $ghInstaller = download_from_installer_url -url $ghAsset.url -filename $ghAsset.name
        Start-Process msiexec -ArgumentList "/i `"$ghInstaller`" /quiet /norestart" -Wait
        Refresh-Path
    }
    Write-Host "GitHub CLI installed"
}
# =============================================
# Reboot gate -- must pass before any distro work
# =============================================
# WSL features only take effect after a reboot. 'wsl --status' is NOT reliable:
# before a reboot it still exits 0 and prints "Default Version", while telling
# you to enable the optional component. The decision below uses the required
# feature states, the (NUL-stripped) wsl --status text, and an actual distro
# launch -- see the comment on the signals.

# Decision signals (all printed so a wrong decision can be diagnosed):
#   requiredPending : a required feature is not in state "Enabled" (authoritative
#                     for "needs reboot"; Windows reports EnablePending until reboot)
#   statusSaysEnable: wsl --status asks to enable the component. Its output is
#                     UTF-16, so NUL chars are stripped before matching.
#   distroLaunch    : an installed distro actually starts -> WSL is definitely
#                     active, which overrides everything else. $null = no distro.
# Generic Windows pending-reboot flags are ignored on purpose (other installers
# set them all the time).
$statusText = ""
try { $statusText = (wsl.exe --status 2>&1 | Out-String) -replace "`0", "" } catch {}
$statusSaysEnable = $statusText -match 'enable the|optional component|not supported with your current'

$distroLaunch = $null
$installedDistros = @()
try {
    $installedDistros = @((wsl.exe --list --quiet 2>$null) -replace "`0", "" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} catch {}
if ($installedDistros.Count -gt 0) {
    try { wsl.exe -d $installedDistros[0] -- /bin/true 2>$null; $distroLaunch = ($LASTEXITCODE -eq 0) } catch { $distroLaunch = $false }
}

$launchText = if ($null -eq $distroLaunch) { "n/a(no distro)" } else { "$distroLaunch" }
Write-Host "  reboot check: requiredPending=$rebootNeeded statusSaysEnable=$statusSaysEnable distroLaunch=$launchText optionalPending=[$($optionalPending -join ',')]"

$needReboot = $false
if ($distroLaunch -ne $true) {
    $needReboot = $rebootNeeded -or $statusSaysEnable
}

if ($needReboot) {
    Write-Host ""
    Write-Host "================================================"
    Write-Host " REBOOT REQUIRED"
    Write-Host " WSL2 features were enabled but are not active until you reboot."
    Write-Host ""
    Write-Host " 1. Reboot Windows."
    Write-Host " 2. Re-run:  .\setup.ps1 -wsl"
    Write-Host "================================================"
    if (-not $noConfirm) {
        $ans = Read-Host "Reboot now? [y/N]"
        if ($ans -match '^[Yy]') { Restart-Computer -Force }
    }
    # Do NOT continue to distro install -- WSL is not usable yet.
    exit 2
}
if ($optionalPending.Count -gt 0) {
    Write-Host "  NOTE: optional feature(s) not active: $($optionalPending -join ', ') (not required for WSL2)"
}
Write-Host "WSL is operational."

# =============================================
# Distro install
# =============================================
if ($importDistro -or $localImage -or (-not $noConfirm)) {
    Write-Host ""
    Write-Host "Install WSL2 distro?"
    Write-Host "  [1] Skip"
    Write-Host "  [2] Microsoft Store (Debian)"
    Write-Host "  [3] GitHub Releases (linuxdev custom)"
    Write-Host "  [4] Local file (offline)"
    # Non-interactive selection: -importdistro -> GitHub custom; -localImage -> local;
    # otherwise (plain -noConfirm) default to Store (Debian). Interactive: ask.
    $choice = if ($importDistro) { "3" }
              elseif ($localImage) { "4" }
              elseif ($noConfirm) { "2" }
              else { Read-Host "Enter choice [1]" }

    switch ($choice.Trim()) {
        "2" { & "$PSScriptRoot\..\wsl\install-distro-store.ps1"  -EnvFile $envFile; $installed = $true; $installedDistro = "Debian" }
        "3" { & "$PSScriptRoot\..\wsl\install-distro-github.ps1" -EnvFile $envFile; $installed = $true; $installedDistro = "Linuxdev" }
        "4" {
            $img = if ($localImage) { $localImage } else { Read-Host "Path to .tar or .tar.gz" }
            & "$PSScriptRoot\..\wsl\install-distro-local.ps1" -ImagePath $img -EnvFile $envFile
            $installed = $true; $installedDistro = "Linuxdev"
        }
        default { Write-Host "Skipped. Run install-distro-*.ps1 later." }
    }
    # NOTE: each install-distro-*.ps1 runs post-install.ps1, which waits for the
    # distro to be ready and then runs bootstrap-wsl.sh (--noninteractive --envfile).
    # Do not call bootstrap here -- that caused a double-run with the wrong distro name.

    # --- Expose WSL docker to Windows (only when a docker runtime was set up) ---
    if ($installed) {
        $runtime = "docker"
        if (Test-Path $envFile) {
            foreach ($line in Get-Content $envFile) {
                if ($line -match '^\s*WSL_CONTAINER_RUNTIME\s*=\s*(.+?)\s*$') { $runtime = $matches[1].Trim() }
            }
        }
        if ($runtime -eq "docker" -or $runtime -eq "both") {
            $distro = if ($installedDistro) { $installedDistro } else { $script:DefaultDistroName }
            Write-Host ""
            Write-Host "----- Docker: exposing WSL daemon to Windows -----"
            # Convert repo path to WSL mount path
            $repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
            $repoUnc  = if ($repoRoot -match '^([A-Za-z]):\\(.*)$') { "/mnt/$($matches[1].ToLower())/$($matches[2] -replace '\\','/')" } else { $repoRoot -replace '\\','/' }
            # 1) Ensure systemd/docker are live, then open localhost TCP inside WSL
            wsl --terminate $distro 2>$null
            Start-Sleep -Seconds 2
            wsl -d $distro -u root -- bash "$repoUnc/scripts/wsl/enable-docker-tcp.sh"
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "enable-docker-tcp.sh failed; skipping Windows docker CLI setup."
            } else {
                # 2) Install Windows docker CLI if missing + set DOCKER_HOST
                & "$PSScriptRoot\..\wsl\setup-docker-host.ps1"
            }
        }
    }
}

# =============================================
# Optional: GitLab Runner (CI) -- guidance only
# =============================================
# The runner is NOT installed here. It is an optional add-on for turning this
# machine into a CI runner host. The install lives inside the distro (bash) and
# the auto-start is a Windows scheduled task -- both are run on demand.
Write-Host ""
Write-Host "----- Optional: GitLab Runner (CI) -----"
Write-Host "To turn this WSL2 machine into a GitLab CI runner, do this AFTER the"
Write-Host "distro is installed and bootstrapped (docker is set up):"
Write-Host ""
Write-Host "  1) Put the runner token in .env (keeps it out of the command line):"
Write-Host "       RUNNER_TOKEN=glrt-xxxxxxxx          # required (GitLab 16+ token)"
Write-Host "       RUNNER_URL=https://gitlab.imaginetoolbox.com   # optional"
Write-Host "       RUNNER_TAGS=linux,localstack,runner            # optional"
Write-Host "       RUNNER_EXECUTOR=docker                         # optional (shell|docker)"
Write-Host "       RUNNER_DOCKER_IMAGE=whitech/lambda:build-22.11 # optional"
Write-Host ""
Write-Host "  2) Register the runner (reads .env, runs install-runner.sh in WSL):"
$distroHint = if ($installedDistro) { $installedDistro } else { "<DistroName>" }
Write-Host "       .\scripts\wsl\register-runner.ps1 -DistroName $distroHint"
Write-Host ""
Write-Host "  3) Auto-start the distro at Windows logon (admin PowerShell):"
Write-Host "       .\scripts\wsl\register-autostart.ps1 -DistroName $distroHint"
Write-Host ""
Write-Host "  Skip all of this if you only need a local dev environment."
Write-Host "----------------------------------------"
