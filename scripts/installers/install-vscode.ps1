. "$PSScriptRoot\..\common\installer-utils.ps1"

Write-Host ---------------------------------------
Try {
  $installed_vscode_version = code --version| select-object -First 1
} catch {}

$vscode_url = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user"
$vscode_installer_url = [System.Uri](Invoke-WebRequest -UseBasicParsing -Method Head -MaximumRedirection 0 -Uri $vscode_url -ErrorAction SilentlyContinue).Headers.Location

$vscode_installer_filename = $vscode_installer_url.Segments | Select-Object -Last 1
$vscode_installer_version = $vscode_installer_filename| select-string -Pattern '([0-9]+(\.[0-9]+)+)' | ForEach-Object{$_.Matches[0].Value}
Write-Host "$vscode_installer_filename, $vscode_installer_version"

$vscode_installer = "$env:temp\$($vscode_installer_filename)"
Write-Host "VS Code installer `"$vscode_installer_version`" (installed: $installed_vscode_version)"
if ($installed_vscode_version -And $vscode_installer_version -match $installed_vscode_version) {
  Write-Host already installed
} else {
  if (Test-Path($vscode_installer)) {
    Write-Host Found $vscode_installer, skip downloading
  } Else {
    Write-Host Downloading $vscode_installer_url
    Invoke-WebRequest -UseBasicParsing -Uri $vscode_installer_url -OutFile $vscode_installer
  }
  Write-Host Installing $vscode_installer_filename
  Try {
    Start-Process -Wait -FilePath $vscode_installer -Argument "/SILENT /NORESTART /MERGETASKS=!runcode" -PassThru
  } catch {
    Write-Host $_
  }
  Write-Host Installed VS Code.
}