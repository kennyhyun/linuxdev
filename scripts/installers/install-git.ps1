param($OsArchBit)

. "$PSScriptRoot\..\common\installer-utils.ps1"

Write-Host ---------------------------------------
Try {
  $installed_git_version = git --version | %{$_.split(' ')[-1]} | %{$_.SubString(0, $_.IndexOf('.windows'))}
} catch {}
$git_asset = get_github_release_url -url "https://api.github.com/repos/git-for-windows/git/releases/latest" -pattern "*$OsArchBit-bit.exe"
Write-Host $git_asset.name "(installed: $installed_git_version)"
if ($installed_git_version -And $git_asset.name -match $installed_git_version) {
  Write-Host already installed
} Else {
  $git_installer = download_from_installer_url -url $git_asset.url -name $git_asset.name
  $git_install_inf = "$PSScriptRoot\..\..\config\git.inf"
  $install_args = "/SP- /SILENT /NOCANCEL /NORESTART /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /LOADINF=""$git_install_inf"""
  Write-Host Installing $git_installer, $install_args
  Start-Process -FilePath $git_installer -ArgumentList $install_args -Wait
  Write-Host Installed Git.
}