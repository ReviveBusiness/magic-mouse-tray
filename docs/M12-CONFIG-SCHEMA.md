# M12 Registry Configuration Schema
# K8s-CRD-style Device Registry

**Version:** 1.0
**Date:** 2026-04-28
**Author:** Claude Sonnet 4.6 (ai/m12-empirical-and-crd)
**Status:** DRAFT -- pending fold into M12-DESIGN-SPEC.md v1.3
**Linked:** M12-DESIGN-SPEC.md v1.2, M12-CRD-CONFIG-NOTE-FOR-V1.3.md

---

## 1. Purpose and Design Philosophy

This schema defines a registry-driven device configuration system for the M12 driver.
It is modeled on Kubernetes CRD semantics: each supported device is a named resource
with a typed schema. Adding support for a new Magic Mouse variant (v4, v5, ...) requires
only a registry entry -- NO driver rebuild, NO recompile, NO INF update.

The schema uses Windows registry conventions (not YAML/JSON) because the driver reads
configuration at kernel IRQL from a registry path that is already cached by the kernel
key map during driver loading. This is the standard KMDF pattern for per-device tunables.

### Design goals

1. **Forward compatibility**: A Magic Mouse v4 (hypothetical PID 0x033F) is supported
   by adding one registry subkey under `Devices\`. No code change.
2. **Operator tuning**: BATTERY_OFFSET, BatteryScale, and DebugLevel are all operator-
   adjustable without a driver rebuild or system restart (requires device re-bind:
   `pnputil /disable-device + /enable-device` cycle on the affected PnP node).
3. **INF-installable defaults**: INF `AddReg` sections populate all keys at install time.
   The driver treats missing keys as "use compiled-in default". No key is mandatory.
4. **Driver validation**: The driver validates every tunable on read at `EvtDeviceAdd`
   time. Out-of-range values produce a DbgPrint warning and are clamped or defaulted.
5. **Config tooling friendly**: The schema is flat enough that a PowerShell module or
   .reg file can export/import a complete device config without parsing binary data.

---

## 2. Registry Path Structure

```
HKLM\SYSTEM\CurrentControlSet\Services\M12\
|
+-- Parameters\                          (global driver tunables)
|   +-- DebugLevel: REG_DWORD
|   +-- PoolTag: REG_SZ
|   +-- DefaultDeviceConfig: REG_SZ      (fallback JSON config for unknown PIDs)
|
+-- Devices\                             (per-device configuration, keyed by PID string)
    |
    +-- VID_004C&PID_0323\               (Magic Mouse 2024 / v3)
    |   +-- DeviceName: REG_SZ
    |   +-- BatteryReportID: REG_DWORD
    |   +-- BatteryReportType: REG_SZ
    |   +-- BatteryReportLength: REG_DWORD
    |   +-- BatteryByteOffset: REG_DWORD
    |   +-- BatteryScale: REG_SZ
    |   +-- BatteryLookupTable: REG_BINARY  (optional)
    |   +-- ScrollPassthrough: REG_DWORD
    |   +-- FeatureFlags: REG_DWORD
    |   +-- ShadowBufferSize: REG_DWORD
    |   +-- FirstBootPolicy: REG_DWORD
    |   +-- MaxStalenessMs: REG_DWORD
    |
    +-- VID_004C&PID_030D\               (Magic Mouse 1)
    |   +-- (same keys as above)
    |
    +-- VID_004C&PID_0310\               (Magic Mouse 1 trackpad-class PID)
    |   +-- (same keys as above)
    |
    +-- VID_004C&PID_0269\               (Magic Mouse 2 / v2, hypothetical)
    |   +-- (same keys as above)
    |
    +-- VID_004C&PID_XXXX\              (future variants -- no code change required)
        +-- (same keys as above)
