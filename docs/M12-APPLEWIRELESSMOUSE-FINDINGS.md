# M12 Ghidra Findings -- applewirelessmouse.sys (Apple HID lower-filter)

Captured: Tue Apr 28 21:17:37 MDT 2026
Analyst: ai/m12-ghidra-applewirelessmouse agent
Architecture: x86_64 (PE64, LE)
Image base: 0x140000000
File size: 78,424 bytes (76.6 KB)
MD5: f4ae407c228c3db6147d9e3307ed5f20
Binary: applewirelessmouse.sys (from MagicMouse2DriversWin11x64 project)
Ghidra project: M12-MagicMouse (second binary, imported 2026-04-28)

## Analysis Context

applewirelessmouse.sys is the open-source reference HID lower-filter for v3 Magic Mouse.
It is the minimum viable kernel filter to use as M12's baseline. Empirically known to:
- Enable scroll on v3 via synthesized HID descriptor (Mode B)
- Fill scroll input with native vendor bytes from RID=0x02 (no in-IRP translation)
- Declare Feature 0x47 in descriptor (synthesized battery reporting)
- Return err=87 on Feature 0x47 reads (v3 firmware does not back it)
- Run with NO userland service (pure kernel, no license gate)
- Process EnableTwoButtonClick preference from HKCU (no userland service for this either)

---

## Q1: Imports (kernel APIs)

**Key question**: Is this BCrypt-heavy like MagicMouse.sys (34 imports, 11x BCrypt), or HID/WDF minimal?

```
ExAllocatePoolWithTag
ExFreePoolWithTag
IoAllocateIrp
IoBuildDeviceIoControlRequest
IoFreeIrp
IoGetCurrentProcess
IoGetDeviceObjectPointer
IofCallDriver
KeClearEvent
KeInitializeEvent
KeSetEvent
KeWaitForMultipleObjects
KeWaitForSingleObject
MmGetSystemRoutineAddress
ObOpenObjectByPointer
ObReferenceObjectByHandle
ObfDereferenceObject
PsCreateSystemThread
PsReferencePrimaryToken
PsTerminateSystemThread
RtlAppendUnicodeStringToString
RtlAppendUnicodeToString
RtlConvertSidToUnicodeString
RtlCopyUnicodeString
RtlInitUnicodeString
RtlQueryRegistryValues
RtlRaiseException
RtlUnicodeStringToInteger
WdfVersionBind
WdfVersionBindClass
WdfVersionUnbind
WdfVersionUnbindClass
ZwClose
ZwQueryInformationToken
__C_specific_handler
sqrt
wcsstr
```

Total: 37 imports

### Import Classification

| Category | Count | Key Names |
|----------|-------|-----------|
| WDF (KMDF runtime) | 4 | WdfVersionBind/Unbind/BindClass/UnbindClass |
| **BCrypt (crypto/license)** | **0** | **NONE -- confirmed no license gate** |
| HID stack (HidD_/HidP_) | 0 | NONE -- operates below HID class driver |
| Rtl* (runtime) | 8 | RtlQueryRegistryValues, RtlConvertSidToUnicodeString, RtlUnicodeStringToInteger, ... |
| IO/Ke/Ex/Mm kernel | 19 | IoAllocateIrp, IoBuildDeviceIoControlRequest, PsCreateSystemThread, ObOpenObjectByPointer, ... |
| Math / string | 2 | sqrt, wcsstr |

**Key finding**: NO BCrypt imports. Confirms pure-kernel design with no license/crypto gate.
This is the definitive structural difference from MagicMouse.sys (11 BCrypt imports).

### Notable imports for M12 design

- `PsCreateSystemThread` -- driver spawns a kernel thread (likely async vendor input reader or
  registry-change notification loop for per-user preferences)
- `ObOpenObjectByPointer` + `ZwQueryInformationToken` + `RtlConvertSidToUnicodeString` --
  driver queries the current process token for user SID, then builds the HKCU path:
  `\Registry\User\<SID>\Software\Apple Inc.\Mouse` to read per-user button prefs
- `IoGetDeviceObjectPointer` + `IoBuildDeviceIoControlRequest` + `IofCallDriver` --
  driver opens and sends IOCTLs to `\Device\AppleBluetoothMultitouch` (see strings),
  likely to coordinate re-enumeration after descriptor injection
