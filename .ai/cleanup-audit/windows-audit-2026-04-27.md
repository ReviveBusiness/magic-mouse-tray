# Windows Magic Mouse Driver Audit — 2026-04-27

**Scope:** Magic Mouse 0x0323 (D0C050CC8C4D), MagicUtilities residue, MagicMouseDriver experiment artifacts
**Mode:** READ-ONLY. No registry writes, no driver deletions, no file mutations.
**Mouse state at audit time:** BT HID active, `LowerFilters=applewirelessmouse`, scroll working.

---

## Executive Summary

**Total items reviewed:** 47 distinct locations (PnP nodes, registry keys, driver packages, files, tasks, startup entries)
**Safe-to-delete (very low risk):** 18 items
**Risky cleanups (could affect working scroll path):** 4 items
**Do-not-touch (active working path):** 5 items

### Top 5 Cleanup Recommendations (risk-adjusted, highest value first)

| # | Item | Risk | Action |
|---|------|------|--------|
| 1 | `MagicMouseDriver` service key (`HKLM\...\Services\MagicMouseDriver`) — .sys is MISSING but key enumerates a live device | Medium | SAFE-TO-DELETE after confirming mouse still works without it |
| 2 | `HKLM\SYSTEM\CurrentControlSet\Enum\USB\VID_05AC&PID_0323&MI_01` `LowerFilters=MagicMouse` — references a non-existent service | Medium | DELETE-RISKY — remove only if USB mode is not in use |
| 3 | `C:\Temp\mu-extract\` (80 MB MagicUtilities binary extract, dated 2025-11-19) | Very Low | SAFE-TO-DELETE |
| 4 | `C:\Temp\` experiment artifacts (before/after CSVs, ETL trace, test scripts, old EXEs) | Very Low | SAFE-TO-DELETE (keep only current `MagicMouseTray.exe`) |
| 5 | `HKLM\SYSTEM\CurrentControlSet\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo` — orphan MU PnP enumeration node with Status=Unknown | Low | SAFE-TO-DELETE (pnputil /remove-device after confirming) |

### Items That Would BREAK the Working Mouse if Removed
- `oem0.inf` / `applewirelessmouse.sys` / `applewirelessmouse` service — **DO NOT TOUCH**
- `BTHENUM\{00001124-...}_VID&0001004C_PID&0323` LowerFilters=applewirelessmouse — **DO NOT TOUCH**
- `C:\Program Files\MagicMouseTray\startup-repair.ps1` — active COL02 repair logic, **DO NOT TOUCH**
- `MM-Dev-Cycle` scheduled task — headless build trigger, **KEEP**
- `HKCU\Run MagicMouseTray` entry pointing to `C:\Temp\MagicMouseTray.exe` — **intentional, KEEP**

---

## Section 1 — PnP Topology: Magic Mouse 0x0323

Scanned for `VID&0001004C_PID&0323`, `VID_05AC&PID_0323`, and `D0C050CC8C4D`.

### 1.1 Active / OK Nodes

| FriendlyName | InstanceId | Status | Class | Notes |
|---|---|---|---|---|
| Magic Mouse | `BTHENUM\DEV_D0C050CC8C4D\9&73B8B28&0&BLUETOOTHDEVICE_D0C050CC8C4D` | OK | Bluetooth | Root BT device node — correct |
| Device Identification Service | `BTHENUM\{00001200-...}_VID&0001004C_PID&0323\9&73B8B28&0&D0C050CC8C4D_C00000000` | OK | Bluetooth | SDP DID profile — normal |
| Apple Wireless Mouse | `BTHENUM\{00001124-...}_VID&0001004C_PID&0323\9&73B8B28&0&D0C050CC8C4D_C00000000` | OK | HIDClass | Active HID parent. `LowerFilters=applewirelessmouse`, `Service=HidBth`. This is the working stack node. |
| HID-compliant mouse (BT COL01) | `HID\{00001124-...}_VID&0001004C_PID&0323\A&31E5D054&B&0000` | OK | Mouse | Motion/click collection — active |

**Status:** All OK. Working scroll path is intact.

### 1.2 Unknown-Status Nodes (Orphans / Stale Enumerations)

| FriendlyName | InstanceId | Status | Risk | Recommended Action |
|---|---|---|---|---|
| Magic Mouse 2024 - USB-C | `USB\VID_05AC&PID_0323&MI_01\7&80F490&0&0001` | Unknown | Low | SAFE-TO-DELETE — USB mode child, not connected |
| HID-compliant vendor-defined device (BT COL02) | `HID\{00001124-...}_VID&0001004C_PID&0323&COL02\A&31E5D054&B&0001` | Unknown | Low | Orphan HID collection — battery descriptor stripped by applewirelessmouse filter on each reboot. startup-repair.ps1 handles this. KEEP as-is. |
| Magic Mouse 3 USB device interface | `{7D55502A-2C87-441F-9993-0761990E0C7A}\MAGICMOUSERAWPDO\8&4FB45D0&0&0323-2-D0C050CC8C4D` | Unknown | Low | MU RawPdo orphan. See Section 2. |
| USB Composite Device | `USB\VID_05AC&PID_0323\J84HJ804YSB000053A` | Unknown | Low | USB parent — mouse not connected via USB. Normal. |
| Magic Mouse 2024 - USB Auxiliary Device | `USB\VID_05AC&PID_0323&MI_00\7&80F490&0&0000` | Unknown | Low | USB HID auxiliary child — stale. |
| HID-compliant vendor-defined device (USB COL03) | `HID\VID_05AC&PID_0323&MI_01&COL03\8&4FB45D0&0&0002` | Unknown | Low | USB multi-collection, stale. |
| HID-compliant touch pad (USB COL02) | `HID\VID_05AC&PID_0323&MI_01&COL02\8&4FB45D0&0&0001` | Unknown | Low | USB touch collection, stale. |
| HID-compliant mouse (USB COL01) | `HID\VID_05AC&PID_0323&MI_01&COL01\8&4FB45D0&0&0000` | Unknown | Low | USB mouse collection, stale. |
| HID-compliant mouse (BT COL01 alt) | `HID\{00001124-...}_VID&0001004C_PID&0323&COL01\A&31E5D054&B&0000` | Unknown | Low | Duplicate COL01 entry from prior enumeration. |

**Note on Unknown-status USB nodes:** These are normal for a device that was connected via USB at least once. Windows retains ghost nodes. They are harmless and will re-appear if the mouse is plugged in again. Mass-removal via Device Manager "Show Hidden Devices" > delete non-present USB entries is safe but cosmetic only.

**Cleanup command (USB ghosts only — cosmetic):**
```powershell
# Set env var then open Device Manager to see ghost nodes
$env:DEVMGR_SHOW_NONPRESENT_DEVICES = 1
devmgmt.msc
# In Device Manager: View > Show Hidden Devices, then delete grayed-out USB entries for VID_05AC&PID_0323
```

---

## Section 2 — PnP Topology: MagicUtilities Residue

### 2.1 MAGICMOUSERAWPDO Orphan Node

| Item | Value |
|---|---|
| InstanceId | `{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D` |
| Status | Unknown |
| Class | (none) |
| DeviceDesc | Magic Mouse 3 USB device interface |
| LocationInformation | Magic Mouse Filter |
| ContainerID | `{7389d67c-d54f-5da7-839d-d60959a3ec98}` |
| Registry Key | `HKLM\SYSTEM\CurrentControlSet\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D` |
| WDF subkey | Present |

**Analysis:** This node was created by the MagicUtilities driver (MagicMouse.sys) as a software-enumerated virtual device. MagicMouse.sys has been uninstalled, so the enumerator service no longer runs — but the registry node was never cleaned up. The DeviceClasses interface GUID `{7D55502A-2C87-441F-9993-0761990E0C7A}` has **no entry** in `HKLM\SYSTEM\CurrentControlSet\Control\DeviceClasses`, confirming the interface is dead.

**Status:** ORPHAN — completely disconnected from any running driver. No functional impact on the working BT scroll path.

**Recommended Action:** SAFE-TO-DELETE

**Risk if wrong:** Removing a PnP node that has no live driver backing it cannot break anything functional. Worst case: node reappears if MagicUtilities is reinstalled.

**Cleanup command:**
```powershell
# View the node first
Get-PnpDevice | Where-Object { $_.InstanceId -match '7D55502A' }

# Remove it (requires elevated prompt)
pnputil /remove-device "{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D"
```

### 2.2 MagicUtilities Interface Class GUID

| Item | Value |
|---|---|
| Registry Key | `HKLM\SYSTEM\CurrentControlSet\Control\DeviceClasses\{7D55502A-2C87-441F-9993-0761990E0C7A}` |
| Status | NOT FOUND |

**Analysis:** Interface class GUID not registered. MagicUtilities removed its class registration cleanly. Only the Enum node (Section 2.1) remains.

---

## Section 3 — Installed Driver Packages (pnputil /enum-drivers)

### 3.1 Magic Mouse / Apple Related Packages

| Published Name | Original Name | Provider | Version | Status | Recommended Action |
|---|---|---|---|---|---|
| `oem0.inf` | `applewirelessmouse.inf` | Apple Inc. | 2026-04-21 v6.2.0.0 | CURRENT — active LowerFilter on BT HID device | **KEEP** — do not touch |
| `oem43.inf` | `appleusb.inf` | Apple, Inc. | 2023-06-14 v538.0.0.0 | CURRENT — Apple Mobile Device USB driver (iPhone/iPad) | KEEP — unrelated to mouse |

**Key finding:** There is **no `oem52.inf`** in the INF directory. The `MagicMouseDriver` service references `@oem52.inf` in its `DisplayName`, but that package was never successfully published to the driver store (or was deleted). This means `MagicMouseDriver` is a broken service key with no corresponding INF package.

**Key finding:** There is **no MagicUtilities / MagicMouse.sys INF** in the driver store. MagicUtilities was uninstalled and its oem INF was removed. Only the RawPdo PnP node (Section 2.1) and the `C:\ProgramData\MagicUtilities\` skeleton remain.

**Key finding:** `oem0.inf` signer is listed as `MagicMouseFix` (not Microsoft WHCP). This is the custom-signed `applewirelessmouse.inf` built for this project. Correct and expected.

### 3.2 No Duplicate Magic Mouse Packages

Only one `applewirelessmouse`-related INF is installed (`oem0.inf`). No duplicate `oem*.inf` versions of the same driver. No MagicMouseDriver INF in the store. Clean.

---

## Section 4 — Registry: LowerFilters / UpperFilters

### 4.1 BTHENUM HID Instance (Active BT Device)

| Registry Key | LowerFilters | UpperFilters | Status |
|---|---|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001124-...}_VID&0001004C_PID&0323\9&73B8B28&0&D0C050CC8C4D_C00000000` | `applewirelessmouse` | (none) | CORRECT — this is the working scroll filter |

No residue from MagicMouseDriver or MagicUtilities in this key. Working path is clean.

### 4.2 HID Children (BT COL01, COL02)

| Registry Key | LowerFilters | UpperFilters | Status |
|---|---|---|---|
| `HID\{00001124-...}_VID&0001004C_PID&0323\A&31E5D054&B&0000` | (none) | (none) | Clean |
| `HID\{00001124-...}_VID&0001004C_PID&0323&Col01\A&31E5D054&B&0000` | (none) | (none) | Clean |
| `HID\{00001124-...}_VID&0001004C_PID&0323&Col02\A&31E5D054&B&0001` | (none) | (none) | Clean |

No residue filters on any HID child node. 

### 4.3 USB MI_01 LowerFilters — PROBLEM FOUND

| Registry Key | LowerFilters | Status |
|---|---|---|
| `HKLM\SYSTEM\CurrentControlSet\Enum\USB\VID_05AC&PID_0323&MI_01\7&80f490&0&0001` | `MagicMouse` | **ORPHAN** — `MagicMouse` service does not exist |

**Analysis:** This is a leftover from a MagicUtilities installation attempt or from an earlier experiment. The `MagicMouse` service key does not exist in `HKLM\SYSTEM\CurrentControlSet\Services\`. The LowerFilter value references a service that doesn't exist. This node applies to the **USB HID interface** (not the active BT stack), so it does not currently affect mouse operation. However, if the mouse is plugged in via USB-C, this dangling filter will cause the USB HID device to fail to enumerate with Code 10 or Code 39.

**Recommended Action:** DELETE-RISKY (safe for BT use; risky only if USB mode is intended)

**Risk if wrong:** If you remove this and then need USB mode, the filter is gone. If you leave it and plug in via USB, the USB stack fails. Remove it if USB mode is not planned.

**Cleanup command:**
```powershell
# Elevated prompt required
$key = "HKLM:\SYSTEM\CurrentControlSet\Enum\USB\VID_05AC&PID_0323&MI_01\7&80f490&0&0001"
Remove-ItemProperty -Path $key -Name LowerFilters
# Then verify:
(Get-ItemProperty $key).LowerFilters
```

### 4.4 USB HID Children (USB COL01, COL02, COL03)

| Registry Key | LowerFilters | UpperFilters | Status |
|---|---|---|---|
| `HID\VID_05AC&PID_0323&MI_01&Col01\8&4fb45d0&0&0000` | (none) | (none) | Clean |
| `HID\VID_05AC&PID_0323&MI_01&Col02\8&4fb45d0&0&0001` | (none) | (none) | Clean |
| `HID\VID_05AC&PID_0323&MI_01&Col03\8&4fb45d0&0&0002` | (none) | (none) | Clean |

No filter residue on USB HID children.

### 4.5 HID Class Global Filters

`HKLM\SYSTEM\CurrentControlSet\Control\Class\{745a17a0-74d3-11d0-b6fe-00a0c90f57da}` has no `LowerFilters` or `UpperFilters` values set. No class-wide filter injection. Clean.

---

## Section 5 — Registry: Driver Service Entries

### 5.1 MagicMouseDriver Service

| Property | Value |
|---|---|
| Registry Key | `HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseDriver` |
| ImagePath | `\SystemRoot\System32\drivers\MagicMouseDriver.sys` |
| Start | 4 (DISABLED) |
| ServiceType | 1 (KERNEL_DRIVER) |
| DisplayName | `@oem52.inf,%ServiceDesc%;Magic Mouse Driver (scroll + battery coexistence)` |
| Enum\Count | 1 |
| Enum\0 | `BTHENUM\{00001124-...}_VID&0001004c_PID&0323\9&73b8b28&0&D0C050CC8C4D_C00000000` |

**Analysis:** Service is DISABLED (Start=4). The `.sys` file (`C:\Windows\System32\drivers\MagicMouseDriver.sys`) is **NOT PRESENT** — it was never deployed to System32, or was removed. The `oem52.inf` referenced in DisplayName does not exist in `C:\Windows\INF\`. The Enum key lists the live BT device as a former client — this is a stale backlink from the last time the driver was bound.

**Status:** ORPHAN service key — broken reference. Disabled and missing its binary. No functional impact.

**Recommended Action:** SAFE-TO-DELETE (the service key alone, not the Enum device node which is the live BT device)

**Risk if wrong:** If MagicMouseDriver is ever reinstalled, it will re-create this key. No other driver reads this service key. Removing it is safe.

**Cleanup command:**
```powershell
# Elevated prompt
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseDriver" /f
```

### 5.2 MagicMouse Service (MagicUtilities)

| Property | Value |
|---|---|
| Registry Key | `HKLM\SYSTEM\CurrentControlSet\Services\MagicMouse` |
| Status | NOT FOUND |

MagicUtilities removed its service key cleanly during uninstall. The only residue is the USB MI_01 LowerFilter entry (Section 4.3) that references this non-existent service.

### 5.3 applewirelessmouse Service (Active)

| Property | Value |
|---|---|
| Registry Key | `HKLM\SYSTEM\CurrentControlSet\Services\applewirelessmouse` |
| ImagePath | `\SystemRoot\System32\drivers\applewirelessmouse.sys` |
| Start | 3 (DEMAND_START) |
| ServiceType | 1 (KERNEL_DRIVER) |
| Enum\Count | 1 |
| Enum\0 | `BTHENUM\{00001124-...}_VID&0001004c_PID&0323\9&73b8b28&0&D0C050CC8C4D_C00000000` |

**Status:** ACTIVE — this is the working scroll filter driver. Enum correctly points to the live BT device. Do not touch.

### 5.4 HidBth Enum

| Property | Value |
|---|---|
| Registry Key | `HKLM\SYSTEM\CurrentControlSet\Services\HidBth\Enum` |
| Count | 2 |
| Item 0 | `BTHENUM\{00001124-...}_VID&000205ac_PID&0239\...E806884B0741_C00000000` |
| Item 1 | `BTHENUM\{00001124-...}_VID&0001004c_PID&0323\...D0C050CC8C4D_C00000000` |

Item 0 is another BT HID device (VID 05AC PID 0239 — likely Apple Magic Keyboard or Magic Trackpad). Item 1 is the Magic Mouse. Both are managed by HidBth. This is correct.

---

## Section 6 — Filesystem Residue

### 6.1 C:\ProgramData\MagicUtilities\

| Property | Value |
|---|---|
| Path | `C:\ProgramData\MagicUtilities\` |
| Status | Exists but EMPTY (0 items) |
| Recommended Action | SAFE-TO-DELETE |
| Risk | None |

**Cleanup command:**
```powershell
Remove-Item "C:\ProgramData\MagicUtilities" -Force
```

### 6.2 Program Files

| Path | Found | Status |
|---|---|---|
| `C:\Program Files\Magic*` | `C:\Program Files\MagicMouseTray\` (exists, 1 file) | ACTIVE — see below |
| `C:\Program Files (x86)\Magic*` | Not found | Clean |

**C:\Program Files\MagicMouseTray\startup-repair.ps1** (7,396 bytes, 2026-04-24):

This is an active part of the project — the COL02 battery collection repair script that runs at startup via scheduled task. It is deliberately placed here. **KEEP.**

### 6.3 C:\Windows\System32\drivers\ — Apple / Magic files

| File | Size | Date | Status | Recommended Action |
|---|---|---|---|---|
| `applewirelessmouse.sys` | 78,424 bytes | 2026-03-18 | ACTIVE — the working scroll filter | **KEEP** |
| `AppleLowerFilter.sys` | 55,608 bytes | 2023-06-27 | Likely related to appleusb (Mobile Device) | KEEP |
| `AppleSSD.sys` | 113,456 bytes | 2024-04-01 | Apple NVMe SSD driver | KEEP |

**No MagicMouse.sys or MagicMouseDriver.sys found.** MagicUtilities .sys and our experimental .sys were never deployed to System32.

### 6.4 C:\Temp — Experiment Artifacts

| File/Dir | Size | Date | Status | Recommended Action |
|---|---|---|---|---|
| `MagicMouseTray.exe` | 177 MB | 2026-04-27 | CURRENT build — startup entry points here | **KEEP** |
| `mm-tray-new\` | 177 MB | 2026-04-27 | Staging dir for latest build | KEEP (or fold into main) |
| `MagicMouseTray-test.exe` | 177 MB | 2026-04-21 | Old test build, superseded | SAFE-TO-DELETE |
| `MagicMouseFix.cer` | 772 bytes | 2026-04-21 | Test signing cert | SAFE-TO-DELETE (unless needed to re-sign) |
| `mu-extract\` | ~80 MB | 2025-11-19 | MagicUtilities binary extract used for reverse engineering | SAFE-TO-DELETE |
| `before-mu.csv` | 758 bytes | 2026-04-21 | Pre-MU-install PnP snapshot | SAFE-TO-DELETE |
| `after-mu.csv` | 2,338 bytes | 2026-04-21 | Post-MU-install PnP snapshot | SAFE-TO-DELETE |
| `before-mu-services.csv` | 569 bytes | 2026-04-21 | Pre-MU services snapshot | SAFE-TO-DELETE |
| `after-mu-services.csv` | 758 bytes | 2026-04-21 | Post-MU services snapshot | SAFE-TO-DELETE |
| `bttrace.etl` | 8 MB | 2026-04-26 | BT ETW trace | SAFE-TO-DELETE (keep .cab if needed) |
| `bttrace.cab` | 3.4 MB | 2026-04-26 | BT trace archive | SAFE-TO-DELETE |
| `capture-hid-descriptor.ps1` | 5.7 KB | 2026-04-26 | Probe script (also in D:\mm3-driver\scripts) | SAFE-TO-DELETE (canonical copy in D:\) |
| `capture-state.ps1` | 7.6 KB | 2026-04-27 | State capture script (also in D:\) | SAFE-TO-DELETE (canonical in D:\) |
| `debug-hid-descriptor.ps1` | 4.7 KB | 2026-04-26 | Debug probe | SAFE-TO-DELETE |
| `test-filter-stack.ps1` | 8.1 KB | 2026-04-26 | Filter stack test (also in D:\) | SAFE-TO-DELETE (canonical in D:\) |
| `startup-repair-fixed.ps1` | 8.1 KB | 2026-04-27 | Revised startup repair | INVESTIGATE-FIRST — confirm it supersedes `C:\Program Files\MagicMouseTray\startup-repair.ps1` before deleting |
| `register-task.ps1` | 1.6 KB | 2026-04-22 | Task registration script | SAFE-TO-DELETE |
| `state-pre-reboot-1.json` | 2.8 KB | 2026-04-27 | Reboot state capture | SAFE-TO-DELETE |
| `state-post-reboot-1.json` | 2.8 KB | 2026-04-27 | Reboot state capture | SAFE-TO-DELETE |
| `TouchpadProbe.ps1` | 9.5 KB | 2026-04-26 | Touchpad probe (also in D:\) | SAFE-TO-DELETE |
| `TouchpadProbe_reports.txt` | 40 bytes | 2026-04-26 | Probe output | SAFE-TO-DELETE |
| `chrome-debug-profile\` | — | 2026-04-21 | Chrome debug profile (unrelated) | INVESTIGATE-FIRST |

**Total safe-to-delete from C:\Temp:** approximately 270 MB (dominated by old EXE and mu-extract).

### 6.5 D:\mm3-driver\ — Active Build Directory

| Property | Value |
|---|---|
| Total size | 0.62 MB (source + build artifacts) |
| Last modified | 2026-04-27 12:10 (today) |
| Status | ACTIVE — current working build |

This is the active source tree. All files are either source (`.c`, `.h`, `.inf`, `.vcxproj`) or build artifacts (`x64\Debug\`). The `x64\Debug\` tree contains intermediate objects (`.obj`, `.pdb`, `.tlog`) from today's build but NOT a linked `.sys` — consistent with the driver service having no binary in System32.

**Recommended Action:** KEEP entire directory. `x64\Debug\` build artifacts can be cleaned (`git clean` equivalent) if disk space is needed, but they are 0.5 MB total.

### 6.6 LocalAppData Probe Logs

| File | Size | Date | Status | Recommended Action |
|---|---|---|---|---|
| `mm-accept-test-2026-04-27T11-45-26.json` | 2,946 bytes | Today | Acceptance test result | SAFE-TO-DELETE after reviewing |
| `mm-accept-test-2026-04-27T12-05-16.json` | 2,946 bytes | Today | Acceptance test result | SAFE-TO-DELETE after reviewing |
| `mm-battery-probe.log` | 1,938 bytes | Today | Battery probe output | SAFE-TO-DELETE |
| `mm-hid-probe.log` | 4,655 bytes | Today | HID descriptor probe | SAFE-TO-DELETE |
| `mm-state-flip.log` | 362 bytes | Today | Filter state flip log | SAFE-TO-DELETE |

All are small diagnostic files from today's session. None are referenced by any running service or task.

### 6.7 MagicMouseTray debug.log

| Property | Value |
|---|---|
| Path | `C:\Users\Lesley\AppData\Roaming\MagicMouseTray\debug.log` |
| Size | 234,230 bytes (228 KB) |
| Last write | 2026-04-27 12:09 (active, written today) |
| Rotation | No sibling log files found — single file, no rotation configured |
| config.ini | 39 bytes — present |

**Status:** ACTIVE — tray app is writing to this file. Size is modest (228 KB). No rotation risk at current size.

**Recommended Action:** KEEP. Consider implementing log rotation if the tray runs long-term (the single file will grow unbounded).

---

## Section 7 — Scheduled Tasks

### 7.1 MM-Dev-Cycle

| Property | Value |
|---|---|
| Task Name | `\MM-Dev-Cycle` |
| Status | Ready |
| Schedule Type | On demand only |
| Task To Run | `powershell.exe ... -File "D:\mm3-driver\scripts\mm-task-runner.ps1"` |
| Run As | Lesley |
| Last Run | 2026-04-27 12:10:32 |
| Last Result | 1 (non-zero — last run had an error or exit code) |
| Timeout | 30 minutes |

**Status:** ACTIVE — correct. On-demand only, triggered from WSL. Last result code 1 is worth investigating (non-zero exit from mm-task-runner.ps1) but is not an audit concern.

**Note:** No other Magic Mouse, applewirelessmouse, MagicUtilities, or startup-repair scheduled tasks found beyond this one. The startup-repair.ps1 does not appear to have a registered scheduled task at this time — if it was unregistered, COL02 battery repair will not auto-run at boot.

**Action item:** Verify whether the `startup-repair.ps1` scheduled task still exists under a different name:
```powershell
schtasks /query /fo CSV | ConvertFrom-Csv | Where-Object { $_.TaskName -match 'startup|repair|battery|COL02' }
```

---

## Section 8 — Startup Entries

### 8.1 HKCU Run

| Value Name | Data | Status | Recommended Action |
|---|---|---|---|
| `MagicMouseTray` | `C:\Temp\MagicMouseTray.exe` | ACTIVE — launches tray at login | KEEP, but consider moving to a more stable path than `C:\Temp\` |

**Note on path:** Running the persistent tray app from `C:\Temp\` is unconventional. If `C:\Temp` is ever cleared by a cleanup tool, the startup entry will fail silently. Consider relocating the binary to `C:\Program Files\MagicMouseTray\MagicMouseTray.exe` and updating the Run value.

### 8.2 HKLM Run

No Magic Mouse, MagicUtilities, or related entries in HKLM Run. Only `SecurityHealth` and `RtkAudUService` (Realtek audio). Clean.

---

## Section 9 — Surprises and Anomalies

### 9.1 MagicMouseDriver service key with no binary

The `MagicMouseDriver` service key exists, is disabled, references `oem52.inf` (non-existent) and `MagicMouseDriver.sys` (absent from System32). The `Enum\0` backlink points to the live BT device. This is unusual — it means the driver was registered (possibly via `pnputil /add-driver` + manual `sc create`) but never installed onto the device, or was installed and then the binary was manually deleted without removing the service key. The Enum backlink is a stale artifact of a previous `pnputil /install-device` attempt. This key is safe to remove.

### 9.2 MagicUtilities `before`/`after` CSV snapshots in C:\Temp

The files `before-mu.csv`, `after-mu.csv`, `before-mu-services.csv`, and `after-mu-services.csv` (dated 2026-04-21) are forensic snapshots captured during MagicUtilities install/uninstall experiments. The `before-mu.csv` shows the MAGICMOUSERAWPDO node was already present **before** MU was installed on that date — suggesting it was created during an earlier MU install that predates the CSV. These files are valuable historical data but are safe to delete now.

### 9.3 startup-repair-fixed.ps1 in C:\Temp

There are two versions of the startup repair script:
- `C:\Program Files\MagicMouseTray\startup-repair.ps1` (7,396 bytes, 2026-04-24)
- `C:\Temp\startup-repair-fixed.ps1` (8,323 bytes, 2026-04-27 00:50)

The Temp version is newer and larger — it may be an updated version not yet deployed to Program Files. **Resolve this before deleting `C:\Temp\startup-repair-fixed.ps1`.** If it supersedes the installed version, deploy it first.

### 9.4 USB MI_01 LowerFilter = `MagicMouse` (ghost service)

This is the highest-priority functional finding. The filter reference `MagicMouse` on the USB HID interface will cause a Code 39 (driver load failure) if the mouse is connected via USB-C. The BT stack is completely unaffected (BT uses a different device node). This is a direct leftover from MagicUtilities' USB driver installation — it set the LowerFilter but then left it orphaned on uninstall.

### 9.5 No MagicMouse.sys or MagicMouseDriver.sys anywhere on disk

Both driver binaries are absent from System32, DriverStore, and C:\Temp. This is correct — MagicUtilities was uninstalled, and MagicMouseDriver.sys from our experiment was never deployed to System32 (the build only outputs to `D:\mm3-driver\x64\Debug\` and the .sys is not in the output — the last build ended with `unsuccessfulbuild` tlog marker).

---

## Appendix A — Complete Finding Inventory

| # | Item | Location | Status | Action |
|---|---|---|---|---|
| 1 | Magic Mouse BT root node | BTHENUM\DEV_D0C050CC8C4D | Active/OK | KEEP |
| 2 | Apple Wireless Mouse BT HID parent | BTHENUM\{00001124-...}\VID&0001004C_PID&0323 | Active/OK | KEEP |
| 3 | HID mouse COL01 (BT) | HID\{00001124-...}\...\A&31E5D054&B&0000 | Active/OK | KEEP |
| 4 | BT HID LowerFilters=applewirelessmouse | BTHENUM instance registry | Active | KEEP |
| 5 | applewirelessmouse service | HKLM\...\Services\applewirelessmouse | Active | KEEP |
| 6 | applewirelessmouse.sys | C:\Windows\System32\drivers\ | Active | KEEP |
| 7 | oem0.inf / applewirelessmouse.inf | C:\Windows\INF\ + DriverStore | Active | KEEP |
| 8 | startup-repair.ps1 | C:\Program Files\MagicMouseTray\ | Active | KEEP |
| 9 | MagicMouseTray.exe (current) | C:\Temp\ | Active | KEEP (consider relocating) |
| 10 | MM-Dev-Cycle task | Windows Task Scheduler | Active | KEEP |
| 11 | HKCU Run MagicMouseTray | HKCU\...\Run | Active | KEEP |
| 12 | debug.log | C:\Users\Lesley\AppData\Roaming\MagicMouseTray\ | Active | KEEP |
| 13 | D:\mm3-driver\ (source) | D:\mm3-driver\ | Active | KEEP |
| 14 | HidBth Enum (2 devices) | HKLM\...\Services\HidBth\Enum | Active | KEEP |
| 15 | MAGICMOUSERAWPDO PnP node | HKLM\...\Enum\{7D55502A-...} | Orphan | SAFE-TO-DELETE |
| 16 | MagicMouseDriver service key | HKLM\...\Services\MagicMouseDriver | Orphan (no .sys) | SAFE-TO-DELETE |
| 17 | C:\ProgramData\MagicUtilities\ | C:\ProgramData\ | Empty dir | SAFE-TO-DELETE |
| 18 | USB MI_01 LowerFilters=MagicMouse | HKLM\...\Enum\USB\VID_05AC&PID_0323&MI_01 | Orphan filter | DELETE-RISKY |
| 19 | mu-extract\ | C:\Temp\mu-extract\ | Stale | SAFE-TO-DELETE |
| 20 | MagicMouseTray-test.exe | C:\Temp\ | Old build | SAFE-TO-DELETE |
| 21 | MagicMouseFix.cer | C:\Temp\ | Test cert | SAFE-TO-DELETE |
| 22 | before/after MU CSVs (4 files) | C:\Temp\ | Historical | SAFE-TO-DELETE |
| 23 | bttrace.etl / .cab | C:\Temp\ | Trace data | SAFE-TO-DELETE |
| 24 | capture-hid-descriptor.ps1 | C:\Temp\ | Duplicate | SAFE-TO-DELETE |
| 25 | capture-state.ps1 | C:\Temp\ | Duplicate | SAFE-TO-DELETE |
| 26 | debug-hid-descriptor.ps1 | C:\Temp\ | Duplicate | SAFE-TO-DELETE |
| 27 | test-filter-stack.ps1 | C:\Temp\ | Duplicate | SAFE-TO-DELETE |
| 28 | register-task.ps1 | C:\Temp\ | Done | SAFE-TO-DELETE |
| 29 | state-pre/post-reboot-1.json | C:\Temp\ | Stale | SAFE-TO-DELETE |
| 30 | TouchpadProbe.ps1 / _reports.txt | C:\Temp\ | Duplicate | SAFE-TO-DELETE |
| 31 | mm-accept-test JSON (2 files) | LocalAppData | Session data | SAFE-TO-DELETE |
| 32 | mm-battery-probe.log | LocalAppData | Session data | SAFE-TO-DELETE |
| 33 | mm-hid-probe.log | LocalAppData | Session data | SAFE-TO-DELETE |
| 34 | mm-state-flip.log | LocalAppData | Session data | SAFE-TO-DELETE |
| 35 | startup-repair-fixed.ps1 | C:\Temp\ | Possibly newer version | INVESTIGATE-FIRST |
| 36 | mm-tray-new\ dir | C:\Temp\ | Staging dir | KEEP or consolidate |
| 37 | USB ghost nodes (8 nodes) | PnP / Device Manager | Stale BT/USB nodes | SAFE-TO-DELETE (cosmetic) |
| 38 | HID COL02 BT orphan | HID\{00001124-...}&COL02 | Unknown/expected | KEEP (startup-repair manages) |
| 39 | D:\mm3-driver\x64\Debug\ | D:\mm3-driver\ | Build artifacts | SAFE-TO-DELETE (cosmetic, 0.5 MB) |
| 40 | oem43.inf (appleusb) | C:\Windows\INF\ | Active, iPhone/iPad | KEEP |
| 41 | AppleLowerFilter.sys | C:\Windows\System32\drivers\ | Mobile Device driver | KEEP |
| 42 | AppleSSD.sys | C:\Windows\System32\drivers\ | Apple SSD driver | KEEP |
| 43 | config.ini | C:\Users\Lesley\AppData\Roaming\MagicMouseTray\ | Active | KEEP |
| 44 | chrome-debug-profile\ | C:\Temp\ | Unrelated | INVESTIGATE-FIRST |
| 45 | MagicMouse.sys DeviceClasses GUID | HKLM\...\Control\DeviceClasses\{7D55502A-...} | NOT FOUND — clean | n/a |
| 46 | MagicMouse service (MU) | HKLM\...\Services\MagicMouse | NOT FOUND — clean | n/a |
| 47 | HKLM Run (Magic Mouse entries) | HKLM\...\CurrentVersion\Run | NOT FOUND — clean | n/a |

---

*Generated by WSL read-only audit on 2026-04-27. All PowerShell commands used Get-* and reg query only. No mutations performed.*