```

### 2a. Key naming convention

The subkey name under `Devices\` uses Windows PnP hardware ID substring format:
`VID_<VENDORID>&PID_<PRODUCTID>` where vendor and product IDs are uppercase 4-digit hex.

This matches the BTHENUM hardware ID suffix used in INF `[Standard.NTamd64]` sections:
  `BTHENUM\{00001124-...}_VID&0001004C_PID&0323`

The driver constructs the lookup key by extracting VID and PID from the device's
hardware ID at `EvtDeviceAdd` time via `WdfDeviceQueryProperty(DevicePropertyHardwareID)`.

---

## 3. Parameters\ -- Global Tunables

### DebugLevel (REG_DWORD, default = 0)

Controls driver verbosity for DbgPrint output.

| Value | Level | Output |
|-------|-------|--------|
| 0     | Silent | No DbgPrint (production default) |
| 1     | Error | Errors only (STATUS_* failures) |
| 2     | Warning | Warnings + errors (unexpected states) |
| 3     | Info | Info + above (EvtDeviceAdd, shadow buffer updates) |
| 4     | Verbose | All output including per-IRP trace and shadow hex dumps |

Range validation: clamp to [0..4] on read.

**Level 4 is the empirical validation level**: every Feature 0x47 query logs the full
46-byte Shadow.Payload[] as hex. This is the M12 LogShadowBuffer() path.

### PoolTag (REG_SZ, default = "M12 ")

4-character ASCII pool tag for `ExAllocatePool2` calls. Must be exactly 4 ASCII chars.
Overridable for diagnostic isolation (e.g., if running alongside another M12 instance
in a testing scenario). Driver validates: if not exactly 4 printable ASCII chars, reverts
to hardcoded `'M12 '` (0x2032314D).

### DefaultDeviceConfig (REG_SZ, default = empty)

Reserved for a future JSON/YAML fallback config string applied to any PID not found
under `Devices\`. If empty (default), the driver uses hardcoded compiled-in defaults
for unknown PIDs. This field is NOT parsed in M12 v1.x; it is a forward-compatibility
placeholder that prevents a schema migration when the feature is added.

---

## 4. Devices\<PID>\ -- Per-Device Schema

All fields are optional. Missing fields use the compiled-in default shown in the
"Default" column. This means a minimal device entry may contain ONLY `DeviceName`
and `BatteryByteOffset` -- all other fields inherit from compiled-in defaults.

### 4a. Identity fields

#### DeviceName (REG_SZ)

| Field | Value |
|-------|-------|
| Type | REG_SZ |
| Default | "Magic Mouse" |
| Validation | None (display only) |
| Purpose | Human-readable device label for DbgPrint and future userland display |

Example values:
- "Magic Mouse 1" (PID 0x030D)
- "Magic Mouse 2" (PID 0x0269)
- "Magic Mouse 2024" (PID 0x0323)

### 4b. Battery report configuration

#### BatteryReportID (REG_DWORD)

| Field | Value |
|-------|-------|
| Type | REG_DWORD |
| Default | 0x27 (39 decimal) |
| Validation | Must be in [0x01..0xFE] |
| Purpose | Report ID of the input report containing battery data |

For all known Apple Magic Mouse variants, this is 0x27. A future variant using a
different vendor blob RID (e.g., 0x28) can be supported by changing this value.

#### BatteryReportType (REG_SZ)

| Field | Value |
|-------|-------|
| Type | REG_SZ |
| Default | "Input" |
| Validation | Must be "Input" or "Feature" (case-insensitive) |
| Purpose | Whether battery report arrives via interrupt pipe (Input) or polling (Feature) |

All current Apple Magic Mouse variants use "Input" (the 0x27 frame arrives on the
interrupt pipe without polling). A future variant that natively backs a Feature report
would use "Feature" -- this changes the M12 tap path from OnReadComplete to a polling
loop, a significant code change that the flag documents but does not automatically implement
(see Section 7 for the failure mode this introduces).

#### BatteryReportLength (REG_DWORD)

| Field | Value |
|-------|-------|
| Type | REG_DWORD |
| Default | 46 |
| Validation | Must be in [1..255] |
| Purpose | Expected payload size in bytes (excluding the RID prefix byte) |

Used to validate `pkt->reportBufferLen` in the completion routine. If the device
delivers a different-length report, the completion routine logs a warning and skips
the shadow buffer update (protects against buffer overread).

A Magic Mouse v4 with a longer vendor blob (e.g., 62 bytes) would set this to 62
AND allocate a larger SHADOW_BUFFER. See Section 7 for the failure mode this introduces.

#### BatteryByteOffset (REG_DWORD)

| Field | Value |
|-------|-------|
| Type | REG_DWORD |
| Default | 0 (first payload byte) |
| Validation | Must be in [0..BatteryReportLength-1]; if >= BatteryReportLength, clamp to 0 |
| Purpose | Index into Shadow.Payload[] for the battery raw value byte |

This is the open empirical question (OQ-A in M12-DESIGN-SPEC.md v1.2).
The default of 0 reads Shadow.Payload[0], which is on-wire byte 1 of the RID=0x27
report (the first data byte after the RID prefix).

**Phase 3 action**: After M12 installation, set DebugLevel=4, query tray battery,
read LogShadowBuffer output, identify which Shadow.Payload[N] equals the expected
raw value (65 at 100% charge), update this value.

#### BatteryScale (REG_SZ)

| Field | Value |
|-------|-------|
| Type | REG_SZ |
| Default | "linear" |
| Validation | Must be "linear" or "lookup" |
| Purpose | Battery translation algorithm selector |

Values:
- `"linear"`: Apply `(raw - 1) * 100 / 64` (standard HID linear interpolation from
  Logical Min=1, Max=65 to Physical 0-100). This is the correct formula per HID 1.11.
  The constants (1, 64) are hardcoded for the known Apple descriptor range.
- `"lookup"`: Use BatteryLookupTable (see below) for a non-linear mapping.
  Required if empirical data shows the firmware emits discrete values (e.g., 1, 13,
  25, 37, 49, 65) rather than a continuous linear distribution.

#### BatteryLookupTable (REG_BINARY)

| Field | Value |
|-------|-------|
| Type | REG_BINARY |
| Default | absent (not used when BatteryScale="linear") |
| Validation | If present: must be exactly 66 bytes (indices 0..65, each a UINT8 percentage) |
| Purpose | Non-linear LUT: lut[raw] = percentage for raw in [0..65] |

Layout: 66 bytes where byte N is the percentage to report when raw value == N.
  lut[0] = percentage for raw=0 (should be 0 -- device disconnected)
  lut[1] = percentage for raw=1 (minimum, should be 0 or 1)
  ...
  lut[65] = percentage for raw=65 (maximum, should be 100)

Bytes beyond lut[65] are ignored. If fewer than 66 bytes, driver extends with
lut[N] = N * 100 / 65 (linear fallback for missing entries).

This field is OPTIONAL and unused in v1.x unless BatteryScale="lookup".

### 4c. Behavioral configuration

#### ScrollPassthrough (REG_DWORD)

| Field | Value |
|-------|-------|
| Type | REG_DWORD |
| Default | 1 (pass through) |
| Validation | Must be 0 or 1 |
| Purpose | Whether M12 passes RID=0x02 (scroll) events unchanged |

0 = M12 synthesizes scroll (reserved for future Mode A / Resolution Multiplier support)
1 = M12 passes native RID=0x02 unchanged (current M12 v1.2 behavior)

Do NOT set to 0 in M12 v1.x -- scroll synthesis code is not implemented.
The flag is present for forward compatibility and schema completeness.

#### FeatureFlags (REG_DWORD)

| Field | Value |
|-------|-------|
| Type | REG_DWORD |
| Default | 0x03 (intercept_0x47=1, cache_0x27=1) |
| Validation | Bitmask, undefined bits ignored |
| Purpose | Enable/disable individual M12 behaviors |

Bit definitions:
```
Bit 0 (0x01): intercept_0x47 -- intercept IOCTL_HID_GET_FEATURE for RID=0x47
              and short-circuit with shadow buffer value.
              0 = disabled (pass Feature 0x47 IRP to device unchanged)
              1 = enabled (M12 serves Feature 0x47 from shadow; default)

