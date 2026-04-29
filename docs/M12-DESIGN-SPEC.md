# M12 Design Specification

**Status:** v1.1 — DRAFT pending user approval (NLM peer-review patches applied)
**Date:** 2026-04-28
**Linked PRD:** PRD-184 v1.26
**Linked PSN:** PSN-0001 v1.9
**Linked review:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-2026-04-28.md`
**Approval gate:** PR ai/m12-design-prd-mop must be approved by user before any code is written.

## Revision history

- **v1.1 (2026-04-28):** Patched after NLM peer review CHANGES-NEEDED verdict. Section 3b descriptor delivery rewritten to use `IOCTL_INTERNAL_BTH_SUBMIT_BRB` + SDP TLV interception (lower filter cannot intercept `IOCTL_HID_GET_REPORT_DESCRIPTOR` — that IOCTL is absorbed by HidBth). Section 11 added F13 (BTHPORT SDP cache trap on already-paired devices) and F14 (sequential queue blocking on stalled GET_REPORT 0x90). MOP companion patches: VG-0 pre-validation step + 7c-pre cache wipe / re-pair gate.
- **v1.0 (2026-04-28):** Initial design package.

---

## 1. BLUF

M12 is a pure-kernel KMDF lower filter driver, built clean-room from public references, that binds to Apple Magic Mouse v1 (PIDs 0x030D, 0x0310) and v3 (PID 0x0323) BTHENUM HID devices. It replicates Magic Utilities' "Mode A" HID descriptor (high-resolution scroll layout: Wheel + AC Pan + two Resolution Multiplier Feature reports across 5 link collections) and performs in-IRP translation of two flows: (a) vendor multi-touch input report 0x12 -> Mode A 8-byte mouse Input report (Wheel/Pan synthesised from per-finger touch deltas using the algorithm published in `drivers/hid/hid-magicmouse.c`), and (b) upstream `IOCTL_HID_GET_FEATURE` for ReportID 0x47 -> downstream `IOCTL_HID_GET_INPUT_REPORT` for ReportID 0x90, repackaged into a standard Feature 0x47 response (1-byte battery percentage). M12 is self-contained — no userland service, no license layer, no trial expiry. Estimated 300-500 LOC. Replaces both `applewirelessmouse.sys` (Apple/tealtadpole) and `MagicMouse.sys` (Magic Utilities) on the v1+v3 mouse stacks.

---

## 2. Goals and Non-Goals

### Goals

1. Deliver simultaneous scroll AND battery on Magic Mouse v3 (PID 0x0323) on Windows 11.
2. Maintain regression-free operation on Magic Mouse v1 (PID 0x030D) — both scroll and battery readable in the existing tray's "Feature 0x47" code path.
3. Deterministic at every cold boot, sleep/wake, and BT reconnect — no PnP recycle scripts, no userland watchdog, no startup tasks required.
4. Pure kernel: no userland service, no license enforcement, no trial mechanism. The captured Magic Utilities artefacts confirmed empirically (H-013) that the userland gate is the failure mode we must NOT replicate.
5. Clean-room implementation under interoperability exemption (DMCA section 1201(f), Canada Copyright Act section 30.61, EU Software Directive 2009/24/EC Article 6). Linux `hid-magicmouse.c` (GPL-2) is a read-only reference for algorithm description; no source code or binary fragment is copied. Magic Utilities `MagicMouse.sys` is examined for KMDF API patterns, never reproduced.
6. WHQL-pathable: design uses standard KMDF, standard HID class IOCTLs, standard INF directives. WHQL submission is OUT of scope for M12 itself but the implementation must not preclude it.

### Non-Goals

- Magic Trackpad support (PIDs 0x030E, 0x0314 — different report formats, not on the user's hardware).
- Magic Keyboard support (handled by `MagicKeyboard.sys` reference; out of scope for this PR).
- Multi-finger gestures beyond single-finger scroll (Linux driver supports more — M12 implements the same minimal scroll-from-touch behaviour the existing tray expects).
- Force-feedback, click-pressure, or other sensor data not surfaced by the Mode A descriptor.
- USB-C wired path. v3 charges via USB-C but the host-mouse data path is BT-only on this hardware. USB-C path can be added later if the user's workflow ever requires it.
- Replacing `MagicKeyboard.sys` for the AWK keyboard. The Apple keyboard already battery-reads through its own filter; M12 does not touch it.

---

## 3. Architecture

### 3a. Driver position in the HID stack

```
                      +------------------------------+
                      |   Win32 input subsystem      |
                      |   (mouhid, RawInput, etc.)   |
                      +---------------+--------------+
                                      |
                      +---------------v--------------+
                      |       HidClass (FDO)         |
                      +---------------+--------------+
                                      |
                      +---------------v--------------+
                      |   HidBth (function driver)   |   <- delivers BT-HID reports
                      +---------------+--------------+
                                      |
                      +---------------v--------------+
                      |    M12 (lower filter)        |   <- this design
                      |    MagicMouseDriver.sys      |
                      +---------------+--------------+
                                      |
                      +---------------v--------------+
                      |   BthEnum / Bluetooth stack  |
                      +------------------------------+
                                      |
                                  Magic Mouse
                                  (v1 PID 0x030D
                                   v1 PID 0x0310 trackpad-class
                                   v3 PID 0x0323)
