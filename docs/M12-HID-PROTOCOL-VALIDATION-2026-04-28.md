# M12 HID Protocol Validation -- 2026-04-28

Analyst: Claude Sonnet 4.6 (ai/m12-hid-protocol-validation agent)
Sources: Phase 1 Ghidra findings, empirical Windows HID caps capture (Mode B),
         Linux hid-magicmouse.c (GPL-2.0, read-only reference), Microsoft Learn HID docs

---

## BLUF

The 116-byte descriptor at applewirelessmouse.sys offset 0xa850 is well-formed and
HID-1.11-compliant. Phase 1's descriptor analysis is substantively correct with one
critical ambiguity resolved: "Max=65" belongs to RID=0x27 (Input vendor blob), NOT
to RID=0x47 (Feature battery). RID=0x47 uses Logical Max=100, which is exactly what
the tray's HidD_GetFeature(0x47) expects. The M12 interception strategy (IRP completion
intercept, extract battery from RID=0x27, translate, fill Feature 0x47 buffer) is
HID-spec-compliant. The Linux hid-magicmouse.c does NOT provide the RID=0x27 battery
byte offset or translation formula -- Linux processes different Report IDs (0x12, 0x29)
over a different descriptor, not Windows RID=0x27. The battery byte offset within
RID=0x27 remains an open empirical question requiring ETW or BT sniff capture.

---

## 116-byte descriptor decode (item-by-item)

Source: applewirelessmouse.sys binary offset 0xa850, confirmed by Phase 1 Ghidra
analysis and cross-validated against Mode B empirical Windows HID caps capture.

HID 1.11 short item encoding: byte 0 = (bTag[7:4] | bType[3:2] | bSize[1:0]).
bType: 0=Main, 1=Global, 2=Local. bSize: 0=0B, 1=1B, 2=2B, 3=4B.

### Top-level Application Collection

| Offset | Bytes      | Item (bType/bTag)     | Value          | Meaning                          |
|--------|------------|-----------------------|----------------|----------------------------------|
| 0      | 05 01      | Global: Usage Page    | 0x01           | Generic Desktop Controls         |
| 2      | 09 02      | Local: Usage          | 0x02           | Mouse                            |
| 4      | A1 01      | Main: Collection      | 0x01           | Application (opens TLC)          |

### Report ID 0x02 -- Input report (Mouse movement + buttons)

| Offset | Bytes      | Item                  | Value          | Meaning                          |
|--------|------------|-----------------------|----------------|----------------------------------|
| 6      | 85 02      | Global: Report ID     | 0x02           | RID = 2                          |
| 8      | 05 09      | Global: Usage Page    | 0x09           | Button                           |
| 10     | 19 01      | Local: Usage Min      | 0x01           | Button 1 (Left)                  |
| 12     | 29 02      | Local: Usage Max      | 0x02           | Button 2 (Right)                 |
| 14     | 15 00      | Global: Logical Min   | 0              | Not pressed                      |
| 16     | 25 01      | Global: Logical Max   | 1              | Pressed                          |
| 18     | 95 02      | Global: Report Count  | 2              | 2 fields                         |
| 20     | 75 01      | Global: Report Size   | 1              | 1 bit per field                  |
| 22     | 81 02      | Main: Input           | 0x02           | Data, Variable, Absolute         |
|        |            |                       |                | --> 2 bits: button state         |
| 24     | 95 01      | Global: Report Count  | 1              | 1 field                          |
| 26     | 75 05      | Global: Report Size   | 5              | 5 bits                           |
| 28     | 81 03      | Main: Input           | 0x03           | Constant (padding)               |
|        |            |                       |                | --> 5 bits: pad to byte boundary |

| 30     | 06 02 FF   | Global: Usage Page    | 0xFF02         | Vendor-defined (Apple)           |
| 33     | 09 20      | Local: Usage          | 0x20           | Vendor Usage 0x20                |
| 35     | 95 01      | Global: Report Count  | 1              |                                  |
| 37     | 75 01      | Global: Report Size   | 1              | 1 bit                            |
| 39     | 81 03      | Main: Input           | 0x03           | Constant (vendor bit, always 0)  |
|        |            |                       |                | --> 1 bit: Apple vendor constant |

