# Descriptor A vs Descriptor B — empirical diff

**Source data:**
- Descriptor A: tray debug.log lines `HIDP_CAPS path=…&col01…` and `HIDP_CAPS path=…&col02…` from 2026-04-27 18:43:44 (during the 96-OK-read window)
- Descriptor B: probe output from 2026-04-28 16:30 (`battery-everything-probe.txt`) and tray debug.log lines `HIDP_CAPS path=…&pid&0323#…` (no col suffix) from 2026-04-27 20:13:45 onward
- Filter on stack in BOTH cases: `applewirelessmouse` (LowerFilters), per `bt-stack-snapshot.txt` (yesterday post-reboot) and `devmgr-dump-v3-bthenum.json` (today)

---

## A. PnP enumeration tree (parent's children)

### Descriptor A — TWO HID interfaces enumerated under v3 BTHENUM HID PDO

```
BTHENUM\…PID&0323\…D0C050CC8C4D_C00000000           [OK, HIDClass]   ← parent BTHENUM HID PDO
├── HID\…PID&0323&COL01\A&31E5D054&C&0000           [OK, Mouse]      ← Mouse TLC interface
└── HID\…PID&0323&COL02\A&31E5D054&C&0001           [OK, HIDClass]   ← Vendor 0xFF00 TLC (battery!)
```

### Descriptor B — ONE HID interface enumerated

```
BTHENUM\…PID&0323\…D0C050CC8C4D_C00000000           [OK, HIDClass]   ← parent (SAME)
└── HID\…PID&0323\A&31E5D054&C&0000                 [OK, Mouse]      ← combined Mouse TLC, NO col suffix

(orphans — registered but Status=Unknown):
   HID\…PID&0323&COL01\A&31E5D054&C&0000             [Unknown]
   HID\…PID&0323&COL02\A&31E5D054&C&0001             [Unknown]
```

The COL01 and COL02 PDOs **still exist in the registry** (in `…\Control\DeviceContainers\{fbdb1973-…}\BaseContainers`) but PnP doesn't actively enumerate them as children of the parent.

---

## B. HIDP_GetCaps comparison

| Field | Descriptor A — COL01 | Descriptor A — COL02 | **Descriptor B — single TLC** |
|---|---|---|---|
| TLC UsagePage | 0x0001 (Generic Desktop) | **0xFF00 (Apple Vendor Battery)** | 0x0001 (Generic Desktop) |
| TLC Usage | 0x0002 (Mouse) | 0x0014 (vendor battery) | 0x0002 (Mouse) |
| InputReportByteLength | 8 | **3** | **47** ← much bigger |
| FeatureReportByteLength | **65** | 0 | **2** ← much smaller |
| OutputReportByteLength | (n/a) | (n/a) | 0 |

### What the InLen/FeatLen tell us about each variant

**Descriptor A — COL01 (Mouse TLC):**
- `InLen=8`: ReportID(1) + buttons(1) + X(2) + Y(2) + padding = ~6-8 bytes for the standard mouse input report 0x12.
- `FeatLen=65`: ReportID(1) + 64-byte touchpad-mode Feature 0x55 (UP=0xFF02). Matches our SDP cache decode exactly — Feature 0x55 with ReportCount 0x40 (64 bytes).

**Descriptor A — COL02 (Vendor Battery TLC):**
- `InLen=3`: ReportID 0x90 (1) + flags byte (1) + battery percentage byte (1). Matches the SDP cache decode of the vendor 0xFF00 TLC.
- `FeatLen=0`: vendor TLC has no Feature reports.

**Descriptor B — single combined TLC:**
- `InLen=47`: that's much bigger than any single SDP-cached input report (the cached descriptor's largest input is 11 bytes). The 47 bytes likely contains **raw touch-surface data** (multi-finger touches × ~10 bytes each + position + buttons + padding). This is the "raw touchpad" data the filter would normally translate into wheel events at the input layer.
- `FeatLen=2`: phantom Feature 0x47 — ReportID(1) + battery percent(1). Cap exists but reads return err=87.
- **Vendor TLCs (0xFF00 + 0xFF02) NOT exposed.** Descriptor A had them as separate interfaces; Descriptor B has nothing equivalent.

---

## C. Inferred descriptor structure

### Descriptor A (real device descriptor, faithful to SDP cache)

```
Application Collection (Mouse, UP=0x01 U=0x02)
  ReportID 0x12
  Input: buttons + X + Y                                 ← 8-byte mouse input
  Feature 0x55 Vendor 0xFF02                              ← 64-byte touchpad mode (Application sub-collection)
End

Application Collection (Vendor Apple Battery, UP=0xFF00 U=0x14)
  ReportID 0x90
  Input: flags + AbsoluteStateOfCharge percentage         ← 3-byte battery input
End
```

Two TLCs → two HID interfaces enumerated → tray's `splitVendorBattery` code path activates on COL02 → `HidD_GetInputReport(0x90)` returns `[reportID, flags, pct]` → battery byte at offset 2.

### Descriptor B (filter-mutated)

```
Application Collection (Mouse, UP=0x01 U=0x02)
  ReportID ?? (one or more)
  Input: 47 bytes of merged data (likely raw touch + buttons + position)
  Feature 0x47 Generic Device Battery Strength            ← phantom; device returns err=87
  Feature 0x55 Vendor 0xFF02                              ← preserved? not certain (FeatLen=2 says no, but the filter could be expressing 0x55 separately)
End

(no vendor TLCs)
```

One TLC → one HID interface → tray sees `unified-apple Feature 0x47` cap → calls `HidD_GetFeature(0x47)` → device doesn't back the report → err=87.

---

## D. Critical differences summarized