- `sqrt` -- floating-point math; unexpected in a pure scroll/battery lower-filter;
  likely gesture distance calculation (two-finger trackpad, same driver package covers
  Magic Mouse + Magic Trackpad) or scroll acceleration curve

---

## Q2: Registry Reads

**Registry-related imports**: `RtlQueryRegistryValues`, `ZwQueryInformationToken`

### Registry strings found

```
140008180  refs=2  u"RtlQueryRegistryValuesEx"
1400081c0  refs=1  u"\Device\AppleBluetoothMultitouch"
140008210  refs=1  u"\DosDevices\AppleBluetoothMultitouch"
140008260  refs=2  u"\Registry\User\"
1400082b0  refs=2  u"SwapMouseButtons"
1400082f0  refs=1  u"\Software\Apple Inc.\Mouse"
140011418  refs=0  "IoBuildDeviceIoControlRequest"
140012118  refs=0  u"Apple Inc."
140012158  refs=0  u"Apple Wireless Mouse"
1400121dc  refs=0  u"AppleWirelessMouse.sys"
```

Also found:
```
140008280  refs=1  u"\Control Panel\Mouse"    (Windows standard mouse prefs)
140008330  refs=2  u"EnableTwoButtonClick"    (Apple-specific: left/right region split)
```

### Registry analysis

The driver builds a per-user HKCU path by:
1. Calling `ZwQueryInformationToken` + `PsReferencePrimaryToken` to get the current user SID
2. Converting the SID to string via `RtlConvertSidToUnicodeString`
3. Appending `\Registry\User\<SID>\Software\Apple Inc.\Mouse`
4. Calling `RtlQueryRegistryValues` to read:
   - `SwapMouseButtons` (also reads `\Control Panel\Mouse\SwapMouseButtons`)
   - `EnableTwoButtonClick` (Apple-specific: splits Magic Mouse into left/right regions)

**No license key, trial timestamp, or version check in registry reads.**
**No `HKLM\SOFTWARE\...` machine-wide driver config (contrast with MagicMouse.sys).**

### M12 implication

M12 does not need EnableTwoButtonClick or SwapMouseButtons (v3 hardware already
reports 2 separate physical buttons). The entire per-user registry block can be omitted.
This eliminates the `PsCreateSystemThread`, `ObOpenObjectByPointer`, `ZwQueryInformationToken`,
`RtlConvertSidToUnicodeString` imports entirely from M12.

---

## Q3: Descriptor Mutation Routine

### HID descriptor bytes confirmed at binary offset 0xa850

The actual descriptor bytes embedded in the .sys file (verified byte-for-byte match):

```
05 01 09 02 A1 01    UsagePage(GenericDesktop), Usage(Mouse), Collection(Application)
85 02                ReportID(0x02)

  -- Buttons (2 physical on v3) --
  05 09 19 01 29 02  UsagePage(Button), UsageMin(1), UsageMax(2)
  15 00 25 01        Logical Min(0), Max(1)
  95 02 75 01 81 02  Count(2), Size(1), Input(Data,Variable,Absolute)
  95 01 75 05 81 03  Count(1), Size(5), Input(Constant) -- 5-bit padding

  -- Vendor bit (0xFF02/0x20, const) --
  06 02 FF 09 20     UsagePage(Vendor 0xFF02), Usage(0x20)
  95 01 75 01 81 03  Count(1), Size(1), Input(Constant)

  -- X/Y axes --
  05 01 09 01 A1 00  UsagePage(GenericDesktop), Usage(Pointer), Collection(Logical)
  15 81 25 7F        Logical Min(-127), Max(127)
  09 30 09 31        Usage(X), Usage(Y)
  75 08 95 02 81 06  Size(8), Count(2), Input(Data,Variable,Relative)

  -- Scroll: horizontal pan --
  05 0C 0A 38 02     UsagePage(Consumer), Usage(AC Pan = 0x0238)
  75 08 95 01 81 06  Size(8), Count(1), Input(Data,Variable,Relative)

  -- Scroll: vertical wheel --
  05 01 09 38        UsagePage(GenericDesktop), Usage(Wheel = 0x38)
  75 08 95 01 81 06  Size(8), Count(1), Input(Data,Variable,Relative)

  C0                 End Collection (Logical/Pointer)

-- Feature 0x47: synthesized battery --
05 06 09 20          UsagePage(0x06 Generic Device), Usage(0x20)
85 47                ReportID(0x47)
15 00 25 64          Logical Min(0), Max(100)
75 08 95 01 B1 A2    Size(8), Count(1), Feature(Data,Variable,Absolute)

-- Vendor blob pass-through (RID=0x27) --
05 06 09 01          UsagePage(0x06 Generic Device), Usage(BatteryStrength=0x01)
85 27                ReportID(0x27)
15 01 25 41          Logical Min(1), Max(65)
75 08 95 2E          Size(8), Count(46)
81 06                Input(Data,Variable,Relative)

C0                   End Collection (Application)
```

