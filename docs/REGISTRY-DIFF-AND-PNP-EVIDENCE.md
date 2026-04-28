# Registry diff (Nov 2025 → Apr 03 → Apr 27 → Today) + PnP enumeration evidence

**Purpose:** show side-by-side what changed in the registry across the three Apple-driver regimes the system has been through, plus prove that COL02 (vendor 0xFF00 TLC, where battery actually lives) is no longer being enumerated as an active PDO.

**Sources:**
- `2025-11-24 - Windows11_registry-backup.reg` (344 MB UTF-16LE)
- `2026-04-03 - Windows11_registry-backup.reg` (404 MB UTF-16LE)
- `2026-04-27 - Windows11_registry-backup.reg` (439 MB UTF-16LE)
- Live state: `devmgr-dump-*.json`, `pnp-topology.txt` snapshots, `bt-battery-probe.txt`

---

## Part 1 — Filter regimes side-by-side

| Field | 2025-11-24 | 2026-04-03 | 2026-04-27 morning | Today (04-28) |
|---|---|---|---|---|
| Bootcamp `AppleBMT` service | YES (8 reg blocks) | YES (6 blocks, residual) | RESIDUAL (3 strings only) | unknown |
| `MagicMouse` service (Magic Utilities) | no | **YES (8 blocks, ACTIVE)** | RESIDUAL (59 strings — driver still in registry) | RESIDUAL |
| `MagicMouseDriver` service (Magic Utilities renamed) | no | no | **YES (8 blocks, ACTIVE)** | unknown |
| `applewirelessmouse` service (Apple, MS-distributed) | YES (13 strings, dormant) | YES (2 stub blocks, dormant) | **YES (8 blocks, ACTIVE)** | **YES (active)** |

## Part 2 — `MagicMouse` service registry block (April 3, 2026 — when v3 worked)

```
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\MagicMouse]
"Type"=dword:00000001                       ← SERVICE_KERNEL_DRIVER
"Start"=dword:00000003                       ← SERVICE_DEMAND_START
"ErrorControl"=dword:00000001
"ImagePath"="…System32\drivers\MagicMouse.sys"
"DisplayName"="@oem53.inf,%Service.Desc%;Magic Mouse Service"
"Owners"=oem53.inf
"Group"=""

[HKEY_LOCAL_MACHINE\…\MagicMouse\Parameters\Wdf]
"KmdfLibraryVersion"="1.15"
"WdfMajorVersion"=dword:00000001
"WdfMinorVersion"=dword:0000000f

[HKEY_LOCAL_MACHINE\…\MagicMouse\Enum]
"Count"=dword:00000002
"NextInstance"=dword:00000002
"0"="BTHENUM\\{00001124-…}_VID&000205ac_PID&030d\\9&73b8b28&0&04F13EEEDE10_C00000000"   ← v1 mouse
"1"="BTHENUM\\{00001124-…}_VID&0001004c_PID&0323\\9&73b8b28&0&D0C050CC8C4D_C00000000"  ← v3 mouse !!
```

**This proves Magic Utilities WAS bound to v3 mouse in April 2026.** Two devices in the Enum list: v1 and v3.

## Part 3 — `applewirelessmouse` service block (today)

```
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\applewirelessmouse]
"Type"=dword:00000001                       ← SERVICE_KERNEL_DRIVER
"Start"=dword:00000003                       ← SERVICE_DEMAND_START
"ErrorControl"=dword:00000000                ← SERVICE_ERROR_IGNORE (looser than MagicMouse=1)
"ImagePath"="\SystemRoot\System32\drivers\applewirelessmouse.sys"
"DisplayName"="@oem0.inf,%AppleWirelessMouse.SvcDesc%;Apple Wireless Mouse"
"Owners"=oem0.inf | *                        ← multi-INF ownership

\applewirelessmouse\Parameters       (subkey exists, EMPTY — no tunables)
\applewirelessmouse\Enum:
  Count        = 2
  NextInstance = 2
  0 = BTHENUM\{...}_VID&0001004c_PID&0323\...D0C050CC8C4D...   (v3 mouse)
  1 = BTHENUM\{...}_VID&000205ac_PID&030d\...04F13EEEDE10...   (v1 mouse)
```

**Difference from MagicMouse:** applewirelessmouse has `Owners=oem0.inf | *` (the `| *` means "any INF can claim ownership"), `ErrorControl=0` (loosest — failures are silent), no Group, identical Parameters layout.

**Critical:** applewirelessmouse Parameters is EMPTY in both eras (04-03 stub and today). There's no per-driver registry tunable to influence behavior.

