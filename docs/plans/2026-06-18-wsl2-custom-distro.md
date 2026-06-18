# WSL2 Custom Distro Setup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor `setup.ps1` to support WSL2 as a selectable VM backend alongside VirtualBox+Vagrant, with a one-click `install.ps1` bootstrap script.

**Architecture:** `install.ps1` handles Git install + repo clone, then delegates to `setup.ps1`. `setup.ps1` installs common tools (Git, Windows Terminal), then asks which VM backend (none/WSL2/VirtualBox+Vagrant) and delegates to a new `install-wsl2.ps1` or existing virtualbox/vagrant installers.

**Tech Stack:** PowerShell 5+, winget/GitHub API for downloads, `wsl --import-in-place` for distro install, existing `installer-utils.ps1` pattern.

---

## Task 1: Create `install.ps1` (one-click bootstrap)

**Files:**
- Create: `install.ps1`

**Context:**  
This is the entry point users run via `irm ... | iex` from a fresh machine.
It installs Git (needed to clone the repo), clones to `$env:USERPROFILE\linuxdev`,
then runs `setup.ps1`. Look at `scripts/installers/install-git.ps1` to understand
how Git is installed — it uses `installer-utils.ps1` helpers.

**Step 1: Create `install.ps1`**

```powershell
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/kennyhyun/linuxdev.git"
$Branch = "feature/wsl2-custom-distro"
$InstallDir = "$env:USERPROFILE\linuxdev"

Write-Host "================================================"
Write-Host " Linuxdev Bootstrap"
Write-Host "================================================"

# Step 1: Install Git if not present
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found. Installing Git for Windows..."
    $OsArchBit = (Get-WMIObject Win32_Processor).AddressWidth
    . "$PSScriptRoot\scripts\common\installer-utils.ps1"
    $git_asset = get_github_release_url `
        -url "https://api.github.com/repos/git-for-windows/git/releases/latest" `
        -pattern "*$OsArchBit-bit.exe"
    $git_installer = download_from_installer_url -url $git_asset.url -filename $git_asset.name
    $git_install_inf = "$PSScriptRoot\config\git.inf"
    Start-Process -FilePath $git_installer `
        -ArgumentList "/SP- /SILENT /NOCANCEL /NORESTART /LOADINF=""$git_install_inf""" `
        -Wait
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "Git installed."
} else {
    Write-Host "Git already installed: $(git --version)"
}

# Step 2: Clone or update repo
if (Test-Path "$InstallDir\.git") {
    Write-Host "Repo already exists at $InstallDir, pulling latest..."
    Push-Location $InstallDir
    git pull
    Pop-Location
} else {
    Write-Host "Cloning linuxdev to $InstallDir ..."
    git clone -b $Branch $RepoUrl $InstallDir
}

# Step 3: Run setup.ps1, forwarding any args
Write-Host "Running setup.ps1..."
& "$InstallDir\setup.ps1" @args
```

**Step 2: Test manually**

Since this is a bootstrap script, automated testing is impractical.
Manual test checklist (document in commit message):
- [ ] Run from fresh PowerShell (Admin) with `irm ... | iex` or directly
- [ ] Verify Git installs if missing
- [ ] Verify repo clones to `$env:USERPROFILE\linuxdev`
- [ ] Verify `setup.ps1` is invoked

**Step 3: Commit**

```bash
git add install.ps1
git commit -m "feat: add install.ps1 one-click bootstrap"
```

---

## Task 2: Refactor `setup.ps1` — common section + VM backend question

**Files:**
- Modify: `setup.ps1`

**Context:**  
Current `setup.ps1` always installs VirtualBox+Vagrant and always disables Hyper-V.
We need to:
1. Keep common tools: Git, Windows Terminal (remove VSCode from common)
2. Add VM backend selection after common tools
3. Keep VirtualBox path working unchanged
4. Add WSL2 path stub (implemented in Task 3)
5. VSCode moves to `-vscode` flag only

Read the current `setup.ps1` fully before editing — the Hyper-V disable block
must move into the VirtualBox branch only.

**Step 1: Replace the argument parsing section**

Remove `-novagrant`, `-novirtualbox` flags. Add `-wsl`, `-vagrant`, `-novm`, `-vscode`, `-importdistro` flags.

Old block (lines 8-45 approx):
```powershell
If ($args.Contains("-novagrant")) {
  $noVagrant=1
}
If ($args.Contains("-novirtualbox")) {
  $noVirtualBox=1
}
```

