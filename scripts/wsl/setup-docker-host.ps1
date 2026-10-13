<#
.SYNOPSIS
    Install the Docker CLI on Windows and point it at the WSL distro's Docker
    daemon over localhost (tcp://127.0.0.1:2375).

.DESCRIPTION
    Run `enable-docker-tcp.sh` inside WSL FIRST so the daemon listens on
    127.0.0.1:2375. This script then:
      - installs the docker CLI on Windows (winget: Docker.DockerCLI)
      - sets DOCKER_HOST=tcp://127.0.0.1:<port> as a user environment variable
      - verifies `docker version` reaches the WSL daemon

    No TLS: the port is localhost-only (WSL2 shares localhost with Windows and
    does not expose it to the network).

.PARAMETER Port
    TCP port the WSL dockerd listens on. Default 2375.

.PARAMETER Remove
    Remove the DOCKER_HOST user environment variable (does not uninstall CLI).

.EXAMPLE
    .\setup-docker-host.ps1
.EXAMPLE
    .\setup-docker-host.ps1 -Remove
#>
param(
    [int]$Port = 2375,
    [switch]$Remove
)
$ErrorActionPreference = "Stop"

$dockerHost = "tcp://127.0.0.1:$Port"

if ($Remove) {
    [System.Environment]::SetEnvironmentVariable("DOCKER_HOST", $null, "User")
    Write-Host "Removed DOCKER_HOST user environment variable."
    Write-Host "Open a new terminal for it to take effect."
    return
}

# --- Install docker CLI (client only; daemon lives in WSL) ---
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Host "docker CLI already installed: $((docker --version))"
} else {
    Write-Host "Installing Docker CLI via winget..."
    try {
        winget install --id Docker.DockerCLI -e --silent --accept-package-agreements --accept-source-agreements
    } catch {
        Write-Warning "winget install failed. Install the Docker CLI manually, then re-run."
    }
    # Refresh PATH for this session
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

# --- Set DOCKER_HOST (user scope, persists) ---
[System.Environment]::SetEnvironmentVariable("DOCKER_HOST", $dockerHost, "User")
$env:DOCKER_HOST = $dockerHost
Write-Host "DOCKER_HOST set to $dockerHost (user environment)."

# --- Verify ---
Write-Host ""
Write-Host "Verifying connection to the WSL Docker daemon..."
$ok = $false
if (Get-Command docker -ErrorAction SilentlyContinue) {
    try {
        docker version | Out-Null
        if ($LASTEXITCODE -eq 0) { $ok = $true }
    } catch {}
}
Write-Host "================================================"
if ($ok) {
    Write-Host " SUCCESS: Windows docker CLI is talking to the WSL daemon."
    Write-Host "   Try:  docker ps"
} else {
    Write-Host " Could not reach the daemon at $dockerHost."
    Write-Host " Checklist:"
    Write-Host "   1. Inside WSL: sudo bash scripts/wsl/enable-docker-tcp.sh"
    Write-Host "   2. Is the distro running?  wsl -d <Distro> -- docker ps"
    Write-Host "   3. Open a NEW terminal (env var applies to new shells)."
}
Write-Host "================================================"
