@echo off
echo Starting Vagrant VM for Linuxdev
echo Please allow the User Acc Control dialog to continue

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command Start-Process '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList '-NoProfile -InputFormat None -ExecutionPolicy Bypass -Command cd %~dp0\..; C:\HashiCorp\Vagrant\bin\vagrant up; Read-Host ''Type ENTER to exit'' ' -Verb RunAs