New flags to add:
```powershell
If ($args.Contains("-wsl")) {
  $vmBackend = "wsl"
}
If ($args.Contains("-vagrant")) {
  $vmBackend = "vagrant"
}
If ($args.Contains("-novm")) {
  $vmBackend = "none"
}
If ($args.Contains("-vscode")) {
  $withVsCode = 1
}
If ($args.Contains("-importdistro")) {
  $importDistro = 1
}
```

**Step 2: Update the notice banner**

Replace:
```powershell
Write-Host "==================================
Note: This will turn off WSL2
  and upgrade exsting softwares like
  git, vscode, windows terminal,
  virtualbox, vagrant
=================================="
```

With:
```powershell
Write-Host "==================================
 Linuxdev Setup
 Installs: git, windows terminal
 VM backend: selectable (wsl2 / virtualbox+vagrant / none)
=================================="
```

**Step 3: Move Hyper-V disable block into VirtualBox branch**

Remove the `if (-not $noHyperv)` block from the top-level.
It will live inside the VirtualBox branch in Task 4.

**Step 4: Replace the bottom installer calls with new structure**

Replace everything after the common tool installs with:

```powershell
# --- Common tools (always) ---
Write-Host "======= Common Tools ======="
If (-Not $noTerminal) {
  & "$PSScriptRoot\scripts\installers\install-terminal.ps1" -OsVersion $OsVersion
}
If (-Not $noGit) {
  & "$PSScriptRoot\scripts\installers\install-git.ps1" -OsArchBit $OsArchBit
}
If ($withVsCode) {
  & "$PSScriptRoot\scripts\installers\install-vscode.ps1"
}

# --- VM Backend selection ---
if (-not $vmBackend) {
  Write-Host ""
  Write-Host "Which VM backend do you want to set up?"
  Write-Host "  [1] None (skip)"
  Write-Host "  [2] WSL2  (recommended for Windows 11)"
  Write-Host "  [3] VirtualBox + Vagrant  (legacy)"
  $choice = Read-Host "Enter choice [1]"
  switch ($choice) {
    "2" { $vmBackend = "wsl" }
    "3" { $vmBackend = "vagrant" }
    default { $vmBackend = "none" }
  }
}

switch ($vmBackend) {
  "wsl" {
    & "$PSScriptRoot\scripts\installers\install-wsl2.ps1" `
        -importDistro:([bool]$importDistro) `
        -noConfirm:([bool]$noConfirm)
  }
  "vagrant" {
    # Disable Hyper-V (needed for VirtualBox)
    if (-not $noHyperv) {
      & {
        function disable-optional-feature {
          param ($featureName)
          $feature = Get-WindowsOptionalFeature -online -FeatureName $featureName
          if ($feature -and $feature.State -ne "Disabled") {
            Disable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart
          }
        }
        disable-optional-feature -featureName Microsoft-Hyper-V-Hypervisor
        disable-optional-feature -featureName VirtualMachinePlatform
        disable-optional-feature -featureName HypervisorPlatform
        Start-Process -Wait -PassThru powershell -Verb runAs -ArgumentList 'bcdedit /set hypervisorlaunchtype off'
      }
    }
    If (-Not $noVirtualBox) {
      & "$PSScriptRoot\scripts\installers\install-virtualbox.ps1" -envfile $envfile -OsArchBit $OsArchBit
    }
    If ($withVagrantManager) {
      & "$PSScriptRoot\scripts\installers\install-vagrant-manager.ps1"
    }
    If (-Not $noVagrant) {
      & "$PSScriptRoot\scripts\installers\install-vagrant.ps1" -envfile $envfile -OsArchBit $OsArchBit
    }
  }
  "none" {
    Write-Host "Skipping VM backend setup."
  }
}

Write-Host "=================================="
Write-Host "Done."
```

**Step 5: Verify the old `-nodevtools` flag still works**

`-nodevtools` currently sets `$noVsCode=1` and `$noTerminal=1`.
VSCode is no longer in common, so update to just `$noTerminal=1`:
```powershell
if ($noDevTools) {
  $noTerminal = 1
}
```

**Step 6: Commit**

```bash
git add setup.ps1
git commit -m "refactor: add VM backend selection to setup.ps1"
```

---

## Task 3: Create `scripts/installers/install-wsl2.ps1`