Bit 1 (0x02): cache_0x27 -- tap RID=0x27 input reports and update shadow buffer.
              0 = disabled (no shadow buffer updates; Feature 0x47 intercept returns stale)
              1 = enabled (shadow buffer updated on every RID=0x27 completion; default)

Bit 2 (0x04): log_shadow -- force LogShadowBuffer() on every Feature 0x47 query.
              Overrides DebugLevel for shadow logging specifically.
              0 = shadow logging controlled by DebugLevel (default)
              1 = always log shadow (useful for one-off empirical validation)

Bit 3 (0x08): strict_length -- reject RID=0x27 frames shorter than BatteryReportLength.
              0 = accept shorter frames (use available bytes, default)
              1 = reject and skip shadow update if frame shorter than expected

Bits 4-31: reserved, must be 0. Unrecognized bits ignored on read.
```

For v1 (PID 0x030D): Set FeatureFlags=0x03 (same as v3). The v1 device natively backs
Feature 0x47 via Apple firmware, but having M12 short-circuit it ensures consistent
behavior from the same shadow buffer path. No regression risk because v1 also emits
RID=0x27 on the interrupt channel.

#### ShadowBufferSize (REG_DWORD)

| Field | Value |
|-------|-------|
| Type | REG_DWORD |
| Default | 46 |
| Validation | Must be in [1..512]; if > 512 or 0, use default |
| Purpose | Size in bytes of Shadow.Payload[] allocation |

For all current Magic Mouse variants: 46 (the fixed 46-byte vendor blob).
A hypothetical future variant with a 62-byte vendor blob would require ShadowBufferSize=62
AND BatteryReportLength=62. If these two values differ, the driver logs a warning;
it uses MIN(ShadowBufferSize, BatteryReportLength) as the effective shadow copy length.

**See Section 7 (failure modes) for the dynamic allocation risk this introduces.**

#### FirstBootPolicy (REG_DWORD)

| Field | Value |
|-------|-------|
| Type | REG_DWORD |
| Default | 0 |
| Validation | Must be 0 or 1 |
| Purpose | Behavior when Feature 0x47 is queried before any RID=0x27 received |

0 = Return STATUS_DEVICE_NOT_READY (tray shows N/A until first RID=0x27 arrives)
1 = Return [0x47, 0x00] (tray shows 0% immediately; may confuse user)

Default 0 is safer because the tray will display N/A rather than incorrect 0%.
The first RID=0x27 arrives within 100ms of the mouse connecting, so the N/A
state is transient and typically invisible to the user.

#### MaxStalenessMs (REG_DWORD)

| Field | Value |
|-------|-------|
| Type | REG_DWORD |
| Default | 0 (disabled) |
| Validation | [0..ULONG_MAX]; 0 = disabled |
| Purpose | Maximum age of shadow buffer before returning STATUS_DEVICE_NOT_READY |

0 = disabled (always serve shadow regardless of age; M12 v1.2 default behavior)
N > 0 = if shadow buffer age > N milliseconds, return STATUS_DEVICE_NOT_READY.

This prevents the tray from showing a stale percentage when the mouse has been
idle for a long time. OQ-C in M12-DESIGN-SPEC.md. Disabled by default because
the v3 mouse emits RID=0x27 ~10/sec when in use, and when idle the battery
level doesn't change significantly.

---

## 5. Known Device Configurations

### 5a. Magic Mouse 2024 (v3) -- PID 0x0323

```
HKLM\SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0323\
  DeviceName             = "Magic Mouse 2024"
  BatteryReportID        = 0x00000027  ; 39 decimal
  BatteryReportType      = "Input"
  BatteryReportLength    = 0x0000002E  ; 46 decimal
  BatteryByteOffset      = 0x00000000  ; PENDING empirical confirmation (Phase 3)
  BatteryScale           = "linear"
  ScrollPassthrough      = 0x00000001
  FeatureFlags           = 0x00000003  ; intercept_0x47 + cache_0x27
  ShadowBufferSize       = 0x0000002E  ; 46
  FirstBootPolicy        = 0x00000000
  MaxStalenessMs         = 0x00000000  ; disabled
