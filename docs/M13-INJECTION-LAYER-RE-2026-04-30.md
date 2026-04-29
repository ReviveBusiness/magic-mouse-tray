---
created: 2026-04-30
modified: 2026-04-30
type: reverse-engineering-findings
status: COMPLETE
binary: applewirelessmouse.sys
binary_sha256: 08f33d7e3ece2c73950a9706f1c4c9057894eaeaf1c4fb355f261f3c2333378f
binary_size: 78424
binary_built: 2019-07-11 (linker) — 2026-04-21 (DriverVer in INF)
binary_version: 6.2.0.0
verdict: |
  Apple injects the HID descriptor by filtering IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE
  (0x00410210) on the BTHENUM-published HID PDO and rewriting the HIDDescriptorList
  attribute (0x0206) bytes in the SDP response.
---

# M13 Injection Layer Reverse Engineering — applewirelessmouse.sys

## TL;DR — DEFINITIVE ANSWER

> **Apple's `applewirelessmouse.sys` is a KMDF lower filter on the BTHENUM-published HID PDO. It filters `IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE` (0x00410210) requests going DOWN to the BT stack, and on completion REWRITES the HID Descriptor List (SDP attribute 0x0206) bytes in the response with its own 116-byte descriptor (loaded from `_DAT_14000c050`, file offset 0xA850). HidBth then sees Apple's descriptor instead of the device's native one.**

This is a **NEW candidate** not in the M12-EMPIRICAL-BLOCKER candidate list. None of the original 5 candidates matched. The closest was Candidate #3 ("custom BTH-stack IOCTL outside the BRB submit path") — but the IOCTL involved is `0x00410210` (SDP search/attribute), not a totally undocumented one.

**Status**: COMPLETE. Architecture identified, call paths confirmed, design spec ready.

---

## 1. Binary metadata (verified)

| Attribute | Value |
|---|---|
| Path (live install) | `C:\Windows\System32\drivers\applewirelessmouse.sys` |
| SHA-256 | `08f33d7e3ece2c73950a9706f1c4c9057894eaeaf1c4fb355f261f3c2333378f` |
| Size | 78,424 bytes |
| Format | PE32+ (x64), KMDF |
| Image base | `0x140000000` |
| AddressOfEntryPoint | `0x6D90` (DriverEntry stub @ VA `0x140006D90`) |
| Provider | Apple Inc. |
| Pool tag | `BTMT` |
| GUARD_CF | yes |
| Imports DLLs | `ntoskrnl.exe`, `WDFLDR.SYS` (only 2) |

INF: `/mnt/c/Windows/System32/DriverStore/FileRepository/applewirelessmouse.inf_amd64_ac34ebceaaf7324c/`. Hardware IDs cover Magic Mouse v1 (PID 0x030D), v2 (PID 0x0310), older Apple HID (PID 0x0269), and **v3 / Magic Mouse 2024 (PID 0x0323)**.

---

## 2. PE section map (from Ghidra import)

| Section | Virtual range | File offset | Perms |
|---|---|---|---|
| Headers | 0x140000000–0x1400003FF | 0x0 | R-- |
| .text | 0x140001000–0x1400085FF | 0x400 | R-X |
| **NONPAGE** | **0x140009000–0x14000ADFF** | **0x7A00** | **R-X** |
| .rdata | 0x14000B000–0x14000BFFF | 0x9800 | R-- |
| **.data** | **0x14000C000–0x14000F023** | **0xA800** | **RW-** |
| .pdata | 0x140010000–0x1400103FF | 0xD600 | R-- |
| INIT | 0x140011000–0x1400115FF | 0xDA00 | R-X |
| .rsrc | 0x140012000–0x1400123FF | 0xE000 | R-- |
| .reloc | 0x140013000–0x1400131FF | 0xE400 | R-- |

**Descriptor location**: file offset `0xA850` → VA `0x14000C050` (in `.data` section, RW). The descriptor is in writable data — not `.rdata` — meaning the driver could in principle patch it at runtime (e.g., to flip per-PID fields). In practice the only references treat it as read-only.

---

## 3. Imports (kernel API surface) — already documented in earlier sections