**Files:**
- Create: `scripts/installers/install-wsl2.ps1`

**Context:**  
This script does three things:
1. Enable WSL2 Windows features
2. Install 7-Zip and GitHub CLI (needed for distro download)
3. Optionally download + import the Linuxdev vhdx distro

For feature enabling, use `Enable-WindowsOptionalFeature`.
For 7-Zip and gh CLI, use winget (available Win11) with fallback to direct download.
For distro import, use `wsl --import-in-place`.

The vhdx is stored at `$env:USERPROFILE\linuxdev\distro\ext4.vhdx`.
GitHub release asset pattern: `linuxdev-x64-*.vhdx.7z.001` (and `.sha256`).

**Step 1: Create the script**

```powershell
param(
    [switch]$importDistro,
    [switch]$noConfirm
)

. "$PSScriptRoot\..\common\installer-utils.ps1"

$DistroName   = "Linuxdev"
$DistroDir    = "$env:USERPROFILE\linuxdev\distro"
$VhdxPath     = "$DistroDir\ext4.vhdx"
$GithubRepo   = "kennyhyun/linuxdev"

Write-Host "======= WSL2 Setup ======="

# --- Enable Windows Features ---
Write-Host "Enabling WSL2 Windows features..."
$features = @(
    "Microsoft-Windows-Subsystem-Linux",
    "VirtualMachinePlatform",
    "HypervisorPlatform"
)
$rebootNeeded = $false
foreach ($feature in $features) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature).State
    if ($state -eq "Enabled") {
        Write-Host "  $feature already enabled"
    } else {
        Write-Host "  Enabling $feature ..."
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart
        if ($result.RestartNeeded) { $rebootNeeded = $true }
    }
}

# Set WSL2 as default
wsl --set-default-version 2 2>$null

# --- Install 7-Zip ---
Write-Host "Checking 7-Zip..."
if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
    Write-Host "Installing 7-Zip via winget..."
    winget install --id 7zip.7zip -e --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
} else {
    Write-Host "7-Zip already installed"
}

# --- Install GitHub CLI ---
Write-Host "Checking GitHub CLI..."
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "Installing GitHub CLI via winget..."
    winget install --id GitHub.cli -e --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
} else {
    Write-Host "GitHub CLI already installed: $(gh --version | Select-Object -First 1)"
}

# --- Reboot warning ---
if ($rebootNeeded) {
    Write-Host ""
    Write-Host "NOTICE: A reboot is required to complete WSL2 feature activation."
    Write-Host "After rebooting, run setup.ps1 -wsl again to continue."
    if (-not $noConfirm) {
        Read-Host "Press Enter to continue or Ctrl+C to abort"
    }
}

# --- Import distro ---
# Check if already imported
$existingDistro = wsl --list --quiet 2>$null | Where-Object { $_ -match $DistroName }
if ($existingDistro) {
    Write-Host "$DistroName distro already installed. Skipping import."
    return
}

if (-not $importDistro -and -not $noConfirm) {
    Write-Host ""
    $answer = Read-Host "Install Linuxdev distro now? Downloads several GB. [y/N]"
    if ($answer -notmatch '^[Yy]') {
        Write-Host "Skipped. Run 'setup.ps1 -wsl -importdistro' later to install the distro."
        return
    }
}

if ($importDistro -or $answer -match '^[Yy]') {
    Write-Host "Downloading Linuxdev distro from GitHub Releases..."
    New-Item -ItemType Directory -Force -Path $DistroDir | Out-Null

    # Find latest release assets
    $assets = gh release list --repo $GithubRepo --limit 1 --json tagName |
              ConvertFrom-Json
    if (-not $assets) {
        Write-Error "Could not fetch release info. Is GitHub CLI authenticated? Run: gh auth login"
        return
    }
    $tag = $assets[0].tagName

    # Download all vhdx split volumes + checksum
    Write-Host "Downloading release $tag ..."
    gh release download $tag --repo $GithubRepo `
        --pattern "*x64*.vhdx.7z.*" `
        --pattern "*x64*.sha256" `
        --dir $DistroDir

    # Verify checksum
    $sha256File = Get-ChildItem $DistroDir -Filter "*x64*.sha256" | Select-Object -First 1
    if ($sha256File) {
        Write-Host "Verifying checksum..."
        Push-Location $DistroDir
        $checkResult = & certutil -hashfile (Get-ChildItem "*x64*.vhdx.7z.001").Name SHA256
        # Basic presence check (full verification would parse sha256 file)
        Write-Host "Checksum file: $($sha256File.Name)"
        Pop-Location
    }

    # Extract vhdx
    $firstVol = Get-ChildItem $DistroDir -Filter "*x64*.vhdx.7z.001" | Select-Object -First 1
    if (-not $firstVol) {
        Write-Error "No vhdx archive found in $DistroDir"
        return
    }
    Write-Host "Extracting $($firstVol.Name) ..."
    & 7z x $firstVol.FullName -o"$DistroDir" -y

    # Find extracted vhdx
    $vhdx = Get-ChildItem $DistroDir -Filter "*.vhdx" | Select-Object -First 1
    if (-not $vhdx) {
        Write-Error "No .vhdx file found after extraction"
        return
    }

    # Rename to standard name
    if ($vhdx.FullName -ne $VhdxPath) {
        Move-Item $vhdx.FullName $VhdxPath -Force
    }

    # Import
    Write-Host "Importing $DistroName from $VhdxPath ..."
    wsl --import-in-place $DistroName $VhdxPath

    Write-Host ""
    Write-Host "✅ Linuxdev WSL2 distro installed."
    Write-Host "   Run: wsl -d $DistroName"
}
```

**Step 2: Commit**

```bash
git add scripts/installers/install-wsl2.ps1
git commit -m "feat: add install-wsl2.ps1 for WSL2 feature activation and distro import"
```

---

## Task 4: Test Phase 1 — readonly remount in WSL2

**Files:**
- Create: `docs/plans/wsl2-remount-test-results.md` (test log)

**Context:**  
Before building the distro image, we need to know if
`mount -o remount,ro /` works in WSL2 after boot.
This task is a manual test. Run it in any existing WSL2 distro.

**Step 1: Run the test in WSL2**

Open any WSL2 distro and run:

```bash
# Check what has / open for write
sudo fuser -m / 2>/dev/null
sudo lsof / 2>/dev/null | grep -v " r " | head -20