```

### 5b. Magic Mouse 1 (original, v1) -- PID 0x030D

```
HKLM\SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_030D\
  DeviceName             = "Magic Mouse 1"
  BatteryReportID        = 0x00000027
  BatteryReportType      = "Input"
  BatteryReportLength    = 0x0000002E  ; 46 -- VERIFY empirically; v1 may differ
  BatteryByteOffset      = 0x00000000  ; PENDING empirical confirmation
  BatteryScale           = "linear"
  ScrollPassthrough      = 0x00000001
  FeatureFlags           = 0x00000003
  ShadowBufferSize       = 0x0000002E
  FirstBootPolicy        = 0x00000000
  MaxStalenessMs         = 0x00000000
```

NOTE: M12 v1.2 design spec (Section 7d) asserts v1 and v3 share the same
descriptor and RID=0x27 layout. If Phase 3 testing reveals v1 uses a different
BatteryByteOffset, this subkey diverges from v3 without any code change.

### 5c. Magic Mouse 1 (trackpad-class PID) -- PID 0x0310

```
HKLM\SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0310\
  DeviceName             = "Magic Mouse 1 (Trackpad-class PID)"
  BatteryReportID        = 0x00000027
  BatteryReportType      = "Input"
  BatteryReportLength    = 0x0000002E
  BatteryByteOffset      = 0x00000000
  BatteryScale           = "linear"
  ScrollPassthrough      = 0x00000001
  FeatureFlags           = 0x00000003
  ShadowBufferSize       = 0x0000002E
  FirstBootPolicy        = 0x00000000
  MaxStalenessMs         = 0x00000000
