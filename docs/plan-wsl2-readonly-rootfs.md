# Plan: WSL2 Custom Distro with Readonly Root

## Goal

Prevent rootfs corruption on improper shutdown (forced power off, Windows crash)
by making the root filesystem read-only after boot, using a custom distro
distributed via GitHub Releases.

## Background

### Current Problem

WSL2 uses a single `ext4.vhdx` file as the root filesystem.
On improper shutdown, the ext4 journal may be left in a dirty state,
causing filesystem corruption that requires manual recovery.

### Why Readonly Root Solves It

A read-only filesystem cannot be left in a dirty state — there is nothing to journal.
Corruption is only possible on writable partitions, which can be isolated
to data-only disks that are easier to recover or recreate.

### WSL2 Constraints

- WSL2 mounts `ext4.vhdx` as `/` in rw mode during init
- No initramfs hook to pivot_root before init
- `kernelCommandLine = ro` breaks WSL2 init
- **However**: `mount -o remount,ro /` after boot is testable
- `/etc/wsl.conf` `[boot] command` runs after init — this is our hook

---

## Architecture

```
GitHub Release
  linuxdev-x64-YYYYMMDD.vhdx.7z.001  (256MB splits)
  linuxdev-x64-YYYYMMDD.sha256

Windows PowerShell (setup.ps1):
  1. Download + verify + extract vhdx
  2. wsl --import-in-place Linuxdev C:\wsl\linuxdev\ext4.vhdx
  3. wsl -d Linuxdev  →  first boot runs /usr/local/bin/wsl-boot.sh

WSL2 boot layout:
  ext4.vhdx  (rootfs — target: remounted ro after boot)
  ├── /usr          →  ro after boot
  ├── /etc          →  ro after boot (wsl.conf survives)
  ├── /home         →  rw (separate vhdx, optional)
  └── /var/lib/docker →  rw (separate vhdx, optional)
```

---

## Phases

### Phase 1: Proof of Concept — readonly remount test

**Goal**: Verify that `mount -o remount,ro /` works in WSL2 after boot.

Steps:

1. Install any WSL2 distro (e.g. Debian from store)
2. Run manually inside WSL:
   ```bash
   sudo fuser -m / 2>/dev/null
   sudo lsof / | grep -v " r "
   sudo mount -o remount,ro /
   ```
3. If it fails, identify blocking processes and try subdirectory approach:
   ```bash
   sudo mount -o remount,ro /usr
   sudo mount -o remount,ro /usr/local
   ```
4. Verify system still works after remount (ssh, basic commands)
5. Simulate improper shutdown:
   - `wsl --terminate Linuxdev` from PowerShell (equivalent of forced kill)
   - Restart WSL and confirm no corruption

**Success criteria**:
- `mount -o remount,ro /` or `/usr` succeeds
- System remains functional
- No fsck errors after forced termination

**Fallback if full `/` remount fails**:
- Try `/usr` only (covers most system binaries and libraries)
- Try bind+ro mount for specific dirs
- Document which dirs can and cannot be made ro

---

### Phase 2: Build QEMU base image with WSL boot script

**Goal**: Prepare a Debian 12 image that remounts ro on WSL boot.

Based on `kenny/feature/qemu-support-for-macos` branch.

Steps:

1. Build Debian 12 image using existing `scripts/qemu.create.sh`
2. Inside the image, install `/usr/local/bin/wsl-boot.sh`:
   ```bash
   #!/bin/bash
   # Remount root (or /usr) as readonly
   # Called by /etc/wsl.conf [boot] command
   mount -o remount,ro /
   # or fallback:
   # for dir in /usr /usr/local /bin /sbin /lib /lib64; do
   #   mount --bind $dir $dir && mount -o remount,ro,bind $dir
   # done
   ```
3. Add `/etc/wsl.conf`:
   ```ini
   [boot]
   command = /usr/local/bin/wsl-boot.sh

   [user]
   default = linuxdev

   [interop]
   enabled = true
   appendWindowsPath = false
   ```
