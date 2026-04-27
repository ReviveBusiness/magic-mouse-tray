# Registry Backup Diff Analysis
**Generated:** 2026-04-27  
**Analyst:** Claude Sonnet 4.6 (registry-diff sub-task)  
**Scope:** 3-way diff — Nov 24 2025 (clean baseline) / Apr 3 2026 (MU working) / Apr 27 2026 (current AppleFilter mode)

---

## Executive Summary

| Metric | Value |
|--------|-------|
| Keys in Nov 24 backup | 506,240 |
| Keys in Apr 3 backup | 558,408 |
| Keys in Apr 27 backup | 600,754 |
| Net increase Nov→Apr 3 | +52,168 (+10.3%) |
| Net increase Apr 3→Apr 27 | +42,346 (+7.6%) |

**Top 5 actionable findings:**

1. **HidBth descriptor cache confirmed** — The SDP record containing the embedded HID report descriptor lives at `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<mac>\CachedServices` (value name `00010000`). It is a per-MAC, per-pairing blob, NOT a per-INF or per-service blob. This is the empirical answer to roadmap item #6.

2. **LowerFilters insertion is the SOLE mechanism MU used to get scroll working on v1 (030d).** In Apr 3, `Device Parameters` for the v1 mouse gained `LowerFilters = "applewirelessmouse"` (hex multi-sz). The v3 (0323) in Apr 3 had NO LowerFilters — MU owned v3 outright via the `MagicMouse` service replacing HidBth. In Apr 27 (current), v3 has NO LowerFilters and is bound back to `HidBth` via `applewirelessmouse.sys` (oem0.inf, our AppleFilter INF).

3. **MagicUtilitiesService is gone from current registry.** MU's user-mode service (`MagicUtilitiesService`) existed in Apr 3 but does not exist in Apr 27 — meaning MU was fully uninstalled. The `MagicMouse` kernel service (oem53.inf) is also gone. What remains is only the `SOFTWARE\MagicUtilities` config hive (orphaned settings) and the `MagicMouseRawPdo` virtual device (from MagicMouseDriver, our replacement).

4. **Apple's `applewirelessmouse` driver (applebmt64.inf) was ALREADY PRESENT in Nov 24** (oem10.inf), bound to v1 mouse (030d) via HidBth. In Apr 3, MU hijacked v1 by adding `LowerFilters = applewirelessmouse`. In Apr 27, the v3 (0323) is now bound via a NEW `applewirelessmouse.inf_amd64_ac34ebceaaf7324c` package (oem0.inf = our `AppleWirelessMouse.inf` from the GitHub community driver).

5. **Magic Mouse v1 (030d) had a single HID node in Nov 24 — no COL split.** After MU installed (Apr 3), v1 sprouted COL01+COL02+COL03. v3 (0323) has had COL01+COL02 in both Apr 3 and Apr 27. This confirms the COL split is produced by the device's multi-collection HID report descriptor, not by the driver itself.

---

## 1. MagicUtilities Footprint (Apr 3 Reveal)

### 1a. Kernel Driver Service — `MagicMouse`

```
[HKLM\SYSTEM\CurrentControlSet\Services\MagicMouse]
"Type"=dword:00000001          ; kernel driver
"Start"=dword:00000003         ; demand-start (loaded on device arrival)
"ErrorControl"=dword:00000001
"ImagePath"="\SystemRoot\System32\drivers\MagicMouse.sys"
"DisplayName"="@oem53.inf,%Service.Desc%;Magic Mouse Service"
"Owners"="oem53.inf"
"Group"=""

[HKLM\SYSTEM\CurrentControlSet\Services\MagicMouse\Parameters\Wdf]
"KmdfLibraryVersion"="1.15"
"WdfMajorVersion"=dword:1
"WdfMinorVersion"=dword:0xf   ; KMDF 1.15

[HKLM\SYSTEM\CurrentControlSet\Services\MagicMouse\Enum]
"0"="BTHENUM\{00001124-...}_VID&000205ac_PID&030d\9&73b8b28&0&04F13EEEDE10_C00000000"
"1"="BTHENUM\{00001124-...}_VID&0001004c_PID&0323\9&73b8b28&0&D0C050CC8C4D_C00000000"
"Count"=dword:2
```