| 41     | 05 01      | Global: Usage Page    | 0x01           | Generic Desktop                  |
| 43     | 09 01      | Local: Usage          | 0x01           | Pointer                          |
| 45     | A1 00      | Main: Collection      | 0x00           | Physical (child of Application)  |
| 47     | 15 81      | Global: Logical Min   | -127           | Signed min for axes              |
| 49     | 25 7F      | Global: Logical Max   | 127            | Signed max for axes              |
| 51     | 09 30      | Local: Usage          | 0x30           | X axis                           |
| 53     | 09 31      | Local: Usage          | 0x31           | Y axis                           |
| 55     | 75 08      | Global: Report Size   | 8              | 8 bits per field                 |
| 57     | 95 02      | Global: Report Count  | 2              | 2 fields (X, Y)                  |
| 59     | 81 06      | Main: Input           | 0x06           | Data, Variable, Relative         |
|        |            |                       |                | --> 2 bytes: X + Y delta         |

| 61     | 05 0C      | Global: Usage Page    | 0x0C           | Consumer Controls                |
| 63     | 0A 38 02   | Local: Usage          | 0x0238         | AC Pan (horizontal scroll)       |
| 66     | 75 08      | Global: Report Size   | 8              | 8 bits                           |
| 68     | 95 01      | Global: Report Count  | 1              | 1 field                          |
| 70     | 81 06      | Main: Input           | 0x06           | Data, Variable, Relative         |
|        |            |                       |                | --> 1 byte: horizontal scroll    |

| 72     | 05 01      | Global: Usage Page    | 0x01           | Generic Desktop                  |
| 74     | 09 38      | Local: Usage          | 0x38           | Wheel (vertical scroll)          |
| 76     | 75 08      | Global: Report Size   | 8              | 8 bits                           |
| 78     | 95 01      | Global: Report Count  | 1              | 1 field                          |
| 80     | 81 06      | Main: Input           | 0x06           | Data, Variable, Relative         |
|        |            |                       |                | --> 1 byte: vertical scroll      |

| 82     | C0         | Main: End Collection  | --             | Closes Physical (Pointer)        |

### Report ID 0x47 -- Feature report (synthesized battery percentage)

| Offset | Bytes      | Item                  | Value          | Meaning                          |
|--------|------------|-----------------------|----------------|----------------------------------|
| 83     | 05 06      | Global: Usage Page    | 0x06           | Generic Device Controls          |
| 85     | 09 20      | Local: Usage          | 0x20           | Battery Strength (HUT 1.4)       |
| 87     | 85 47      | Global: Report ID     | 0x47           | RID = 71 decimal                 |
| 89     | 15 00      | Global: Logical Min   | 0              | 0% battery                       |
| 91     | 25 64      | Global: Logical Max   | 100 (0x64)     | 100% battery                     |
| 93     | 75 08      | Global: Report Size   | 8              | 8 bits                           |
| 95     | 95 01      | Global: Report Count  | 1              | 1 field                          |
| 97     | B1 A2      | Main: Feature         | 0xA2           | Data, Variable, Absolute,        |
|        |            |                       |                | No Preferred, No Null            |
|        |            |                       |                | --> 1 byte: battery 0-100        |

### Report ID 0x27 -- Input report (vendor blob pass-through)

| Offset | Bytes      | Item                  | Value          | Meaning                          |
|--------|------------|-----------------------|----------------|----------------------------------|
| 99     | 05 06      | Global: Usage Page    | 0x06           | Generic Device Controls          |
| 101    | 09 01      | Local: Usage          | 0x01           | Battery Strength (alt usage)     |
| 103    | 85 27      | Global: Report ID     | 0x27           | RID = 39 decimal                 |
| 105    | 15 01      | Global: Logical Min   | 1              | Vendor raw min                   |
| 107    | 25 41      | Global: Logical Max   | 65 (0x41)      | Vendor raw max                   |
| 109    | 75 08      | Global: Report Size   | 8              | 8 bits per field                 |
| 111    | 95 2E      | Global: Report Count  | 46             | 46 fields                        |
| 113    | 81 06      | Main: Input           | 0x06           | Data, Variable, Relative         |
|        |            |                       |                | --> 46 bytes: raw Apple format   |

