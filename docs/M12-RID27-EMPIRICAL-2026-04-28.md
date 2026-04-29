# M12 RID=0x27 Empirical Analysis — 2026-04-28

**Analyst:** Claude Haiku 4.5 (ai/m12-rid27-empirical analysis)  
**Date:** 2026-04-28  
**Capture:** ETW HID/Bluetooth trace from test-A2 (2026-04-27-154930-T-V3-AF)  
**Objective:** Extract RID=0x27 input report payloads and identify battery byte offset

---

## Executive Summary

**Status:** BLOCKED — Capture does not contain RID=0x27 input report payloads

The ETW capture (test-A2-etw-bth-hid-20260428-181312.csv/txt) was decoded to analyze
Windows applewirelessmouse.sys vendor input format RID=0x27. However, the tracerpt
conversion to CSV/TXT format **does not preserve binary HID input report payloads**.

The capture file contains:
- Microsoft-Windows-BTH-BTHPORT events (10,699 items)
- Microsoft-Windows-BTH-BTHUSB events (4 items)
- Microsoft-Windows-Input-HIDCLASS events (24 items)

None of these event types include the raw 47-byte HID input report data (1 RID byte + 46 payload bytes).

---

## Capture Analysis

### Files Examined

| File | Size | Format | Content |
|------|------|--------|---------|
| test-A2-etw-bth-hid-20260428-181312.csv | 1.1 MB | CSV (tracerpt export) | Event metadata; no payloads |
| test-A2-etw-bth-hid-20260428-181312.txt | 1.1 MB | Text (tracerpt export) | Event metadata; no payloads |
| test-A2-etw-bth-hid-20260428-181312-summary.md | 261 B | Markdown summary | Event counts only |

### Payload Search Results

| Query Pattern | Matches | Result |
|---------------|---------|--------|
| `0x27` or `27` in CSV | 2,881 | Timestamps and process IDs only (e.g., T18:13:12.65274276) |
| `0x27` or `27` in TXT | 0 | No matches |
| RID=0x27 marker text | 0 | No matches |
| 46-byte hex sequences | 0 | No matches |

---

## RID=0x27 Expected Format

Per M12-HID-PROTOCOL-VALIDATION-2026-04-28.md:

| Attribute | Value |
|-----------|-------|
| Report ID | 0x27 (decimal 39) |
| Report Type | Input (interrupt pipe) |
| Payload Size | 46 bytes |
| On-wire Size | 47 bytes (1 RID + 46 payload) |
| Logical Min (per descriptor) | 1 |
| Logical Max (per descriptor) | 65 |
| Declared Usage Page | 0x06 (Generic Device Controls) |
| Declared Usage | 0x01 (Battery Strength) |

Battery byte offset: UNKNOWN (the unresolved empirical question)

---

## Why This Capture Failed

### Root Cause

The ETW provider configuration for this capture did NOT include HID input event
payload logging. The tracerpt text export format includes only:
- Event timestamp
- Provider name
- Event ID
- Severity level

HID input report **payloads** (the raw 46-byte vendor blob) are optional detailed
fields in the ETW event; they must be explicitly enabled in the capture configuration.

### ETW Provider Limits

Microsoft-Windows-Input-HIDCLASS level=Information captures event **metadata**
(ReportID declarations, HID device enumeration) but NOT the **payload** of each
input report.

To capture payloads, one of these approaches is required:

1. **ETW with Verbose/Debug level + custom manifest**
   - Enable: Microsoft-Windows-Input-HIDCLASS level=5 (Verbose)
   - Requires: Custom ETW manifest with payload field definitions
   - Window: Can capture detailed HID input events with raw bytes
   - **Effort:** Moderate (requires manifest authoring or third-party tool)