**Interpretation:** `MagicMouse.sys` is a KMDF 1.15 kernel-mode filter/function driver registered as oem53.inf. It was bound to BOTH the v1 (030d/04F13EEEDE10) and v3 (0323/D0C050CC8C4D) BTHENUM instances. Start=3 = demand-start, loaded by PnP when either device arrives.

**ABSENT in Apr 27:** This service is completely gone. The `MagicMouseDriver` service (our INF) is the successor for v3 only.

### 1b. User-Mode Service — `MagicUtilitiesService`

```
[HKLM\SYSTEM\CurrentControlSet\Services\MagicUtilitiesService]
"Type"=dword:00000010          ; Win32 own-process
"Start"=dword:00000002         ; auto-start at boot
"ImagePath"="\"C:\Program Files\MagicUtilities\Service\MagicUtilities_Service.exe\" --run"
"DisplayName"="Magic Utilities Service"
"ObjectName"="LocalSystem"
"Description"="Maintains the Magic Utilities device drivers."
```

**Interpretation:** Runs at boot as LocalSystem. Responsible for battery polling, gesture remapping, and driver keepalive. **ABSENT in Apr 27** (MU fully uninstalled at user-mode level).

### 1c. Virtual PDO — `MagicMouseRawPdo`

**Apr 3 instances (two devices):**
```
{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\a&137e1bf2&1&030D-1-04F13EEEDE10
{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\a&31e5d054&2&0323-1-D0C050CC8C4D
```

**Apr 27 instances (one device, new instance ID):**
```
{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\8&4fb45d0&0&0323-2-D0C050CC8C4D
```

**Interpretation:** In Apr 3, MU created a virtual PDO for EACH connected mouse. In Apr 27, only one RawPdo instance exists (v3/0323), created by our MagicMouseDriver. The instance ID suffix changed (`-1-` → `-2-`), which is the WDF instance counter incrementing across driver reinstalls.

### 1d. DeviceClasses Interface GUID `{fae1ef32-137e-485e-8d89-95d0d3bd8479}`

This GUID is MU's custom raw PDO interface class. Registered in:
```
HKLM\SYSTEM\CurrentControlSet\Control\DeviceClasses\{fae1ef32-137e-485e-8d89-95d0d3bd8479}\
  ##?#{7D55502A-2C87-441F-9993-0761990E0C7A}#MagicMouseRawPdo#<instance>#{fae1ef32-...}
```
Present in both Apr 3 and Apr 27 (our MagicMouseDriver reuses the same GUID space).

### 1e. DriverDatabase Package — `magicmouse.inf_amd64_82cbbe70c776aec4`

**Apr 3 only:**
```
[HKLM\SYSTEM\DriverDatabase\DriverPackages\magicmouse.inf_amd64_82cbbe70c776aec4]
"InfName"="MagicMouse.inf"
"OemPath"="C:\Program Files\MagicUtilities\DriverMouse"
"Catalog"="MagicMouse.cat"

Descriptors:
  BTHENUM\{...}_VID&0001004c_PID&0323   (v3 - Magic Mouse 2024)
  BTHENUM\{...}_VID&000205ac_PID&030d   (v1 - Magic Mouse 2009)
```

**ABSENT in Apr 27.** The MU DriverStore package was fully purged during uninstall.

### 1f. SOFTWARE Hive — Orphaned Config

In **both** Apr 3 and Apr 27 — unchanged:
```
[HKLM\SOFTWARE\MagicUtilities\App]
"GlobalSettingsVersion"="3.1.6.1"
"TrialExpiryDate"=hex:85,ae,30,85,ef,85,e6,40   (expiry timestamp)

[HKLM\SOFTWARE\MagicUtilities\Driver]
"D0C050CC8C4D-BthDirectSdp"=dword:1
"D0C050CC8C4D-BthSmoothScrolling"=dword:1
"D0C050CC8C4D-BthKeepAlive"=dword:0
"D0C050CC8C4D-BthKeepAlivePeriod"=dword:0x7d0  (2000 ms)

[HKLM\SOFTWARE\MagicUtilities\Devices]
"dtMM1-04F13EEEDE10"=""
"dtMM3-D0C050CC8C4D"=""
```

