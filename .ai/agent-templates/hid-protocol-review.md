# HID Protocol Expert -- Review Template

## Role

HID protocol specialist cross-checking implementation against HID Usage Tables 1.4,
HID 1.11 specification, Bluetooth HIDP, and the Linux hid-magicmouse.c driver
(GPL-2, read-only reference). Focus: descriptor byte correctness, report ID semantics,
IRP contracts, and IOCTL completion patterns. Verdicts are backed by byte-level
citations from the spec or empirical captures.

---

## Required reading (always)

1. The PR diff (every .c, .h, .inf change)
2. docs/M12-HID-PROTOCOL-VALIDATION-2026-04-28.md -- item-by-item descriptor decode
   (confirmed byte offsets, RID semantics, Linux cross-check conclusions)
3. .ai/rev-eng/ -- Phase 1 Ghidra findings (applewirelessmouse binary analysis)
4. .ai/test-runs/ -- empirical Windows HID caps capture (Mode B)

---

## Required reading (per topic)

| Topic | Reference |
|---|---|
| Descriptor byte encoding | HID 1.11 section 6.2.2 (short item format) |
| Report ID semantics | HID 1.11 section 8.1 (Report IDs) |
| Logical / Physical min/max | HID 1.11 section 6.2.2.7 |
| IOCTL contracts | MSDN IOCTL_HID_GET_FEATURE, IOCTL_HID_READ_REPORT, IOCTL_HID_GET_REPORT_DESCRIPTOR |
| Feature vs Input report handling | HID 1.11 section 7.2 (GET_REPORT); IRP_MJ_INTERNAL_DEVICE_CONTROL |
| applewirelessmouse descriptor | Offset 0xa850 in binary (116 bytes); confirmed in M12-HID-PROTOCOL-VALIDATION-2026-04-28.md |
| MagicUtilities (MU) descriptors | docs/M12-APPLEWIRELESSMOUSE-FINDINGS.md (Mode A layout) |
| Linux source | /tmp/m12-refs/hid-magicmouse.c (read-only; GPL-2) -- RID 0x12 for v3 mouse |

---

## Review checklist

Copy this block verbatim into your review output. Mark each item PASS / FAIL / N/A.
For every FAIL, cite byte offset or line number and include the correct byte sequence.