### Descriptor close

| Offset | Bytes      | Item                  | Value          | Meaning                          |
|--------|------------|-----------------------|----------------|----------------------------------|
| 115    | C0         | Main: End Collection  | --             | Closes Application               |

Total: 116 bytes (offsets 0 through 115). Confirmed against binary range 0xa850-0xa8c3.

### Descriptor structural validity

Per HID 1.11 section 6.2.2:
- Every opened Collection is matched by an End Collection: 2 opens, 2 closes. VALID.
- Report IDs are unique within the TLC (0x02, 0x27, 0x47). VALID.
- All short items have valid bSize (0, 1, or 2 bytes). VALID.
- Global state stack is self-consistent (Usage Page restored explicitly at each section). VALID.
- Usage Page 0x06 (Generic Device Controls) is a defined HUT 1.4 page. VALID.
- Usage 0x20 (Battery Strength) is a defined usage on page 0x06. VALID.
- Usage 0x38 (Wheel) on page 0x01 is Generic Desktop Wheel. VALID.
- Usage 0x238 (AC Pan) on page 0x0C is Consumer Controls Horizontal Scroll. VALID.
- Feature item B1 A2: bTag=0xB (Feature), Data/Variable/Absolute flags. VALID.

Verdict: descriptor is well-formed and correctly declares all three report structures.

---

## RID=0x47 (Feature) semantics

Data from empirical Windows HID caps capture (Mode B, applewirelessmouse filter active):

  Feature Value Caps [0]:
    RID=0x47, UP=0x0006, Usage=0x20
    BitField=0x00A2, BitSize=8, ReportCount=1
    LogMin=0, LogMax=100, PhysMin=0, PhysMax=0

- Logical Min: 0
- Logical Max: 100
- Physical Min: 0, Physical Max: 0 (per HID 1.11 section 6.2.2.7: both zero means
  Physical extent equals Logical extent; no unit conversion applied)
- Report Size: 8 bits
- Report Count: 1 field
- On-wire feature report: 2 bytes total [ReportID=0x47] [percentage_value]
- Feature flags 0xA2: Data(0), Variable(1), Absolute(0), No Preferred(1), No Null(1)

Verified against tray expectations: YES.
The tray's HidD_GetFeature(0x47) call submits a 2-byte buffer [0x47, 0x00].
hidclass.sys routes this to the device as a GET_REPORT for RID=0x47.
M12 intercepts the completion and writes [0x47, percentage_byte] where
percentage_byte is in range 0-100. This is exactly what the declared descriptor
says to expect. No scale conversion needed at the Feature 0x47 layer.

---

## RID=0x27 (Input vendor blob) layout

Data from empirical Windows HID caps capture (Mode B):

  Input Value Caps [4]:
    RID=0x27, UP=0x0006, Usage=0x1
    BitField=0x0006, BitSize=8, ReportCount=46
    LogMin=1, LogMax=65, PhysMin=0, PhysMax=0

- Total payload size: 46 bytes
- On-wire input report: 47 bytes [ReportID=0x27] [46 bytes vendor data]
- Logical range: 1-65 (raw Apple firmware units, NOT a percentage)
- Physical range: undefined (both 0 = same as Logical)
- Usage declared: 0x0006/0x01 (Generic Device Controls / Battery Strength alt usage)
- BitField 0x0006: Data, Variable, Relative

The Max=65 descriptor parameter applies ONLY to RID=0x27. It does NOT apply to
RID=0x47. These are two separate, independent report definitions. Phase 1 correctly
listed both with different Max values but the open-question framing implied ambiguity
about which RID owned which Max. This is now resolved unambiguously.

### Battery byte offset within RID=0x27: UNRESOLVED

The Linux hid-magicmouse.c does NOT process RID=0x27. Linux handles:
- MOUSE_REPORT_ID = 0x29 (original v1 mouse)
- MOUSE2_REPORT_ID = 0x12 (v2/v3 mouse, also USB)
- TRACKPAD_REPORT_ID = 0x28 (original trackpad)
- TRACKPAD2_BT_REPORT_ID = 0x31 (v2 trackpad BT)
- TRACKPAD2_USB_REPORT_ID = 0x02 (v2 trackpad USB)