```

The filter is a lower filter under HidClass and underneath HidBth. `WdfFdoInitSetFilter` marks it as a non-power-policy-owner filter so HidClass remains the function driver of record.

### 3b. Data flow

**Inbound (device -> Win32):**
1. Device emits vendor multi-touch input report on the BT HID interrupt channel.
2. HidBth packages it into an HID transfer.
3. M12's `EvtIoInternalDeviceControl` sees `IOCTL_HID_READ_REPORT` completion at the bottom of its parallel queue.
4. M12 inspects the ReportID:
   - `0x12` (MOUSE2_REPORT_ID per Linux): parse the 14-byte header + N x 8-byte touch blocks, run scroll/touch algorithm, emit synthesised Mode A 8-byte input report (ReportID 0x02, X/Y in bytes 1-2/3-4, Wheel in bytes 5-6, AC Pan in bytes 7-8 per the Mode A descriptor's 5-link-collection layout).
   - `0x29` (MOUSE_REPORT_ID — v1 BT format): parse v1's 6-byte header + N x 8-byte touch blocks per Linux `hid-magicmouse.c` `case MOUSE_REPORT_ID`. Same Mode A output format.
   - `0x90` (vendor battery): cache battery percentage in DEVICE_CONTEXT for the next Feature 0x47 query. Drop the report from the upstream stream (Mode A descriptor doesn't expose Input 0x90).
   - other ReportIDs: forward unchanged.
5. M12 completes the IRP upstream with the synthesised Mode A buffer.

**Outbound (host -> device, IOCTL path):**
1. Tray app calls `HidD_GetFeature(handle, 0x47, ...)`.
2. HidClass issues `IOCTL_HID_GET_FEATURE` down the stack.
3. M12's `EvtIoDeviceControl` (sequential queue) intercepts. Switch on ReportID:
   - `0x47` and PID is v3 (0x0323): synthesise Feature 0x47 response from cached battery percentage. If no recent cache entry (older than 30s), forward as `IOCTL_HID_GET_INPUT_REPORT` for ReportID 0x90, parse 3-byte response `[0x90, flags, pct]`, repackage as 2-byte Feature 0x47 `[0x47, pct]`, complete upstream.
   - `0x47` and PID is v1 (0x030D / 0x0310): forward unchanged. v1 firmware backs Feature 0x47 natively.
   - other ReportIDs: forward unchanged.

**Descriptor delivery (corrected per NLM peer review 2026-04-28):**

`IOCTL_HID_GET_REPORT_DESCRIPTOR` is absorbed by HidBth before reaching a lower filter on the BTHENUM stack — a lower filter cannot intercept it directly. The correct hook is `IOCTL_INTERNAL_BTH_SUBMIT_BRB` (the BT minidriver-level path HidBth uses to pull the SDP HIDDescriptorList from the device during pairing). M12 must intercept BRB completion and rewrite the SDP TLV in place.

1. HidBth issues `IOCTL_INTERNAL_BTH_SUBMIT_BRB` down the stack as part of the L2CAP SDP query during pairing.
2. M12's `EvtIoInternalDeviceControl` sees the IRP and forwards downstream with a completion routine attached.
3. In the completion routine, M12 inspects BRB Type at offset `+0x16` of the BRB structure. If `BRB_L2CA_ACL_TRANSFER` and the ACL buffer (mapped via `MmGetSystemAddressForMdlSafe`) contains an SDP HIDDescriptorList byte pattern, M12 rewrites the embedded descriptor bytes in place.
4. SDP TLV pattern to match: `35 LL` (SEQUENCE) -> `09 02 06` (Attribute ID 0x0206 HIDDescriptorList) -> `35 LL` (SEQUENCE) -> `35 LL` (per-entry SEQUENCE) -> `08 22` (UNSIGNED int 0x22 = "report descriptor type") -> `25 NN ...` (length-prefixed descriptor bytes). Replace the `NN`-byte payload with `g_HidDescriptor[]`. Adjust the three SDP length bytes (outer SEQUENCE + inner SEQUENCE + descriptor 25-prefix) accordingly. If `g_HidDescriptor[]` length crosses the 127-byte threshold, encoding shifts from 1-byte to 2-byte length form and all subsequent offsets shift — implementer must use a recursive TLV parser, not a fixed-offset writer (per prior security-reviewer finding from PRD-184 M13 work, captured in `.ai/code-reviews/bthport-patch-safety.md`).
5. **BTHPORT cache trap (failure mode F13):** on already-paired devices, HidBth does NOT re-fetch the SDP descriptor; it reads the cached copy from `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<mac>\CachedServices\00010000` (REG_BINARY). The BRB-level injection only fires during a fresh SDP exchange. To force fresh SDP on an already-paired device, the MOP either wipes the cached value (preferred, scripted) or has the operator unpair + re-pair (fallback). See MOP Section 7c-pre.

### 3c. Why pure kernel (no userland)

H-013 confirmed empirically (Session 12) that Magic Utilities splits descriptor mutation (kernel) from translation + battery (userland service, license-gated). With trial-expired userland the kernel filter alone produces broken scroll and hidden battery. M12 collapses the split: descriptor + translation + battery synthesis all in one kernel filter, no userland dependency, no license check, no trial expiry surface area. Estimated kernel size 300-500 LOC keeps the per-IRP path simple enough to audit and test.

---

## 4. INF Design

### 4a. Hardware ID matching

The INF must enumerate all three Apple BT HID PIDs that this user owns:

```
[Standard.NTamd64]
%MM_v1_DeviceDesc% = Install_Mouse, BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&030D
%MM_TrackpadClass_DeviceDesc% = Install_Mouse, BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0310
%MM_v3_DeviceDesc% = Install_Mouse, BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0323
```

PID 0x0310 is included to bind any Magic Mouse advertising as the "trackpad-class" hardware ID even though the user owns the standard v1 (0x030D); this matches the Magic Utilities INF behaviour and forecloses the over-match that bit Apple's INF (`applewirelessmouse` mis-binding to v3 due to wildcard hardware IDs).

### 4b. Service registration and filter binding

```
[Install_Mouse]
CopyFiles = DriverFiles

[Install_Mouse.HW]
AddReg = AddReg_LowerFilter

[AddReg_LowerFilter]
HKR,,"LowerFilters",0x00010008,"MagicMouseDriver"   ; FLG_ADDREG_TYPE_MULTI_SZ|FLG_ADDREG_APPEND

[Install_Mouse.Services]
AddService = MagicMouseDriver, 0x00000002, ServiceInstall

