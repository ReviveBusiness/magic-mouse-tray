# NotebookLM deep research findings — Apple BT battery on Windows

**Run:** 2026-04-28 ~13:00
**Sources:** 150 (deep-research mode), notebook `bd78726f-814b-4f84-943e-0c653aadd896`
**Trigger:** User asked us to verify our approach against the open-source landscape.

---

## TL;DR — corrections to our prior assumptions

| Was | Now |
|---|---|
| "v3 battery requires applewirelessmouse filter to translate vendor 0x90" | **v3 battery is on an INPUT report (not Feature) at RID 0x90, byte 1, on the vendor TLC (UP=0xFF00, Usage=0x14). It's read via `HidD_GetInputReport`, not `HidD_GetFeature`. No filter needed for the read itself.** |
| "Apple filter traps Feature 0x47" | **err=87 on Feature 0x47 means the report ID exists in the LIVE descriptor (per `HidP_GetValueCaps`) but is not actually backed by the device. Source of the cap mismatch: filter previously mutated the descriptor and HidBth cached the mutation — even though filter isn't on stack now, HidBth still serves the mutated descriptor.** |
| "Three batteries (v1/v3/keyboard) all read via Feature 0x47" | **Two pathways**: v1+keyboard use **Feature 0x47** (UP=0x06 standard) — `HidD_GetFeature`. v3 uses **Input 0x90** on vendor TLC (UP=0xFF00) — `HidD_GetInputReport`. Different code paths. |
| "AirPods Pro out of scope" | **Confirmed** out of HID scope. Use BLE Advertisement listening (Apple Co. ID 0x004C, 0x07 prefix, nibbles in bytes 6–7). WinRT `BluetoothLEAdvertisementWatcher` API. Separate subsystem entirely. |
| "Tray polls every 5 min when uncertain" | **Magic Utilities polls every 15 min**. Faster polling causes 10–50ms scroll stutters because GetReport over the HID control pipe pauses the interrupt pipe. Our cadence may be aggressive. |

---

## Three battery channels (industry consensus from 150-source synthesis)

| Channel | Used by | Mechanism | Win API | Privilege |
|---|---|---|---|---|
| **BLE Manufacturer Data** (Co. ID 0x004C, 0x07 prefix) | AirPods, Beats — modern audio | Passive advertisement listening; no connection | WinRT `BluetoothLEAdvertisementWatcher` | None (passive) |
| **GATT Battery Service** (UUID 0x180F, char 0x2A19) | Modern BLE keyboards (M3/Touch ID) | Active GATT read or notify-subscribe | Windows.Devices.Bluetooth | Often blocked by exclusive lock |
| **HID Feature/Input Report** (Classic BT BR/EDR) | Magic Mouse v1+v3, Magic Keyboard | `HidD_GetFeature` or `HidD_GetInputReport` | hid.dll | Often admin |