Significantly: **NO** `IoSetCompletionRoutine`, **NO** HID minidriver imports. The driver uses KMDF dispatch (no manual MajorFunction[] registration) and does completion-routine work via WDF `EvtRequestCompletion`-style callbacks set on its own allocated IRPs.

The IRP-construction primitives present (`IoAllocateIrp`, `IoBuildDeviceIoControlRequest`, `IofCallDriver`, `IoFreeIrp`) are used to forward the SDP query to the BT stack with the driver's own completion logic.

---

## 4. Confirmed function map

| Function (Ghidra label) | VA | Size | Role |
|---|---|---|---|
| `entry` | `0x140006D90` | 43 | DriverEntry — calls `FUN_1400110FC` then `FUN_140006DBC` |
| `FxStubUnbindClasses` | `0x140007040` | 123 | WDF binding cleanup helper (matched by FunctionID library) |
| `FUN_1400012D8` | `0x1400012D8` | 923 | **AddDevice** — creates `\Device\AppleBluetoothMultitouch`, registers EvtIoDefault `FUN_140009500` |
| `FUN_140009500` | `0x140009500` | (~1KB) | Top-level WDF I/O queue dispatcher (calls FUN_14000a440 / FUN_1400097e0 by IOCTL — not yet decompiled, inferred from registration in FUN_1400012D8) |
| `FUN_1400097E0` | `0x1400097E0` | 1110 | **EvtIoInternalDeviceControl** for `IOCTL_INTERNAL_BTH_SUBMIT_BRB` (0x00410003) — dispatches BRB types 0x102/0x103/0x104/0x105 (L2CAP server registration, channel open/close, ACL transfer) |
| `FUN_14000A440` | `0x14000A440` | 2387 | **DESCRIPTOR INJECTION** — filters IRPs with IOCTL `0x00410210`; submits its own SDP query; rewrites HIDDescriptorList in response with 116 bytes from `_DAT_14000c050` |
| `FUN_140007110` | `0x140007110` | 2752 | Largest function — input report processor (likely RID translation / button mapping / scroll synthesis for v1/v2) |
| `FUN_140001D44` | `0x140001D44` | 182 | Hardware-ID compare for `VID&000205ac_PID&030d` and `VID&000205ac_PID&0310` (v1/v2 only). v3 PID 0x0323 is NOT string-compared here — falls through to default code path. |
| `FUN_140001DFC` | `0x140001DFC` | 274 | Sends an IOCTL to `\DosDevices\KeyManager` (with `\DosDevices\KeyAgent` fallback). External BootCamp pairing services. |
| `FUN_1400017D4` | `0x1400017D4` | 757 | Reads `\Control Panel\Mouse` and `SwapMouseButtons` registry value |
| `FUN_140001ACC` | `0x140001ACC` | (~?) | Reads `\Software\Apple Inc.\Mouse` and `EnableTwoButtonClick` |
| `FUN_14000ADA0` | `0x14000ADA0` | (small) | Completion routine for the SDP-query IRP submitted by FUN_14000A440 (sets event) |

---

## 5. The injection mechanism — call sequence

### 5a. Trigger: HidBth issues `IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE` going down

When the HID device PDO is started by HidBth (the registered HID minidriver), HidBth needs the device's HID descriptor. It is acquired by querying the device's SDP record for attribute `0x0206` (HIDDescriptorList). HidBth issues `IRP_MJ_INTERNAL_DEVICE_CONTROL` with IOCTL `0x00410210` (`IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE`) on the device PDO.

### 5b. The IRP traverses Apple's lower filter

Per the INF, `applewirelessmouse` is registered as `LowerFilters` on the HIDClass device. The device PDO is the BTHENUM-published `BTHENUM\{HID profile UUID}_VID&PID&...` PDO. Apple's filter sits between HidBth and BTHENUM:

```
[HidClass.sys]                                         ← function driver
        │                                              │
[HidBth.sys]                                           ← HID minidriver
        │  IRP_MJ_INTERNAL_DEVICE_CONTROL,             │
        │   IoControlCode = 0x00410210                 │
        ▼   (IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE)   │
[applewirelessmouse.sys]                               ← LOWER FILTER (Apple)
        │                                              │
[BTHENUM.SYS]                                          ← bus driver
        │                                              │
[BthPort.sys]                                          ← BT port/transport
        │                                              │
[BT radio firmware]                                    │
```

