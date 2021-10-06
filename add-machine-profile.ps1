$ErrorActionPreference = "Stop"
$machine_name=$args[0]

if (-not $machine_name) {
  write-host machine_name is required
  exit 1
}
$machine_title=(Get-Culture).TextInfo.ToTitleCase($machine_name)

######################
# add profile directory
$PROFILE_DIR="$HOME\AppData\Local\Microsoft\Windows Terminal\Fragments\$machine_title"
New-Item -ItemType Directory -Force -Path $PROFILE_DIR | Out-Null

$PROFILE_FILE="$HOME\AppData\Local\Microsoft\Windows Terminal\Fragments\$machine_title\$machine_name.json"
#write-host $PROFILE_FILE
$iconfile="$PSScriptRoot\config\debian.png"
$guid=New-Guid

write-host $PROFILE_FILE, icon: $iconfile, guid: $guid

$json=Get-Content -Path $PSScriptRoot\config\windows-terminal.json  | ConvertFrom-Json

$profile=$json.profiles[0]

$profile.guid="{$guid}"
$profile.name=$machine_title
$profile.commandline="ssh -X $machine_name"
$profile.icon=$iconfile

#$json | ConvertTo-Json -Depth 4

$json | ConvertTo-Json -Depth 4 | Out-File -encoding ASCII -FilePath $PROFILE_FILE
