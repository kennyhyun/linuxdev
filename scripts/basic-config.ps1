# Disable Secure Desktop (UAC Dimming)
$registryPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
$Name = "PromptOnSecureDesktop"
$value = "0"

New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType DWORD -Force | Out-Null

# Active hour
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name ActiveHoursStart -Value 8 -PassThru
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings -Name ActiveHoursEnd -Value 2 -PassThru

# Show hidden files
$key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty $key Hidden 1
Set-ItemProperty $key HideFileExt 0
Stop-Process -processname explorer

# Disable Windows Update
$AUSettings = (New-Object -com "Microsoft.Update.AutoUpdate").Settings
# 1: aunlDisabled,
# 2: aunlNotifyBeforeDownload,
# 3: aunlNotifyBeforeInstallation,
# 4: aunlScheduledInstallation
$AUSettings.NotificationLevel = 1
$AUSettings.Save