## Part 4 — v3 mouse Device Parameters comparison

For `HKLM\…\Enum\BTHENUM\{HID profile}_VID&0001004C_PID&0323\…\Device Parameters`:

| Value | 2026-04-03 (v3 working) | 2026-04-27 morning | Today (broken) |
|---|---|---|---|
| `LowerFilters` | `MagicMouse` | `MagicMouse` then `applewirelessmouse` (multi-update) | `applewirelessmouse` |
| `Service` | `HidBth` | `HidBth` | `HidBth` |
| `SelectiveSuspendEnabled` | 0 | 0 | 0 |
| `EnhancedPowerManagementEnabled` | 1 | 1 | 1 |
| `AllowIdleIrpInD3` | 1 | 1 | 1 |
| `DeviceResetNotificationEnabled` | 1 | 1 | 1 |
| `LegacyTouchScaling` | 0 | 0 | 0 |

The ONLY structural change: `LowerFilters` value name (which filter is loaded). All other power/PnP knobs are identical.

## Part 5 — PnP enumeration evidence: COL02 active vs. orphan

Three snapshots of the v3 mouse's PnP child tree, taken at three points in time:

### 2026-04-27 14:41:56 (afternoon, before reboot)

```
Status  Class     FriendlyName                        InstanceId
------  -----     ------------                        ----------
Unknown HIDClass  HID-compliant vendor-defined device HID\…PID&0323&COL02\A&31E5D054&B&0001  ← orphan (B instance)
Unknown           Magic Mouse 3 USB device interface  {7D55502A-…}\MAGICMOUSERAWPDO\…
OK      Bluetooth Device Identification Service       BTHENUM\…PID&0323\…
OK      HIDClass  Apple Wireless Mouse                BTHENUM\…PID&0323\…
OK      Bluetooth Magic Mouse                         BTHENUM\DEV_D0C050CC8C4D\…
OK      Mouse     HID-compliant mouse                 HID\…PID&0323\A&31E5D054&B&0000   ← single Mouse PDO
Unknown Mouse     HID-compliant mouse                 HID\…PID&0323&COL01\A&31E5D054&B&0000  ← orphan
```

State: **Descriptor B** — single Mouse PDO active, COL01/COL02 children orphaned.

### 2026-04-27 17:59:03 (post-reboot, DURING the 96-OK-read window)

```
Status  Class     FriendlyName                        InstanceId
------  -----     ------------                        ----------
OK      Mouse     HID-compliant mouse                 HID\…PID&0323&COL01\A&31E5D054&C&0000   ← COL01 ACTIVE
OK      HIDClass  HID-compliant vendor-defined device HID\…PID&0323&COL02\A&31E5D054&C&0001   ← COL02 ACTIVE !!
OK      Bluetooth Device Identification Service       BTHENUM\…PID&0323\…
OK      HIDClass  Apple Wireless Mouse                BTHENUM\…PID&0323\…
OK      Bluetooth Magic Mouse                         BTHENUM\DEV_D0C050CC8C4D\…
Unknown Mouse     HID-compliant mouse                 HID\…PID&0323\A&31E5D054&C&0000   ← orphan (replaced by COL01+COL02)
```

State: **Descriptor A** — both COL01 (Mouse TLC) and COL02 (vendor 0xFF00 TLC) active. Tray successfully reads battery via `HidD_GetInputReport(0x90)` on COL02 path. **96 successful battery polls in this state.**

### 2026-04-28 14:12:10 (today)

From `bt-battery-probe.txt`:

```
[Unknown] [Mouse] HID\…PID&0323&COL01\A&31E5D054&C&0000           ← orphan
[Unknown] [HIDClass] HID\…PID&0323&COL02\A&31E5D054&C&0001        ← orphan (battery PDO not active!)
[OK] [Bluetooth] BTHENUM\…PID&0323\…                              ← active
[OK] [HIDClass] BTHENUM\…PID&0323\…                               ← active
  Child[Mouse]: HID\…PID&0323\A&31E5D054&C&0000                   ← single mouse PDO
[OK] [Bluetooth] BTHENUM\DEV_D0C050CC8C4D\…                       ← active
[OK] [Mouse] HID\…PID&0323\A&31E5D054&C&0000                      ← single mouse PDO (no col)
```

State: **Descriptor B** — back to single Mouse PDO. COL01 and COL02 both Status=Unknown (registered but no driver loaded).

### Summary of PnP enumeration evidence