**Descriptor is 116 bytes total** (from 0xa850 to 0xa8c4, two End Collections).

### Input report sizes

| ReportID | Type | Payload bytes | On-wire size | Notes |
|----------|------|--------------|--------------|-------|
| 0x02 | Input | 5 bytes | 6 bytes | Buttons+padding+vendor bit (1B) + X+Y (2B) + Pan (1B) + Wheel (1B) |
| 0x27 | Input | 46 bytes | 47 bytes | Vendor blob pass-through -- explains empirical Input=47 |
| 0x47 | Feature | 1 byte | 2 bytes | Synthesized battery; Feature=2 in empirical caps |

**HID max input report = 47 bytes (RID=0x27). This is the "47-byte unified TLC" reference.**

---

## Q4: Feature 0x47 Backing

Feature 0x47 is **declared** in the synthesized descriptor at `85 47 ... B1 A2`.

- `B1 A2` = Feature(Data, Variable, Absolute) -- Windows HID class will expose this capability
- However, v3 firmware does NOT respond to RID=0x47 Feature requests
- When Windows calls `HidD_GetFeature` with ReportID=0x47, the IRP reaches the BT stack,
  which returns err=87 (ERROR_INVALID_PARAMETER) because the device has no data for that ID

**Mechanism**: The driver declares the capability in the descriptor but provides NO interception
in the completion path for Feature IRPs with RID=0x47. The IRP falls through to the device
which rejects it. This is NOT an active trap -- it is a passive pass-through of a declared
capability that the firmware does not implement.

### M12 implication for battery

M12 must **intercept** Feature 0x47 GET_REPORT IRPs in the completion path and fill them
with battery percentage translated from the vendor format. applewirelessmouse.sys does NOT
do this -- it declares the capability and lets it fail. M12 is the delta that makes
Feature 0x47 actually work by:
1. Intercepting the completion IRP
2. Reading vendor battery bytes from the native RID=0x27 input stream
3. Translating from vendor format to 0-100 percentage
4. Writing the translated value into the Feature 0x47 response buffer

---

## Q5: License Check / Userland Handshake

**Result: NONE found.**

- No license/trial/expired strings in binary
- No BCrypt imports (the license gate in MagicMouse.sys uses BCrypt for its trial marker)
- No custom device interface GUID (the `{7D55502A-...}` PDO bus in MagicMouse.sys)
- No IoBuildDeviceIoControlRequest to any service-named pipe or license server
- No `WdfDeviceCreateDeviceInterface` equivalent (no custom bus interface exposed)

The only IOCTL construction (`IoBuildDeviceIoControlRequest`) is used to communicate
with `\Device\AppleBluetoothMultitouch` for trackpad coordination, not for licensing.

**Confirmed pure-kernel, no userland service required.**

---

## Q6: Function Size Table (Top 10)

```
size_bytes  addr        name
      2752  140007110  FUN_140007110   <-- likely: main IRP dispatch or descriptor inject
      2387  14000a440  FUN_14000a440   <-- likely: per-user preference / system thread body
      1503  140009e60  FUN_140009e60   <-- likely: IRP completion or device open
      1283  140002d3c  FUN_140002d3c
      1216  140005c70  FUN_140005c70
      1110  1400097e0  FUN_1400097e0
      1087  1400051bc  FUN_1400051bc
      1052  140009000  FUN_140009000
      1041  140004da8  FUN_140004da8
       923  1400012d8  FUN_1400012d8
```