```
[ ] 1.  DESCRIPTOR BYTE CORRECTNESS
        - Every byte in the static descriptor array matches the 116-byte empirical
          capture at applewirelessmouse.sys offset 0xa850, OR the deviation is
          explicitly documented with HID 1.11 justification.
        - Item prefix bytes are correct:
          - Global items: 0x05 (Usage Page 1B), 0x15 (LogMin 1B), 0x25 (LogMax 1B),
            0x16 (LogMin 2B), 0x26 (LogMax 2B), 0x75 (Report Size), 0x95 (Report Count)
          - Local items: 0x09 (Usage 1B), 0x19 (Usage Min), 0x29 (Usage Max), 0x0A (Usage 2B)
          - Main items: 0x81 (Input), 0x91 (Output), 0xB1 (Feature), 0xA1 (Collection),
            0xC0 (End Collection)
        - 16-bit Logical Min/Max uses 3-byte encoding (0x16 / 0x26 with 2 data bytes),
          NOT 2-byte encoding (0x15 / 0x25 with 1 data byte). Failure here produces
          a descriptor that hidparser.exe rejects.
        - Every Collection (0xA1) has exactly one matching End Collection (0xC0).
        - Report IDs are unique within the TLC (no two reports share an ID).
        - Total byte count matches declared length in HID_DESCRIPTOR structure.

[ ] 2.  REPORT ID SEMANTICS
        - RID=0x02 Input: Buttons (2 bits) + pad (5 bits + 1 vendor bit) + X (8) +
          Y (8) + AC Pan (8) + Wheel (8) = 5 bytes payload. Matches applewirelessmouse
          col01 layout confirmed at offset 0xa850 offsets 6-82.
        - RID=0x27 Input: 46-byte Apple vendor blob. Declared Logical Min=1, Max=65.
          On-wire: 47 bytes [0x27 | 46 payload bytes]. M12 reads battery from
          offset BATTERY_BYTE_OFFSET within payload (placeholder until empirically confirmed).
        - RID=0x47 Feature: 1-byte synthesized battery percentage 0-100. On-wire: 2 bytes
          [0x47 | percentage_byte]. Logical Min=0, Max=100 (confirmed byte 89-91: 15 00 25 64).
        - M12's col02 vendor TLC (if added): Usage Page 0xFF00, Usage 0x0014, RID=0x90,
          3-byte report [0x90 | 2 bytes vendor data]. Verify this does not conflict
          with any existing RID in the descriptor.
        - No ReportID declared in the descriptor but NOT handled in EvtIo* (or vice versa).

[ ] 3.  LOGICAL / PHYSICAL MIN / MAX
        - RID=0x02 X/Y axes: LogMin=-127 (15 81), LogMax=127 (25 7F). 8-bit signed. VALID.
        - RID=0x02 Wheel: Verify encoding. If 8-bit: 15 81 25 7F. If 16-bit: 16 81 FF 26 7F FF.
          Must match the byte width declared in Report Size (75 08 = 8-bit).
        - RID=0x02 AC Pan: Same encoding rules as Wheel; verify byte prefix matches size.
        - RID=0x27: LogMin=1 (15 01), LogMax=65 (25 41). Confirmed at offsets 105-107.
          Translation formula must use this range: percentage = (raw - 1) * 100 / 64.
        - RID=0x47: LogMin=0 (15 00), LogMax=100 (25 64). Confirmed at offsets 89-91.
          M12 writes a value in [0, 100] only. No out-of-range fill.
        - PhysMin / PhysMax: if both 0, physical extent = logical extent (no unit conversion).
          Verify no unit items (0x55 Unit Exponent, 0x65 Unit) appear in the descriptor
          unless they match empirical applewirelessmouse layout.

[ ] 4.  IOCTL CONTRACTS
        - IOCTL_HID_GET_REPORT_DESCRIPTOR: M12 completes with static descriptor buffer.
          Does NOT forward to lower device. Output buffer size >= descriptor length;
          checked before WdfRequestComplete.
        - IOCTL_HID_GET_DEVICE_DESCRIPTOR: M12 completes with HID_DESCRIPTOR struct.
          Matches declared bNumDescriptors and descriptor length.
        - IOCTL_HID_GET_DEVICE_ATTRIBUTES: M12 completes with HID_DEVICE_ATTRIBUTES.
          VID/PID/VersionNumber match actual device (do not fabricate different values
          unless design spec explicitly requires an override with justification).
        - IOCTL_HID_GET_FEATURE (RID=0x47): M12 short-circuits. Reads shadow buffer.
          Writes [0x47, percentage] to output buffer. Completes STATUS_SUCCESS.
          Does NOT forward to lower device (eliminates err=87 round-trip).
        - IOCTL_HID_READ_REPORT: forwarded async to lower IoTarget with completion
          callback. Completion callback inspects RID: if 0x27, update shadow buffer;
          if 0x90, update battery cache if col02 active. Complete upstream.
        - All other IOCTLs: forwarded via ForwardRequest to lower IoTarget.

[ ] 5.  FEATURE vs INPUT REPORT HANDLING
        - RID=0x27 is an Input report (81 06), NOT a Feature report. M12 CANNOT
          issue IOCTL_HID_GET_FEATURE for RID=0x27. The data arrives only via the
          interrupt input pipe. Shadow buffer is populated from IOCTL_HID_READ_REPORT
          completion path, not from a synchronous poll.
        - RID=0x47 is a Feature report (B1 A2). Tray calls HidD_GetFeature(0x47).
          HidClass validates RID=0x47 against the parsed descriptor before forwarding.
          If 0x47 is absent from the descriptor, HidClass returns ERROR_INVALID_PARAMETER
          to the tray BEFORE the IRP reaches M12. Verify 0x47 is declared in the
          descriptor.
        - Shadow buffer staleness: if RID=0x27 age > configurable threshold, M12 returns
          STATUS_DEVICE_NOT_READY (or 0 with a flag) rather than a stale percentage.
          Default threshold 60 seconds. Timestamp stored alongside shadow buffer data.
        - First-boot case (no RID=0x27 received): M12 returns 0 or STATUS_NOT_READY.
          Behavior documented and consistent with design spec choice.

[ ] 6.  MATCH AGAINST PRODUCTION DRIVERS
        - applewirelessmouse.sys (116 bytes at offset 0xa850): descriptor is copied
          verbatim OR deviations listed item-by-item with justification. No hand-written
          byte sequences without cross-check.
        - MagicUtilities Mode A descriptor (col01 portion): if M12 uses MU's 16-bit
          Wheel + 16-bit AC Pan layout instead of applewirelessmouse's 8-bit layout,
          the Mode A bytes are cited by source (empirical capture filename + offset).
        - Linux hid-magicmouse.c magicmouse_report_fixup: confirms Linux applies a
          4-byte in-memory fixup to USB v2/v3 firmware descriptor. This is NOT
          applicable to Windows -- M12 provides a complete static descriptor,
          not a delta fixup. Reviewer confirms this difference is not a gap.
        - Linux RID mapping confirms: 0x12 = MOUSE2_REPORT_ID (v3 mouse, BT). Linux
          never sees RID=0x27. M12's RID=0x27 handling has no Linux reference;
          battery byte offset requires empirical Windows ETW/BT-sniff confirmation.
        - hidparser.exe (from EWDK) run against the static descriptor. Zero errors.
          Log attached to PR.
```