[ServiceInstall]
DisplayName   = %ServiceDesc%
ServiceType   = 1                ; SERVICE_KERNEL_DRIVER
StartType     = 3                ; SERVICE_DEMAND_START
ErrorControl  = 1                ; SERVICE_ERROR_NORMAL
ServiceBinary = %12%\MagicMouseDriver.sys
```

### 4c. Class

```
Class       = HIDClass
ClassGuid   = {745A17A0-74D3-11D0-B6FE-00A0C90F57DA}
```

Note: the existing scaffold inherited `Class = Bluetooth`, ClassGuid `{e0cbf06c-cd8b-4647-bb8a-263b43f0f974}` from earlier exploration. M12 ratifies HIDClass per LowerFilter binding semantics — the filter sits on the HID-class GUID stack (per AP-16 lesson: filter binding lives on `{00001124-...}`, not the BT-service GUID). The captured `magicmouse.inf` from Magic Utilities uses HIDClass; we follow that pattern.

### 4d. Include / Needs

The captured `applewirelessmouse.inf` (tealtadpole / Magic Mouse 2 Drivers Win11 x64) and `magicmouse.inf` (Magic Utilities 3.1.5.x) both use:

```
Include = input.inf, hidbth.inf
Needs   = HID_Inst.NT, HID_Inst.NT.Services
```

at their `[Install_Mouse]` section. M12 follows the same pattern. `Needs=HID_Inst.NT.Services` ensures HidClass is registered as the function driver of record when the device is enumerated; M12 sits below it as a lower filter without taking ownership.

### 4e. PnpLockdown

`PnpLockdown=1` is set so that user-mode tools cannot tamper with the driver service registration. This matches WDM best practice and Magic Utilities' INF.

### 4f. Strings

`Provider`, `DeviceDesc`, `ServiceDesc` are M12-specific. No reuse of Apple or Magic Utilities trademarks.

---

## 5. Descriptor mutation: byte-level Mode A spec

M12 declares the following HID Report Descriptor (the "Mode A" descriptor) on `IOCTL_HID_GET_REPORT_DESCRIPTOR`. This is the descriptor empirically observed under Magic Utilities v3.1.5.2 (capture: `.ai/test-runs/2026-04-27-154930-T-V3-AF/hid-descriptor-full-v3-col01.txt`, 2026-04-28 19:50:47 captured):

```
HIDP_CAPS expected:
  TLC: UsagePage=0x0001 Usage=0x0002 (Mouse)
  Report lengths: Input=8, Output=0, Feature=2
  Counts: LinkColl=5, InpBC=1, InpVC=4, FeatVC=2

Link Collections (5):
  [0] App   UP=0x0001 U=0x0002 (Mouse, top-level)
  [1] Logical (parent=0)
  [2] Physical UP=0x0001 U=0x0001 (Pointer, parent=1)
  [3] Logical (parent=2) - hosts vertical wheel + Resolution Multiplier
  [4] Logical (parent=2) - hosts AC Pan + Resolution Multiplier

Input Button Caps (1):
  [0] RID=0x02 UP=0x0009 (Button) UsageMin=0x1 UsageMax=0x5 LinkColl=2

Input Value Caps (4):
  [0] RID=0x02 UP=0x0001 U=0x31 (Y)     LinkColl=2 BitSize=8  ReportCount=1 LogMin=-127 LogMax=127
  [1] RID=0x02 UP=0x0001 U=0x30 (X)     LinkColl=2 BitSize=8  ReportCount=1 LogMin=-127 LogMax=127
  [2] RID=0x02 UP=0x0001 U=0x38 (Wheel) LinkColl=3 BitSize=16 ReportCount=1 LogMin=-32767 LogMax=32767
  [3] RID=0x02 UP=0x000C U=0x238 (AC Pan) LinkColl=4 BitSize=16 ReportCount=1 LogMin=-32767 LogMax=32767

Feature Value Caps (2):
  [0] RID=0x03 UP=0x0001 U=0x48 (Resolution Multiplier) LinkColl=3 BitSize=8 ReportCount=1
  [1] RID=0x04 UP=0x0001 U=0x48 (Resolution Multiplier) LinkColl=4 BitSize=8 ReportCount=1
```

### 5a. Descriptor bytes (canonical layout, ~110 bytes)

```
05 01           Usage Page (Generic Desktop)
09 02           Usage (Mouse)
A1 01           Collection (Application)
  85 02            Report ID (0x02)
  09 02            Usage (Mouse)
  A1 02            Collection (Logical)
    09 01            Usage (Pointer)
    A1 00            Collection (Physical)
      05 09            Usage Page (Button)
      19 01            Usage Minimum (Button 1)
      29 05            Usage Maximum (Button 5)
      15 00            Logical Min (0)
      25 01            Logical Max (1)
      75 01            Report Size (1)
      95 05            Report Count (5)
      81 02            Input (Data,Var,Abs)
      75 03            Report Size (3)        ; padding
      95 01            Report Count (1)
      81 03            Input (Cnst,Var,Abs)
      05 01            Usage Page (Generic Desktop)
      09 30            Usage (X)
      09 31            Usage (Y)
      15 81            Logical Min (-127)
      25 7F            Logical Max (127)
      75 08            Report Size (8)
      95 02            Report Count (2)
      81 06            Input (Data,Var,Rel)
      A1 02            Collection (Logical)        ; LC[3] vertical wheel + ResMult
        85 03            Report ID (0x03)
        09 48            Usage (Resolution Multiplier)
        15 00            Logical Min (0)
        25 01            Logical Max (1)
        35 01            Physical Min (1)
        45 78            Physical Max (120)
        75 02            Report Size (2)
        95 01            Report Count (1)
        B1 02            Feature (Data,Var,Abs)
        35 00            Physical Min (0)         ; reset
        45 00            Physical Max (0)
        75 06            Report Size (6)          ; padding
        B1 03            Feature (Cnst,Var,Abs)
        85 02            Report ID (0x02)
        09 38            Usage (Wheel)
        15 81 FF         Logical Min (-32767, 16-bit)
        25 7F FF         Logical Max (32767)
        75 10            Report Size (16)
        95 01            Report Count (1)
        81 06            Input (Data,Var,Rel)
      C0               End Collection (LC[3])
      A1 02            Collection (Logical)        ; LC[4] AC Pan + ResMult
        85 04            Report ID (0x04)
        05 01            Usage Page (Generic Desktop)
        09 48            Usage (Resolution Multiplier)
        15 00            Logical Min (0)
        25 01            Logical Max (1)
        35 01            Physical Min (1)
        45 78            Physical Max (120)
        75 02            Report Size (2)
        95 01            Report Count (1)
        B1 02            Feature (Data,Var,Abs)
        35 00            Physical Min (0)
        45 00            Physical Max (0)
        75 06            Report Size (6)
        B1 03            Feature (Cnst,Var,Abs)
        85 02            Report ID (0x02)
        05 0C            Usage Page (Consumer)
        0A 38 02         Usage (AC Pan)
        15 81 FF         Logical Min (-32767)
        25 7F FF         Logical Max (32767)
        75 10            Report Size (16)
        95 01            Report Count (1)
        81 06            Input (Data,Var,Rel)
      C0               End Collection (LC[4])
    C0              End Collection (Physical)
  C0              End Collection (Logical)