RID=0x27 is an Apple Windows-only format introduced by applewirelessmouse.sys.
Linux never sees it because the Linux driver uses a completely different HID
descriptor (not the applewirelessmouse.sys synthesized one).

The MOUSE2_REPORT_ID=0x12 handler in magicmouse_raw_event reads touch data from
data[14..] and buttons from data[1], x from data[2..3], y from data[4..5].
This is the Linux v3 mouse format -- unrelated to the Windows RID=0x27 blob.

Linux obtains battery via the HID battery subsystem through magicmouse_fetch_battery,
which calls hid_hw_request for a feature report (ReportID=0xF1 or similar) for USB
devices only. For BT devices Linux relies on the HID battery class built into the
kernel from the device's declared battery capability -- NOT from a vendor blob byte.

Result: Linux source provides NO usable battery byte offset for Windows RID=0x27.

### Notable fields in RID=0x27 (from empirical/reverse-eng context)

Based on Phase 1 analysis and the empirical 47-byte input report length:
- Byte 0: ReportID (0x27, consumed by Windows HID class before delivery to driver)
- Bytes 1..46: Raw Apple firmware payload (native BT format)
- The payload includes: button state, timestamp, touch data, and device status fields
- The specific byte offset for battery within bytes 1..46 is undetermined without
  ETW input trace or Bluetooth sniff capture at a known battery level

Required to resolve: Capture RID=0x27 raw bytes via ETW HID trace or Bluetooth HCI
sniff while battery indicator shows a known level (e.g., 100% vs 20%).

### Translation algorithm (raw to percentage)

Given Logical Min=1, Max=65 for RID=0x27 and Logical Min=0, Max=100 for RID=0x47:

If the battery field in RID=0x27 is a linear raw value in range [1..65]:
  percentage = (raw_value - 1) * 100 / 64
  Example: raw=1 -> 0%, raw=33 -> 50%, raw=65 -> 100%

If the raw value is in range [0..64] (despite Logical Min=1):
  percentage = raw_value * 100 / 64

Neither formula is confirmed. The Logical Min=1 suggests the firmware never reports
0 (device is off/disconnected when battery is exhausted), making the first formula
more likely. However, this is a hypothesis -- not empirically validated.

Linux provides NO lookup table for this conversion. The Linux driver does not access
RID=0x27 at all. Translation formula requires empirical validation.

---

## Translation algorithm verification

### M12 interception strategy HID-1.11 compliance assessment

The proposed strategy:
  (a) Tray sends HidD_GetFeature with ReportID=0x47
  (b) hidclass.sys constructs IOCTL_HID_GET_FEATURE IRP, sends downward
  (c) M12 (positioned as lower filter below hidclass.sys, above hidbth.sys) sets
      an IoCompletion callback on the IRP before forwarding it
  (d) Device (via hidbth.sys) returns STATUS_INVALID_PARAMETER / err=87
  (e) M12's completion callback fires: M12 reads the last-cached RID=0x27 byte at
      offset N, applies translation formula, writes percentage into IRP output buffer,
      completes the IRP with STATUS_SUCCESS
  (f) hidclass.sys delivers the 2-byte Feature buffer to the tray application

HID 1.11 section 7.2 GET_REPORT compliance:
- The spec requires the device to return a Feature report matching the declared
  descriptor. Since applewirelessmouse.sys synthesizes the descriptor, the HID
  class driver trusts the descriptor and passes the GET_REPORT request to the device.
- There is no HID spec prohibition on a filter driver intercepting the completion
  path of a Feature report IRP and substituting synthesized data.
- The descriptor declares RID=0x47 as Feature(Data,Variable,Absolute) with 1 byte,
  range 0-100. M12's synthesized response conforms to this declaration. VALID.

IRP ordering compliance:
- M12 sets IoCompletion via IoSetCompletionRoutine before calling IofCallDriver.
  This is the standard Windows lower-filter IRP interception pattern.
- Completing the IRP with STATUS_SUCCESS after overwriting the buffer is valid
  when the IRP status indicates failure (err=87) from below.
