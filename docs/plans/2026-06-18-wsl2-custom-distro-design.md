# Design: WSL2 Custom Distro Setup

**Date**: 2026-06-18  
**Branch**: `feature/wsl2-custom-distro`

## Problem

The current `setup.ps1` is tightly coupled to VirtualBox + Vagrant.
Users on Windows 11 who want WSL2 instead have no automated path.
Additionally, improper shutdown can corrupt the WSL2 ext4.vhdx rootfs.

## Goals

1. One-command bootstrap for new Windows machines via `install.ps1`
2. `setup.ps1` supports WSL2 and VirtualBox+Vagrant as selectable backends
3. WSL2 distro distributed as vhdx via GitHub Releases (`wsl --import-in-place`)
4. Readonly root remount after boot to prevent rootfs corruption

---

## User Flow

### First-time setup (new machine)

```
# Admin PowerShell — one line
irm https://raw.githubusercontent.com/kennyhyun/linuxdev/feature/wsl2-custom-distro/install.ps1 | iex
```

`install.ps1` does:
1. Install Git (with Git Bash)
2. Clone repo → `$env:USERPROFILE\linuxdev`
3. Run `setup.ps1`

### Subsequent updates

```bash
# Git Bash
cd ~/linuxdev
git pull
./setup.ps1
```

---

## setup.ps1 Flow

```
[Common — always runs]
  - Install Git (with Git Bash)
  - Install Windows Terminal

[VM Backend Question]
  "Which VM backend do you want to set up?"
    [1] None (skip)
    [2] WSL2  (recommended for Windows 11)
    [3] VirtualBox + Vagrant  (legacy)

  Flags bypass the question:
    -wsl      → WSL2 path
    -vagrant  → VirtualBox + Vagrant path
    -novm     → skip

[WSL2 path]  →  scripts/installers/install-wsl2.ps1
  - Enable Windows features: WSL, VirtualMachinePlatform, HypervisorPlatform
  - Install 7-Zip, GitHub CLI
  - Prompt: "Install Linuxdev distro now? (several GB, takes time) [Y/n]"
      Y → download vhdx from GitHub Releases
          verify checksum
          wsl --import-in-place Linuxdev $env:USERPROFILE\linuxdev\distro\ext4.vhdx
      N → print: "Run setup.ps1 -importdistro later"

[VirtualBox + Vagrant path]  (existing code, unchanged)
  - Disable Hyper-V
  - Install VirtualBox
  - Install Vagrant

[Optional — flag only]
  -vscode   → install VSCode
```

---

## File Structure Changes

```
install.ps1                            ← NEW  one-click bootstrap
setup.ps1                              ← REFACTOR  add VM backend selection
scripts/installers/
  install-git.ps1                      ← keep
  install-terminal.ps1                 ← keep
  install-vscode.ps1                   ← keep (flag-only: -vscode)
  install-virtualbox.ps1               ← keep
  install-vagrant.ps1                  ← keep
  install-wsl2.ps1                     ← NEW  WSL2 + distro import
```

---

## WSL2 Distro Design

### Distribution

- Format: `.vhdx` (not tar.gz)
- Import: `wsl --import-in-place` (Windows 11 + WSL 0.67+)
- Install path: `$env:USERPROFILE\linuxdev\distro\ext4.vhdx`
- Release artefacts on GitHub:
  ```
  linuxdev-x64-YYYYMMDD.vhdx.7z.001
  linuxdev-x64-YYYYMMDD.vhdx.7z.002
  linuxdev-x64-YYYYMMDD.sha256
  ```

### Build pipeline (macOS, existing QEMU branch)

```
scripts/qemu.create.sh   →  disk.qcow2  (Debian 12, arm64/x64)
scripts/export-split.sh --wsl  →  .vhdx  →  7z split  →  GitHub Release
```

### Readonly root (post-boot remount)

The distro image includes:

**`/etc/wsl.conf`**:
```ini
[boot]
command = /usr/local/bin/wsl-boot.sh

[user]
default = linuxdev

[interop]
enabled = true
appendWindowsPath = false
```

**`/usr/local/bin/wsl-boot.sh`**:
```bash
#!/bin/bash
# Attempt readonly remount after WSL2 init completes.
# Falls back to per-directory bind+ro if full remount fails.
mount -o remount,ro / 2>/dev/null || {
  for dir in /usr /usr/local /bin /sbin /lib /lib64; do
    [ -d "$dir" ] || continue
    mount --bind "$dir" "$dir"
    mount -o remount,ro,bind "$dir"
  done
}
```

> **Note**: Full `/` remount,ro feasibility in WSL2 must be validated
> empirically before the distro build (see Open Questions below).

---

## Open Questions

| # | Question | Impact |
|---|---|---|
| 1 | Does `mount -o remount,ro /` succeed in WSL2 after init? | Determines wsl-boot.sh strategy |
| 2 | Does `qemu-img convert -O vhdx` produce a WSL-importable vhdx? | Determines export pipeline |
| 3 | Windows 10 fallback needed? (`--import-in-place` is Win11 only) | Determines if tar.gz export also needed |

---

## Out of Scope

- macOS / QEMU path changes (handled in `feature/qemu-support-for-macos`)
- Readonly root implementation detail (separate task after Phase 1 test)
- microk8s setup inside distro (separate task)