C0              End Collection (Application)
```

The exact byte layout will be authored as a `static const UCHAR g_HidDescriptor[]` array in `HidDescriptor.c` and hand-validated against:
- `hidparser.exe` from EWDK samples (must parse without warnings)
- `HidD_GetPreparsedData` + `HidP_GetCaps` against a synthetic tree that produces TLC/InLen/FeatLen identical to the captured Mode A reading

### 5b. Why this descriptor

- **8-byte input report** matches the Mode A capture exactly: 1 byte Report ID 0x02, 5 button bits + 3 padding bits = 1 byte, X (1 byte) + Y (1 byte), Wheel (2 bytes), AC Pan (2 bytes) = 8 bytes. HidClass reads this as a standard Generic Desktop Mouse.
- **Resolution Multiplier Features (RIDs 0x03, 0x04)** are the high-resolution scrolling protocol Microsoft introduced in Win10 1809. They tell HidClass to deliver wheel deltas at 120-units-per-detent precision instead of 1-per-detent. Magic Utilities declares them; we replicate.
- **No Feature 0x47 in the descriptor.** Battery is delivered via the IOCTL intercept path (Section 3b Outbound), not via a HID-declared Feature ReportID. The tray's existing `unifiedAppleBattery` code path calls `HidD_GetFeature(0x47)` regardless of whether the descriptor declares it; HidClass passes the IOCTL down; M12 synthesises the response. This means the descriptor matches what userland can cleanly poll without spurious phantom IDs.
- **Not the v1 native descriptor.** The native Apple v1 descriptor declares Feature 0x47 in its TLC. M12 overrides this for v1 too — same Mode A descriptor for both PIDs — because the existing tray's `MouseBatteryReader.cs` path through `HidD_GetFeature(0x47)` works on Mode A via the IOCTL intercept and is the unified call path. v1's native 0x47 backing is preserved by the IOCTL pass-through (Section 3b).

---

## 6. Translation algorithm: vendor input -> Mode A input

This algorithm is described in our own voice based on the public Linux `hid-magicmouse.c` (file SHA: `git describe HEAD` of torvalds/linux current). It is NOT copied. M12's implementation in `InputHandler.c` will be hand-written; this section documents the spec.

### 6a. Vendor input report 0x12 layout (v3 / Magic Mouse 2 / Magic Mouse 2 USB-C)

```
Offset  Size    Field
0       1       ReportID (0x12)
1       1       clicks      (bit 0 = left, bit 1 = right, bit 2 = middle for 3-button emulation)
2-3     2       (reserved, possibly buttons-extended)
3       1       x_lo (used in pointer emulation: x = ((data[3] << 24) | (data[2] << 16)) >> 16)
4       1       x_hi  -- Linux: x = (int)((data[3] << 24) | (data[2] << 16)) >> 16
5       1       y_lo  -- Linux: y = (int)((data[5] << 24) | (data[4] << 16)) >> 16
6       1       y_hi
7-13    7       (timestamp + padding; data[11..13] are ts bits per Linux comment)
14+     8*N     N touch blocks, 8 bytes each, up to 15 touches per packet

Per-touch block (8 bytes), v3 layout:
  tdata[0]   x_lo
  tdata[1]   x_mid (12-bit X = (tdata[1]<<28 | tdata[0]<<20) >> 20)
  tdata[2]   y_lo (12-bit Y = -((tdata[2]<<24 | tdata[1]<<16) >> 20))
  tdata[3]   touch_major
  tdata[4]   touch_minor
  tdata[5]   size (low 6 bits) + id_lo (high 2 bits used in id calc)
  tdata[6]   id_hi (id = (tdata[6]<<2 | tdata[5]>>6) & 0xf) + orientation high bits
  tdata[7]   touch_state (low 4 bits: 0x10=hover/start, 0x20=transition, 0x30=START, 0x40=DRAG)