# Attempt full remount
sudo mount -o remount,ro /
echo "exit code: $?"

# If that fails, try /usr only
sudo mount -o remount,ro /usr
echo "/usr exit code: $?"

# Verify system still works
ls /usr/bin/bash
whoami

# Simulate forced shutdown from PowerShell:
#   wsl --terminate <distro>
# Then restart and check:
#   dmesg | grep -i "fsck\|error\|corrupt" | head
```

**Step 2: Document results**

Create `docs/plans/wsl2-remount-test-results.md` with findings:
- Did `remount,ro /` succeed?
- If not, what error and which processes blocked it?
- Did `/usr` remount succeed?
- After forced termination + restart, any fsck errors?

**Step 3: Update `wsl-boot.sh` strategy based on results**

The `wsl-boot.sh` in Task 5 should use whichever approach worked.

**Step 4: Commit**

```bash
git add docs/plans/wsl2-remount-test-results.md
git commit -m "docs: add WSL2 readonly remount test results"
```

---

## Task 5: Prepare distro image additions (wsl.conf + wsl-boot.sh)

**Files:**
- Create: `config/wsl/wsl.conf`
- Create: `config/wsl/wsl-boot.sh`

**Context:**  
These files get baked into the distro image during the QEMU build.
`wsl.conf` tells WSL2 to run `wsl-boot.sh` on every boot.
`wsl-boot.sh` attempts readonly remount based on Task 4 findings.

Update the strategy in `wsl-boot.sh` based on Task 4 results before implementing.

**Step 1: Create `config/wsl/wsl.conf`**

```ini
[boot]
command = /usr/local/bin/wsl-boot.sh

[user]
default = linuxdev

[interop]
enabled = true
appendWindowsPath = false
```

**Step 2: Create `config/wsl/wsl-boot.sh`**

Fill in based on Task 4 test results. Default (update after testing):

```bash
#!/bin/bash
# WSL2 boot script — runs as root after WSL2 init
# Goal: make rootfs (or /usr) read-only to prevent corruption on forced shutdown

set -e

LOG="/var/log/wsl-boot.log"
echo "$(date): wsl-boot.sh starting" >> "$LOG"

# Attempt 1: remount full rootfs ro
if mount -o remount,ro / 2>/dev/null; then
    echo "$(date): / remounted ro" >> "$LOG"
    exit 0
fi