4. Test boot inside QEMU — confirm wsl-boot.sh logic is sound

---

### Phase 3: Add vhdx export to export-split.sh

**Goal**: Export QEMU disk as vhdx for `wsl --import-in-place`.

Modify `scripts/export-split.sh` to add `--wsl` flag:

```bash
# New export function
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

Then pipe through existing `create_7zip_volumes` for split + checksum.

Release artefacts:
```
linuxdev-x64-20260618.vhdx.7z.001
linuxdev-x64-20260618.vhdx.7z.002
linuxdev-x64-20260618.sha256
```

---

### Phase 4: Windows bootstrap — download and import

**Goal**: Add WSL import flow to `setup.ps1`.

New PowerShell function in `setup.ps1`:

```powershell
function Install-LinuxdevWSL {
    param(
        [string]$DistroName = "Linuxdev",
        [string]$InstallPath = "$env:USERPROFILE\wsl\linuxdev"
    )

    # 1. Get latest release from GitHub
    $release = gh release view --repo kennyhyun/linuxdev --json assets | ConvertFrom-Json
    $vhdxAssets = $release.assets | Where-Object { $_.name -match "vhdx\.7z\." }

    # 2. Download all split volumes + checksum
    New-Item -ItemType Directory -Force -Path $InstallPath
    foreach ($asset in $vhdxAssets) {
        gh release download --repo kennyhyun/linuxdev --pattern $asset.name -D $InstallPath
    }

    # 3. Verify checksum
    # 4. Extract with 7z
    $firstVol = Get-ChildItem $InstallPath -Filter "*.7z.001" | Select-Object -First 1
    & 7z x $firstVol.FullName -o"$InstallPath"

    # 5. Import
    $vhdx = Get-ChildItem $InstallPath -Filter "*.vhdx" | Select-Object -First 1
    wsl --import-in-place $DistroName $vhdx.FullName

    Write-Host "✅ Linuxdev WSL distro installed. Run: wsl -d $DistroName"
}
```

---

## Open Questions

1. **Does `mount -o remount,ro /` actually work in WSL2?**
   → Must be tested in Phase 1 before committing to this design.
   
2. **If `/` can't go ro, can `/usr` alone be sufficient?**
   → `/usr` covers most system binaries. `/etc` changes are rare post-setup.
   
3. **Does docker need a separate vhdx, or is tmpfs sufficient?**
   → tmpfs means re-pulling images on reboot. Separate vhdx is better for dev use.

4. **Windows 10 support?**
   → `--import-in-place` requires Windows 11 / WSL 0.67+.
   → Fallback: tar.gz export + `wsl --import` (slower but works on Win10).

---

## Tasks

- [ ] **Phase 1**: Test `mount -o remount,ro /` in WSL2 manually
- [ ] **Phase 1**: Document what works (full `/`, `/usr` only, or bind mounts)
- [ ] **Phase 2**: Write `wsl-boot.sh` based on Phase 1 findings
- [ ] **Phase 2**: Add `wsl.conf` to QEMU image build
- [ ] **Phase 2**: Add microk8s setup to bootstrap (from `wsl-local-cluster` branch)
- [ ] **Phase 3**: Add `--wsl` / `--vhdx` flag to `export-split.sh`
- [ ] **Phase 3**: Test `qemu-img convert -O vhdx` output is importable
- [ ] **Phase 4**: Add `Install-LinuxdevWSL` to `setup.ps1`
- [ ] **Phase 4**: Test full flow end-to-end on Windows 11

---

## Branch Strategy

```
kenny/feature/qemu-support-for-macos  (base — existing QEMU build pipeline)
  └── feature/wsl2-readonly-rootfs    (new — this plan)
        ├── Phase 1 findings committed as docs/wsl2-remount-test-results.md
        ├── Phase 2 changes to bootstrap.sh + new wsl-boot.sh
        ├── Phase 3 changes to scripts/export-split.sh
        └── Phase 4 changes to setup.ps1
```