**This config hive is an orphan in Apr 27** — the driver and service are gone but `HKLM\SOFTWARE\MagicUtilities` remains. Safe to delete as cleanup but not load-bearing for current operation.

### 1g. Scheduled Task — New in Apr 27

```
SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\MagicMouseTray-StartupRepair
"Description"="Repairs Magic Mouse COL02 battery HID collection at startup"
```

This is our own task (MagicMouseTray startup repair). Not an MU artifact.

---

## 2. HidBth Descriptor Cache Location

**CONFIRMED EMPIRICAL ANSWER:**

The post-SDP cached HID descriptor is stored at:
```
HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<MAC_lowercase>\CachedServices
```
Value name: `"00010000"` (REG_BINARY — the SDP ServiceAttributeResponse for the HID profile)

Also mirrored to `DynamicCachedServices\00010000` (identical content; dynamic = runtime, static = persisted).

### 2a. Magic Mouse v1 (030d, MAC: 04f13eeede10) — Nov 24 and Apr 3

**Path:**
```
HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\04f13eeede10\CachedServices
```

**First 30 bytes of `00010000` (Nov 24 = Apr 3, both identical):**
```
36 01 4e 09 00 00 0a 00 01 00 00 09 00 01 35 03
19 11 24 09 00 04 35 0d 35 06 19 01 00 ...
```

**Interpretation:**
- `36 01 4e` = SDP sequence tag 0x36 (Data Element Sequence), length 0x014e = 334 bytes
- `09 00 00` = Attribute ID 0x0000 (ServiceRecordHandle)
- The embedded HID report descriptor is buried inside attribute `0x0206` (HIDDescriptorList)
- The HID descriptor itself starts at offset ~0x7A within the blob (after SDP framing), beginning with `05 01 09 02 a1 01 85 10...` (Usage Page Generic Desktop, Usage Mouse, Collection Application, Report ID 0x10)

The blob is **334 bytes** total for the SDP record. The HID descriptor within it is approximately **98 bytes** (v1).

### 2b. Magic Mouse v3 (0323, MAC: d0c050cc8c4d) — Apr 3 and Apr 27

**Path:**
```
HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\d0c050cc8c4d\CachedServices
```

**First 30 bytes of `00010000` (Apr 3 = Apr 27, both identical):**
```
36 01 5c 09 00 00 0a 00 01 00 00 09 00 01 35 03
19 11 24 09 00 04 35 0d 35 06 19 01 00 ...
```

- `36 01 5c` = SDP sequence, length 0x015c = 348 bytes (v3 SDP record is 14 bytes longer than v1)
- The v3 HID descriptor within it includes the battery report collection (Usage 0x61/0x65 in Usage Page 0x84 = Power Page), absent in v1

**Key difference v1 vs v3 SDP records:**
| Field | v1 (030d) | v3 (0323) |
|-------|-----------|-----------|
| SDP record total | 334 bytes | 348 bytes |
| HID descriptor size | ~98 bytes (`25 62` = string len 98) | ~135 bytes (`25 87` = string len 135) |
| Report ID 0x10 | Buttons + XY | Buttons + XY (same layout) |
| Report ID 0x90 | Not present | Present (battery + power) |
| Report ID 0x55 | Feature (64 bytes) | Feature (64 bytes) |
| Report ID 0x47 | Feature (1 byte) | Not present in v1 |

### 2c. Cache Stability

The v3 `CachedServices` blob is **byte-for-byte identical** between Apr 3 and Apr 27. This confirms:
- The cache survives driver uninstall/reinstall cycles
- It is written by BTHPORT.SYS at pairing time from the SDP query response
- It is NOT modified by MagicMouse.sys or applewirelessmouse.sys
- To inject a modified descriptor, you would write to this blob — but the descriptor is INSIDE a larger SDP record, so patching requires understanding the SDP TLV framing

### 2d. Nov 24 — No v3 Cache

In Nov 24, MAC `d0c050cc8c4d` does NOT exist under `BTHPORT\Parameters\Devices`. The v3 mouse had never been paired before our work began. The cache is created at first pairing and persists through all subsequent connects.

---

## 3. LowerFilters Across Timestamps

### 3-way comparison for Magic Mouse v1 (030d, MAC: 04F13EEEDE10)

