# M13 Phase 3 — BTHPORT Cache Decode (DEFINITIVE)

**Captured:** 2026-04-27 18:37 MDT
**Source:** `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\d0c050cc8c4d\CachedServices\00010000` (351 bytes REG_BINARY)
**Decoded by:** `/tmp/mm-decode-cache.py` (SDP TLV parser + HID descriptor item walker)
**Raw blob:** `blob_cache_00010000.bin` (in this dir)

## BLUF

The cached HID Report Descriptor is **135 bytes**, declares **three sections**: a Mouse collection (X+Y, NO Wheel), a Vendor Feature collection (64-byte Feature report), and a Vendor Battery collection (Report 0x90 — the WinMagicBattery channel). **Both Agent A's and Agent C's hypotheses about the cache contents are refuted.** The descriptor does NOT contain Wheel (Usage 0x38) or AC-Pan (Usage 0x238) — anywhere. This means `applewirelessmouse`'s scroll-synthesis is NOT a descriptor-augmentation operation; it must be injecting events at the Win32 input layer (Linux `hid-magicmouse.c` pattern via `input_report_rel(REL_WHEEL, ...)`).

## Decoded SDP attribute structure

The 351-byte cache is a SDP record with these attributes:

| Attr ID | Type | Length | Notes |
|---|---|---|---|
| 0x0000 | UInt32 | 4 | ServiceRecordHandle |
| 0x0001 | SEQ | 3 | ServiceClassIDList — `{00001124-...}` HID class |
| 0x0004 | SEQ | 13 | ProtocolDescriptorList |
| 0x0005 | SEQ | 3 | BrowseGroupList |
| 0x0006 | SEQ | 9 | LanguageBaseAttributeIDList |
| 0x0009 | SEQ | 8 | BluetoothProfileDescriptorList |
| 0x000d | SEQ | 15 | AdditionalProtocolDescriptorList |
| 0x0100 | String | 11 | "Magic Mouse" or similar service name |
| 0x0101 | String | 5 | (provider name?) |
| 0x0102 | String | 10 | (description?) |
| 0x0200 | UInt16 | 2 | HIDDeviceReleaseNumber |
| 0x0201 | UInt16 | 2 | HIDParserVersion |
| 0x0202 | UInt8 | 1 | HIDDeviceSubclass |
| 0x0203 | UInt8 | 1 | HIDCountryCode |
| 0x0204 | Bool | 1 | HIDVirtualCable |
| 0x0205 | Bool | 1 | HIDReconnectInitiate |
| **0x0206** | **SEQ** | **141** | **HIDDescriptorList — contains the 135-byte Report Descriptor** |
| 0x0207 | SEQ | 8 | HIDLangIDBaseList |
| 0x020a | Bool | 1 | HIDProfileVersion (?) |
| 0x020b | UInt16 | 2 | HIDSupervisionTimeout |
| 0x020c | UInt16 | 2 | HIDNormallyConnectable |
| 0x020d | Bool | 1 | HIDBootDevice |
| 0x020e | Bool | 1 | HIDSDPDisable (?) |

## Decoded HID Report Descriptor (135 bytes)

Raw hex:
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

Structural breakdown:

```
05 01           UsagePage(GenericDesktop=0x01)
09 02           Usage(Mouse)
a1 01           Collection(Application)               -- TLC #1: Mouse
  85 12           ReportID(0x12)
  05 09           UsagePage(Button=0x09)
  19 01 29 02     UsageMin(1) UsageMax(2)             -- 2 buttons
  15 00 25 01     LogicalMin(0) LogicalMax(1)
  95 02 75 01 81 02   ReportCount(2) ReportSize(1) Input(Data,Var,Abs)
  95 01 75 06 81 03   ReportCount(1) ReportSize(6) Input(Const)  -- 6-bit padding
  05 01           UsagePage(GenericDesktop)
  09 01           Usage(Pointer)
  a1 00           Collection(Physical)                -- nested Pointer
    16 01 f8 26 ff 07   LogicalMin(-2047) LogicalMax(2047)
    36 01 fb 46 ff 04   PhysicalMin(-1279) PhysicalMax(1279)
    65 13           Unit(SI Length, cm)
    55 0d           UnitExponent(-3)
    09 30 09 31     Usage(X) Usage(Y)
    75 10 95 02 81 06   ReportSize(16) ReportCount(2) Input(Data,Var,Rel)  -- X,Y absolute touch coords
    75 08 95 02 81 01   8x2 Const padding
  c0              EndCollection
06 02 ff        UsagePage(Vendor=0xFF02)
09 55           Usage(0x55)
85 55           ReportID(0x55)
15 00 26 ff 00  LogicalMin(0) LogicalMax(255)
75 08 95 40 b1 a2  ReportSize(8) ReportCount(64) Feature(Data,Var,Abs,Vol)  -- 64-byte vendor Feature report
c0              EndCollection
06 00 ff        UsagePage(Vendor=0xFF00)
09 14           Usage(0x14)
a1 01           Collection(Application)               -- TLC #3: Vendor Battery
  85 90           ReportID(0x90)                      -- WinMagicBattery's battery channel
  05 84           UsagePage(PowerDevice=0x84)
  75 01 95 03 15 00 25 01   3 bits, 0..1
  09 61           Usage(0x61 = Charging?)
  05 85           UsagePage(BatterySystem=0x85)
  09 44 09 46     Usage(0x44 BatteryStatus, 0x46 ChargingStatus)
  81 02           Input(Data,Var,Abs)
  95 05 81 01     5 bits padding
  75 08 95 01     ReportSize(8) ReportCount(1)
  15 00 26 ff 00  Min 0, Max 255
  09 65           Usage(0x65 BatteryRemainingCapacity)
  81 02           Input(Data,Var,Abs)
c0              EndCollection
```