| Aspect | Descriptor A | Descriptor B |
|---|---|---|
| # of TLCs (HID interfaces) | **2** | **1** |
| Vendor 0xFF00 battery TLC exposed | **YES** (as COL02) | **NO** (stripped) |
| Vendor 0xFF02 touchpad-mode TLC exposed | **YES** (as COL01 Feature 0x55, FeatLen=65) | maybe (FeatLen=2 doesn't fit; may be hidden) |
| Standard Feature 0x47 (UP=0x06 BatteryStrength) | NO (not declared) | **YES, but phantom** (err=87) |
| Mouse InputReportByteLength | 8 (small, just X/Y/buttons) | **47 (large, raw touch-surface data)** |
| Battery readable via HID API | YES — `HidD_GetInputReport(0x90)` on COL02 | **NO** — every channel returns nothing (588 attempts, 0 hits) |
| Scroll works | **NO** (per user — never observed concurrent with battery) | YES (confirmed user-perceptible) |
| Filter `applewirelessmouse` on stack | YES | YES (same!) |
| Registry on `Enum\BTHENUM\…PID&0323\…\Device Parameters` | identical | identical |

**Empirical correction (2026-04-28 PM, user feedback)**: We have NEVER observed v3
mouse battery and scroll working simultaneously on this system. The 96 OK
battery reads on 2026-04-27 06:04-19:43 happened during a Descriptor A window;
scroll was NOT confirmed working in that window. The user's observation of
"scrolling does not work" earlier on 2026-04-27 likely COINCIDED with that
exact window. Modes A and B are **mutually exclusive** in their operational
behavior, not orthogonal as the original diff section assumed.

---

## E. What the filter is doing differently between A and B (REVISED interpretation)

The filter `applewirelessmouse.sys` is on the v3 stack in BOTH states. The registry is identical. Yet the descriptor delivered to HidClass is completely different.

**Mutually exclusive operational modes** — corrected per user observation:

- **Split mode (Descriptor A)** — filter is a passthrough. Vendor TLCs exposed as separate HID children. Battery readable via Input 0x90 on COL02. **No scroll synthesis** — Mouse TLC's small input report only carries X/Y/buttons; raw touch data isn't surfaced anywhere the filter is doing wheel translation from.
- **Unified mode (Descriptor B)** — filter is active. Vendor TLCs stripped. Mouse TLC's 47-byte input report carries raw multi-touch data merged in. **Filter synthesizes wheel events from that raw touch data** via the Win32 input layer. Battery is unreachable because the vendor TLC is gone and the phantom Feature 0x47 isn't backed.

The two modes embody two opposite design choices Apple's filter author had to make:
- Mode A treats v3 as a "battery-aware HID device" — preserves the device's native descriptor, lets standard HID battery utilities work, but **doesn't translate touch to wheel** because the standard mouse interface is intentionally minimal.
- Mode B treats v3 as a "raw-touch source" — exposes everything in one Mouse TLC for downstream consumers (precision touchpad pipeline, custom userland tools) AND synthesizes wheel events itself, but **trades away the standard battery channel** because everything's merged into one report.

The filter binary picks one mode at AddDevice time based on a condition we don't directly observe. Empirically:
- Reboot followed by fresh BT pair tended to land in Mode A (per the April 27 17:43 → 19:43 window — 96 OK battery reads).
- DSM property writes trigger A→B flips (correlation: 19:50 DSM event → 20:13 first FEATURE_BLOCKED).
- The persistence-monitor's repeated `FLIP:VerifyOnly` recycles (which do Disable+Enable BTHENUM) on April 27 evening also landed in Mode B.

**Implication**: the filter is structurally incapable of giving us both battery AND scroll simultaneously. The two modes are exclusive by design. Magic Utilities (when previously bound) presumably gives both because their custom KMDF does scroll synthesis WHILE preserving the vendor TLC's standalone HID interface — that's a different filter architecture, not just a different mode.

---

## F. Reading the diff — what it tells us about the recovery path

**To go from B back to A**, we need to make the filter pick "split mode" at next AddDevice. The empirically observed triggers:
- Reboot followed by fresh BT pair (we have one data point — yesterday post-reboot got A)
- BTHENUM Disable+Enable timing-coincident with a "good" device state (non-deterministic)

**To stay in A**, we need to suppress whatever DSM does at 19:50:53 that flips it. Options:
- Disable DSM auto-service for this container (specific registry path unknown — would need experimentation)
- Block DSM's property-write effect via a custom filter that intercepts DEVPKEY changes
- Tell DSM to never re-enumerate this device (likely not supported)

**To bypass A/B entirely**, we'd need:
- A filter that doesn't mutate the descriptor (Magic Utilities or our own — Phase M12)
- OR a userland tool that talks to `\\.\AppleBluetoothMultitouch` IOCTL with the right code (need RE)

---

## G. Files referenced

- `.ai/test-runs/2026-04-27-154930-T-V3-AF/snapshots/mm-state-20260427T235903Z/pnp-topology.txt` — Descriptor A enum tree (during OK-read window)
- `.ai/test-runs/2026-04-27-154930-T-V3-AF/bt-battery-probe.txt` — Descriptor B enum tree (today)
- `~/AppData/Roaming/MagicMouseTray/debug.log` — HIDP_CAPS readings for both states
- `.ai/test-runs/2026-04-27-154930-T-V3-AF/bthport-discovery-d0c050cc8c4d.json` — SDP cache descriptor (the device's "real" descriptor as published over BT)
- `.ai/test-runs/2026-04-27-154930-T-V3-AF/multi-device-cache-comparison.md` — full SDP descriptor decode
- `.ai/test-runs/2026-04-27-154930-T-V3-AF/battery-everything-probe.txt` — empirical proof that no documented channel returns battery in Descriptor B