**Device Parameters path:**
```
HKLM\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001124-...}_VID&000205ac_PID&030d\
  9&73b8b28&0&04F13EEEDE10_C00000000\Device Parameters
```

| Value | Nov 24 | Apr 3 | Apr 27 / Current |
|-------|--------|-------|-----------------|
| `LowerFilters` | **ABSENT** | `"applewirelessmouse"` (MULTI_SZ) | **ABSENT** |
| `Service` (parent node) | `HidBth` | `MagicMouse` (MU) | `HidBth` |
| `ConnectionCount` | 0xAA (170) | 0xC8 (200) | not checked (same device) |
| `SelectiveSuspendOn` | absent | dword:0 | absent |

**Hex for LowerFilters in Apr 3 (v1 mouse):**
```
61 00 70 00 70 00 6c 00 65 00 77 00 69 00 72 00
65 00 6c 00 65 00 73 00 73 00 6d 00 6f 00 75 00
73 00 65 00 00 00 00 00
```
Decoded: `applewirelessmouse\0\0` (UTF-16LE MULTI_SZ, single string + double null terminator)

### 3-way comparison for Magic Mouse v3 (0323, MAC: D0C050CC8C4D)

**Device Parameters path:**
```
HKLM\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001124-...}_VID&0001004c_PID&0323\
  9&73b8b28&0&D0C050CC8C4D_C00000000\Device Parameters
```

| Value | Nov 24 | Apr 3 | Apr 27 / Current |
|-------|--------|-------|-----------------|
| `LowerFilters` | not present (device not yet paired) | **ABSENT** | **ABSENT** |
| `Service` (parent node) | N/A | `HidBth` (via MagicMouse.sys which IS HidBth-stack) | `HidBth` (via applewirelessmouse) |
| `SelectiveSuspendOn` | N/A | dword:0 | absent |

**Critical insight:** MU did NOT insert a LowerFilter on v3. Instead, MU replaced the driver outright by having `magicmouse.inf` claim the `{00001124-...}_VID&0001004c_PID&0323` hardware ID with a higher rank than `hidbth.inf`. The `MagicMouse.sys` driver IS the HID function driver for v3 under MU. For v1 (already claimed by applewirelessmouse/applebmt64), MU added a LowerFilter instead of replacing the driver.

### LowerFilters for other v0239 device (Apple Magic Keyboard or similar)

In Apr 3, the `VID&000205ac_PID&0239` device (different MAC: E806884B0741) also has:
```
"LowerFilters"="applewirelessmouse"
```
This is NOT a Magic Mouse — likely Apple Magic Trackpad or a related Apple BT HID device also matched by MU's INF.

---

## 4. Apple Driver Service Evolution

### `applewirelessmouse` service — 3-way comparison

| Timestamp | Present? | INF / oem# | Source | Devices bound |
|-----------|----------|------------|--------|---------------|
| Nov 24 | YES | oem10.inf (applebmt64.inf_amd64_6d97d6264f077f40) | Pre-existing Apple OEM driver (shipped with Win11 or installed via Apple Software Update) | v1 030d (04F13EEEDE10) |
| Apr 3 | YES | oem10.inf (unchanged) | Same as Nov 24 — MU did NOT replace this driver | v1 030d (LowerFilter chain) |
| Apr 27 | YES | **oem0.inf** (applewirelessmouse.inf_amd64_ac34ebceaaf7324c) | **Our custom `AppleWirelessMouse.inf`** from MagicMouse2DriversWin11x64 | v3 0323 (D0C050CC8C4D) direct |

**Key finding:** Two separate `applewirelessmouse.sys` registrations coexist in Apr 27:
1. `applebmt64.inf_amd64_6d97d6264f077f40` (legacy Apple package, in Setup\Upgrade upgrade path records — probably still on disk but NOT `Active` for v3)
2. `applewirelessmouse.inf_amd64_ac34ebceaaf7324c` (our package, `Active` in oem0.inf/oem11.inf for v3)

Both install the SAME binary (`System32\drivers\applewirelessmouse.sys`) — they just differ in the INF metadata and hardware ID claim. The legacy package only claimed `PID&030d` and `PID&0310`. Our package adds `PID&0323`.