- Replacing a failure status with STATUS_SUCCESS is permitted for filter drivers
  when they provide a valid synthetic response. The hidclass.sys client (tray app)
  receives a valid feature buffer and success status. COMPLIANT.

Cancellation safety:
- The IRP could be cancelled between the M12 forward call and the completion
  callback firing. M12 must check Irp->Cancel in the completion routine before
  overwriting the buffer. If cancelled, complete with STATUS_CANCELLED and do not
  overwrite. Standard kernel IRP handling requirement; no HID-specific concern here.

Short-circuit alternative (do not forward to device):
- M12 could alternatively short-circuit the IRP without forwarding to the device,
  immediately completing with STATUS_SUCCESS and the cached percentage.
- This avoids the err=87 round-trip and the cancellation window.
- Equally HID-1.11-compliant since the feature value comes from the synthesized
  descriptor which M12 owns.
- Recommended as the simpler implementation path if RID=0x27 shadow buffer is
  fresh (< some configurable staleness threshold, e.g., 30 seconds).

Verdict: M12's interception strategy is HID-spec-compliant under both approaches.
The short-circuit approach is slightly simpler and eliminates the cancellation race.

---

## Discrepancies between Phase 1 finding and HID spec

### Discrepancy 1: "Max=65" report -- ambiguous attribution (RESOLVED)

Phase 1 open question stated: "RID=0x47 ... Max=65 not 100 -- these are different
reports; Phase 1's wording was ambiguous."

Actual state:
- RID=0x47 Feature: Logical Max=100 (0x64). Confirmed by byte 91 (25 64) in
  descriptor and empirical caps: LogMax=100.
- RID=0x27 Input: Logical Max=65 (0x41). Confirmed by byte 107 (25 41) in
  descriptor and empirical caps: LogMax=65.

Phase 1's descriptor table listed both correctly (25 64 for RID=0x47, 25 41 for
RID=0x27). The ambiguity was only in the open-question prose, not in the byte listing.

Resolution: RID=0x47 is always 0-100. RID=0x27 raw values are 1-65 (vendor scale).
No change to descriptor bytes needed. No change to M12 Feature 0x47 target range.

### Discrepancy 2: "Logical Max=65 -> percentage" formula -- unverified in Phase 1

Phase 1 left the translation formula as an open question. This validation confirms
the formula is NOT resolvable from hid-magicmouse.c because Linux does not process
RID=0x27. The formula remains empirically unvalidated.

Candidate (best-guess, not confirmed):
  percentage = (raw - 1) * 100 / 64  [for raw in range 1..65]

This discrepancy does NOT block Phase 2 design spec -- the formula can be expressed
as a parameter that gets validated during Phase 3 integration testing. M12's
translation layer should be written as a configurable function, not a hardcoded
constant, so the formula can be corrected without a recompile.

### Discrepancy 3: RID=0x27 declared as "Input" not "Feature" -- design implication

Phase 1 correctly identified RID=0x27 as an Input report (81 06, not B1 xx).
This has a specific design implication that was not fully articulated:

RID=0x27 data arrives asynchronously via the input interrupt pipe, NOT via a
GET_REPORT poll. M12 cannot issue a synchronous GET_REPORT for RID=0x27 on demand
when a Feature 0x47 request arrives. M12 MUST maintain a shadow buffer of the
last-received RID=0x27 input event and read the battery byte from that cache.

If no RID=0x27 has been received yet (device just connected, shadow buffer empty),
M12 must decide: return 0% (safe default), return STATUS_NOT_READY (tray will retry),
or use a configurable default. This is a new design constraint not in Phase 1.

### Discrepancy 4: Linux battery path is feature-poll-based, not vendor-blob-based

Phase 1 referenced hid-magicmouse.c as a potential source for the battery offset.
This validation confirms Linux uses a completely different mechanism:
- For USB v2/v3: timer-based hid_hw_request for a USB feature report (not RID=0x27)
- For BT v1 original: the HID battery subsystem using the device's declared feature
- Neither path intersects with Windows RID=0x27 input reports

Linux is NOT a useful reference for the RID=0x27 battery byte offset.
The only useful reference for that offset is Windows ETW trace or BT HCI sniff.

---