```

### 5d. Magic Mouse 2 -- PID 0x0269 (hypothetical; not user-owned)

```
HKLM\SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0269\
  DeviceName             = "Magic Mouse 2"
  BatteryReportID        = 0x00000027
  BatteryReportType      = "Input"
  BatteryReportLength    = 0x0000002E
  BatteryByteOffset      = 0x00000000  ; UNVERIFIED -- requires empirical capture
  BatteryScale           = "linear"
  ScrollPassthrough      = 0x00000001
  FeatureFlags           = 0x00000003
  ShadowBufferSize       = 0x0000002E
  FirstBootPolicy        = 0x00000000
  MaxStalenessMs         = 0x00000000
```

### 5e. Future variant placeholder -- PID 0xXXXX

```
HKLM\SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_XXXX\
  DeviceName             = "Magic Mouse v4 (placeholder)"
  BatteryReportID        = 0x00000027  ; update if firmware changes RID
  BatteryReportType      = "Input"
  BatteryReportLength    = 0x0000002E  ; update if payload length changes
  BatteryByteOffset      = 0x00000000  ; MUST set empirically -- no default valid
  BatteryScale           = "linear"    ; or "lookup" if firmware uses non-linear scale
  ScrollPassthrough      = 0x00000001
  FeatureFlags           = 0x00000003
  ShadowBufferSize       = 0x0000002E  ; must match BatteryReportLength
  FirstBootPolicy        = 0x00000001  ; show 0% while waiting for first frame
  MaxStalenessMs         = 0x00000000
```

---

## 6. INF Integration

The INF installs default registry values using `AddReg` directives with
`HKR` relative to the device's software key (`HKLM\...\Services\M12\`).

### 6a. INF section structure

```ini
[AddReg_M12_Parameters]
HKLM,SYSTEM\CurrentControlSet\Services\M12\Parameters,DebugLevel,0x00010001,0
HKLM,SYSTEM\CurrentControlSet\Services\M12\Parameters,PoolTag,0x00000000,"M12 "

[AddReg_M12_Devices_v3]
HKLM,SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0323,DeviceName,\
  0x00000000,"Magic Mouse 2024"
HKLM,SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0323,BatteryReportID,\
  0x00010001,0x00000027
HKLM,SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0323,BatteryReportLength,\
  0x00010001,0x0000002E
HKLM,SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0323,BatteryByteOffset,\
  0x00010001,0x00000000
HKLM,SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0323,BatteryScale,\
  0x00000000,"linear"
HKLM,SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0323,ScrollPassthrough,\
  0x00010001,0x00000001
HKLM,SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0323,FeatureFlags,\
  0x00010001,0x00000003
HKLM,SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0323,ShadowBufferSize,\
  0x00010001,0x0000002E

[AddReg_M12_Devices_v1]
HKLM,SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_030D,DeviceName,\
  0x00000000,"Magic Mouse 1"