| HID PDO | Pre-reboot 14:41 | DURING OK reads 17:59 | Today |
|---|---|---|---|
| `…&COL01\…` | Unknown (B) | **OK (C)** | Unknown (C, orphan) |
| **`…&COL02\…` (battery!)** | **Unknown (B)** | **OK (C, ACTIVE)** | **Unknown (C, orphan)** |
| `…\A&…` (single Mouse, no COL) | OK (B) | Unknown (C) | OK (C) |

The instance suffix tells us the COL02 PDO is the SAME instance (`&c&0001`) yesterday and today — it didn't disappear, it stopped enumerating. PnP knows it's there (it's in the device tree), but no driver is loaded against it.

## Part 6 — What changed between 17:59 and 14:12 today?

Per `pnp-eventlog.json` event 410 query for v3 BTHENUM, the LAST driver-bound event is **2026-04-27 15:56:37** with applewirelessmouse — there are NO events between 17:59 yesterday and 14:12 today in the Configuration log.

But per `bt-stack-snapshot.txt` analysis:
- The 19:43:45 → 20:13:45 window is when COL02 stopped responding to tray polls
- DSM (`Microsoft-Windows-DeviceSetupManager`) ran a property-write at 19:50:53 against device container `{fbdb1973-…}`
- The persistence-monitor.log captured "COL02 status: missing" starting 19:59:48

So the descriptor flipped between 19:50 and 19:59 — NOT logged as a PnP/Configuration event, only logged in tray and persistence-monitor. The change was a runtime state flip, not a registry mutation.

## Part 7 — Root-cause assessment

**Definitive findings:**
1. The registry on Apr 03 (when MagicMouse filter was bound) had `LowerFilters=MagicMouse`, and per Magic Utilities advertising v3 had functional battery+scroll then.
2. Today's registry has `LowerFilters=applewirelessmouse` and v3 is broken.
3. The applewirelessmouse driver binary has NO PID 0x0323 hardcoded. Its INF over-matched onto v3 but it doesn't have v3-specific logic.
4. Today's registry is IDENTICAL between Descriptor A (yesterday 17:59 working) and Descriptor B (now broken). **The registry value `LowerFilters=applewirelessmouse` doesn't change between the two states.** The state lives in the kernel, not registry.
5. The MagicMouse / applewirelessmouse Services\Parameters subkey is empty — no driver-tunable behavior.

**Therefore — there is no registry-level configuration change that fixes both battery AND scroll on v3 with the applewirelessmouse driver.** The filter binary's behavior with v3 is hardcoded.

**Three real fix options remain:**

| Option | Battery | Scroll | Effort | Reversible |
|---|---|---|---|---|
| Reinstall Magic Utilities (oem53.inf, MagicMouse.sys) | ✅ | ✅ | n/a — paid product, user has ruled out | trivial |
| Detect Descriptor B in tray + recycle to restore A | ✅ (intermittent) | ✅ | 1-2 days tray code | yes |
| Custom KMDF filter (M12) — replaces applewirelessmouse with v3-aware driver we build | ✅ | ✅ | 2-4 weeks (driver dev + signing) | yes |
| Userland scroll synth + remove applewirelessmouse from v3 LowerFilters | ✅ | ✅ (in tray) | 1-2 weeks tray code | yes |

The intrusive PnP recycle test (1 cycle, ~30 min) would empirically confirm option 2's recoverability. We have evidence it CAN restore Descriptor A but it's non-deterministic.

## Part 8 — Files in this analysis

```
docs/
└── REGISTRY-DIFF-AND-PNP-EVIDENCE.md   ← this file

.ai/test-runs/2026-04-27-154930-T-V3-AF/
├── regdiff/
│   ├── README.md
│   ├── 2025-11-24.extracted.txt        (52 BTHENUM/HID/Service blocks)
│   ├── 2026-04-03.extracted.txt        (106 blocks)
│   ├── 2026-04-27.extracted.txt        (78 blocks)
│   ├── 2025-11-24.services.txt         (AppleBMT × 8)
│   ├── 2026-04-03.services.txt         (AppleBMT × 6, MagicMouse × 8, applewirelessmouse × 2)
│   ├── 2026-04-27.services.txt         (MagicMouseDriver × 8, applewirelessmouse × 8)
│   └── SIDE-BY-SIDE-DIFF.md            (full 1381-line per-key drill-down)
├── snapshots/mm-state-…/pnp-topology.txt   (yesterday afternoon + post-reboot)
├── bt-battery-probe.txt                    (today's PnP tree)
├── pnp-eventlog.{txt,json}                 (138 PnP events 2025-11-24 → 2026-04-28)
├── E18-pnp-eventlog-narrative.md           (driver/filter timeline)
└── devmgr-dump-*.json                      (per-device DEVPKEY dumps)
```
