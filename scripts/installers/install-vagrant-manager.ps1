. "$PSScriptRoot\..\common\installer-utils.ps1"

Write-Host ---------------------------------------
$vmanager_location1="$env:ProgramFiles (x86)\Vagrant Manager\VagrantManager.exe"
$vmanager_location2="$env:LOCALAPPDATA\Programs\Vagrant Manager\VagrantManager.exe"
If ((Test-Path $vmanager_location1) -or (Test-Path $vmanager_location2)) {
  Write-Host Vagrant Manager is already installed
} else {
  Write-Host Installing Vagrant Manager
  $vmanager_installer = download_github_release_installer -url "https://api.github.com/repos/lanayotech/vagrant-manager-windows/releases/latest" -pattern "*.exe"
  $install_args = "/SP- /SILENT /NOCANCEL /NORESTART /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS"
  Write-Host Installing $vmanager_installer, $install_args
  Start-Process -FilePath $vmanager_installer -ArgumentList $install_args
  Write-Host Installed Vagrant Manager.
}