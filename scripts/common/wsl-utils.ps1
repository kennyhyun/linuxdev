# Common WSL2 utility functions
# Usage: . "$PSScriptRoot\..\common\wsl-utils.ps1"

$script:DefaultDistroName = "Linuxdev"
$script:DefaultDistroDir  = "$env:USERPROFILE\linuxdev\distro"
$script:DefaultVhdxPath   = "$script:DefaultDistroDir\ext4.vhdx"
$script:GithubRepo        = "kennyhyun/linuxdev"

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
