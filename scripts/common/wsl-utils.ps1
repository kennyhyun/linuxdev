# Common WSL2 utility functions
# Usage: . "$PSScriptRoot\..\common\wsl-utils.ps1"

$script:DefaultDistroName = "Linuxdev"
$script:DefaultDistroDir  = "$env:USERPROFILE\.linuxdev\$script:DefaultDistroName\distro"
$script:DefaultVhdxPath   = "$script:DefaultDistroDir\ext4.vhdx"
$script:GithubRepo        = "kennyhyun/linuxdev"

# Per-distro data location: %USERPROFILE%\.linuxdev\<DistroName>\{disks,distro}
#   Get-LinuxdevDir "linuxdev"           -> C:\Users\me\.linuxdev\linuxdev
#   Get-LinuxdevDir "linuxdev" "disks"   -> C:\Users\me\.linuxdev\linuxdev\disks
function Get-LinuxdevDir {
    param(
        [Parameter(Mandatory)][string]$DistroName,
        [string]$Sub = ""
    )
    $base = Join-Path $env:USERPROFILE ".linuxdev\$DistroName"
    if ($Sub) { return Join-Path $base $Sub }
    return $base
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")
}

function Get-WslDistros {
    # Returns the list of installed distro names.
    # 'wsl --list --quiet' prints UTF-16LE. Depending on how PowerShell captures
    # it, the result can arrive as one string full of NUL bytes or as char-split
    # fragments (which previously yielded a bogus single-letter name like "D").
    # To be robust: force the console to read wsl's output as Unicode, then clean
    # each line of NUL/CR and drop blanks.
    $prev = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [System.Text.Encoding]::Unicode } catch {}
    try {
        $raw = & wsl.exe --list --quiet 2>$null
    } finally {
        try { [Console]::OutputEncoding = $prev } catch {}
    }
    # $raw may be an array of lines or a single multi-line string; normalise.
    $text = ($raw | Out-String)
    $text = $text -replace "`0", ""        # strip any stray NULs
    return $text -split "`r?`n" |
           ForEach-Object { $_.Trim() } |
           Where-Object { $_ -ne "" }
}

function Test-WslDistroExists {
    param([string]$Name)
    return (Get-WslDistros) -contains $Name
}

function Install-BootstrapMessage {
    param([string]$DistroName)
    Write-Host ""
    Write-Host "Distro '$DistroName' installed."
    Write-Host ""
    Write-Host "NEXT STEPS:"
    Write-Host "  1. Run setup-disks.ps1 to create data disks:"
    Write-Host "       .\scripts\wsl\setup-disks.ps1 -DistroName $DistroName"
    Write-Host "  2. Run bootstrap-wsl.sh inside WSL:"
    Write-Host "       wsl -d $DistroName -u root -- bash /mnt/c/Users/$env:USERNAME/linuxdev/bootstrap-wsl.sh"
}

# The 7-Zip installer does NOT add itself to PATH, so `Get-Command 7z` alone
# misses an existing install. Look on PATH, then in the registry and the
# default install folders. Returns the full path of 7z.exe, or $null.
function Find-7Zip {
    $cmd = Get-Command 7z -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $dirs = @()
    foreach ($key in 'HKLM:\SOFTWARE\7-Zip', 'HKCU:\SOFTWARE\7-Zip') {
        $p = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($p) { $dirs += $p.Path64, $p.Path }
    }
    $dirs += "$env:ProgramFiles\7-Zip", "${env:ProgramFiles(x86)}\7-Zip"
    foreach ($d in $dirs) {
        if ($d -and (Test-Path (Join-Path $d "7z.exe"))) { return (Join-Path $d "7z.exe") }
    }
    return $null
}

# Put the folder of the given 7z.exe on PATH for this session so `7z` works.
function Add-7ZipToPath {
    param([string]$Exe)
    $dir = Split-Path $Exe -Parent
    if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$env:Path;$dir" }
}

# Filesystem label of a distro's data/docker volume: "<DistroName>-<role>".
# All WSL2 distros share ONE VM and see every attached disk, so the label is what
# tells the distros' .mount units apart. ext4 labels are limited to 16 bytes: a
# long distro name is shortened (the role suffix is always kept).
#   Get-LinuxdevDiskLabel linuxdev data    -> linuxdev-data
#   Get-LinuxdevDiskLabel linuxdev docker  -> linuxdev-docker
function Get-LinuxdevDiskLabel {
    param(
        [Parameter(Mandatory)][string]$DistroName,
        [Parameter(Mandatory)][ValidateSet("data", "docker")][string]$Role
    )
    $suffix = "-$Role"
    $max = 16 - $suffix.Length
    $base = if ($DistroName.Length -gt $max) { $DistroName.Substring(0, $max) } else { $DistroName }
    return "$base$suffix"
}