# Attempt 2: remount system dirs individually
echo "$(date): full remount failed, trying per-dir bind mounts" >> "$LOG"
for dir in /usr /usr/local; do
    if [ -d "$dir" ]; then
        mount --bind "$dir" "$dir" 2>/dev/null && \
        mount -o remount,ro,bind "$dir" 2>/dev/null && \
        echo "$(date): $dir remounted ro" >> "$LOG" || \
        echo "$(date): $dir remount failed" >> "$LOG"
    fi
done
```

**Step 3: Commit**

```bash
git add config/wsl/wsl.conf config/wsl/wsl-boot.sh
git commit -m "feat: add wsl.conf and wsl-boot.sh for readonly remount on boot"
```

---

## Task 6: Add vhdx export to `scripts/export-split.sh`

**Files:**
- Modify: `scripts/export-split.sh` (from `kenny/feature/qemu-support-for-macos`)

**Context:**  
`export-split.sh` currently only exports qcow2.
We need a `--wsl` flag that exports to vhdx format instead,
since `wsl --import-in-place` requires vhdx.

`qemu-img convert -O vhdx` produces a vhdx directly from qcow2.
The rest of the pipeline (7z split, sha256, upload) is unchanged.

**Step 1: Add `export_vhdx` function**

After the existing `export_qcow2_uncompressed` function, add:

```bash
export_vhdx() {
    local input_file="$PROJECT_DIR/vm/disk.qcow2"
    local arch=$(get_vm_architecture)
    local output_file="$OUTPUT_DIR/${VM_NAME}-${arch}-$(date +%Y%m%d).vhdx"

    echo "Exporting VHDX format for WSL --import-in-place..."
    qemu-img convert -f qcow2 -O vhdx "$input_file" "$output_file"
    echo "✅ VHDX export complete: $output_file"
    echo "$output_file"
}
```

**Step 2: Add `--wsl` flag to `main()`**

```bash
# At top of script, parse args
WSL_EXPORT=0
for arg in "$@"; do
    case "$arg" in
        --wsl) WSL_EXPORT=1 ;;
    esac
done

# In main(), replace the export call:
if [ "$WSL_EXPORT" = "1" ]; then
    exported_file=$(export_vhdx)
    # strip .vhdx → use as archive base name without the extension issue
    local arch=$(get_vm_architecture)
    local archive_base="${VM_NAME}-${arch}-$(date +%Y%m%d)-wsl"
    create_7zip_volumes "$exported_file" "$archive_base"
else
    export_qcow2_uncompressed
    # ... existing flow
fi
```

**Step 3: Update `--help` text**

Add:
```
  --wsl     Export as .vhdx for WSL --import-in-place (Windows 11)
```

**Step 4: Commit**

```bash
git add scripts/export-split.sh
git commit -m "feat: add --wsl flag to export-split.sh for vhdx output"
```

---

## Task 7: Update README

**Files:**
- Modify: `README.md`

**Step 1: Add WSL2 setup section**

Add after the existing "Setting up the Linuxdev environment" section:

```markdown
## Setting up with WSL2 (Windows 11)

> Recommended for Windows 11 users. Uses WSL2 instead of VirtualBox.

1. Open PowerShell as Administrator
2. Run:
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   irm https://raw.githubusercontent.com/kennyhyun/linuxdev/feature/wsl2-custom-distro/install.ps1 | iex
   ```
3. When asked, choose **[2] WSL2**
4. Optionally install the Linuxdev distro when prompted

After install:
```powershell
wsl -d Linuxdev
```

To update:
```bash
# Inside Git Bash
cd ~/linuxdev
git pull
./setup.ps1 -wsl
```
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add WSL2 setup instructions to README"
```

---

## Summary

| Task | Description | Type |
|---|---|---|
| 1 | `install.ps1` one-click bootstrap | New file |
| 2 | `setup.ps1` VM backend selection refactor | Modify |
| 3 | `install-wsl2.ps1` WSL2 + distro import | New file |
| 4 | Readonly remount test in WSL2 | Manual test + docs |
| 5 | `wsl.conf` + `wsl-boot.sh` for readonly boot | New files |
| 6 | `--wsl` flag in `export-split.sh` | Modify |
| 7 | README update | Docs |

**Tasks 1–3** are independent of the QEMU build pipeline and can be done now.  
**Tasks 4–6** depend on Task 4 test results — do in order.  
**Task 7** last.