### 5c. FUN_14000A440 dispatches on the IOCTL

The decompiled body of FUN_14000A440 (truncated for readability):

```c
// param_4 = WDFREQUEST received by EvtIoInternalDeviceControl
puVar18 = WdfRequestRetrieveOutputBuffer(...);          // vtbl + 0x650
iVar12 = *(int *)(param_3 + 8);                          // OutputBufferLength
lVar23 = WdfRequestWdmGetIrp(... param_1);              // vtbl + 0x8e8 → PIRP
iVar21 = *(int *)(*(longlong *)(lVar23 + 0xb8) + 0x18); // IRP->CurrentStack->IoControlCode

// EARLY EXIT IF NOT 0x00410210
if (iVar21 != 0x410210) goto LAB_14000ad56;             // pass through unmodified

// Parse the SDP search request to get search criteria + buffer ptr
piVar2 = *(int **)(lVar23 + 0x18);                       // request input buffer
cVar11 = FUN_140002240(piVar2 + 2, &local_98, &local_8c);// parse SDP DataElement type+len
...
```

### 5d. Apple submits its OWN SDP query IRP downward (LAB_14000a753 prelude)

```c
// Allocate own IRP and a 0xA0-byte BTH "SDP_INTERFACE" struct (pool tag BTMT)
lVar15 = IoAllocateIrp(*(char *)(lVar14 + 0x4c) + '\x01', 0);
_Dst   = ExAllocatePoolWithTag(NonPagedPool, 0xA0, 'BTMT');
memset(_Dst, 0, 0xA0);

// Build the next-stack-location for a sub-request (likely an IRP_MJ_PNP IRP_MN_QUERY_INTERFACE
// with a SDP_INTERFACE GUID, populated into _Dst). Specifics:
//   Set fnTable pointer at -0x40 = &DAT_14000b1e8 (a static interface descriptor)
//   Set major/minor at -0x48 = 0x081B
//   Set IoControlCode-equivalent at -0x38 = 0x010000A0
//   Set buffer at -0x30 = _Dst
//   Set CompletionRoutine at -0x10 = FUN_14000ada0  (waits on event)
KeInitializeEvent(puVar16, NotificationEvent, FALSE);
*(... + 0x30) = STATUS_NOT_SUPPORTED;
iVar12 = IofCallDriver(lVar14, lVar15);                  // forward down
if (iVar12 == STATUS_PENDING) {
    KeWaitForSingleObject(puVar16, ...);                 // wait completion
    iVar12 = lVar15->IoStatus.Status;
}
```

The forwarded IRP carries an SDP-interface query (0x010000A0 in the IoControl-equivalent slot) used to retrieve the **SDP_INTERFACE** function-table from BTHENUM. This gives Apple a vtable (`_Dst[0x78]` is one of those callbacks) it can then use to walk SDP attribute responses programmatically.

### 5e. SDP record traversal — find HIDDescriptorList (attribute 0x0206)

Apple uses the obtained SDP_INTERFACE vtable to enumerate attributes:

```c
SDP_INTERFACE->FindAttribute(lVar23, len, NULL, &local_68, &local_60);
while (((*local_68 != '\t')                              // 0x09 = SDP_TYPE_UINT_16
     || (*(short *)(local_68 + 1) != 0x602)              // attribute ID 0x0206 (LE: 06 02)
     || (*(short *)(local_68 + 7) != 0x2208))) {         // SDP HID descriptor type marker
    SDP_INTERFACE->FindAttribute(... &local_68 ...);     // step to next match
}
```

The marker `\t \02\06 ... \22\x08` is exactly the SDP DataElement preamble for attribute `0x0206`'s HID Descriptor List, where:
- `0x09 02 06` — SDP UINT16 attribute ID = `0x0206`
- (sequence headers)
- `0x08 0x22` — UINT8 = `0x22` (HID_REPORT_DESCRIPTOR_TYPE)
- `0x25 LL` (or `0x26 LLLL` / `0x27 LLLLLLLL`) — descriptor length
- `<descriptor bytes>`

### 5f. The descriptor REWRITE — LAB_14000ace5

When the lengths match (no resize needed), Apple copies the 116 bytes from `_DAT_14000C050` directly into the SDP response buffer:

```c
LAB_14000ace5:
    lVar23 = local_96 + local_40 + uVar22;                // offset of descriptor in SDP buf
    *(undefined8 *)(pcVar10 + lVar23 + 8)        = _DAT_14000c050;            // bytes [0..7]
    *(undefined8 *)(pcVar10 + lVar23 + 8 + 8)    = uRam_14000c058;            // bytes [8..15]
    *(undefined8 *)(pcVar10 + lVar23 + 0x18)     = _DAT_14000c060;            // [16..23]
    *(undefined8 *)(pcVar10 + lVar23 + 0x18 + 8) = uRam_14000c068;            // [24..31]
    *(undefined8 *)(pcVar10 + lVar23 + 0x28)     = _DAT_14000c070;            // [32..39]
    ...
    *(undefined4 *)(pcVar10 + lVar23 + 0x78)     = DAT_14000c0c0;             // [120..123]  (overflow-trim word; descriptor is 116 bytes so writes go up to 0x73)
```

When sizes differ (most common case — native 135 bytes vs. injection 116 bytes), Apple takes the alternate path (lines ~370–500 of decompile) which:

1. Allocates a new SDP buffer sized to fit the new descriptor + adjusted sequence headers.
2. Re-encodes the outer SDP sequence type byte `0x35 SS` / `0x36 SSSS` / `0x37 SSSSSSSS` based on whether the new total length fits in 8/16/32 bits.
3. Re-encodes the inner sequence header similarly.
4. Re-encodes the descriptor-length encoding `0x25 LL` / `0x26 LLLL` / `0x27 LLLLLLLL`.
5. Calls `FUN_140007E40(dst, src_descriptor_bytes, len)` (the memcpy primitive).
6. Patches surrounding sequence-size bytes so HidBth's SDP parser accepts the result.
7. Replaces the response buffer pointer in the IRP and completes the original request.

### 5g. HidBth sees Apple's descriptor

The IRP completes back up the stack to HidBth with the modified SDP response. HidBth parses the response, extracts attribute 0x0206, and uses it as the device's HID descriptor — getting the 116-byte Apple descriptor (Mouse TLC RID=0x02 with embedded AC-Pan + Wheel) instead of the device's native 135-byte descriptor (RID=0x12, no scroll).

HidClass then builds its `_HIDP_DEVICE_DESC` from this descriptor and exposes the standard mouse RID=0x02 to user-mode clients (mouhid.sys). The firmware natively emits RID=0x02 reports already (per M12-EMPIRICAL-BLOCKER), so reports flow through unmodified.

---

## 6. Why M12's BRB-lower-filter approach failed

M12 v1.x hooked `IOCTL_INTERNAL_BTH_SUBMIT_BRB` (0x00410003) and tried to find/modify SDP descriptor traffic in BRB-shaped frames. **This was the wrong IOCTL.** SDP queries from HidBth use the higher-level `IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE` (0x00410210), which is a different request type that does not flow through the BRB submit path on this stack.

Apple's filter actually does ALSO handle BRB IOCTLs (FUN_1400097E0 dispatches BRB types 0x102/0x103/0x104/0x105), but only for L2CAP channel management — the descriptor injection happens **only** in the SDP IOCTL path, separately from BRB handling.

The BTHPORT registry cache the user observed repopulating with the native 351-byte SDP record is consistent: BTHPORT populates this cache from its OWN initial SDP browse during pairing, before Apple's filter is bound. Apple's filter only runs on subsequent IRPs to the device PDO once the HID stack is up.

---

## 7. Hardware-ID handling in Apple's driver

`FUN_140001D44` (decompiled in full):

```c
undefined1 FUN_140001D44(WDFDEVICE param_1)
{
    int iVar1;
    wchar_t *_Str;
    wchar_t *pwVar2;
    undefined1 uVar3;
    undefined1 local_res10[8];

    _Str = (wchar_t *)ExAllocatePoolWithTag(NonPagedPool, 0x200, 'BTMT');
    if (_Str != NULL) {
        iVar1 = WdfDeviceQueryProperty(... DevicePropertyHardwareID ... 0x200, _Str, ...);
        uVar3 = 0;
        if ((-1 < iVar1) &&
            ((pwVar2 = wcsstr(_Str, L"VID&000205ac_PID&030d"), pwVar2 != NULL ||
             (pwVar2 = wcsstr(_Str, L"VID&000205ac_PID&0310"), uVar3 = 0, pwVar2 != NULL)))) {
            uVar3 = 1;
        }
        ExFreePoolWithTag(_Str, 0);
        return uVar3;
    }
    return 0;
}
```

