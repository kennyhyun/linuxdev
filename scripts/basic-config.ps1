$registryPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
$Name = "PromptOnSecureDesktop"
$value = "0"

New-ItemProperty -Path $registryPath -Name $name -Value $value -PropertyType DWORD -Force | Out-Null
