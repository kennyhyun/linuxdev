# WSL2 Readonly Remount Test Results

**Date**: 2026-06-18  
**Machine**: Windows 11, x64  
**Distro**: Debian (Microsoft Store)  
**WSL kernel**: 6.18.33.1-microsoft-standard-WSL2

## Tests Performed

### 1. Full rootfs remount,ro

```bash
sudo mount -o remount,ro /
```

**Result**: FAILED — `mount: /: mount point is busy`  
**Reason**: WSL2 init holds `/` at kernel level, not visible to userspace `fuser`.  
Full rootfs remount is not possible in WSL2.

### 2. /usr bind+remount,ro

```bash
sudo mount --bind /usr /usr
sudo mount -o remount,ro,bind /usr
touch /usr/test  # → Read-only file system ✅
```

**Result**: SUCCESS

### 3. All system dirs bind+remount,ro

```bash
for dir in /usr /bin /sbin /lib /lib64 /etc; do
    mount --bind $dir $dir && mount -o remount,ro,bind $dir
done
```

**Result**: All SUCCESS. System remained functional (sudo, bash, apt all worked).

### 4. /var/log on tmpfs

```bash
mount -t tmpfs -o size=64m tmpfs /var/log
```

**Result**: SUCCESS

### 5. wsl.conf [boot] command auto-execution

Configured `/etc/wsl.conf`:
```ini
[boot]
command = /usr/local/bin/wsl-boot.sh
```

After `wsl --terminate Debian` + restart:
- All bind+ro mounts applied automatically ✅
- `/var/log` on tmpfs ✅
- `apt`, `sudo`, basic commands all functional ✅

### 6. Forced shutdown simulation (wsl --terminate)

`wsl --terminate` is equivalent to SIGKILL on the WSL VM.

**Before wsl-boot.sh**: journal corruption observed on restart:
```
systemd-journald: File .../system.journal corrupted or uncleanly shut down
```

**After wsl-boot.sh**: No new journal corruption messages after forced termination.
Previous corruption messages remain in dmesg (from prior session) but no new ones added.

## Conclusions

| Goal | Result |
|---|---|
| Full `/` remount,ro | ❌ Not possible in WSL2 |
| System dirs bind+ro (`/usr`, `/bin`, `/sbin`, `/lib`, `/etc`) | ✅ Works reliably |
| `/var/log` on tmpfs (journal protection) | ✅ Works, eliminates journal corruption |
| Auto-apply on boot via wsl.conf | ✅ Works |
| System functional after protection | ✅ apt, sudo, bash all work |

## Remaining Writable Paths (intentional)

After wsl-boot.sh runs, the following remain writable:

- `/home` — user data (expected)
- `/var` (except `/var/log`) — runtime state, docker data
- `/var/lib/docker` — docker storage (separate vhdx recommended)
- `/tmp` — already tmpfs
- `/run` — already tmpfs

## mount Output (after wsl-boot.sh)

```
/dev/sdd on /usr type ext4 (ro,relatime,discard,errors=remount-ro,data=ordered)
/dev/sdd on /usr/bin type ext4 (ro,...)
/dev/sdd on /usr/sbin type ext4 (ro,...)
/dev/sdd on /usr/lib type ext4 (ro,...)
/dev/sdd on /usr/lib64 type ext4 (ro,...)
/dev/sdd on /etc type ext4 (ro,...)
tmpfs on /var/log type tmpfs (rw,...)
```

## Next Steps

1. Add `wsl-boot.sh` install to bootstrap script
2. Export Debian as tar.gz for GitHub Release (`wsl --export`)
3. Update `install-wsl2.ps1` to import from tar.gz release