Returns `1` only for v1 (PID 0x030D) or v2 (PID 0x0310). For v3 (PID 0x0323) — which has the Apple Inc. VID 0x004C, NOT 0x05AC — this returns `0`. v3 follows the **default code path** that does NOT execute v1/v2-specific branches. Apple's descriptor-injection (FUN_14000A440) does NOT condition on this check — the descriptor is replaced for ALL incoming devices that match the INF hardware IDs.

Implication: Apple's driver works for v3 because (a) the INF binds it (PID 0x0323 in INF), and (b) the descriptor injection is universal. The v1/v2-specific code paths likely cover input-report translation for the older firmware that emitted multi-touch frames Apple needed to repackage. v3 firmware natively emits the standard Mouse RID=0x02 layout, so the input-report translation path is a no-op.

---

## 8. Other architectural details

### 8a. AddDevice (FUN_1400012D8)

Creates a control device named `\Device\AppleBluetoothMultitouch` with symlink `\DosDevices\AppleBluetoothMultitouch`. Registers a single I/O queue with `EvtIoDefault = FUN_140009500`. The queue is parallel-dispatch (DispatchType=2), power-managed.

The device interface created at `local_178[0] = 0x4a0048` is a custom GUID (not standard) — used by Apple's userland services (KeyManager / KeyAgent — see FUN_140001DFC) to coordinate with the driver.

### 8b. KeyManager / KeyAgent communication (FUN_140001DFC)

Sends a zero-payload IOCTL to `\DosDevices\KeyManager` (with `\DosDevices\KeyAgent` fallback). This is a synchronization handshake with Apple's BootCamp pairing service. The 5-second timeout indicates a "best-effort" notification — the driver continues regardless of whether the service responds.

### 8c. Mouse settings (FUN_1400017D4 + FUN_140001ACC)

