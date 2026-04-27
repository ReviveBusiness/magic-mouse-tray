# MM3 Pre-Validation Baseline — 2026-04-26

Captured before KMDF driver development begins (M12). All data collected on the live Windows 11
machine with Magic Mouse 3 (PID 0323) paired and COL01+COL02 both present.

## Device Identity

| Field | Value |
|-------|-------|
| BTHENUM instance ID | `BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0323\9&73B8B28&0&D0C050CC8C4D_C00000000` |
| Pairing session | `9&73B8B28&0` |
| BT MAC address | `D0C050CC8C4D` (permanent) |
| PID | 0323 (Magic Mouse 3 / 2024 USB-C model) |
| VID | 004C (Apple, Bluetooth class) |

## Device Stack (Baseline — Filter Absent)

```
Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_Stack'

\Driver\HidBth
\Driver\BthEnum
```

`applewirelessmouse` is NOT present. Clean stack: BthEnum (bus) → HidBth (function driver only).
This is the state where battery works and scroll does not.

## HID Devices (Healthy State)

```
Get-PnpDevice | Where-Object { $_.InstanceId -match '0323' -and $_.Status -eq 'OK' }
```

Expected 4 devices: 2× BTHENUM + COL01 + COL02, all Status=OK.

### COL01 — Pointer / Scroll

| Field | Value |
|-------|-------|
| Path | `\\?\hid#{00001124-0000-1000-8000-00805f9b34fb}_vid&0001004c_pid&0323&col01#a&31e5d054&9&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}` |
| UsagePage | 0x0001 (Generic Desktop) |
| Usage | 0x0002 (Mouse) |
| InputReportByteLength | 8 |
| Access | mouhid holds exclusive read — CreateFile(GENERIC_READ) → ReadFile err=5 (ACCESS_DENIED) |
| Zero-access | Works for HidD_GetPreparsedData / HidP_GetCaps; ReadFile still fails |

### COL02 — Battery / Vendor

| Field | Value |
|-------|-------|
| Path | `\\?\hid#{00001124-0000-1000-8000-00805f9b34fb}_vid&0001004c_pid&0323&col02#a&31e5d054&9&0001#{4d1e55b2-f16f-11cf-88cb-001111000030}` |
| UsagePage | 0xFF00 (Vendor-defined) |
| Usage | 0x0014 |
| InputReportByteLength | 3 |
| Access | Zero-access CreateFile works; HidD_GetInputReport works |

## Battery Report Confirmation

```
HidD_GetInputReport(col02, buf[3], 0x90)
→  90 04 31
   buf[0] = 0x90  (Report ID)
   buf[1] = 0x04  (flags)
   buf[2] = 0x31  = 49%  ← battery percentage
```

Confirms `MouseBatteryReader.cs` layout: `buf[2]` = battery %. ✅

## Raw Descriptor Capture — Not Obtained

`IOCTL_HID_GET_REPORT_DESCRIPTOR` (0x000B0083) returns err=1 (ERROR_INVALID_FUNCTION) when
sent to COL01 or COL02. This IOCTL is only handled by the HID class FDO (parent device), which
does not expose an accessible `GUID_DEVINTERFACE_HID` path for multi-collection BT devices.

**Not needed for KMDF driver design.** The KMDF driver defines a custom HID descriptor; it does
not copy the device's descriptor. Linux `drivers/hid/hid-magicmouse.c` fully documents the raw
report format (Report ID 0x12: multi-touch, Report ID 0x90: battery).

## Probe Scripts (saved to C:\Temp\ on Windows machine)

| Script | Purpose | Result |
|--------|---------|--------|
| `capture-hid-descriptor.ps1` | Enumerate HID devices, attempt raw descriptor capture | COL01/COL02 found; IOCTL err=1 |
| `TouchpadProbe.ps1` | Read raw input reports from COL01/COL02 | COL02 battery 49% ✅; COL01 err=5 (mouhid exclusive) |

## Key Findings for KMDF Driver Design

1. **COL01 is exclusively owned by mouhid** — any user-space raw HID read path fails. KMDF
   function driver must intercept at kernel level, before mouhid, to access raw touch reports.

2. **COL02 InputReportLen=3** — battery report is 3 bytes: Report ID (0x90) + 2 data bytes.
   `buf[2]` = battery %. MagicMouseTray reads this correctly.

3. **Device stack is clean** — no applewirelessmouse filter. KMDF driver will bind to the same
   BTHENUM hardware ID (`BTHENUM\{00001124-...}_VID&0001004c_PID&0323`) as function driver,
   replacing HidBth.

4. **Custom HID descriptor plan:**
   - TLC 1: Generic Desktop Mouse (0x0001/0x0002) — pointer + scroll axes
   - TLC 2: Vendor (0xFF00) — Report ID 0x90, battery percentage in byte 2
   - No stripping needed — driver owns the full descriptor from init.