## Cross-check against Linux hid-magicmouse.c

The Linux driver handles the v3 Magic Mouse under MOUSE2_REPORT_ID = 0x12.
In magicmouse_raw_event(), the case MOUSE2_REPORT_ID block:
- Accepts packets of size 8 or (14 + 8*N)
- Extracts touch data from data[14..] in 8-byte chunks (N fingers)
- Reads buttons from data[1], X from data[2..3], Y from data[4..5]
- Passes click/button state to magicmouse_emit_buttons()
- Reports relative X, Y via input_report_rel()

The descriptor fixup in magicmouse_report_fixup() patches the firmware's native
descriptor by replacing bytes at rdesc[0..3] to change Usage Page 0xFF00 (Vendor)
to 0x0001 (Generic Desktop) and Usage 0x0B to 0x02 (Mouse). This is a 4-byte
in-memory fixup applied after hid_parse reads the firmware descriptor. The fixup
applies to USB v2/v3 devices (is_usb_magicmouse2 check). For Bluetooth devices,
no fixup is applied -- the firmware descriptor is used as-is by the kernel HID class.

For battery on USB v2/v3: magicmouse_fetch_battery() calls hid_hw_request for the
battery HID report (identified via hid_get_battery() and the report_enum hash table).
This is a USB control transfer GET_REPORT for a feature report declared in the USB
firmware descriptor -- unrelated to the Windows synthesized descriptor or RID=0x27.

Report IDs in hid-magicmouse.c vs Windows applewirelessmouse.sys synthesized descriptor:

| Linux REPORT_ID | Hex | Device        | Windows equivalent      |
|-----------------|-----|---------------|-------------------------|
| MOUSE_REPORT_ID | 0x29| v1 BT mouse   | No equivalent in Win32  |
| MOUSE2_REPORT_ID| 0x12| v2/v3 mouse   | No equivalent in Win32  |
| TRACKPAD_REPORT_ID|0x28| v1 BT trackpad| No equivalent in Win32  |
| TRACKPAD2_BT_REPORT_ID|0x31|v2 trackpad BT|No equivalent in Win32 |
| TRACKPAD2_USB_REPORT_ID|0x02|v2 trackpad USB|Partial overlap RID=0x02|

Windows applewirelessmouse.sys synthesized report IDs:

| Windows RID | Type    | Content                             |
|-------------|---------|-------------------------------------|
| 0x02        | Input   | Buttons + X/Y + Pan + Wheel (5 bytes)|
| 0x27        | Input   | Apple vendor blob (46 bytes)        |
| 0x47        | Feature | Synthesized battery (1 byte, 0-100) |

The only overlap is RID=0x02 on the trackpad USB side. For the v3 BT mouse,
Linux and Windows use entirely different report ID schemes. Linux and Windows
are completely decoupled after the firmware reports via BT interrupt.

Conclusion: hid-magicmouse.c is not a useful reference for RID=0x27 internals.

---

## Open issues (escalate to design author)

### OI-1: Battery byte offset in RID=0x27 [BLOCKING for Phase 3 battery logic]

The exact byte offset (N) within the 46-byte vendor payload for the battery
value is unknown. This is the primary open empirical question from Phase 1,
and it remains unresolved after this protocol validation because no reference
source (Linux, Ghidra static strings, HID spec) provides it.

Recommended resolution path:
  Option A (ETW trace): Run Windows HID ETW provider while monitoring battery
    level. Capture RID=0x27 raw bytes at 100% and at 20%. Diff the bytes;
    the changing byte is the battery field.
  Option B (BT HCI sniff): Capture Bluetooth HCI traffic with Wireshark + btsnoop.
    RID=0x27 packets appear on L2CAP CID 0x13 (interrupt channel). Same diff approach.
  Option C (empirical probe): Write a kernel-mode probe that logs all RID=0x27
    bytes during a session; correlate with system battery indicator over time.

This should be resolved before Phase 3 implementation of the translation function.
Phase 2 design spec can use a placeholder constant (e.g., BATTERY_OFFSET = 0)
with a TODO gate.

### OI-2: Translation formula validation [BLOCKING for Phase 3 battery accuracy]