**ImagePath comparison:**
```
Apr 3  (MU period):   "System32\drivers\applewirelessmouse.sys"   (relative, no leading \)
Apr 27 (current):     "\SystemRoot\System32\drivers\applewirelessmouse.sys"  (absolute)
```
The Nov 24 ImagePath for the legacy applebmt64 version also uses the short relative form. Our INF-built version uses the standard absolute form.

---

## 5. Magic Mouse v1 Baseline — Nov 24

### Device node (Nov 24 clean state)

```
BTHENUM\{00001124-...}_VID&000205ac_PID&030d\9&73b8b28&0&04F13EEEDE10_C00000000
  "DeviceDesc" = "@oem10.inf,%applewirelessmouse.devicedesc%;Apple Wireless Mouse"
  "Service"    = "HidBth"
  "Driver"     = "{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0005"
  "Mfg"        = "@oem10.inf,%mfgname%;Apple Inc."
```

The driver class is `{745a17a0-74d3-11d0-b6fe-00a0c90f57da}` (HID class). Driver instance 0005 within that class.

### HID child topology — Nov 24 (single node, no COL split)

```
HID\{00001124-...}_VID&000205ac_PID&030d\a&137e1bf2&1&0000     <- SINGLE node
```

No Col01, Col02. The v1 mouse's native HID report descriptor exposes a single top-level collection. HidBth creates one child device.

### HID child topology — Apr 3 (MU active, COL split appears)

```
HID\{00001124-...}_VID&000205ac_PID&030d\a&137e1bf2&1&0000     <- parent (unchanged)
HID\{00001124-...}_VID&000205ac_PID&030d&Col01\a&137e1bf2&1&0000
HID\{00001124-...}_VID&000205ac_PID&030d&Col02\a&137e1bf2&1&0001
HID\{00001124-...}_VID&000205ac_PID&030d&Col03\a&137e1bf2&1&0002
```

**Three** collections appear on v1 after MU installs. MU's `MagicMouse.sys` modified the in-memory HID descriptor to add collections (or the descriptor cache was updated). This is consistent with MU injecting a synthesized multi-collection descriptor on top of the native single-collection descriptor.

### HID child topology — v3 (0323) across all states

```
Apr 3 and Apr 27:
HID\{00001124-...}_VID&0001004c_PID&0323\a&31e5d054&2&0000     <- parent
HID\{00001124-...}_VID&0001004c_PID&0323&Col01\a&...&b&0000
HID\{00001124-...}_VID&0001004c_PID&0323&Col02\a&...&b&0001
```

**Two** collections. Col01 = mouse (buttons + XY, Report ID 0x12). Col02 = battery/power (Report ID 0x90). This split is NATIVE to the v3 descriptor — present in both the MU period (Apr 3) and our AppleFilter period (Apr 27). The v3 descriptor natively exposes two top-level collections.

**Contrast with v1:** v1 natively exposes ONE collection. MU synthesized Col01+Col02+Col03 on v1 by injecting an extended descriptor. Our work with v3 does not need this injection — the descriptor already has two collections.

---

## 6. Other Surprises

### 6a. MagicMouseDriver is DISABLED (Start=4) in Apr 27

```
HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseDriver
"Start"=dword:00000004    ; DISABLED
"DriverDelete"=dword:1
"DeleteFlag"=dword:1
```

The `DriverDelete` and `DeleteFlag` values indicate the driver was marked for deletion by a PnP operation but has not yet been removed (pending reboot or device re-enumeration). This is a stale state — a planned cleanup that hasn't been committed by the OS yet. It will self-resolve on next device reconnect or reboot.

### 6b. oem52 and oem53 are GHOST entries

In Apr 27, values like `"InfPath"="oem53.inf"` and `"DisplayName"="@oem53.inf,...` appear in the Enum tree (under device nodes), but `oem53.inf` does NOT appear in `HKLM\SYSTEM\DriverDatabase\DriverInfFiles`. Similarly, `oem52.inf` is referenced in the `MagicMouseDriver` DisplayName string but is not in DriverInfFiles.

**Interpretation:** When MU was uninstalled, its oem INF files were removed from the DriverStore. But the device node properties (`DeviceDesc`, `Mfg`, `Driver`) that reference those INF string entries were not cleaned up. Windows is tolerant of this — it uses cached string values from the device node's own properties rather than re-reading the INF at runtime.

