<#
.SYNOPSIS
    Register this WSL2 distro as a GitLab Runner, reading the token from .env.

.DESCRIPTION
    Reads RUNNER_TOKEN (and optional RUNNER_* overrides) from .env and runs
    scripts/wsl/install-runner.sh inside the WSL distro as root. Keeps the token
    out of the command line / shell history.

    .env keys:
      RUNNER_TOKEN      (required) GitLab runner token. GitLab 16+ uses a
                        runner authentication token (starts with 'glrt-').
      RUNNER_URL        (optional) default https://gitlab.imaginetoolbox.com
      RUNNER_TAGS       (optional) default linux,localstack,runner
      RUNNER_NAME       (optional) default wsl2-<COMPUTERNAME>
      WSL_USERNAME      (optional) service user (fallbacks to distro default)

.PARAMETER DistroName
    WSL distro to register in. Default: Linuxdev.

.PARAMETER NoAutostart
    Do not pass --autostart to install-runner.sh.

.EXAMPLE
    .\register-runner.ps1
.EXAMPLE
    .\register-runner.ps1 -DistroName Debian
#>
param(
    [string]$DistroName = "",
    [ValidateSet("", "shell", "docker")]   # "" = unspecified (fall back to .env / install-runner default)
    [string]$Executor = "",
    [string]$DockerImage = "",
    [switch]$Privileged,
    [switch]$NoAutostart
)
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$envFile  = Join-Path $repoRoot ".env"

if (-not (Test-Path $envFile)) {
    Write-Error "No .env found at $envFile. Add RUNNER_TOKEN=... first."
    exit 1
}

# --- read .env ---
$envVars = @{}
foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
        $envVars[$matches[1]] = $matches[2].Trim()
    }
}

$token = $envVars.RUNNER_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Error "RUNNER_TOKEN is not set in $envFile."
    exit 1
}

$url   = if ($envVars.RUNNER_URL)  { $envVars.RUNNER_URL }  else { "https://gitlab.imaginetoolbox.com" }
$tags  = if ($envVars.RUNNER_TAGS) { $envVars.RUNNER_TAGS } else { "linux,localstack,runner" }
$name  = if ($envVars.RUNNER_NAME) { $envVars.RUNNER_NAME } else { "wsl2-$env:COMPUTERNAME" }
$user  = $envVars.WSL_USERNAME
# executor: -Executor param > .env RUNNER_EXECUTOR > install-runner default (shell)
$executor = if ($Executor) { $Executor } elseif ($envVars.RUNNER_EXECUTOR) { $envVars.RUNNER_EXECUTOR } else { "" }
$dockerImage = if ($DockerImage) { $DockerImage } elseif ($envVars.RUNNER_DOCKER_IMAGE) { $envVars.RUNNER_DOCKER_IMAGE } else { "" }

# --- verify distro is running/available ---
$distros = (wsl --list --quiet 2>$null) -replace "`0","" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if (-not $DistroName) {
    if ($distros.Count -eq 1) {
        $DistroName = $distros[0]
        Write-Host "Auto-detected distro: $DistroName"
    } elseif ($distros.Count -eq 0) {
        Write-Error "No WSL distro installed. Install one first, or pass -DistroName."
        exit 1
    } else {
        Write-Error "Multiple distros installed ($($distros -join ', ')). Pass -DistroName <name>."
        exit 1
    }
} elseif ($distros -notcontains $DistroName) {
    Write-Error "Distro '$DistroName' not found. Installed: $($distros -join ', ')"
    exit 1
}

# --- build the WSL path to install-runner.sh ---
function ConvertTo-WslPath($winPath) {
    if ($winPath -match '^([A-Za-z]):\\(.*)$') { return "/mnt/$($matches[1].ToLower())/$($matches[2] -replace '\\','/')" }
    return ($winPath -replace '\\','/')
}
$scriptUnc = ConvertTo-WslPath (Join-Path $repoRoot "scripts\wsl\install-runner.sh")

# --- assemble args (token passed as argument to the in-WSL script, not echoed here) ---
$argList = @("--url", $url, "--token", $token, "--tags", $tags, "--name", $name)
if ($user)             { $argList += @("--user", $user) }
if ($executor)         { $argList += @("--executor", $executor) }
if ($dockerImage)      { $argList += @("--docker-image", $dockerImage) }
if ($Privileged)       { $argList += "--privileged" }
if (-not $NoAutostart) { $argList += "--autostart" }

Write-Host "Registering runner in '$DistroName'..."
Write-Host "  url:  $url"
Write-Host "  tags: $tags"
Write-Host "  name: $name"
if ($executor) { Write-Host "  executor: $executor$(if($dockerImage){" (image: $dockerImage)"})" }
Write-Host "  token: (hidden)"

wsl -d $DistroName -u root -- bash $scriptUnc @argList
$code = $LASTEXITCODE

Write-Host ""
if ($code -eq 0) {
    Write-Host "================================================"
    Write-Host " Runner registered. Verify:"
    Write-Host "   wsl -d $DistroName -- gitlab-runner list"
    Write-Host "   wsl -d $DistroName -- sudo systemctl status gitlab-runner"
    Write-Host "================================================"
} else {
    Write-Error "install-runner.sh exited with code $code (see output above)."
    exit $code
}