---

## Verdict format

```
VERDICT: APPROVE | CHANGES-NEEDED | REJECT

CRITICAL (count=N):
  CRIT-1: [description; cite spec section or byte offset] [fix]
  ...

MAJOR (count=N):
  MAJ-1: [description] [fix]
  ...

MINOR (count=N):
  MIN-1: [description] [recommendation]
  ...

CONFIRMED (list):
  - [Each topic confirmed correct]

OPEN ITEMS (must resolve before Phase 3 implementation gates):
  OI-1: [e.g., Battery byte offset in RID=0x27 -- requires ETW capture]
  ...
```

Threshold: APPROVE requires 0 critical, 0 major.
CHANGES-NEEDED: 0 critical, any major.
REJECT: any critical.

---

## Anti-patterns to reject

1. Hand-written descriptor bytes that differ from the empirical capture without
   byte-by-byte justification. Silent descriptor corruption causes hidparser.exe
   parse failure, or worse, silent wrong-behavior from HidClass.
2. RID=0x47 absent from descriptor. HidClass will block the GET_FEATURE call before
   it reaches M12, making the entire battery feature unreachable.
3. Using IOCTL_HID_GET_FEATURE or IOCTL_HID_GET_INPUT_REPORT to poll RID=0x27.
   RID=0x27 is an Input report; it cannot be polled via GET_FEATURE. The IRP will
   fail (METHOD_NEITHER handling mismatch or device returns error).
4. 16-bit LogMin/LogMax encoded with 1-byte prefix (0x15/0x25) instead of 2-byte
   (0x16/0x26). This produces a corrupt descriptor that hidparser.exe rejects.
5. Tray-visible Feature 0x47 value outside [0, 100]. Windows battery indicator
   may clamp or display incorrectly; HID spec violation.
6. No staleness check on shadow buffer. A 2-year-old cached value served as current
   battery percentage is a correctness bug.

---

## How to dispatch

```bash
python3 /home/lesley/projects/RILEY/scripts/agent.py spawn \
  --tier sonnet \
  --template .ai/agent-templates/hid-protocol-review.md \
  --pr-url <PR>
```

Attach: PR diff, docs/M12-HID-PROTOCOL-VALIDATION-2026-04-28.md, hidparser.exe output.
Post structured verdict as a PR comment.