2. **Bluetooth HCI Sniff (recommended for BT devices)**
   - Tool: Wireshark + btsnoop.log or Ubertooth
   - Packets: L2CAP CID 0x13 (interrupt channel) = HID input data
   - Window: Captures BT frame-level data including all HID payloads
   - **Effort:** Low if hardware supports sniffing; zero effort for packet replay analysis

3. **In-kernel probe via WinDbg or ETW events with debugger**
   - Window: IRP completion callback in filter driver
   - Requires: Custom kernel probe; not trivial
   - **Effort:** High (kernel mode code required)

4. **Userland HID intercept via HidD_GetInputReport or Read(FILE_HIDDEN)**
   - Window: User-mode HID I/O interception
   - Limitation: May not capture async input stream (input interrupt pipe)
   - **Effort:** Medium

---

## Recommendation for Phase 3 Resolution

### Primary Path: Bluetooth HCI Sniff

1. **Setup:**
   - Run Wireshark on host (or capture-side tool if direct capture unavailable)
   - Enable Bluetooth packet capture via OS native driver or USB Bluetooth adapter
   - Load btsnoop filter, or use Ubertooth

2. **Capture Session:**
   - Monitor Magic Mouse battery level (known %)
   - Capture 30-60 seconds of mouse activity (generate cursor movements)
   - Stop capture
   - Filter L2CAP CID 0x13 (HID interrupt channel)

3. **Analysis:**
   - Extract RID=0x27 frames (should be frequent: 10+ per second for active mouse)
   - Tabulate all 46-byte payloads
   - Find byte offset with values matching current battery level
   - Cross-validate with second capture at significantly different battery level

4. **Expected Outcome:**
   - Byte offset N with low variance (e.g., 1-5 unique values) matching battery %
   - Confidence: VERY_HIGH if values span the full 1-65 range in the capture

### Fallback Path: ETW with Enhanced Configuration

If HCI sniff is not feasible:

1. Reconfigure ETW trace to capture HIDCLASS at level=VERBOSE
2. Use tool like EventLogz.exe or custom ETL decoder to extract payload fields
3. Same analysis as above (tabulate RID=0x27, diff byte offsets)
4. **Challenge:** Verbose ETW may not log all payload fields; may require debugger symbols

### Timeline

- **Ideal:** HCI sniff captures take 5-10 min per attempt, analysis takes 10 min
- **Phase 3 gate:** Resolve battery offset BEFORE implementing M12 translation function
- **No workaround:** Battery translation is design-critical; cannot ship with BATTERY_OFFSET=TBD

---

## Analysis Script

Location: `scripts/mm-rid27-extract.py`

Purpose: Parse RID=0x27 payloads from capture and identify byte offset candidates

Usage:
```bash
python3 scripts/mm-rid27-extract.py
```

Output:
- Total frames matched
- Per-byte unique-value counts (table)
- Top 3 candidates ranked by confidence
- Recommendation (or "needs fresh capture")

**Status:** Prepared but unused this session (no payloads found in capture)

---

## Open Issues

| Issue | Status | Blocker |
|-------|--------|---------|
| RID=0x27 battery byte offset | UNRESOLVED | YES — Phase 3 implementation |
| Translation formula validation | UNRESOLVED | YES — Phase 3 testing |
| ETW capture format for HID payloads | IDENTIFIED | Not a blocker (HCI sniff is workaround) |

---

## Conclusion

The 2026-04-27-154930-T-V3-AF test run's ETW capture (test-A2) was not configured to
preserve HID input report payloads. The empirical battery byte offset question remains
open.

**Next step:** Initiate fresh HCI sniff capture (preferred) or reconfigured ETW trace
with Verbose-level HIDCLASS logging. Target: capture RID=0x27 frames at known battery
levels (100% vs. 20%) and cross-diff.

**Timeline to resolution:** 1-2 hours of hands-on capture + 30 min analysis.

---

Document version: 1.0  
Session: ai/m12-rid27-empirical  
Date: 2026-04-28T21:35 MDT
