param($OsVersion)

. "$PSScriptRoot\..\common\installer-utils.ps1"

Write-Host ---------------------------------------

# Skip entirely if Windows Terminal is already present, OR if we are running
# inside Windows Terminal right now ($env:WT_SESSION is set by WT). In either
# case there is nothing to do -- and we avoid a needless GitHub API call and
# download. (Like install-git.ps1, an existing install is left as-is.)
$installed_terminal_version = (Get-AppxPackage -Name *WindowsTerminal).Version

if ($env:WT_SESSION) {
  Write-Host "Running inside Windows Terminal (WT_SESSION set) - skipping install."
  return
}
if ($installed_terminal_version) {
  Write-Host "Windows Terminal already installed (v$installed_terminal_version) - skipping."
  return
}

# Not installed: fetch the latest release and install it.
$OsPrefix = "Win10"
if ($OsVersion -like '* 11*') {
  $OsPrefix = "Win11"
}
$terminal_asset = get_github_release_url -url "https://api.github.com/repos/microsoft/terminal/releases/latest" -pattern "*msixbundle"
Write-Host "Installing $($terminal_asset.name)"
$terminal_installer = download_from_installer_url -url $terminal_asset.url -filename $terminal_asset.name
Try {
  Add-AppPackage -path $terminal_installer
} catch {
  Write-Host $_
}
Write-Host "Installed Windows Terminal."
