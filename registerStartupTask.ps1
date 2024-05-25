if (!$args[0]) {
  write-error "taskName is require as the first argument"
  exit -1;
}
if (!$args[1]) {
  write-error "schedCommand is require as the second argument"
  exit -1;
}
$taskName=$args[0]
$schedCommand=$args[1]

Write-host "Registinering new '$taskName'"
$Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NonInteractive -NoLogo -ExecutionPolicy Bypass -Command `"$schedCommand`""
$Trigger =  @(
  $(New-ScheduledTaskTrigger -AtLogon)
)
$Settings = New-ScheduledTaskSettingsSet
$Task = New-ScheduledTask -Action $Action -Trigger $Trigger -Settings $Settings

$user=((Get-WMIObject -class Win32_ComputerSystem | Select-Object -ExpandProperty username)) 

Register-ScheduledTask -TaskName $taskName -InputObject $Task -User "$user"