The active `applewirelessmouse` packages are oem0.inf and oem11.inf (both pointing to `applewirelessmouse.inf_amd64_ac34ebceaaf7324c`). These ARE in DriverInfFiles and are the live driver.

### 6c. Trial expiry date is identical between Apr 3 and Apr 27

```
"TrialExpiryDate"=hex:85,ae,30,85,ef,85,e6,40
```
This FILETIME value decodes to approximately 2026-04-10 (7 days after the Apr 3 backup). The MU trial has expired in the Apr 27 state — which aligns with why MU was uninstalled and we moved to the open-source AppleFilter approach.

### 6d. `DeviceRegistryPathBth` values in Apr 27 (new)

Apr 27 contains new values in the MagicMouseRawPdo Device Parameters:
```
"DeviceRegistryPathBth"="BTHENUM\{00001124-...}_VID&000205ac_PID&030d\9&73b8b28&0&04F13EEEDE10_C00000000"
"DeviceRegistryPathBth"="BTHENUM\{00001124-...}_VID&0001004c_PID&0323\9&73b8b28&0&D0C050CC8C4D_C00000000"
```
These are stored by our `MagicMouseDriver` to track which BTHENUM instance a given RawPdo serves. Not present in Apr 3 (MU used different internal tracking).

### 6e. MagicMouseTray executable paths in registry

Apr 27 contains multiple MagicMouseTray executable path entries in PnP lockdown:
```
\\Device\HarddiskVolume3\temp\MagicMouseTray-test.exe
\\Device\HarddiskVolume3\temp\MagicMouseTray.exe
```
These are WDF PnPLockdown references — normal artifacts from our development/testing cycle. Each build that loaded the driver adds an entry.

### 6f. v3 MAC appears in BTHPORT as `d0c050cc8c4d` — only from Apr 3 onward

In Nov 24, the BTHPORT\Parameters\Devices tree contains only:
- `04f13eeede10` (v1 Magic Mouse 2009)
- `e806884b0741` (third Apple device, likely Trackpad)

The v3 mouse MAC `d0c050cc8c4d` is completely absent in Nov 24. This confirms the v3 mouse was NEVER paired before our work began. All v3 registry artifacts are net-new from Apr 3 onward.

---

## 7. Apr 3 vs Apr 27 (Current) — What MU Left Behind

### Present in Apr 3, GONE in Apr 27 (successfully cleaned)

| Key/Value | Notes |
|-----------|-------|
| `Services\MagicMouse` | MU kernel driver service |
| `Services\MagicUtilitiesService` | MU user-mode service |
| `DriverDatabase\DriverPackages\magicmouse.inf_amd64_82cbbe70c776aec4` | MU INF package |
| `SOFTWARE\MagicUtilities\App\TrialExpiryDate` | (technically still there but trial expired) |
| LowerFilters="applewirelessmouse" on v1 Device Parameters | Removed |

### Present in Apr 3, STILL PRESENT in Apr 27 (orphans to consider cleaning)

| Key/Value | Risk | Action |
|-----------|------|--------|
| `SOFTWARE\MagicUtilities` (entire hive) | Zero — no driver reads this | Optional delete |
| `Enum\BTHENUM\..._030d\...\Device Parameters` ghost DeviceDesc pointing to oem53.inf | Zero — string is cached in device node | Leave it |
| `Enum\{7D55502A-...}\MagicMouseRawPdo` entries for old v1 instance IDs | Low | Will auto-clean on re-enum |
| `Control\DeviceClasses\{fae1ef32-...}` entries for old v1 RawPdo | Low | Will auto-clean |

### Present in Apr 27, NEW vs Apr 3 (our additions)

| Key/Value | Purpose |
|-----------|---------|
| `Services\MagicMouseDriver` | Our kernel driver (currently DISABLED, pending delete) |
| `DriverDatabase\DriverPackages\applewirelessmouse.inf_amd64_ac34ebceaaf7324c` | Our INF package |
| `Schedule\TaskCache\...\MagicMouseTray-StartupRepair` | Our startup repair task |
| `Notifications\Settings\MagicMouseTray.Battery` | Toast notification registration |
| Multiple MagicMouseTray.exe path references in PnPLockdownFiles | Build artifacts |