Three repos that target HID Feature path (closest reference for us):
- **WinMagicBattery** (C# .NET 8, hank1101444) — closest match to our architecture
- **martinsoft/magic-battery-checker** — CLI Magic Mouse/Keyboard battery
- **alberti42/Magic-Warnings** — low-battery alert app
- **mac-precision-touchpad** (imbushuo) — alternative kernel driver to applewirelessmouse

## v3 Magic Mouse (PID 0x0323) battery — ACTUAL mechanism

Per source synthesis (sources [8], [10], [11] in the report):

```
Vendor TLC: Usage Page 0xFF00, Usage 0x0014, Collection 0x01 (Application)
ReportID 0x90 (Input, NOT Feature)
Byte 0: ReportID (0x90)
Byte 1: Charging Status (3-bit bitfield: AC, Charging, etc.) + 5 padding bits
Byte 2: Battery Percentage (0-100, AbsoluteStateOfCharge usage 0x65)
```

**Access**: open the HID device interface at the vendor TLC (a separate child PDO at COL02 in PnP terms), then call `HidD_GetInputReport`.

This matches our v3 SDP cache descriptor exactly (we decoded it correctly the first time). The tray's existing `splitVendorBattery` code path (lines 165–204 of `MouseBatteryReader.cs`) DOES handle this correctly — it expects `caps.UsagePage == 0xFF00 AND caps.Usage == 0x14`, and uses `HidD_GetInputReport`.

**The bug**: with `applewirelessmouse` historically bound on the v3 stack, HidBth cached a MUTATED descriptor where the vendor TLC was stripped and Feature 0x47 was added to the Mouse TLC. Without the filter on stack now, HidBth still serves the mutated descriptor. The tray sees the "Apple unified" Feature 0x47 cap, calls `HidD_GetFeature(0x47)`, gets err=87 because the device doesn't actually serve that report. The vendor TLC (where battery actually lives) is **not enumerated** as a child PDO.

**Test of this hypothesis**: PnP recycle the v3 mouse (Disable+Enable BTHENUM PDO) WITHOUT the filter binding kicking in. HidBth would re-fetch the descriptor and get the original (with vendor TLCs). The vendor 0xFF00 TLC would enumerate as a separate HID interface. The tray's `splitVendorBattery` path would activate. Battery would be readable WITHOUT THE FILTER.

This would invalidate Phase 4-Ω entirely — we wouldn't need to bind the filter. We'd just need to recycle the device once after filter cleanup.

## v1 Magic Mouse (PID 0x030D) battery — VERIFIED

```
Mouse TLC: ReportID 0x10
Standard Generic Device Battery Strength: ReportID 0x47 Feature
Byte 0: ReportID (0x47)
Byte 1: Battery Strength (0-100)
```

`HidD_GetFeature(0x47)` on the Mouse HID interface. Already working — tray reads 100%.

## Apple Keyboard (PID 0x0239) battery — INFERRED PATTERN MATCH

Same standard mechanism as v1 mouse. Descriptor declares Feature 0x47 (UP=0x06, U=0x20). Apply tray's existing unified-apple code path with keyboard-class enumeration.

## AirPods Pro (PID 0x2024) — different subsystem

```
BLE Manufacturer Data (AD Type 0xFF, Apple Co. ID 0x004C):
Byte 0: 0x07 (Proximity Pairing Message prefix)
Byte 1: 0x19 (length)
Byte 2: Pairing Mode (0x01=paired)
Byte 3-4: Device Model (big-endian PID)
Byte 5: Status bitfield
Byte 6: Pod battery (high nibble = Left, low nibble = Right; nibble × 10 = %)
Byte 7: Case battery (high nibble = case %, low nibble = flags)
```

Requires WinRT API (no admin, passive listener). Not currently in mm-tray scope.

## Scroll-vs-battery contention — the right cadence

> When a project like WinMagicBattery calls HidD_GetFeature, the Windows HID class driver (mshid.sys) must pause the interrupt pipe to send a GET_REPORT request on the control pipe. Because the Magic Mouse firmware is optimized for high-speed touch reporting, this interruption can cause a 10-50ms "hang" in touch processing.

Magic Utilities defaults to **15-minute** intervals; community drivers use "Quiet Time" (poll only after touch idle ≥15 min). Our adaptive poller runs at 5-min intervals when battery state is uncertain, 30-min when low, 2-hour when fine. **We should consider extending the uncertain interval to 15 min** to avoid contention-induced scroll stutter (a known issue per [22]).

## Updated Phase E results

| # | Test | Result after research |
|---|---|---|
| E1/E2 (Stop-Service) | Service can't be stopped while bound to keyboard PDO | Still blocked, but **less important now** — research suggests filter may be irrelevant to the v3 battery problem; the bug is the cached mutated descriptor. |
| E3 (Keyboard battery) | DEVPKEY empty, Feature 0x47 read wedges due to kbdhid lock | Inferentially confirmed — keyboard descriptor + INF parity with v1; needs tray-side polling to verify byte. |
| E4 (v3 recycle) | Not yet run | **NOW MOST IMPORTANT** — test the hypothesis that recycle restores the unmutated descriptor and exposes the vendor TLC as a separate enumerated HID child. |
| E5 (filter-bound vs unbound) | Not yet run | Less important — if E4 confirms filter-free path works, filter is unnecessary. |
| E6 (source audit) | Done — log message mis-attributed | Confirmed. Logger string needs rewording. |
| E7c (driver static analysis) | Done — no v3 PID hardcoded in binary | Confirmed. Filter is v1/Trackpad-era code, INF over-matched onto v3. |

## Next-step proposal — revised Phase E

1. **Capture the v3 LIVE descriptor right now** — write a small probe that calls `HidD_GetPreparsedData` + `HidP_GetCaps` + manual walk of preparsed bytes, dumps the FULL runtime descriptor. Compare to SDP cache. This proves whether the runtime is mutated.

2. **Test Disable+Enable v3 BTHENUM** — IF filter is NOT bound at the moment of recycle (current state), HidBth should re-fetch and get the original descriptor. Vendor TLC should enumerate as a child. Tray's existing `splitVendorBattery` path should activate. Battery byte reads via `HidD_GetInputReport(0x90)`.

3. **If (2) succeeds** → Phase 4-Ω is unnecessary. The fix is: clean up keyboard's stale LowerFilter ref (task #26), recycle v3 once, tray reads battery natively from the vendor TLC. Filter is permanently abandonable.

4. **Code changes implied**:
   - `MouseBatteryReader.cs` line 225: rewrite log string from "Apple driver traps Feature 0x47; needs custom KMDF filter" to something accurate ("Feature 0x47 declared in cap table but device does not back it; runtime descriptor is mutated remnant of prior filter binding").
   - Add keyboard class enumeration (task #31) — Feature 0x47 standard path.
   - Optional: extend AdaptivePoller intervals to match Magic Utilities cadence.
   - Optional: AirPods battery via BLE adv (separate subsystem; out of current scope).

## Open questions (post-research)

| # | Question | How to answer |
|---|---|---|
| Q1 | Is HidBth's cached descriptor refreshed by Disable+Enable on the BTHENUM PDO? | E4 test |
| Q2 | After recycle without filter, does the vendor 0xFF00 TLC enumerate as a separate HID child? | E4 + PnP enum check |
| Q3 | Is the keyboard's stale LowerFilter ref in HKLM only or does it have a per-user variant? | Registry sweep |
| Q4 | Was our earlier multi-decode of v3 cache wrong about `(85, 65282, 85)` Feature mapping? Probably yes — the parser tagged things misleadingly | Re-walk done; correct picture in this doc |

## Source quality

The deep-research synthesis was thorough. 150 sources, 27 with substantive technical detail. Notable reference projects:
- AirPodsDesktop (BLE adv path, robust)
- WinMagicBattery (C#, our closest analog)
- mac-precision-touchpad (alternative driver)
- linux/drivers/hid/hid-magicmouse.c (the canonical reference)
- librepods/Proximity Pairing Message.md (BLE adv format spec)