```

Size validation:

```c
if (size != 8 && (size < 14 || (size - 14) % 8 != 0)) drop_report();
npoints = (size - 14) / 8;
if (npoints > 15) drop_report();
```

### 6b. Pointer + buttons (v3)

```c
int x = (int)((data[3] << 24) | (data[2] << 16)) >> 16;
int y = (int)((data[5] << 24) | (data[4] << 16)) >> 16;
uint8_t buttons = data[1] & 0x07;  // bits 0..2: L, R, M (after 3-button emulation)
```

These map directly to Mode A's X (RID 0x02 byte 2) and Y (RID 0x02 byte 3) and button bitmap (byte 1). No translation work — pass-through.

### 6c. Scroll synthesis (per-touch, single finger)

For each touch block, the Linux algorithm (paraphrased, not copied):

1. Decode (id, x, y, state) from the 8-byte block per Section 6a.
2. Look up per-id state in the driver's touch table (`msc->touches[id]`):
   - `scroll_x`, `scroll_y` — last position used to compute delta
   - `scroll_x_active`, `scroll_y_active` — whether HR axis has crossed threshold this gesture
   - `scroll_x_hr`, `scroll_y_hr` — last position used for high-resolution wheel
3. On `state == TOUCH_STATE_START` (0x30):
   - Reset `scroll_x = x`, `scroll_y = y`, `scroll_x_hr = x`, `scroll_y_hr = y`
   - Reset `scroll_x_active = scroll_y_active = false`
   - Decay or reset `scroll_accel` based on time since last gesture
4. On `state == TOUCH_STATE_DRAG` (0x40):
   - `step_x = scroll_x - x`, `step_y = scroll_y - y`
   - `step_x /= (64 - scroll_speed) * scroll_accel`. If non-zero: emit horizontal wheel delta `-step_x`, advance `scroll_x` by `step_x * (64 - scroll_speed) * scroll_accel`.
   - Same for `step_y`. Emit vertical wheel delta `step_y`.
   - HR axes: track `step_x_hr` / `step_y_hr` separately, gate by `SCROLL_HR_THRESHOLD`, emit at `SCROLL_HR_MULT` precision multiplier.
5. Map the algorithm's `input_report_rel(REL_WHEEL, n)` and `input_report_rel(REL_HWHEEL, n)` calls to writes into the Mode A 8-byte synthesized buffer's Wheel (bytes 5-6) and AC Pan (bytes 7-8) fields.

The constants `scroll_speed` (default 32 in Linux), `scroll_accel` (default 1, max 4), `SCROLL_HR_THRESHOLD`, `SCROLL_HR_MULT`, `SCROLL_HR_STEPS` are tunable parameters in M12's `DEVICE_CONTEXT`. Initial values match Linux defaults; can be exposed via a `HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Parameters` registry key in a follow-up if behaviour-tuning is needed.

### 6d. Vendor input 0x29 (v1 BT) translation

v1 Magic Mouse uses MOUSE_REPORT_ID = 0x29 with a 6-byte header instead of 14:

```
size validation: size >= 6 AND (size - 6) % 8 == 0
npoints = (size - 6) / 8
x = (int)(((data[3] & 0x0c) << 28) | (data[1] << 22)) >> 22
y = (int)(((data[3] & 0x30) << 26) | (data[2] << 22)) >> 22
clicks = data[3]
per-touch blocks at data + ii * 8 + 6
```

Per-touch layout for v1 mouse uses the same 8-byte structure as v3 (per Linux `case USB_DEVICE_ID_APPLE_MAGICMOUSE` in `magicmouse_emit_touch`).

### 6e. v1 PID 0x030D natively backs Feature 0x47

For v1 (PID 0x030D), the device firmware natively responds to `IOCTL_HID_GET_INPUT_REPORT` for ReportID 0x47 (it is in v1's native HID descriptor). M12's IOCTL intercept for v1 still presents the Mode A descriptor (no Feature 0x47 declared upstream), but the tray's `HidD_GetFeature(0x47)` call still works because M12 routes the IOCTL down to the native v1 path. See Section 7c for the PID branch.

---

## 7. Battery synthesis: 0x47 over 0x90

### 7a. Cached-input path (preferred, fast)

When v3 emits an unsolicited Input report 0x90 on the BT interrupt channel (whether from a probe or from the device's own status push), M12 caches `(timestamp, battery_pct)` in `DEVICE_CONTEXT.battery_cache`. Subsequent `IOCTL_HID_GET_FEATURE` for 0x47 within `BATTERY_CACHE_TTL_MS` (default 30000) returns the cached value with zero downstream traffic.

Pseudocode:

```c
NTSTATUS HandleGetFeature47_Cached(WDFREQUEST req, PDEVICE_CONTEXT ctx, PUCHAR outBuf, size_t outLen) {
    KIRQL irql;
    KeAcquireSpinLock(&ctx->BatteryLock, &irql);
    LARGE_INTEGER now; KeQuerySystemTime(&now);
    LONGLONG age_ms = (now.QuadPart - ctx->BatteryCachedAt.QuadPart) / 10000;
    UCHAR pct = ctx->BatteryCachedPct;
    KeReleaseSpinLock(&ctx->BatteryLock, irql);

    if (age_ms > BATTERY_CACHE_TTL_MS || pct == 0xFF) {
        return STATUS_NOT_FOUND;  // fall through to active-poll path
    }
    if (outLen < 2) return STATUS_BUFFER_TOO_SMALL;
    outBuf[0] = 0x47;
    outBuf[1] = pct;
    WdfRequestSetInformation(req, 2);
    return STATUS_SUCCESS;
}
```

### 7b. Active-poll path (fallback)

If the cache is stale, M12 issues a downstream `IOCTL_HID_GET_INPUT_REPORT` for ReportID 0x90 to the lower target (HidBth -> device), parses the 3-byte response, populates the cache, returns the Feature 0x47 form upstream.

Pseudocode:

```c
NTSTATUS HandleGetFeature47_ActivePoll(WDFREQUEST req, PDEVICE_CONTEXT ctx, PUCHAR outBuf, size_t outLen) {
    HID_XFER_PACKET pkt;
    UCHAR inBuf[3] = { 0x90, 0, 0 };
    pkt.reportId = 0x90;
    pkt.reportBuffer = inBuf;
    pkt.reportBufferLen = sizeof(inBuf);

    WDF_REQUEST_SEND_OPTIONS opts;
    WDF_REQUEST_SEND_OPTIONS_INIT(&opts, WDF_REQUEST_SEND_OPTION_SYNCHRONOUS);
    opts.Timeout = WDF_REL_TIMEOUT_IN_MS(500);

    NTSTATUS s = WdfIoTargetSendIoctlSynchronously(
        ctx->IoTarget, NULL,
        IOCTL_HID_GET_INPUT_REPORT,
        &pkt, sizeof(pkt), NULL, NULL);
    if (!NT_SUCCESS(s)) return s;

    UCHAR pct = inBuf[2];
    if (pct > 100) pct = 100;

    KIRQL irql;
    KeAcquireSpinLock(&ctx->BatteryLock, &irql);
    KeQuerySystemTime(&ctx->BatteryCachedAt);
    ctx->BatteryCachedPct = pct;
    KeReleaseSpinLock(&ctx->BatteryLock, irql);

    if (outLen < 2) return STATUS_BUFFER_TOO_SMALL;
    outBuf[0] = 0x47;
    outBuf[1] = pct;
    WdfRequestSetInformation(req, 2);
    return STATUS_SUCCESS;
}
```

### 7c. PID branch

```c
NTSTATUS EvtIoDeviceControl_Feature(WDFREQUEST req, PDEVICE_CONTEXT ctx, ULONG ioctl) {
    if (ioctl != IOCTL_HID_GET_FEATURE) return ForwardRequest(req, ctx);

    HID_XFER_PACKET *pkt;
    NTSTATUS s = WdfRequestRetrieveInputBuffer(req, sizeof(*pkt), (PVOID*)&pkt, NULL);
    if (!NT_SUCCESS(s)) return ForwardRequest(req, ctx);

    if (pkt->reportId != 0x47) return ForwardRequest(req, ctx);

    if (ctx->Pid == 0x030D || ctx->Pid == 0x0310) {
        // v1 firmware natively backs 0x47 — pass through.
        return ForwardRequest(req, ctx);
    }
    if (ctx->Pid == 0x0323) {
        s = HandleGetFeature47_Cached(req, ctx, pkt->reportBuffer, pkt->reportBufferLen);
        if (s == STATUS_NOT_FOUND) {
            s = HandleGetFeature47_ActivePoll(req, ctx, pkt->reportBuffer, pkt->reportBufferLen);
        }
        WdfRequestComplete(req, s);
        return s;
    }
    return ForwardRequest(req, ctx);
}
```

`ctx->Pid` is read once at `EvtDeviceAdd` time from `WdfDeviceQueryProperty(DevicePropertyHardwareID, ...)` and stashed in DEVICE_CONTEXT.

---

## 8. WDF queue layout

| Queue | Dispatch | What it handles |
|-------|----------|-----------------|
| Default queue | parallel | All IRPs by default; forwards to specialised queues by IOCTL |
| Sequential IOCTL queue | sequential | `IOCTL_HID_GET_FEATURE`, `IOCTL_HID_GET_REPORT_DESCRIPTOR`, `IOCTL_HID_GET_DEVICE_DESCRIPTOR`, `IOCTL_HID_GET_DEVICE_ATTRIBUTES` — all reads of static or cached state |
| Parallel input queue | parallel | `IOCTL_HID_READ_REPORT` — input report stream from device, hot path |

The sequential queue serialises IOCTL access so cache reads/writes are linearised without spinlocks on the GET path; the parallel queue handles the high-rate read stream where ordering is enforced by HidClass anyway.

`WdfIoQueueCreate` is called twice: once for the IOCTL queue with `WdfIoQueueDispatchSequential`, once for the read queue with `WdfIoQueueDispatchParallel`. Forwarding from default queue to specialised queues uses `WdfDeviceConfigureRequestDispatching` with the IOCTL major function code.

---

## 9. Function signatures

```c
// Driver.c
NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath);
EVT_WDF_DRIVER_DEVICE_ADD EvtDriverDeviceAdd;
EVT_WDF_OBJECT_CONTEXT_CLEANUP EvtDriverContextCleanup;

