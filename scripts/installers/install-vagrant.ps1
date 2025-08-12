param($envfile, $OsArchBit)

. "$PSScriptRoot\..\common\installer-utils.ps1"

Write-Host ---------------------------------------
Try {
  $installed_vagrant_version = vagrant --version | %{$_.split(' ')[1]}
} catch {}

if ($envfile._VER_VAGRANT) {
  $versionString = $envfile._VER_VAGRANT | select-string -Pattern '[0-9.]+' | ForEach-Object{$_.Matches[0].Value}
}

if ($versionString) {
  $vagrant_url = "https://releases.hashicorp.com/vagrant/$versionString"
} else {
  $vagrant_url = "https://www.vagrantup.com/downloads"
}
try {
  $vagrant_link = (Invoke-WebRequest -UseBasicParsing -Uri $vagrant_url).Links | Where-Object {$_.href -like "*$OsArchBit.msi"}
} catch {
  $_.Exception.Response.StatusCode
}
$vagrant_installer_url = [System.Uri]$vagrant_link.href
$vagrant_installer_filename = $vagrant_installer_url.Segments | Select-Object -Last 1
$vagrant_installer_version = $vagrant_installer_filename | select-string -Pattern '([0-9]+(\.[0-9]+)+)' | ForEach-Object{$_.Matches[0].Value}
$vagrant_installer = "$env:temp\$($vagrant_installer_filename)"
Write-Host "Vagrant installer `"$vagrant_installer_version`" (installed: $installed_vagrant_version)"
if (!$vagrant_installer_url) {
  Write-Host "Could not find the download url $versionString"
} elseif ($installed_vagrant_version -And $installed_vagrant_version -match $vagrant_installer_version) {
  Write-Host already installed
} else {
  if (Test-Path($vagrant_installer)) {
    Write-Host Found $vagrant_installer, skip downloading
  } Else {
    Write-Host Downloading $vagrant_installer_url
    Invoke-WebRequest -UseBasicParsing -Uri $vagrant_installer_url -OutFile $vagrant_installer
  }
  Write-Host Installing $vagrant_installer_filename
  Try {
    Start-Process -Wait -FilePath $vagrant_installer -Argument "/passive /norestart" -PassThru
  } catch {
    Write-Host $_
  }
  Write-Host Installed Vagrant.
}