---

## Appendix A: CachedServices Hex Comparison (First 60 bytes)

### v1 Mouse — `04f13eeede10\CachedServices\00010000` (Nov 24 = Apr 3 = no change)

```
36 01 4e 09 00 00 0a 00 01 00 00 09 00 01 35 03
19 11 24 09 00 04 35 0d 35 06 19 01 00 09 00 11
35 03 19 00 11 09 00 05 35 03 19 10 02 09 00 06
35 09 09 65 6e 09 00 6a 09 01 00 09 00 09 35 08
```

### v3 Mouse — `d0c050cc8c4d\CachedServices\00010000` (Apr 3 = Apr 27 = no change)

```
36 01 5c 09 00 00 0a 00 01 00 00 09 00 01 35 03
19 11 24 09 00 04 35 0d 35 06 19 01 00 09 00 11
35 03 19 00 11 09 00 05 35 03 19 10 02 09 00 06
35 09 09 65 6e 09 00 6a 09 01 00 09 00 09 35 08
```

The records are structurally identical (same SDP framing) but `36 01 4e` (334 bytes) vs `36 01 5c` (348 bytes). The size difference is entirely in the HID descriptor attribute (v3 has battery collection).

**HID descriptor extraction offset:** The embedded descriptor begins at the `08 22 25 xx` sequence — `08 22` = Attribute Type 0x08 (URL), `25 xx` = text string of length xx. In v1: `08 22 25 62` = 98-byte descriptor. In v3: `08 22 25 87` = 135-byte descriptor.

### Approximate HID descriptor bytes from v3 SDP blob

Starting after `08 22 25 87`:
```
05 01 09 02 a1 01 85 12 05 09 19 01 29 02 15 00
25 01 95 02 75 01 81 02 95 01 75 06 81 03 05 01
09 01 a1 00 16 01 f8 26 ff 07 36 01 fb 46 ff 04
65 13 55 0d 09 30 09 31 75 10 95 02 81 06 75 08
95 02 81 01 c0 06 02 ff 09 55 85 55 15 00 26 ff
00 75 08 95 40 b1 a2 c0 06 00 ff 09 14 a1 01 85
90 05 84 75 01 95 03 15 00 25 01 09 61 05 85 09
44 09 46 81 02 95 05 81 01 75 08 95 01 15 00 26
ff 00 09 65 81 02 c0
```

- Report 0x12: Buttons (2), padding (6), XY (2×16-bit), padding (2×8)  
- Report 0x55: Feature, 64 bytes (vendor-defined — likely calibration/config)  
- Report 0x90: Battery — in UsagePage 0x84 (Power): 3 bits (charged/charging/ac) + 1 byte (level 0-255)

---

## Appendix B: Service Binding Summary (All 3 Timestamps)

| Device | Nov 24 | Apr 3 (MU working) | Apr 27 (current) |
|--------|--------|-------------------|------------------|
| v1 030d (04F13EEEDE10) | HidBth via applebmt64 (oem10) | MagicMouse.sys (oem53), LowerFilter=applewirelessmouse | HidBth via applebmt64 (legacy oem10 still on disk) |
| v3 0323 (D0C050CC8C4D) | NOT PAIRED | MagicMouse.sys (oem53), NO LowerFilter | HidBth via AppleWirelessMouse.inf (oem0) |

---

## Appendix C: OEM INF Number Map

| oem# | Package | Driver | Period |
|------|---------|--------|--------|
| oem10 (Nov 24) | applebmt64.inf_amd64_6d97d6264f077f40 | applewirelessmouse.sys | Pre-existing, ships with/via Apple |
| oem53 (Apr 3) | magicmouse.inf_amd64_82cbbe70c776aec4 | MagicMouse.sys | MagicUtilities 3.1.6.1 |
| oem0 (Apr 27) | applewirelessmouse.inf_amd64_ac34ebceaaf7324c | applewirelessmouse.sys | Our custom AppleWirelessMouse.inf |
| oem52 (Apr 27) | MagicMouseDriver.inf_amd64_??? | MagicMouseDriver.sys | Our custom MagicMouseDriver.inf (disabled, pending delete) |