// EvtDeviceAdd.c
NTSTATUS EvtDeviceAdd(_In_ WDFDRIVER Driver, _Inout_ PWDFDEVICE_INIT DeviceInit);
NTSTATUS InitializeIoTarget(_In_ WDFDEVICE Device, _Out_ PDEVICE_CONTEXT Ctx);
NTSTATUS QueryHardwareIdAndStorePid(_In_ WDFDEVICE Device, _Out_ PDEVICE_CONTEXT Ctx);
NTSTATUS CreateQueues(_In_ WDFDEVICE Device);

// IoctlHandlers.c
EVT_WDF_IO_QUEUE_IO_DEVICE_CONTROL EvtIoDeviceControl;
EVT_WDF_IO_QUEUE_IO_INTERNAL_DEVICE_CONTROL EvtIoInternalDeviceControl;
NTSTATUS HandleGetReportDescriptor(_In_ WDFREQUEST Req);
NTSTATUS HandleGetFeature(_In_ WDFREQUEST Req, _In_ PDEVICE_CONTEXT Ctx);
NTSTATUS HandleGetFeature47_Cached(_In_ WDFREQUEST Req, _In_ PDEVICE_CONTEXT Ctx,
                                    _Out_writes_bytes_(OutLen) PUCHAR OutBuf, _In_ size_t OutLen);
NTSTATUS HandleGetFeature47_ActivePoll(_In_ WDFREQUEST Req, _In_ PDEVICE_CONTEXT Ctx,
                                       _Out_writes_bytes_(OutLen) PUCHAR OutBuf, _In_ size_t OutLen);
VOID ForwardRequest(_In_ WDFREQUEST Req, _In_ PDEVICE_CONTEXT Ctx);

// InputHandler.c
EVT_WDF_REQUEST_COMPLETION_ROUTINE OnReadComplete;
NTSTATUS TranslateMouse2Report(_In_reads_bytes_(InLen) PUCHAR InBuf, _In_ size_t InLen,
                               _Out_writes_(8) PUCHAR OutBuf, _In_ PDEVICE_CONTEXT Ctx);
NTSTATUS TranslateMouse1Report(_In_reads_bytes_(InLen) PUCHAR InBuf, _In_ size_t InLen,
                               _Out_writes_(8) PUCHAR OutBuf, _In_ PDEVICE_CONTEXT Ctx);
VOID EmitTouch(_In_ PDEVICE_CONTEXT Ctx, _In_ int RawId, _In_ PUCHAR Tdata, _Inout_ PSCROLL_DELTA Delta);
VOID UpdateBatteryCache(_In_ PDEVICE_CONTEXT Ctx, _In_ UCHAR Pct);

