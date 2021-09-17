$ErrorActionPreference = "Stop"

$PROGRAMS_DIR="$HOME\Programs"
invoke-expression -Command $PSScriptRoot\add-programs-to-path.ps1

######################
# save docker bianry to user/programs if docker cli was not found
Write-Host ---------------------------------------
Try {
  $installed_docker_version = docker -v | %{$_.split(',')[0]} | %{$_.split(' ')[-1]}
} catch {}

$docker_url = "https://api.github.com/repos/StefanScherer/docker-cli-builder/releases/latest"
$docker_asset = Invoke-RestMethod -Method Get -Uri $docker_url | % assets | where name -like "*docker.exe"

Write-Host $docker_asset.browser_download_url found. installed_docker_version: $installed_docker_version

if ($installed_docker_version -And $docker_asset.browser_download_url -match $installed_docker_version) {
  Write-Host "$installed_docker_version is already installed"
} Else {
  # download installer unless exists
  $docker_binary = "$PROGRAMS_DIR\$($docker_asset.name)"
  if (Test-Path($docker_binary)) {
    Write-Host Found $docker_binary, skip downloading
  } Else {
    Invoke-WebRequest -UseBasicParsing -Uri $docker_asset.browser_download_url -OutFile $docker_binary
  }
  Write-Host Installed docker.
}

######################
# save docker-compose bianry to user/programs if not found
Write-Host ---------------------------------------
Try {
  $installed_dc_version = docker-compose -v | %{$_.split(',')[0]} | %{$_.split(' ')[-1]}
} catch {}

$dc_url = "https://api.github.com/repos/docker/compose/releases/latest"
$dc_asset = Invoke-RestMethod -Method Get -Uri $dc_url | % assets | where name -like "*x86_64.exe"

Write-Host $dc_asset.browser_download_url found. installed_dc_version: $installed_dc_version

if ($installed_dc_version -And $dc_asset.browser_download_url -match $installed_dc_version) {
  Write-Host "$installed_dc_version is already installed"
} Else {
  # download installer unless exists
  $dc_binary = "$PROGRAMS_DIR\docker-compose.exe"
  if (Test-Path($dc_binary)) {
    Write-Host Found $dc_binary, skip downloading
  } Else {
    Invoke-WebRequest -UseBasicParsing -Uri $dc_asset.browser_download_url -OutFile $dc_binary
  }
  Write-Host Installed docker-compose.
}
