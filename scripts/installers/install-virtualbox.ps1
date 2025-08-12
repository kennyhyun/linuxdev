param($envfile, $OsArchBit)

. "$PSScriptRoot\..\common\installer-utils.ps1"

Write-Host ---------------------------------------
$vbox_path = "$Env:Programfiles\Oracle\VirtualBox"
$vbox_manage = "$vbox_path\VBoxManage"
Try {
  $installed_vbox_version = (& $vbox_manage --version)
} catch {}

try {
  if ($envfile._VER_VIRTUALBOX) {
    $versionString = $envfile._VER_VIRTUALBOX | select-string -Pattern '[0-9.]+' | ForEach-Object{$_.Matches[0].Value}
    $versionPrefix = $versionString | select-string -Pattern '[0-9]+\.[0-9]+\.[0-9]+'
    $vbox_url = "https://www.virtualbox.org/wiki/Download_Old_Builds_$versionPrefix"
    $vbox_url = "https://download.virtualbox.org/virtualbox/$versionPrefix"
    Write-Host "vbox_url with _VER_VIRTUALBOX($($envfile._VER_VIRTUALBOX)) in $vbox_url, Finding \"*$versionString*Win.exe\""
    $vbox_link = (Invoke-WebRequest -UseBasicParsing -Uri $vbox_url).Links | Where-Object {$_.href -like "*$versionString*Win.exe"}
  }
  if (!$vbox_link) {
    $vbox_url = "https://www.oracle.com/virtualization/technologies/vm/downloads/virtualbox-downloads.html"
    Write-Host "Latest vbox_url: $vbox_url"
    $vbox_link = (Invoke-WebRequest -UseBasicParsing -Uri $vbox_url).Links | Where-Object {$_.href -like "*$versionString*Win.exe"}
  }
} catch {
  $_.Exception.Response.StatusCode
}
$href = if ($vbox_link.href.StartsWith('//')) { "http:$($vbox_link.href)" } else { $vbox_link.href }
$vbox_installer_url = [System.Uri]$href
Write-Host "Found vbox_installer_url: $vbox_installer_url"
$vbox_installer_filename = [System.IO.Path]::GetFileName($vbox_installer_url.ToString())
$vbox_installer_version = Write-Output $vbox_installer_filename | select-string -Pattern '([0-9]+(\.[0-9]+)+)' | ForEach-Object{$_.Matches[0].Value}
$vbox_installer = "$env:temp\$($vbox_installer_filename)"
Write-Host "VirtualBox installer `"$vbox_installer_version`" (installed: $installed_vbox_version)"

function save-vm-states {
  & $vbox_manage list runningvms|foreach-object -Process {
    if ($_ -match '"(.+?)"') {
      $vm_name = $matches[1]
      write-host Saving state $vm_name
      & $vbox_manage controlvm "$vm_name" savestate
    }
  }
}

if (!$vbox_installer_url) {
  Write-Host "Could not find the download url $versionString"
} elseif ($installed_vbox_version -And $installed_vbox_version -match $vbox_installer_version) {
  Write-Host already installed
} else {
  if (Test-Path($vbox_installer)) {
    Write-Host Found $vbox_installer, skip downloading
  } Else {
    Write-Host Downloading $vbox_installer_url
    Invoke-WebRequest -UseBasicParsing -Uri $vbox_installer_url -OutFile $vbox_installer
  }
  Write-Host Installing $vbox_installer_filename
  if ($installed_vbox_version) {
    save-vm-states
  }
  Try {
    Start-Process -Wait -FilePath $vbox_installer -Argument "--silent --ignore-reboot" -PassThru
  } catch {
    Write-Host $_
  }
  Write-Host Installed VirtualBox.
}