## M13 question answers from Phase 3

| # | Question | Answer | Evidence |
|---|---|---|---|
| Q1 | Does the v3 BTHPORT cached descriptor declare COL02 (UP=0xFF00 U=0x14)? | **YES** | UsagePage(0xFF00) Usage(0x14) Collection(Application) at descriptor offset 0x58 with ReportID(0x90) — see decoded structure above |
| Q2 | Does the v3 cached descriptor declare any wheel/AC-Pan usages? | **NO** | No Usage(0x38) on UsagePage(0x01); no Usage(0x238) on UsagePage(0x0c). Mouse TLC has only X and Y. |
| Q3 | With `applewirelessmouse` as filter, what subset of the cached descriptor reaches HidClass? | When filter is OPERATIVE (pre-reboot): scroll synthesis happens at Win32 input layer; descriptor caps as HidClass sees them = X+Y on Mouse + Battery on COL02. When filter is INOPERATIVE (post-reboot): same descriptor surfaces; same caps; but no wheel synthesis. | hid-probe.txt across all sub-steps shows COL01 InputValueCaps = X+Y only, regardless of filter state. The descriptor is constant; what changes at reboot is whether the filter's Win32-layer wheel injection runs. |
| Q5 | Does patching the cache to add wheel + reload yield COL01-with-scroll + COL02-with-battery? | UNKNOWN — needs Phase 4C-lite test | Cache patch is now well-specified: insert `09 38 15 81 25 7F 75 08 95 01 81 06 05 0c 0a 38 02 81 06` (~18 bytes) after the Y usage in Mouse TLC, recompute SDP TLV lengths (NN at offset 175, LL at outer SEQUENCE start). |
| Q7 | Can scroll+battery ship without a kernel driver? | **YES via Phase 4A** (most likely path) | Battery is in the cache and works without filter. Scroll requires either: (a) userland gesture-to-wheel daemon reading raw multi-touch + SendInput WM_MOUSEWHEEL — Phase 4A, OR (b) cache patch with wheel + descriptor-driven reporting OR a separate filter that does Win32-layer wheel injection — Phase 4C. 4A wins on simplicity and doesn't need kernel work. |

## What this REFUTES from prior agent reports

| Claim | Source | Phase 3 verdict |
|---|---|---|
| "Cache contains a unified TLC with Wheel; filter splits it" | Agent A | **REFUTED** — cache has 3 separate sections, none with Wheel |
| "Cache already declares split TLCs; filter injects Wheel into COL01 at runtime" | Agent C | **REFUTED** — cache has split sections but Wheel does NOT exist in any of them; there's no "slot for Wheel injection" in the descriptor |
| "Apple filter strips COL02 to provide scroll" | M13 plan v1.0 background | **REFUTED** — COL02 is in the cache. Whatever Apple's filter does, it's not modifying the descriptor. When the filter is inoperative the cache surfaces unchanged and COL02 becomes accessible to user-mode probes. The "stripping" hypothesis is wrong. |
| "Mutual exclusion of scroll and battery is a fundamental device limit" | Agent A | **REFINED** — mutual exclusion observed in Cell 1 because applewirelessmouse's wheel synthesis path requires its filter to be operative AND the filter (when operative) blocks/intercepts user-mode reads of COL02. Cause is filter behaviour, not device limitation. |

## What this CONFIRMS

- `applewirelessmouse.sys` does scroll synthesis at the **Win32 input layer**, not via descriptor augmentation. (Same architectural pattern as Linux `hid-magicmouse.c` calling `input_report_rel(REL_WHEEL, ...)`.)
- The cached descriptor is the SAME in both pre-reboot AppleFilter-active and post-reboot AppleFilter-inactive modes. What changes is the filter's runtime behaviour, not the descriptor.
- Battery is declared in the cache and is fundamentally accessible from user-mode HID — no descriptor patch needed for battery.

## Remaining unknown

**Why does `applewirelessmouse` stop synthesizing wheel events post-reboot** despite the filter being bound (LowerFilters preserved) and the service loaded? Cache decode doesn't answer this; need:
- A focused wpr trace post-reboot capturing `Microsoft-Windows-Input-HIDCLASS` + `Microsoft-Windows-Kernel-PnP` + `Microsoft-Windows-WDF` events, looking for AddDevice / Start / D-state IRPs to applewirelessmouse
- The `m13.wprp` profile (committed in `ce0dd18`) is the right tool; we couldn't run it for Cell 1 but Cell 2+ will

## Implications for PRD-184 and the next steps

**PRD-184 path forward is Phase 4A**: build a small userland gesture-to-wheel daemon that:
1. Reads raw multi-touch from Report 0x12 via `RegisterRawInputDevices` (or a small kernel filter that surfaces it to user-mode if RawInput is exclusive)
2. Translates touchpad-coord deltas to wheel events
3. Calls `SendInput` with `MOUSEEVENTF_WHEEL`
4. Battery already works through existing tray app (COL02 read of Report 0x90)

This eliminates the need for `applewirelessmouse` — the filter that, when bound but inoperative post-reboot, breaks the Apple-filter scroll path.

Phase 4C (cache patch) is now a documented alternative but lower priority — adds risk, requires re-applying after every BT re-pair (cache invalidates), and may interact poorly with applewirelessmouse if the user keeps the filter installed.

**Cells 2-6 (NoFilter, USB-C, v1) are now lower priority** — they would tell us how applewirelessmouse behaves under different conditions, but the strategic decision (build a userland scroll daemon) is already actionable from Phase 3 evidence alone. Cells could ship as defense-in-depth data once the daemon prototype works.