// HidDescriptor.c
extern const UCHAR g_HidDescriptor[];
extern const ULONG g_HidDescriptorLen;
extern const HID_DESCRIPTOR g_HidProtocolDescriptor;
extern const HID_DEVICE_ATTRIBUTES g_HidDeviceAttributes_v1;
extern const HID_DEVICE_ATTRIBUTES g_HidDeviceAttributes_v3;
```

---

## 10. Data structures

### 10a. DEVICE_CONTEXT

```c
typedef struct _DEVICE_CONTEXT {
    WDFDEVICE      Device;
    WDFIOTARGET    IoTarget;            // lower target (HidBth + device)
    WDFQUEUE       IoctlQueue;          // sequential
    WDFQUEUE       ReadQueue;           // parallel

    USHORT         Vid;
    USHORT         Pid;                 // 0x030D / 0x0310 / 0x0323
    BOOLEAN        IsV3;                // Pid == 0x0323

    // Battery cache
    KSPIN_LOCK     BatteryLock;
    LARGE_INTEGER  BatteryCachedAt;     // KeQuerySystemTime units (100ns)
    UCHAR          BatteryCachedPct;    // 0..100, 0xFF = no value yet

    // Touch / scroll state (per finger id 0..15)
    TOUCH_STATE    Touches[16];
    LARGE_INTEGER  ScrollLastTime;
    INT            ScrollAccel;         // 1..4

    // Tunables (read once from registry at AddDevice; defaults if absent)
    UCHAR          ScrollSpeed;         // default 32
    BOOLEAN        EmulateScrollWheel;  // default TRUE
    BOOLEAN        Emulate3Button;      // default TRUE
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;
WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, GetDeviceContext)
```

### 10b. TOUCH_STATE

```c
typedef struct _TOUCH_STATE {
    INT     ScrollX, ScrollY;            // last delta-baseline position
    INT     ScrollXHr, ScrollYHr;        // HR baseline
    BOOLEAN ScrollXActive, ScrollYActive;
    INT     LastSize;                    // last touch_major
} TOUCH_STATE;
```

### 10c. REQUEST_CONTEXT

```c
typedef struct _REQUEST_CONTEXT {
    UCHAR   OriginalReportId;            // for IOCTL_HID_READ_REPORT completion routing
    PVOID   OriginalBuffer;              // upstream buffer to fill on translation
    size_t  OriginalLen;
    BOOLEAN IsTranslatedRead;            // distinguishes synthesised vs pass-through
} REQUEST_CONTEXT, *PREQUEST_CONTEXT;
WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(REQUEST_CONTEXT, GetRequestContext)
```

---

## 11. Failure modes

| # | Failure | Symptom | Mitigation |
|---|---------|---------|------------|
| F1 | v3 firmware doesn't respond to GET_REPORT for 0x90 within timeout | Battery reads return STATUS_TIMEOUT; tray displays N/A | 500ms timeout in `HandleGetFeature47_ActivePoll`; fall through to STATUS_NO_DATA; tray's existing retry logic re-polls on next adaptive interval |
| F2 | AddDevice race: HidClass calls GET_REPORT_DESCRIPTOR before IoTarget is up | Driver returns wrong/empty descriptor; HidClass FDO fails to parse | Initialise `g_HidDescriptor[]` as static const; queue IoTarget creation in EvtDevicePrepareHardware; descriptor IOCTL handler uses static buffer regardless of IoTarget state |
| F3 | v1 regression: M12 over-mutates v1's working descriptor and breaks Feature 0x47 | v1 tray shows N/A after M12 install | PID branch in IOCTL handler routes v1 0x47 IOCTLs straight downstream (Section 7c). Validation gate: VG-2 (MOP) — v1 must produce `OK battery=N% (Feature 0x47)` BEFORE v3 testing begins. v1 regression halts the rollout. |
| F4 | Scroll input report 0x12 arrives during driver init (before scroll state initialised) | First touches produce uninitialised step calculations -> wild deltas | DEVICE_CONTEXT zeroed at AddDevice; `EmulateScrollWheel` gate; `TOUCH_STATE_START` (0x30) state always resets per-id baselines before deltas computed |
| F5 | Touch report size validation fails (corrupt or truncated packet) | Driver drops packet | size != 8 AND (size < 14 OR (size - 14) % 8 != 0) -> drop, return STATUS_SUCCESS with no upstream emit. Linux pattern. No crash. |
| F6 | Memory pressure: `WdfRequestRetrieveOutputBuffer` returns NULL | IOCTL fails with STATUS_INSUFFICIENT_RESOURCES | Standard KMDF handling — complete request with status; HidClass retries or fails the call upstream |
| F7 | BSOD on first install due to descriptor malformed | Bugcheck 0xC4 (Driver Verifier) or HidClass parse failure | Pre-install validation gate: `hidparser.exe g_HidDescriptor[]` must pass clean. MOP step PRE-1 enforces this before signtool. |
| F8 | Driver sees both v1 and v3 AddDevice but the user only paired one | Spurious DEVICE_CONTEXT for unbound PID | EvtDeviceAdd succeeds for any matched PID; if PID is not in {0x030D, 0x0310, 0x0323} the driver returns STATUS_DEVICE_CONFIGURATION_ERROR — INF should not have matched. Defensive but unreachable. |
| F9 | Race between cached battery read and active poll | Two concurrent GET_FEATURE callers, one stale, one fresh | KSPIN_LOCK around battery cache read/write; sequential IOCTL queue serialises GET_FEATURE callers anyway; double-poll possible but harmless |
| F10 | DSM property-write triggers re-enumeration mid-session | M12 EvtDeviceRemove + EvtDeviceAdd cycle; battery cache lost | Acceptable — cache TTL is 30s, re-poll on next IOCTL. No data loss, brief N/A visible in tray for one poll cycle. |
| F11 | PnP rank: M12 INF is outranked by Apple's `applewirelessmouse` or MU's `magicmouse.inf` | Old driver wins on install, M12 doesn't bind | MOP step INSTALL-3: `pnputil /enum-drivers` enumeration BEFORE install; if competing INFs present, MOP halts and asks user; if installed alongside, `pnputil /delete-driver oem<N>.inf` only with backup verification (per AP-24, feedback_backup_before_destructive_commands) |
| F12 | WDF version skew: M12 builds against KMDF 1.33 but target is older | Driver fails to load, error 31 | KMDF version pinned in `MagicMouseDriver.vcxproj` to 1.15 (matches MU `MagicMouse.sys` and OS minimum); EWDK 25H2 supports 1.15-1.33 |
| F13 | BTHPORT SDP cache trap: HidBth reads cached descriptor on already-paired devices and never re-issues SDP | M12 BRB-level mutation never fires on first install; mice still report Mode B descriptor; tray N/A on v3 | Pre-validation step VG-0 confirms HIDP_GetCaps post-install (Input=8, Feature=2, LinkColl=5 = Mode A). On Mode B detection: MOP step 7c-pre wipes `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<mac>\CachedServices\00010000` (with reg backup per AP-24) OR escalates to operator unpair + re-pair (safe default). |
| F14 | Sequential IOCTL queue blocks all callers when active-poll path stalls on downstream GET_REPORT 0x90 | UI stutter, PnP power-state queries delayed, possible driver watchdog bugcheck under tight timeouts | Mitigation 1: shorten downstream timeout from 500ms to 200ms and back-off cache TTL on consecutive timeouts. Mitigation 2 (reserved for VG-4 soak triage): move `HandleGetFeature47_ActivePoll` to a dedicated parallel queue isolated from descriptor + attribute IOCTLs. Implemented in M12-Skeleton, validated in VG-4. |

---

## 12. Open questions

The following items are intentionally LEFT OPEN at design time and resolved in implementation by direct empirical test:

- **OQ-1:** Exact byte layout of v3 input report 0x12 padding (bytes 7-13). Linux comments suggest data[11..13] are timestamp; we will log incoming reports during first install and confirm before relying on any specific offset beyond what Linux specifies.
- **OQ-2:** Whether v3 emits unsolicited Input 0x90 reports often enough that the cached-input path (Section 7a) is the primary source vs. the active-poll path (Section 7b). First install logs will reveal cache-hit ratio; if low (<80%), increase poll proactiveness.
- **OQ-3:** Whether the existing tray's `MouseBatteryReader.cs` `unifiedAppleBattery` path needs any tweak. The tray calls `HidD_GetFeature(0x47)` and checks for a 1-byte battery percentage in the response. M12 returns `[0x47, pct]` (2 bytes). Existing tray code reads `buf[1]` for pct in the unified path — should match. Confirm during MOP step VG-1.
- **OQ-4:** PID 0x0310 binding behaviour. The user owns v1 PID 0x030D; PID 0x0310 is included for completeness but never empirically tested. If a v1 mouse advertises 0x0310 and binds, treat as v1 in PID branch. Add log line on first 0x0310 AddDevice for visibility.
- **OQ-5:** Resolution Multiplier feature reports (RIDs 0x03, 0x04). HidClass may issue `IOCTL_HID_GET_FEATURE` for these at init to discover wheel resolution. M12 returns `0` (multiplier=1, default-low-resolution) until empirical validation confirms whether returning `1` (high-res) is required for the tray to see scroll properly.

---

## 13. References

### Primary references (clean-room, public)

- Linux kernel `drivers/hid/hid-magicmouse.c` — algorithm reference, GPL-2. Read-only. Fetched 2026-04-28 from `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/hid/hid-magicmouse.c`. M12 describes the algorithm in our own words; no source-code or binary fragment is copied.
- Microsoft Learn — KMDF Filter Drivers: `https://learn.microsoft.com/en-us/windows-hardware/drivers/wdf/creating-a-kmdf-filter-driver` and "Creating a Filter Driver" series.
- Microsoft Learn — HID Architecture: `https://learn.microsoft.com/en-us/windows-hardware/drivers/hid/hid-architecture`.
- USB-IF HID 1.11 spec (descriptor encoding).

