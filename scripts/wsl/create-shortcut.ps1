# Create a desktop shortcut that runs a command inside a WSL distro.
# Uses Windows Terminal (wt.exe) when available, otherwise wsl.exe directly.
#
# Usage:
#   .\scripts\wsl\create-shortcut.ps1 -DistroName linuxdev
#   .\scripts\wsl\create-shortcut.ps1 -DistroName dev2 -Command "htop" -Name "htop (dev2)"
#   .\scripts\wsl\create-shortcut.ps1 -DistroName linuxdev -Command "btop" -Folder D:\shortcuts
#
#   -Command  Command to run in the distro (default: htop). Run in the default
#             user's home directory.
#   -Name     Shortcut label (default: "<command> (<DistroName>)").
#   -Folder   Where to put the .lnk (default: the current user's Desktop).

param(
    [Parameter(Mandatory)][string]$DistroName,
    [string]$Command = "htop",
    [string]$Name    = "",
    [string]$Folder  = ""
)

$ErrorActionPreference = "Stop"

if ($DistroName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    Write-Error "Invalid distro name '$DistroName' (use letters, digits, '.', '_', '-')"
    exit 1
}
if (-not $Command.Trim()) { Write-Error "-Command must not be empty"; exit 1 }

# Desktop path honours folder redirection (e.g. OneDrive).
if (-not $Folder) { $Folder = [Environment]::GetFolderPath("Desktop") }
if (-not (Test-Path $Folder)) { New-Item -ItemType Directory -Force -Path $Folder | Out-Null }

if (-not $Name) { $Name = "$($Command.Trim()) ($DistroName)" }
# Strip characters that are invalid in file names.
$fileName = ($Name -replace '[\\/:*?"<>|]', '_') + ".lnk"
$lnkPath  = Join-Path $Folder $fileName

$wsl = Join-Path $env:SystemRoot "System32\wsl.exe"
$wt  = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wt.exe"

# wsl.exe -d <distro> --cd ~ -- <command>
$wslArgs = "-d $DistroName --cd ~ -- $Command"

if (Test-Path $wt) {
    $target = $wt
    $arguments = "new-tab --title `"$Name`" $wsl $wslArgs"
} else {
    $target = $wsl
    $arguments = $wslArgs
}

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath       = $target
$lnk.Arguments        = $arguments
$lnk.WorkingDirectory = $env:USERPROFILE
$lnk.IconLocation     = "$wsl,0"
$lnk.Description      = "Run '$Command' in WSL distro $DistroName"
$lnk.Save()

Write-Host "Shortcut created: $lnkPath"
Write-Host "  target : $target $arguments"
