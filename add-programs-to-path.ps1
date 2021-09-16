$ErrorActionPreference = "Stop"

######################
# add $HOME/Programs and set PATH
$PROGRAMS_DIR="$HOME\Programs"
New-Item -ItemType Directory -Force -Path $PROGRAMS_DIR

$environment_key='Registry::HKEY_CURRENT_USER\Environment'
$oldpath = (Get-ItemProperty -Path $environment_key -Name PATH).path
if ($oldpath.split(';').trim() -match ($PROGRAMS_DIR -replace '\\', '\\')) {
  Write-Host path already exists
} else {
  Write-Host Adding $PROGRAMS_DIR to path
  Set-ItemProperty -Path $environment_key -Name PATH -Value "$oldpath;$PROGRAMS_DIR"
  $ENV:PATH="$ENV:PATH;$PROGRAMS_DIR"
}