Comparison with MagicMouse.sys:
- MagicMouse.sys top function: 3528 bytes (28% larger than Apple's 2752)
- MagicMouse.sys has 13+ functions above 3000 bytes; Apple has 0
- Apple's function size distribution is much more compact, consistent with fewer responsibilities

### Full top 30

```
size_bytes  addr        name
      2752  140007110  FUN_140007110
      2387  14000a440  FUN_14000a440
      1503  140009e60  FUN_140009e60
      1283  140002d3c  FUN_140002d3c
      1216  140005c70  FUN_140005c70
      1110  1400097e0  FUN_1400097e0
      1087  1400051bc  FUN_1400051bc
      1052  140009000  FUN_140009000
      1041  140004da8  FUN_140004da8
       923  1400012d8  FUN_1400012d8
       870  140005900  FUN_140005900
       807  1400036c8  FUN_1400036c8
       787  1400039f0  FUN_1400039f0
       757  1400017d4  FUN_1400017d4
       751  1400025b4  FUN_1400025b4
       727  140001f68  FUN_140001f68
       725  140009500  FUN_140009500
       713  1400028a4  FUN_1400028a4
       697  1400022f8  FUN_1400022f8
       662  140006130  _control87
       648  140007e40  FUN_140007e40
       647  140006964  _raise_exc_ex
       632  140001acc  FUN_140001acc
       606  1400056a0  FID_conflict:__remainder_piby2f_inline
       582  14000430c  FUN_14000430c
       573  140003240  FUN_140003240
       491  140001090  FUN_140001090
       457  140002b70  FUN_140002b70
       426  140003d04  FUN_140003d04
       418  14000465c  FUN_14000465c
```

Notable: `_control87` (FPU control word), `__remainder_piby2f_inline` (trig math) -- confirms
floating-point is present (consistent with `sqrt` import and gesture/acceleration logic).

---

## Q6b: Decompile Results (180-second timeout)

All 4 functions (DriverEntry + top 3) failed decompilation at 180 seconds.

**Decompile completeness: 0 / 4** (same outcome as MagicMouse.sys at 60s; Apple driver
also has stripped symbols and Ghidra's Jython decompiler path fails in headless mode for
this type of KMDF driver binary).

**Workaround approach**: Binary-level analysis (static strings, import table, raw descriptor
bytes at 0xa850) produced more actionable findings than decompile would for M12 purposes.

---

## Notable Strings (Full Sweep)

```
addr        refs  string
1400081c0     1  u"\Device\AppleBluetoothMultitouch"
140008210     1  u"\DosDevices\AppleBluetoothMultitouch"
140008260     2  u"\Registry\User\"
140008280     1  u"\Control Panel\Mouse"
1400082b0     2  u"SwapMouseButtons"
1400082f0     1  u"\Software\Apple Inc.\Mouse"
140008330     2  u"EnableTwoButtonClick"
1400120fe     0  u"CompanyName"
140012118     0  u"Apple Inc."
140012158     0  u"Apple Wireless Mouse"
14001218a     0  u"FileVersion"
1400121dc     0  u"AppleWirelessMouse.sys"
140012230     0  u"Copyright (C) Apple Inc. All Rights Reserved."
1400112e0     0  "RtlQueryRegistryValues"       (IAT stub string for dynamic resolve)
140011418     0  "IoBuildDeviceIoControlRequest" (IAT stub string for dynamic resolve)
```

---

## Comparison vs MagicMouse.sys

| Dimension | applewirelessmouse.sys | MagicMouse.sys | M12 needs |
|-----------|----------------------|----------------|-----------|
| Total imports | 37 | 34 | ~15 (much smaller) |
| BCrypt/crypto | **NONE** | 11 BCrypt imports (license gate) | NONE |
| Custom bus PDO | **NONE** | {7D55502A-2C87-441F-9993-0761990E0C7A} interface | NONE |
| Registry reads | HKCU button prefs only | HKLM\SOFTWARE\MagicUtilities\Driver | NONE (skip button prefs) |
| Userland handshake | **NONE** | Via custom PDO IOCTL | NONE |
| System thread | YES (PsCreateSystemThread) | Unknown (likely similar) | Possibly YES (vendor input async) |
| Descriptor type | Mode B (47-byte unified TLC) | Mode A (Wheel+Pan+ResolutionMultiplier, 5 TLCs) | Mode B (Apple pattern) |
| Feature 0x47 | Declared; pass-through fail (err=87) | Not declared | M12 must intercept + fill |
| Scroll delivery | RID=0x02 native pass-through | In-IRP translation (license-gated) | RID=0x02 pass-through (Apple pattern) |
| Battery delivery | err=87 on Feature 0x47 | Custom PDO IOCTL (license-gated) | M12 must intercept + translate |
| FP math | YES (sqrt, _control87) | Unknown | NO (M12 is scroll+battery only) |
| Largest function | 2752 bytes | 3528 bytes | Expect ~1000-2000 bytes for M12 dispatch |
| Image size | 76.6 KB | ~78 KB (same package) | Expect 20-40 KB (M12 is subset) |

### M12 Minimum Viable Baseline

applewirelessmouse.sys provides the **descriptor** and **architecture** baseline.
MagicMouse.sys provides the **negative example** (what NOT to replicate).

**What M12 takes from applewirelessmouse.sys:**

1. **Descriptor bytes (inject as-is)**: The 116-byte descriptor at binary offset 0xa850.
   Paste verbatim into M12's descriptor injection routine. No redesign needed.

2. **Architecture pattern**: Pure KMDF lower-filter, no custom PDO bus, no BCrypt, no
   userland service. DriverEntry registers IRP dispatch; AddDevice hooks descriptor injection.

3. **RID=0x02 pass-through for scroll**: Native vendor bytes for RID=0x02 already contain
   Buttons, X, Y, AC Pan, Wheel in the correct format. No in-IRP translation needed.

4. **Feature 0x47 declaration**: Include in descriptor so Windows HID class exposes the cap.

**What M12 adds (not in applewirelessmouse.sys):**

5. **Feature 0x47 IRP interception**: Intercept GET_REPORT IRP completions for RID=0x47.
   Read vendor battery byte from RID=0x27 input stream. Translate to 0-100%.
   Write into the IRP buffer instead of letting the firmware return err=87.

6. **RID=0x27 input stream tap**: Maintain a shadow buffer of the last-seen RID=0x27
   native input packet (46 bytes). Extract battery field from vendor offset.

**What M12 explicitly OMITS from applewirelessmouse.sys:**

7. `PsCreateSystemThread`, `ObOpenObjectByPointer`, `ZwQueryInformationToken`,
   `RtlConvertSidToUnicodeString` -- the entire per-user HKCU preference block.
   v3 hardware has distinct physical buttons; EnableTwoButtonClick is not needed.

8. `sqrt`, `_control87`, `__remainder_piby2f_inline` -- FP math for gesture/trackpad.
   M12 is mouse-only; no trackpad gesture processing required.

9. `IoGetDeviceObjectPointer`, `IoBuildDeviceIoControlRequest` to AppleBluetoothMultitouch --
   the inter-device IOCTL coordination. M12 does not manage a trackpad sibling.

### M12 estimated import list

From the above, M12 should need approximately:
- `WdfVersionBind/Unbind/BindClass/UnbindClass` (4 -- KMDF mandatory)
- `ExAllocatePoolWithTag`, `ExFreePoolWithTag` (2 -- memory)
- `IoAllocateIrp`, `IoFreeIrp`, `IofCallDriver` (3 -- IRP management)
- `KeInitializeEvent`, `KeWaitForSingleObject`, `KeClearEvent`, `KeSetEvent` (4 -- sync for RID=0x27 shadow)
- `RtlInitUnicodeString`, `RtlCopyUnicodeString` (2 -- string ops)
- `MmGetSystemRoutineAddress` (1 -- dynamic API resolve)
- `ZwClose`, `__C_specific_handler` (2 -- misc)

**Estimated total: ~18 imports** (vs 37 for Apple driver, vs 34 for MagicMouse.sys).

---

## Open Questions for M12 Design Phase

1. **RID=0x27 battery byte offset**: Which byte(s) in the 46-byte vendor blob contains the
   battery percentage? Needs empirical measurement (ETW capture of RID=0x27 at known
   battery level). The descriptor declares Min=1, Max=65 (not 0-100), suggesting raw
   firmware unit that requires translation formula, not a 1:1 map.

2. **IRP interception point for Feature 0x47**: Does M12 intercept the IRP at the
   completion callback (IRP_MJ_INTERNAL_DEVICE_CONTROL going DOWN to device, then
   intercept the completion going UP)? Or does M12 short-circuit the IRP before it
   reaches the device? The pass-through approach (let it go down, intercept completion,
   overwrite buffer) is simpler but requires the device to not BSOD on an unknown RID.
   Empirical evidence (err=87 not BSOD) confirms the device handles unknown RIDs safely,
   so interception-at-completion is viable.

3. **System thread necessity**: applewirelessmouse.sys spawns a system thread
   (PsCreateSystemThread). For M12, if the RID=0x27 shadow buffer is maintained via
   IRP completion callbacks (no separate thread), the thread can be eliminated. This
   simplifies the driver significantly. Confirm during implementation.