The formula (raw - 1) * 100 / 64 is a hypothesis based on the descriptor's
Logical Min=1, Max=65. It has not been validated against observed raw values.

Once OI-1 is resolved (byte offset known), validation is straightforward:
  At 100% charge: raw value should be 65 (or close), formula yields 100%.
  At low charge: raw value should approach 1, formula yields 0%.

If the raw values do not follow a linear distribution against actual battery level,
a lookup table may be needed. This is a Phase 3 implementation detail.

### OI-3: Shadow buffer staleness threshold

When the tray calls HidD_GetFeature(0x47), M12 reads from the RID=0x27 shadow
buffer. If the mouse has been idle (no input events), the shadow buffer may be
stale. Determine acceptable staleness threshold and behavior when stale.

Recommended: return STATUS_NOT_READY if shadow buffer age > 60 seconds, allowing
the tray to show "unknown" rather than a stale percentage.

### OI-4: First-boot behavior (no RID=0x27 received yet)

On driver load, the shadow buffer is empty. If the tray polls before any RID=0x27
arrives, M12 must handle this gracefully. Options: return 0, return STATUS_NOT_READY,
or issue a proactive GET_REPORT for another report ID to trigger a device response.
Design decision needed in Phase 2.

---

## Recommendations for design spec

1. Descriptor injection: Copy the 116 bytes verbatim from binary offset 0xa850.
   Do not redesign. The descriptor is HID-1.11 compliant as-is.

2. Feature 0x47 response buffer: 2 bytes [0x47, percentage_byte] where
   percentage_byte is UINT8 in range 0-100. No additional framing needed.

3. Translation function signature (pseudocode):
     UINT8 TranslateBatteryRaw(UINT8 raw) {
       if (raw < 1) return 0;
       if (raw > 65) return 100;
       return (UINT8)((raw - 1) * 100 / 64);
     }
   Implement as a standalone function with a #define for the constants so
   they can be updated without structural changes when empirical data arrives.

4. IRP interception: Prefer the short-circuit approach (do not forward to device).
   Set IoCompletion on the GET_FEATURE IRP, but complete it immediately from the
   shadow buffer without forwarding. This eliminates the err=87 round-trip and
   the cancellation race window.

5. Shadow buffer: Allocate in non-paged pool. Size: 47 bytes (1 RID byte + 46
   payload bytes). Update atomically via InterlockedExchange or KSPIN_LOCK.
   Store a timestamp (KeQuerySystemTime) alongside the data for staleness checks.

6. Battery byte offset: Use BATTERY_BYTE_OFFSET = TBD as a named constant.
   Wire it to a registry-readable value so it can be set without recompile during
   Phase 3 validation. Default to 0 (first payload byte) as a safe placeholder.

7. Phase 3 acceptance test must include: RID=0x27 raw byte logging at known battery
   level before the battery offset constant is finalized. This is a required step,
   not optional. Gate Phase 3 completion on this empirical confirmation.

---

## Source confidence table

| Claim                              | Source                          | Confidence  |
|------------------------------------|---------------------------------|-------------|
| 116-byte descriptor at 0xa850      | Phase 1 Ghidra + binary         | CONFIRMED   |
| Descriptor is well-formed HID 1.11 | Item-by-item parse (this doc)   | CONFIRMED   |
| RID=0x47 Logical Max=100           | Empirical caps + byte 91 (25 64)| CONFIRMED   |
| RID=0x27 Logical Max=65            | Empirical caps + byte 107 (25 41)| CONFIRMED  |
| RID=0x27 is Input (not Feature)    | Byte 113 (81 06) + empirical    | CONFIRMED   |
| err=87 = passive passthrough (no trap)| Phase 1 AP-19 analysis        | CONFIRMED   |
| Linux uses different RIDs          | hid-magicmouse.c line 58-62     | CONFIRMED   |
| Battery byte offset in RID=0x27    | No source available             | UNRESOLVED  |
| Translation formula                | Hypothesis from descriptor range| UNVERIFIED  |
| IRP short-circuit compliance       | HID 1.11 s7.2 + MS Learn docs   | CONFIRMED   |

---

Document version: 1.0
Session: ai/m12-hid-protocol-validation
Date: 2026-04-28