HKLM,SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_030D,BatteryReportID,\
  0x00010001,0x00000027
; (same pattern as v3 for remaining keys)
```

INF flags reference:
- `0x00010001` = FLG_ADDREG_TYPE_DWORD (REG_DWORD)
- `0x00000000` = FLG_ADDREG_TYPE_SZ (REG_SZ)
- `0x00010003` = FLG_ADDREG_TYPE_BINARY (REG_BINARY)

### 6b. Adding a new device via INF patch

To add Magic Mouse v4 (PID 0x033F) when it ships:
1. Add hardware ID to `[Standard.NTamd64]` section.
2. Add `[AddReg_M12_Devices_v4]` section with PID_033F subkey.
3. Rebuild INF (no C code change).
4. Test, submit updated INF for signing.

No driver source code change required unless the new variant uses a different
RID, payload length, or requires a non-linear battery scale (all handled by config).

---

## 7. Config Tooling

### 7a. Export device config (PowerShell)

```powershell
# Export a single device config as .reg file
function Export-M12DeviceConfig {
    param([string]$Pid = '0323')
    $key = "HKLM\SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_$Pid"
    $outFile = "M12-config-PID_$Pid-$(Get-Date -Format yyyyMMdd-HHmmss).reg"
    reg.exe export $key $outFile /y
    Write-Host "Exported to $outFile"
}
```

### 7b. Import device config (PowerShell)

```powershell
# Import a .reg file (requires admin)
function Import-M12DeviceConfig {
    param([string]$RegFile)
    reg.exe import $RegFile
}
```

### 7c. Quick-set BatteryByteOffset (PowerShell, requires admin)

```powershell
function Set-M12BatteryOffset {
    param([string]$Pid = '0323', [int]$Offset = 0)
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_$Pid"
    Set-ItemProperty -Path $key -Name BatteryByteOffset -Value $Offset -Type DWord
    Write-Host "BatteryByteOffset set to $Offset for PID $Pid"
    Write-Host "Re-bind device: pnputil /disable-device <instance-id> && pnputil /enable-device <instance-id>"
}
```

---

## 8. Driver Validation Logic

The driver validates every tunable at `EvtDeviceAdd` time. Validation pseudocode:

```c
NTSTATUS ReadDeviceConfig(WDFDEVICE Device, PDEVICE_CONTEXT Ctx) {
    // Open Devices\VID_<V>&PID_<P>\ subkey
    WDFKEY hDevices, hPid;
    // ... open HKLM\Services\M12\Devices\
    // ... open subkey for Ctx->PidKey (e.g., "VID_004C&PID_0323")
    // ... if subkey missing, log warning and use all defaults

    // BatteryReportID
    ULONG rid = ReadDword(hPid, L"BatteryReportID", 0x27);
    if (rid < 1 || rid > 0xFE) {
        DbgPrint("M12: BatteryReportID=0x%X out of range, using 0x27", rid);
        rid = 0x27;
    }
    Ctx->BatteryReportId = (UCHAR)rid;

    // BatteryReportLength
    ULONG rlen = ReadDword(hPid, L"BatteryReportLength", 46);
    if (rlen < 1 || rlen > 255) {
        DbgPrint("M12: BatteryReportLength=%u out of range, using 46", rlen);
        rlen = 46;
    }
    Ctx->BatteryReportLength = (UCHAR)rlen;

    // BatteryByteOffset
    ULONG offset = ReadDword(hPid, L"BatteryByteOffset", 0);
    if (offset >= rlen) {
        DbgPrint("M12: BatteryByteOffset=%u >= BatteryReportLength=%u, clamping to 0",
                 offset, rlen);
        offset = 0;
    }
    Ctx->BatteryOffset = offset;

    // BatteryScale
    WCHAR scaleBuf[32];
    ReadSz(hPid, L"BatteryScale", L"linear", scaleBuf, sizeof(scaleBuf));
    if (_wcsicmp(scaleBuf, L"lookup") == 0 && LookupTablePresent(hPid)) {
        Ctx->UseLookupTable = TRUE;
        LoadLookupTable(hPid, Ctx->LookupTable, sizeof(Ctx->LookupTable));
    } else {
        Ctx->UseLookupTable = FALSE;
    }

    // FeatureFlags
    Ctx->FeatureFlags = ReadDword(hPid, L"FeatureFlags", 0x03);

    // ShadowBufferSize
    ULONG sbSize = ReadDword(hPid, L"ShadowBufferSize", 46);
    if (sbSize < 1 || sbSize > 512) { sbSize = 46; }
    // If sbSize != rlen, use min
    if (sbSize != rlen) {
        DbgPrint("M12: ShadowBufferSize=%u != BatteryReportLength=%u, using min=%u",
                 sbSize, rlen, min(sbSize, rlen));
        sbSize = min(sbSize, rlen);
    }
    Ctx->ShadowBufferSize = sbSize;

    // FirstBootPolicy
    Ctx->FirstBootPolicy = (UCHAR)ReadDword(hPid, L"FirstBootPolicy", 0);
    if (Ctx->FirstBootPolicy > 1) { Ctx->FirstBootPolicy = 0; }

    return STATUS_SUCCESS;
}
```

---

## 9. Failure Modes Introduced by the Config Schema

This section documents new failure modes that exist BECAUSE of the registry config
schema (not despite it). These must be addressed in M12 v1.3 design.

### NF-1: ShadowBufferSize mismatch with BatteryReportLength

**Scenario**: Operator sets `ShadowBufferSize=62` (planning for a future v4 device)
on a v3 machine, but forgets to also set `BatteryReportLength=62`. The shadow buffer
allocates 62 bytes but the completion routine copies only 46 bytes (per BatteryReportLength).
Reading `Shadow.Payload[47]` would read uninitialized memory.

**Mitigation in driver**: Use `effective_copy_len = min(ShadowBufferSize, BatteryReportLength)`.
Zero-initialize the shadow buffer on allocation. DbgPrint warning on mismatch.

### NF-2: BatteryByteOffset beyond the actually-received frame length

**Scenario**: BatteryByteOffset=10 is set for v3. The device sends a 8-byte RID=0x27
frame (truncated, e.g., during a BT retransmission). The completion routine checks
`pkt->reportBufferLen < BatteryReportLength` and skips the update -- shadow buffer
stays at the last valid value. No OOB read. Mitigation already in driver logic.

### NF-3: BatteryScale="lookup" set but BatteryLookupTable absent

**Scenario**: Operator sets `BatteryScale=lookup` but forgets to write the lookup table
binary value. Driver falls back to linear formula. DbgPrint warning issued.
No crash, but operator may not notice the fallback.

**Mitigation**: Document in DebugLevel=2 warning output. Add F-bit to FeatureFlags
status query (future userland tool feature).

### NF-4: Future device with larger payload (ShadowBufferSize > 46)

**Scenario**: Magic Mouse v4 emits a 62-byte vendor blob. Operator adds
`VID_004C&PID_033F` subkey with `BatteryReportLength=62` and `ShadowBufferSize=62`.
However, M12 v1.x DEVICE_CONTEXT has `SHADOW_BUFFER` with a fixed 46-byte array
(`UCHAR Payload[46]`). The driver would overflow the fixed array.

**Required design change in v1.3**: Replace `UCHAR Payload[46]` with a dynamically
allocated buffer (`PUCHAR pPayload; ULONG PayloadAllocSize`). Allocate at
`EvtDeviceAdd` time using `ExAllocatePool2(NonPagedPoolNx, ShadowBufferSize, M12_POOL_TAG)`.
Free in `EvtDeviceRelease`. This is a structural change to DEVICE_CONTEXT that requires
updating all Payload[] references.

**Impact**: This is a NON-TRIVIAL change. If M12 v1.3 only supports the current known
devices (46-byte payload), the static array is safe. Add a runtime check:
if `ShadowBufferSize > 46` and the driver was built without dynamic allocation support,
log an error and clamp to 46 with a warning. Document that dynamic-payload support
requires M12 v2.0 or later.

### NF-5: FeatureFlags=0x00 (both intercept_0x47 and cache_0x27 disabled)

**Scenario**: Operator disables both flags (FeatureFlags=0). The driver loads but
neither intercepts Feature 0x47 nor updates the shadow buffer. The device behaves
as if M12 is not installed (pass-through only). This is a valid diagnostic mode
(used to verify that M12 is not introducing any side effects).

**Mitigation**: No crash risk. DbgPrint warning "M12: FeatureFlags=0x00, all M12
behaviors disabled -- acting as pass-through". Useful for regression isolation.

### NF-6: PID subkey missing for the connected device

**Scenario**: User connects a hypothetical Magic Mouse v4 (PID 0x033F). No
`VID_004C&PID_033F` subkey exists. The INF doesn't match this PID, so M12 shouldn't
load at all. However, if an operator manually added PID_033F to INF's hardware ID
list without adding the registry subkey, the driver loads with all compiled-in defaults.

**Mitigation**: `EvtDeviceAdd` logs "M12: No device config subkey found for PID 0x%X,
using compiled-in defaults." This is acceptable for testing. The defaults (BatteryReportID=0x27,
BatteryByteOffset=0, etc.) are reasonable starting points for a new Apple device.

---

## 10. Example .reg Files

### 10a. v3 Magic Mouse 2024

```reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\M12\Parameters]
"DebugLevel"=dword:00000000
"PoolTag"="M12 "

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0323]
"DeviceName"="Magic Mouse 2024"
"BatteryReportID"=dword:00000027
"BatteryReportType"="Input"
"BatteryReportLength"=dword:0000002e
"BatteryByteOffset"=dword:00000000
"BatteryScale"="linear"
"ScrollPassthrough"=dword:00000001
"FeatureFlags"=dword:00000003
"ShadowBufferSize"=dword:0000002e
"FirstBootPolicy"=dword:00000000
"MaxStalenessMs"=dword:00000000
```

### 10b. v1 Magic Mouse 1

```reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_030D]
"DeviceName"="Magic Mouse 1"
"BatteryReportID"=dword:00000027
"BatteryReportType"="Input"
"BatteryReportLength"=dword:0000002e
"BatteryByteOffset"=dword:00000000
"BatteryScale"="linear"
"ScrollPassthrough"=dword:00000001
"FeatureFlags"=dword:00000003
"ShadowBufferSize"=dword:0000002e
"FirstBootPolicy"=dword:00000000
"MaxStalenessMs"=dword:00000000

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0310]
"DeviceName"="Magic Mouse 1 (Trackpad-class)"
"BatteryReportID"=dword:00000027
"BatteryReportType"="Input"
"BatteryReportLength"=dword:0000002e
"BatteryByteOffset"=dword:00000000
"BatteryScale"="linear"
"ScrollPassthrough"=dword:00000001
"FeatureFlags"=dword:00000003
"ShadowBufferSize"=dword:0000002e
"FirstBootPolicy"=dword:00000000
"MaxStalenessMs"=dword:00000000
```

### 10c. Debug/validation configuration (DebugLevel=4, log_shadow on)

```reg
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\M12\Parameters]
"DebugLevel"=dword:00000004

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\M12\Devices\VID_004C&PID_0323]
"BatteryByteOffset"=dword:00000000
"FeatureFlags"=dword:00000007
```

Import this .reg file, then disable/enable the device in Device Manager to apply.
Query tray battery, observe DebugView output for shadow hex dump.
Identify which byte position contains value ~65 (at 100% charge).

---

## 11. References

- M12-DESIGN-SPEC.md v1.2, Section 7 (shadow buffer, DEVICE_CONTEXT)
- M12-HID-PROTOCOL-VALIDATION-2026-04-28.md, Section OI-1 (BatteryByteOffset BLOCKING)
- M12-RID27-EMPIRICAL-PASS2-2026-04-28.md (this session's empirical findings)
- Microsoft Learn: KMDF Registry Access (WdfDriverOpenParametersRegistryKey)
- Microsoft Learn: INF AddReg section reference (FLG_ADDREG_TYPE_*)
- HID 1.11 specification, Section 6.2.2.7 (Physical vs Logical extents)

---

Document version: 1.0
Session: ai/m12-empirical-and-crd
Date: 2026-04-28
