# M13 Binary Patch: applewirelessmouse.sys — Session 2026-04-29

## TL;DR

Patched `applewirelessmouse.sys` at offset `0xA850` (116-byte embedded HID descriptor) to add
Vendor Battery TLC (RID=0x90) alongside the existing Mouse TLC (RID=0x02). Signed with
MagicMouseFix cert. Staged to `C:\Windows\System32\drivers\applewirelessmouse.sys.new` with
`PendingFileRenameOperations` queued. **Reboot required to apply.**

---

## Background

Track 1 (confirmed 2026-04-29): Battery reads at cold boot via Apple stock filter. COL02
(RID=0x90) appears after reboot when BTHPORT cache is populated with Descriptor A. `applewireless
mouse.sys` intercepts IOCTL `0x410210` (SDP attribute 0x0206 — HIDDescriptorList) and injects a
single-TLC Mouse-only descriptor, stripping COL02/battery.

**Goal**: Instead of replacing the Apple driver with M13 KMDF driver, patch the descriptor
embedded in `applewirelessmouse.sys` at offset `0xA850` to include both TLCs.

---

## Descriptor Layout at 0xA850

Original: 116 bytes — Mouse TLC (RID=0x02) + phantom Feature 0x47 + RID=0x27 input.

Patched: 116 bytes (same size, no length field changes needed):
- **TLC1** (81 bytes): Mouse RID=0x02 — 5 buttons + X/Y + AC Pan + Wheel
- **TLC2** (35 bytes): Vendor Battery RID=0x90 (flags + battery%) + dummy Feature RID=0x91 (10-byte padding)

Key offsets within the 116-byte block:
| Offset | Value | Meaning |
|--------|-------|---------|
| +7     | 0x02  | RID for TLC1 (Mouse) |
| +80    | 0xC0  | End Collection (end of TLC1) |
| +81    | 0x06  | Start of TLC2 (UsagePage vendor) |
| +89    | 0x90  | RID for TLC2 (Battery) |

---

## Signing Behavior

Original `applewirelessmouse.sys`: **78424 bytes** (includes Apple's ~12KB PE authenticode cert).

After `signtool sign` with MagicMouseFix cert: **66288 bytes**. Signtool replaces the entire
certificate table. Apple's large cert is removed; our smaller self-signed cert is added. This is
expected — the cert is a PE overlay, not part of any section. The data section containing offset
`0xA850` is unaffected.

Verified: `data[0xA850+7] == 0x02`, `data[0xA850+89] == 0x90` in the signed binary.

---

## Installation Method: PendingFileRenameOperations

The SYS file is locked by the kernel driver while Windows is running. Even disabling the BTHENUM
device does not unload the module from kernel memory. Solution: queue a boot-time rename.

**Staged file**: `C:\Windows\System32\drivers\applewirelessmouse.sys.new`
**Registry entry**: `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations`
```
\??\C:\Windows\System32\drivers\applewirelessmouse.sys.new  →  \??\C:\Windows\System32\drivers\applewirelessmouse.sys
```

SMSS.exe processes this before any drivers load on the next boot.

---

## PATCH-APPLE-SYS Task Runner Route

Added to `mm-task-runner.ps1`:

```
PATCH-APPLE-SYS|<nonce>|<patched-sys-path>
```

1. Finds BTHENUM HID device instance ID (regex `{00001124...}...004c...0323`)
2. Copies patched sys to `applewirelessmouse.sys.new` in System32\drivers
3. Queues `PendingFileRenameOperations` for atomic boot-time replace
4. Returns 0 on success; log at `C:\mm-dev-queue\patch-apple-<nonce>.log`

Also used: existing `SIGN-FILE|<nonce>|<file-path>|<thumbprint>` route (uses `/sm /sha1` against
`LocalMachine\My`).

---

## Current State (2026-04-29)

| Item | State |
|------|-------|
| Backup (original) | `D:\Backups\AppleWirelessMouse-RECOVERY\AppleWirelessMouse.sys` — 78424 bytes |
| Patched + signed | `D:\Backups\AppleWirelessMouse-RECOVERY\AppleWirelessMouse-patched.sys` — 66288 bytes |
| Staged | `C:\Windows\System32\drivers\applewirelessmouse.sys.new` — 66288 bytes ✅ |
| PendingFileRenameOperations | Queued ✅ |
| **Action required** | **Reboot Windows** |

---

## Post-Reboot Verification

After reboot, run `mm-accept-test.sh` (or `mm-accept-test.ps1`). Key checks:

1. `applewirelessmouse.sys` file size = 66288 bytes (confirms rename applied)
2. COL02 device shows as Started in Device Manager
3. `HidD_GetInputReport(0x90)` returns 0-100% battery
4. Scroll (AC Pan + Wheel) working on COL01

---

## Rollback

If the patched driver causes issues:
1. Boot into Safe Mode
2. Replace `C:\Windows\System32\drivers\applewirelessmouse.sys` with
   `D:\Backups\AppleWirelessMouse-RECOVERY\AppleWirelessMouse.sys`
3. Or use the `ROLLBACK-M12` task runner route (reinstalls from Apple INF backup)