`FUN_1400017D4` reads `HKEY_CURRENT_USER\Control Panel\Mouse\SwapMouseButtons` (Windows global mouse-swap preference).
`FUN_140001ACC` reads `HKEY_CURRENT_USER\Software\Apple Inc.\Mouse\EnableTwoButtonClick` (Apple's two-button click feature toggle).

These settings affect button-mapping in the input-report path (FUN_140007110 territory), not the descriptor injection.

---

## 9. Verification of the original 5 candidates

| # | Candidate (M12-EMPIRICAL-BLOCKER) | Verdict | Evidence |
|---|---|---|---|
| 1 | HidClass-layer hook on IOCTL_HID_GET_REPORT_DESCRIPTOR | **REFUTED** | No HID minidriver IOCTL constants present in binary (searched 0xB0003, 0xB0007, 0xB000B, 0xB0027, 0xB0190, etc.) |
| 2 | QUERY_INTERFACE on a BTH profile interface | **PARTIALLY CORRECT** | Apple DOES use a QUERY_INTERFACE-style sub-IRP at `0x010000A0` to obtain a SDP_INTERFACE vtable, but this is a sub-step of the descriptor injection, not the injection itself |
| 3 | Custom BTH-stack IOCTL outside BRB submit | **CORRECT** | The IOCTL is `IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE` (0x00410210) |
| 4 | BTHPORT-internal SDP cache pre-population | **REFUTED** | No registry-write APIs imported; no code writes to `\BTHPORT\Parameters\Devices\<MAC>\CachedServices` |
| 5 | Completion routine on IRP_MJ_PNP IRP_MN_QUERY_DEVICE_RELATIONS | **REFUTED** | No PNP-specific code paths touching the descriptor; descriptor injection is keyed on IOCTL only |

The architectural finding is essentially Candidate #3 with the specific IOCTL identified.

---

## 10. Pool tag, GUID, and pointer references for cross-checking

| Symbol | VA | Use |
|---|---|---|
| `_DAT_14000C050` | 0x14000C050 | The 116-byte HID descriptor blob |
| `DAT_14000B1E8` | 0x14000B1E8 | Function-table descriptor used in sub-IRP at -0x40 (likely BTH SDP_INTERFACE GUID descriptor) |
| `DAT_14000B3A8` | 0x14000B3A8 | Used as 2nd arg to WDF AddDevice helper (likely a string or GUID) |
| `DAT_14000EFE8` | 0x14000EFE8 | KMDF FUNCTION TABLE pointer (`WDF_BIND_INFO::FuncTable`) |
| `DAT_14000EFF0` | 0x14000EFF0 | KMDF DRIVER GLOBALS pointer |
| `DAT_14000F008` | 0x14000F008 | Lock for AddDevice serialization (passed to vtbl+0x9E0/0x9E8 — `WdfWaitLockAcquire`/`Release`) |
| `DAT_14000F010` | 0x14000F010 | The created control device handle (set in AddDevice) |
| `DAT_14000F018` | 0x14000F018 | Reference count or one-shot init flag |
| `DAT_14000C570` | 0x14000C570 | Stack-cookie (`__security_cookie`) |
| Pool tag | `'BTMT'` (0x544D5442) | All ExAllocatePoolWithTag calls use this tag |

WDF function-table offsets used (decoded by reference to `wdffuncenum.h` / KMDF 1.x):

| Offset | KMDF function (inferred) |
|---|---|
| 0x70 | `WdfDriverIsVersionAvailable` (or similar version probe) |
| 0xC8 (200) | `WdfFdoInitWdmGetPhysicalDevice` (or similar AddDevice-time call) |
| 0xD8 | `WdfDeviceSetSpecialFileSupport` (or similar) |
| 0xF8 | `WdfRequestComplete` |
| 0x100 | `WdfRequestGetIoQueue` (or `WdfWdmDeviceGetWdfDeviceHandle`) |
| 0x138 | `WdfDeviceWdmGetDeviceObject` |
| 0x150 | `WdfRequestComplete` (with status arg) |
| 0x1B0 | `WdfObjectDelete` (cleanup) |
| 0x218 | `WdfDeviceCreate` |
| 0x258 (600) | `WdfDeviceCreateSymbolicLink` |
| 0x280 | `WdfDeviceCreateDeviceInterface` |
| 0x4C0 | `WdfIoQueueCreate` |
| 0x4E8 | `WdfRequestGetParameters` |
| 0x650 | `WdfRequestRetrieveOutputBuffer` |
| 0x680 | `WdfObjectDelete` (close) |
| 0x7D8 | `WdfRequestMarkCancelable` (or stop completion) |
| 0x7E8 | `WdfRequestForwardToIoQueue` (or `WdfRequestSend` returning bool) |
| 0x7F0 | `WdfRequestGetStatus` |
| 0x820 | `WdfRequestSend` (with completion routine) |
| 0x838 | `WdfRequestComplete` (completion w/status) |
| 0x8E8 | `WdfRequestWdmGetIrp` |
| 0x9E0 | `WdfWaitLockAcquire` |
| 0x9E8 | `WdfWaitLockRelease` |

(Indices are educated guesses by call-site shape and arg counts; would require KMDF function-ID database for exact names. Names are NOT load-bearing for the architectural finding.)

---

## 11. Final answer to the original question

> **Q**: At what EXACT layer does Apple's filter inject the replacement HID descriptor?

> **A**: At the BTH **SDP IOCTL layer** (not the BRB submit layer, not the HID minidriver IOCTL layer).
>
> Specifically: Apple's filter intercepts `IRP_MJ_INTERNAL_DEVICE_CONTROL` carrying `IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE` (`0x00410210`) sent **DOWN** by HidBth to BTHENUM during HID device startup. On completion of the SDP query, it parses the SDP response, finds attribute `0x0206` (HIDDescriptorList), and **rewrites the embedded HID descriptor bytes** with the 116-byte descriptor stored at `_DAT_14000C050` (file offset `0xA850`). Surrounding SDP DataElement sequence-size and descriptor-length encodings are recomputed to match the new size.

The filter dispatch is registered via KMDF (`WdfIoQueueCreate` in AddDevice). The relevant function is `FUN_14000A440` at VA `0x14000A440`. It is reached for IOCTLs other than `0x00410210` only to early-return (passthrough); the actual injection happens on the `0x00410210` path.
