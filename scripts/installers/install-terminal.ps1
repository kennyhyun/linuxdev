param($OsVersion)

. "$PSScriptRoot\..\common\installer-utils.ps1"

Write-Host ---------------------------------------
$installed_terminal_version = (Get-AppxPackage -Name *WindowsTerminal).Version
$OsPrefix = "Win10"
if ($OsVersion -like '* 11*') {
  $OsPrefix = "Win11"
}
$terminal_asset = get_github_release_url -url "https://api.github.com/repos/microsoft/terminal/releases/latest" -pattern "*msixbundle"
Write-Host $terminal_asset.name
if ($installed_terminal_version -And $terminal_asset.name -match $installed_terminal_version) {
  Write-Host already installed
} else {
  Write-Host Installing $terminal_asset.name "(installed: $installed_terminal_version)"
  $terminal_installer = download_from_installer_url -url $terminal_asset.url -filename $terminal_asset.name
  Try {
    Add-AppPackage -path $terminal_installer
  } catch {
    Write-Host $_
  }
  Write-Host Installed Windows Terminal.
}