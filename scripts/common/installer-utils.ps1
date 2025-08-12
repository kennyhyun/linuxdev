function get_github_release_url {
  param($url, $pattern)
  $asset = Invoke-RestMethod -Method Get -Uri "$url" | foreach-object assets | where-object name -like "$pattern"
  if (!$asset) {
    Throw "Could not find asset, please review pattern: '$pattern'
 "
  }
  if (($asset).Count) {
    Throw "Could not find a unique assets, please review pattern: '$pattern'
matched $($asset.name -Join ", ")
 "
  }
  return @{"url" = $($asset.browser_download_url); "name" = $($asset.name)}
}

function download_from_installer_url {
  param ($url, $filename)
  if ($url -like '//*') {
    $url = "https:$url"
  }
  if (-not $filename) {
    $filename = $url.split("=/?")[-1]
  }
  $temp_file = "$env:temp\$filename"
  if ($temp_file -notmatch ".exe" -and $temp_file -notmatch ".msi") {
    $temp_file = "$temp_file.exe"
  }
  if (Test-Path($temp_file)) {
    Write-Host Found $temp_file, skip downloading
  } else {
    Invoke-WebRequest -UseBasicParsing -Uri "$url" -OutFile $temp_file
  }
  return $temp_file
}

function download_github_release_installer {
  param($url, $pattern)
  $asset = get_github_release_url -url "$url" -pattern "$pattern"
  $installer = download_from_installer_url -url $asset.url
  return $installer
}