### Captured artefacts (this project)

- `D:\Backups\MagicUtilities-Capture-2026-04-28-1937\` (41 files, 78.6 MB) — MU 3.1.5.2 install state for INF reference patterns. Static analysis only; no binary or source content is embedded in M12.
- `D:\Backups\AppleWirelessMouse-RECOVERY\` — Apple/tealtadpole driver for v1 baseline regression test recovery.
- `.ai/test-runs/2026-04-27-154930-T-V3-AF/hid-descriptor-full-v3-col01.txt` — Mode A descriptor capture (target output).
- `.ai/test-runs/2026-04-27-154930-T-V3-AF/hid-descriptor-full-v3.txt` — Mode B descriptor (Apple filter, control comparison).
- `docs/M12-GHIDRA-FINDINGS.md` — first-pass static analysis of `MagicMouse.sys` (size profile, imports, strings).

### Decision documents

- `Personal/prd/184-magic-mouse-windows-tray-battery-monitor.md` v1.26 — PRD (this PR updates it).
- `magic-mouse-tray/PSN-0001-hid-battery-driver.yaml` v1.9 — hypothesis + decision catalogue.
- `magic-mouse-tray/.ai/playbooks/autonomous-agent-team.md` v1.8 — workflow rules.
- `magic-mouse-tray/docs/M12-MAGIC-UTILITIES-REFERENCE-PLAN.md` — earlier RE plan (314 lines), superseded by this design spec.
- `magic-mouse-tray/docs/M12-PEER-REVIEW-NOTEBOOKLM-2026-04-28.md` — earlier NLM peer review of the RE plan; conclusions material to this design (especially Q6: v1-as-control is incomplete; v3-specific tests required).

### Legal basis (interoperability exemptions)

- USA: `17 U.S.C. section 1201(f)` (DMCA interoperability exemption).
- Canada: `R.S.C. 1985, c. C-42, s. 30.61` (Copyright Act interoperability exemption).
- EU: Software Directive 2009/24/EC Article 6 (decompilation for interoperability).

Interoperability target: Apple Magic Mouse hardware. M12 is independently authored. Captured Magic Utilities artefacts and Linux source are read for facts (API patterns, report formats, algorithm descriptions); no expression is copied.
