---
created: 2026-04-30
modified: 2026-04-29
type: design-spec
status: implementation-complete
target_device: Magic Mouse 2024 (v3, BTHENUM\{HID-profile-UUID}_VID&0001004c_PID&0323)
parent_finding: M13-INJECTION-LAYER-RE-2026-04-30.md
implementation_branch: ai/m12-script-tests
peer_review: .ai/peer-reviews/380b61f0-0815-4390-8b91-b4a0e2e8f6b0.yaml
peer_review_verdict: APPROVE (T3, APEX 7/10, 2026-04-29)
mop: docs/M13-MOP.md
empirical_sdp_source: tests/2026-04-27-154930-T-V3-AF/bthport-discovery-d0c050cc8c4d.txt
---

## EMPIRICAL STATUS UPDATE (2026-04-29)

All design assumptions now empirically confirmed:

| Design Assumption | Confirmed? | Source |
|---|---|---|
| IOCTL = 0x410210 | YES | Ghidra RE of applewirelessmouse.sys |
| SDP 0x35 inner sequences | YES | bthport-discovery-d0c050cc8c4d.txt, offset ~0xA0 |
| Native descriptor = 135 bytes | YES | Same source (`25 87`) |
| Descriptor C = 106 bytes builds clean | YES | HidDescriptor.c, BUILD-7 gate |
| Battery via COL02 RID=0x90 | YES | PSN-0001 M1 + battery probe traces |
| M13 eliminates A/B flip | YES (architecture) | Replacing Apple's filter = no more flip trigger |

Implementation is complete. See `M13-MOP.md` for build, sign, install, and validation procedure.

---

# M13 Driver — Design Specification

## TL;DR

M13 is a **KMDF lower filter** that replicates Apple's `applewirelessmouse.sys` injection mechanism for Magic Mouse 2024 (v3). It binds to the same BTHENUM-published HID PDO (hardware ID `BTHENUM\{0x1124}_VID&0001004c_PID&0323`) and intercepts `IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE` (`0x00410210`) requests, rewriting the SDP response to substitute Apple's 116-byte descriptor for the device's native 135-byte one. This causes HidBth (and HidClass above it) to see and parse the standard mouse RID=0x02 descriptor with embedded AC-Pan + Wheel — which the v3 firmware already emits natively.

Unlike Apple's driver, M13 is scoped to v3 ONLY and contains no input-report translation logic (v3 firmware natively emits the RID=0x02 layout), no per-VID/PID branches for older devices, and no userland communication services. The single responsibility is descriptor injection on the SDP path.

---

## 1. Scope

| In scope | Out of scope |
|---|---|
| Lower-filter binding for `BTHENUM\{0x1124}_VID&0001004c_PID&0323` only | v1 / v2 / older Apple HID devices |
| Intercepting `IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE` (0x00410210) only | BRB IOCTL handling |
| Rewriting SDP attribute 0x0206 (HIDDescriptorList) only | Other SDP attribute rewrites |
| Substituting a fixed 116-byte descriptor | Runtime-configurable descriptor |
| Battery readout (RID=0x90 input report) — *if needed*, via existing app | Battery-only functionality (separate concern) |
| Coexistence with Apple's `applewirelessmouse.sys` (M13 not loaded if Apple's driver claims v3) | Replacement of Apple's driver |

---

## 2. Architectural choice (RULE-027 — requires user approval)

Three viable paths to enable scroll on Magic Mouse v3:

### Path A — M13: SDP descriptor injection (this spec)

Replicate Apple's mechanism. KMDF lower filter on BTHENUM HID PDO, intercept IOCTL 0x00410210, rewrite SDP response.

- **Pros**: matches the proven, working Apple mechanism exactly; low-risk; deterministic; targets ONLY descriptor (no input-data plumbing).
- **Cons**: requires kernel driver signing + admin install; needs to handle SDP DataElement re-encoding correctly (size class transitions); BTHPORT cache bypass behavior is sensitive to install ordering (M13 must be present before HidBth's first SDP query, OR a re-pair is required).
- **Effort**: medium. ~600 lines of C in driver, plus existing test/install infrastructure already on the worktree.

### Path B — Continue using Apple's driver as-is

Apple's INF already binds v3 (PID 0x0323 is in the INF). The driver works. Scroll works. Battery readout via existing `applewirelessmouse` filter and `HidD_GetInputReport(0x90)` from MagicMouseTray app should already be functional.

- **Pros**: zero kernel work; Apple maintains it; signed by Apple.
- **Cons**: depends on Apple's driver remaining installed; user reports the BootCamp installer is fragile (PSN-0001 incidents; APPLE-DRIVER-RECOVERY-PROCEDURE.md exists in this worktree as evidence of recovery work). Magic Mouse Utilities or other 3rd-party drivers may displace it.
- **Effort**: zero. Just verify scroll + battery work today and call it done.

### Path C — Userland-only solution (raw-input synthesis)

Don't touch HidBth at all. Open a raw HID handle to the mouse (RID=0x12), parse multi-touch frames yourself in user-mode, synthesize WM_MOUSEHWHEEL via SendInput.

- **Pros**: no kernel driver; no signing; no admin install.
- **Cons**: user-mode latency; doesn't work in elevated processes (UIPI restriction on SendInput); doesn't work with apps that do raw input themselves; battery drain from userland polling.
- **Effort**: low (small WPF app + WinAPI calls).

### Recommendation

**Path B** (continue using Apple's driver) is the lowest-risk default if it currently works on the live system. Path A (M13) is appropriate ONLY if Apple's driver is actually broken, missing, or unwanted. M13-V3-BATTERY-AUDIT-2026-04-30.md (exists in this worktree) suggests the user has reached a working state on Apple's stock filter; if that's still true, Path A is unnecessary.

This spec documents Path A in case the user wants to proceed for resilience, education, or to have a known-working fallback.

---

## 3. M13 driver architecture (Path A)

### 3.1. Stack position

```
HidClass.sys                                 ← function driver
   │
HidBth.sys                                   ← HID minidriver  
   │  IRP_MJ_INTERNAL_DEVICE_CONTROL,        │
   │   IoControlCode = 0x00410210            │  
   ▼   (IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE)│
M13.sys                                      ← LOWER FILTER (M13)
   │   passthrough for all other IOCTLs     
   │   completion-routine rewrite for 0x410210
   ▼
BTHENUM.SYS                                  ← bus driver
   │
[BthPort, BT radio]
```

### 3.2. INF (skeleton)

```ini
[Version]
Signature   = "$WINDOWS NT$"
Class       = HIDClass
ClassGUID   = {745a17a0-74d3-11d0-b6fe-00a0c90f57da}
Provider    = %ProvName%
DriverVer   = 04/30/2026,1.0.0.0
CatalogFile = m13.cat

[DestinationDirs]
DefaultDestDir = 12

[Manufacturer]
%MfgName% = M13, NTamd64

[M13.NTamd64]
%M13.DeviceDesc% = M13Inst, BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323

[M13Inst.NT]
Include    = hidbth.inf
Needs      = HIDBTH_Inst.NT
CopyFiles  = M13Inst.NT.Copy

[M13Inst.NT.Copy]
m13.sys

[M13Inst.NT.HW]
AddReg     = M13Inst.NT.HW.AddReg
Include    = input.inf
Needs      = HID_Inst.NT.HW

[M13Inst.NT.HW.AddReg]
HKR,,"LowerFilters",0x00010000,"m13"

[M13Inst.NT.Services]
Include    = hidbth.inf
Needs      = HIDBTH_Inst.NT.Services
AddService = m13,, M13Service_Inst

[M13Service_Inst]
DisplayName   = %M13.SvcDesc%
ServiceType   = 1   ; SERVICE_KERNEL_DRIVER
StartType     = 3   ; SERVICE_DEMAND_START
ErrorControl  = 0   ; SERVICE_ERROR_IGNORE
ServiceBinary = %12%\m13.sys

[Strings]
ProvName       = "<provider>"
MfgName        = "<provider>"
M13.DeviceDesc = "Magic Mouse 2024 v3 — Scroll Filter"
M13.SvcDesc    = "M13 Magic Mouse v3 Scroll Filter"
```

**Coexistence**: This INF and Apple's `applewirelessmouse.inf` both target PID 0x0323. PnP rank prefers the more specific match. Both drivers can be `LowerFilters` simultaneously (filters are a sequence). If Apple's driver also rewrites the descriptor, **only the upper-most filter's rewrite wins** because IRPs travel down through the filter list and back up; the second filter sees the already-rewritten response. Practical advice: install ONLY ONE descriptor-rewriting filter at a time. M13 should detect Apple's driver presence (e.g., reading `LowerFilters` value) and refuse install if conflict, OR Apple's driver should be uninstalled first (existing M12 INSTALL-DRIVER scripts already do this).

### 3.3. KMDF callbacks

```c
// DriverEntry — minimal KMDF setup
NTSTATUS DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath)
{
    WDF_DRIVER_CONFIG config;
    WDF_DRIVER_CONFIG_INIT(&config, EvtDriverDeviceAdd);
    return WdfDriverCreate(DriverObject, RegistryPath, WDF_NO_OBJECT_ATTRIBUTES,
                           &config, WDF_NO_HANDLE);
}

// EvtDriverDeviceAdd — bind as filter, register I/O queue
NTSTATUS EvtDriverDeviceAdd(WDFDRIVER Driver, PWDFDEVICE_INIT DeviceInit)
{
    WdfFdoInitSetFilter(DeviceInit);    // attach as filter, not function driver

    WDFDEVICE device;
    NTSTATUS s = WdfDeviceCreate(&DeviceInit, WDF_NO_OBJECT_ATTRIBUTES, &device);
    if (!NT_SUCCESS(s)) return s;

    WDF_IO_QUEUE_CONFIG queueCfg;
    WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(&queueCfg, WdfIoQueueDispatchParallel);
    queueCfg.EvtIoInternalDeviceControl = EvtIoInternalDeviceControl;
    return WdfIoQueueCreate(device, &queueCfg, WDF_NO_OBJECT_ATTRIBUTES, NULL);
}

// EvtIoInternalDeviceControl — filter on IOCTL 0x00410210, passthrough rest
VOID EvtIoInternalDeviceControl(WDFQUEUE Queue, WDFREQUEST Request,
                                size_t OutputBufferLength, size_t InputBufferLength,
                                ULONG IoControlCode)
{
    if (IoControlCode != IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE) {
        ForwardRequestUnmodified(Request);
        return;
    }
    ForwardWithCompletion(Request, OnSdpQueryComplete);
}

VOID ForwardRequestUnmodified(WDFREQUEST Request)
{
    WDFDEVICE device = WdfIoQueueGetDevice(WdfRequestGetIoQueue(Request));
    WDFIOTARGET target = WdfDeviceGetIoTarget(device);
    WDF_REQUEST_SEND_OPTIONS opts;
    WDF_REQUEST_SEND_OPTIONS_INIT(&opts, WDF_REQUEST_SEND_OPTION_SEND_AND_FORGET);
    if (!WdfRequestSend(Request, target, &opts)) {
        NTSTATUS s = WdfRequestGetStatus(Request);
        WdfRequestComplete(Request, s);
    }
}

VOID ForwardWithCompletion(WDFREQUEST Request, EVT_WDF_REQUEST_COMPLETION_ROUTINE Done)
{
    WDFDEVICE device = WdfIoQueueGetDevice(WdfRequestGetIoQueue(Request));
    WDFIOTARGET target = WdfDeviceGetIoTarget(device);
    WdfRequestFormatRequestUsingCurrentType(Request);
    WdfRequestSetCompletionRoutine(Request, Done, NULL);
    if (!WdfRequestSend(Request, target, NULL)) {
        NTSTATUS s = WdfRequestGetStatus(Request);
        WdfRequestComplete(Request, s);
    }
}

// Completion: rewrite the SDP response to substitute our descriptor for attribute 0x0206
VOID OnSdpQueryComplete(WDFREQUEST Request, WDFIOTARGET Target,
                        PWDF_REQUEST_COMPLETION_PARAMS Params, WDFCONTEXT Context)
{
    NTSTATUS s = Params->IoStatus.Status;
    if (NT_SUCCESS(s)) {
        PVOID buf;
        size_t buflen;
        if (NT_SUCCESS(WdfRequestRetrieveOutputBuffer(Request, 1, &buf, &buflen))) {
            RewriteHidDescriptorAttribute(buf, buflen, &Request);
            // RewriteHidDescriptorAttribute may swap the buffer if size differs;
            // it must update WDFREQUEST's IoStatus.Information to the new length.
        }
    }
    WdfRequestComplete(Request, s);
}
```

### 3.4. The rewrite primitive

```c
// SDP DataElement encoding constants
#define SDP_TYPE_UINT16              0x09  // followed by 2 bytes BE
#define SDP_TYPE_UINT8               0x08  // followed by 1 byte
#define SDP_TYPE_DESC_TYPE_BYTE      0x22  // value: HID_REPORT_DESCRIPTOR_TYPE
#define SDP_SEQ_8BIT                 0x35  // sequence, 1-byte length follows
#define SDP_SEQ_16BIT                0x36
#define SDP_SEQ_32BIT                0x37
#define SDP_LEN_8BIT                 0x25
#define SDP_LEN_16BIT                0x26
#define SDP_LEN_32BIT                0x27
#define HID_DESCRIPTOR_LIST_ATTR_ID  0x0206

// The 116-byte Apple descriptor (verbatim from applewirelessmouse.sys offset 0xA850)
static const UCHAR g_AppleHidDescriptor[116] = {
    0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x85, 0x02,  // Mouse TLC, RID=0x02
    0x05, 0x09, 0x19, 0x01, 0x29, 0x02, 0x15, 0x00,
    0x25, 0x01, 0x95, 0x02, 0x75, 0x01, 0x81, 0x02,
    0x95, 0x01, 0x75, 0x05, 0x81, 0x03, 0x06, 0x02,
    0xFF, 0x09, 0x20, 0x95, 0x01, 0x75, 0x01, 0x81,
    0x03, 0x05, 0x01, 0x09, 0x01, 0xA1, 0x00, 0x15,
    0x81, 0x25, 0x7F, 0x09, 0x30, 0x09, 0x31, 0x75,
    0x08, 0x95, 0x02, 0x81, 0x06, 0x05, 0x0C, 0x0A,
    0x38, 0x02, 0x75, 0x08, 0x95, 0x01, 0x81, 0x06,
    0x05, 0x01, 0x09, 0x38, 0x75, 0x08, 0x95, 0x01,
    0x81, 0x06, 0xC0, 0x05, 0x06, 0x09, 0x20, 0x85,
    0x47, 0x15, 0x00, 0x25, 0x64, 0x75, 0x08, 0x95,
    0x01, 0xB1, 0xA2, 0x05, 0x06, 0x09, 0x01, 0x85,
    0x27, 0x15, 0x01, 0x25, 0x41, 0x75, 0x08, 0x95,
    0x2E, 0x81, 0x06, 0xC0
};

// Walk a SDP byte stream, find HIDDescriptorList attribute, replace its descriptor body.
// On size mismatch, allocates a new buffer and updates IoStatus.Information.
NTSTATUS RewriteHidDescriptorAttribute(PUCHAR sdp, size_t sdp_len, WDFREQUEST *Request)
{
    PUCHAR p = sdp, end = sdp + sdp_len;
    while (p + 8 < end) {
        // Looking for: 09 02 06 (UINT16 attr id 0x0206)
        if (p[0] != SDP_TYPE_UINT16 || p[1] != 0x02 || p[2] != 0x06) { p++; continue; }
        p += 3;
        // Now expect outer sequence header: 35/36/37 + size
        ULONG outerSize, outerHdrLen;
        if (!ParseSequenceHeader(p, end, &outerSize, &outerHdrLen)) return STATUS_INVALID_PARAMETER;
        PUCHAR outerStart = p + outerHdrLen;
        PUCHAR outerEnd   = outerStart + outerSize;
        // Inner sequence:
        ULONG innerSize, innerHdrLen;
        if (!ParseSequenceHeader(outerStart, outerEnd, &innerSize, &innerHdrLen)) return STATUS_INVALID_PARAMETER;
        PUCHAR innerStart = outerStart + innerHdrLen;
        PUCHAR innerEnd   = innerStart + innerSize;
        // First DataElement inside should be: 08 22 (UINT8 = 0x22)
        if (innerEnd - innerStart < 2 || innerStart[0] != SDP_TYPE_UINT8 || innerStart[1] != SDP_TYPE_DESC_TYPE_BYTE)
            return STATUS_INVALID_PARAMETER;
        PUCHAR descLenP = innerStart + 2;
        ULONG descLen, descLenHdrLen;
        if (!ParseLengthEncoding(descLenP, innerEnd, &descLen, &descLenHdrLen)) return STATUS_INVALID_PARAMETER;
        PUCHAR descBody = descLenP + descLenHdrLen;
        // 'descBody' .. 'descBody + descLen' is the device's native descriptor.
        return ReplaceDescriptor(sdp, sdp_len, p - 3, /* attribute start in sdp */
                                 outerHdrLen, innerHdrLen, descLenHdrLen,
                                 descBody, descLen, Request);
    }
    return STATUS_NOT_FOUND;     // no HID descriptor attribute — passthrough unchanged
}
```

`ReplaceDescriptor` rewrites the four nested length encodings (outer seq, inner seq, descriptor length, plus the SDP record's outer envelope sequence containing the attribute) to match the new descriptor size of 116 bytes. The encoding-class transitions (8 → 16 bit, etc.) are handled exactly as Apple's code does (see decompile of FUN_14000A440 lines 369–500).

### 3.5. Critical correctness considerations

1. **Outer envelope sequence**: the SDP record CONTAINING this attribute also has a sequence header that needs its `size` field bumped if our descriptor differs in length. Failure to update this OUTER size byte will cause HidBth's SDP parser to read past the actual record end (or reject the response).

2. **Multiple attribute matches**: an SDP record could conceivably have multiple `0x0206` attributes (HID profile permits this, though uncommon). M13 should rewrite ALL matches, not just the first.

3. **Buffer sizing**: the new buffer length = old length - old descriptor length + 116 + delta_in_length_encoding_bytes. WDFREQUEST output buffer is owned by the upper driver — we MUST NOT exceed it. If the output buffer is too small for our new SDP record, options:
   - **Truncate**: invalid; HidBth will fail to parse.
   - **Reallocate**: requires switching the IRP's output buffer pointer, which is fragile across stacks.
   - **Apple's approach**: allocate a new buffer with `ExAllocatePoolWithTag(NonPagedPool, newLen, 'BTMT')`, copy in, replace the IRP's `Parameters.DeviceIoControl.Type3InputBuffer` and `IoStatus.Information`. Apple does this. M13 should do the same. Lifetime: free in completion if newLen > origLen.
   - **Fortunate case**: native = 135, ours = 116. Strictly smaller. Output buffer is always large enough. The size adjustments are downward only. This simplifies M13 to in-place rewrite + size update.

4. **Endianness**: SDP UINT16/UINT32 are **big-endian** on the wire. The byte-swap is in Apple's code (`(ushort)uVar24 << 8 | (ushort)uVar24 >> 8`). M13's `ParseSequenceHeader` and `ParseLengthEncoding` must do the same.

5. **PASSIVE_LEVEL only**: the rewrite happens in the completion routine, which can be at DISPATCH_LEVEL. SDP parsing is small/local CPU work — fine at DPC. But ExAllocatePoolWithTag(`NonPagedPool`, ...) is required (not paged). For Apple's tag `'BTMT'` we use `'M13D'` (or any 4-char tag).

6. **Filter passthrough on error**: if the SDP record doesn't match the expected shape (no 0x0206 attribute, malformed encoding, etc.), M13 must complete the request unchanged with the original status. Never return failure that wasn't already there.

7. **Coexistence with Apple's filter**: if Apple's `applewirelessmouse.sys` is also installed as a lower filter, it will ALSO try to rewrite. Whoever is upper in the filter list wins. The result is the upper filter's descriptor. To avoid confusion: M13 should check the registry `LowerFilters` value at AddDevice time and refuse to load if `applewirelessmouse` is in the list. The existing M12 install scripts already manage Apple-driver removal — reuse that path.

### 3.6. The specific changes vs. M12 v1.x

| Aspect | M12 v1.x | M13 |
|---|---|---|
| Filter target | BTHENUM PDO | BTHENUM PDO (same) |
| Filter type | Lower filter | Lower filter (same) |
| INF Class | HIDClass | HIDClass (same) |
| Hardware ID coverage | (varied) | v3 only (`PID&0323`) |
| Intercepted IOCTL | `IOCTL_INTERNAL_BTH_SUBMIT_BRB` (0x00410003) — **WRONG** | **`IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE` (0x00410210)** |
| Inspect target | BRB structure / L2CAP frames | SDP DataElement bytes |
| Transformation | Descriptor injection in BRB packets (never fired) | SDP attribute 0x0206 rewrite (this is the actual mechanism) |
| Input report translation | Yes, complex | **None** (v3 firmware natively emits RID=0x02) |
| Userland service | trace ring buffer + admin queue | None initially |
| Battery readout | Out of scope (separate utility) | Out of scope |

### 3.7. File layout (worktree)

```
driver/
├── Driver.c                     # DriverEntry + EvtDriverDeviceAdd
├── Driver.h
├── IoControl.c                  # EvtIoInternalDeviceControl + ForwardRequest helpers
├── IoControl.h
├── SdpRewrite.c                 # ParseSequenceHeader, ParseLengthEncoding, RewriteHidDescriptor
├── SdpRewrite.h
├── HidDescriptor.c              # static const g_AppleHidDescriptor[116]
├── HidDescriptor.h
└── M13.inf                      # the INF above
scripts/                          # reuse existing m12 admin queue (sign, install, rollback)
tests/                            # unit-test SdpRewrite logic on captured SDP records
```

The existing `driver/` content in this worktree (M12) is mostly reusable for the install/sign/rollback scripts. The driver source itself is a substantial rewrite; the existing M12 source no longer applies (BRB-filter approach is invalidated).

### 3.8. Test plan (high level)

1. **Unit tests** (offline): feed `SdpRewrite` a captured 351-byte SDP record (which the user has from M12 work — `HKLM:\...\D0C050CC8C4D\CachedServices\'00010000'`). Assert the output is byte-equivalent to the same record with the descriptor swapped to `g_AppleHidDescriptor` and lengths recomputed.

2. **Static install test**: build, sign, install M13. Verify `pnputil /enum-drivers` lists it. Verify `applewirelessmouse` is NOT in the device's `LowerFilters` regkey concurrently.

3. **Live run**:
   1. Uninstall Apple's `applewirelessmouse` (existing M12 ROLLBACK-M12 phase covers this).
   2. Re-pair Magic Mouse v3.
   3. Confirm cursor + scroll work in browser/desktop.
   4. Confirm `HidD_GetPreparsedData` + `HidP_GetCaps` returns `Mouse(GenericDesktop, 0x02)` with AC-Pan + Wheel usages.
   5. (Optional) confirm battery RID=0x90 still readable.

4. **Robustness**:
   - Re-pair with M13 installed → cache repopulates with NATIVE 351 bytes (expected; M13 doesn't write the cache). HidBth's first SDP query DOES go through M13 → modified descriptor.
   - Sleep/resume → M13 sees new SDP queries on each device-start; descriptor is rewritten each time.
   - Uninstall M13 → device returns to native (no scroll) state. Apple driver can be re-installed.

5. **Negative tests**:
   - SDP record without attribute 0x0206 → passthrough unchanged.
   - Malformed SDP (truncated, bad type bytes) → passthrough with original status.
   - IOCTL other than 0x00410210 → instant passthrough.

### 3.9. Out-of-scope — possible follow-ups

- **Battery readout** is a separate concern. Apple's filter declares Feature RID=0x47 (Generic Device Controls Battery Strength). The v3 firmware natively emits RID=0x90 (vendor-page 0xFF00 Usage 0x14, 3 bytes: `[0x90, flags, %]`). User-mode app reads RID=0x90 directly via `HidD_GetInputReport` if the descriptor (whatever's exposed) declares RID=0x90. Apple's 116-byte descriptor does NOT declare RID=0x90 — so this would NOT work unless we either (a) ALSO declare RID=0x90 in our injected descriptor, or (b) use the original native SDP path for that.

  Recommended: ADD a fourth TLC declaring RID=0x90 (`UsagePage 0xFF00, Usage 0x14, RID=0x90, 3-byte input report`) to the M13 descriptor, alongside the Mouse/Battery TLCs. This requires updating `g_AppleHidDescriptor` and re-counting the SDP encoding. Defer until basic scroll works.

- **Three-finger / multi-touch gestures**: Apple does NOT declare these in the 116-byte descriptor — they require the alternate `MagicMouse.sys` (Magic Utilities) which uses a separate userland service and Feature Report 0x55 to put the device into multi-touch mode. Out of scope for M13.

- **Per-device customization**: M13 is a fixed-descriptor filter. No need.

---

## 4. Risks and open questions

| # | Risk / question | Mitigation |
|---|---|---|
| R1 | The output-buffer-shrink from 135→116 should always fit, but the SURROUNDING SDP record envelope may not — check whether the OUTER record sequence header needs to grow if the DataElement type byte encoding changes. | Verify with captured SDP record + unit test BEFORE writing kernel code |
| R2 | Apple's filter expects a specific BTH SDP_INTERFACE callback at IOCTL 0x010000A0 — M13 doesn't issue that sub-IRP. We rely on parsing the response buffer directly (which is plain SDP DataElement bytes). Confirm HidBth-issued SDP responses include the full record (not pre-parsed). | Test with raw SDP capture before scoping production code |
| R3 | Driver signing — M13 needs a code-signing cert. M12 already has a self-signed test cert (CN=MagicMouseFix per memory) installed in TrustedPublisher. Reuse. | Use existing M12 sign/install pipeline |
| R4 | RULE-027: this is an architectural decision. User must approve **Path A vs Path B vs Path C** before any code is written. | Present this spec for decision |
| R5 | If Apple's driver is re-pushed by Windows Update (it's signed, MS distributes it), M13 may be displaced. | Document this in install scripts; provide rollback to Apple-driver state |
| R6 | The `NONPAGE`-section presence in Apple's binary suggests it accesses descriptor data at DPC-level. M13's completion routine will run at DISPATCH_LEVEL. We need to ensure SDP parsing is non-paging. | Place `g_AppleHidDescriptor` and rewrite functions in `NONPAGE` section (use `#pragma alloc_text(NONPAGE, ...)`) or non-paged data |

---

## 5. Recommendation

**Path B is the recommended default**. Apple's driver works on this user's system per the latest M13-V3-BATTERY-AUDIT. The descriptor work documented here was useful for understanding why M12's BRB approach failed and for documenting the Apple mechanism. M13 implementation (Path A) is **only justified** if:
- Apple's driver becomes unavailable / unstable, OR
- The user wants a known-good fallback they control end-to-end, OR
- A future v4 device emerges that Apple won't update for.

Awaiting user decision on which path to pursue. No code will be written until that decision (RULE-027 architectural-decision gate).

---

## 6. References

- `M13-INJECTION-LAYER-RE-2026-04-30.md` — full RE findings + Ghidra evidence
- `M12-DESCRIPTOR-B-ANALYSIS-2026-04-29.md` — descriptor structure, byte layout
- `M12-EMPIRICAL-BLOCKER-2026-04-29.md` — what didn't work + why
- `M13-V3-BATTERY-AUDIT-2026-04-30.md` — current v3 working state on Apple's stock filter
- Microsoft DDK headers: `bthioctl.h` (IOCTL constants), `bthsdpddi.h` (SDP_INTERFACE), `wdf.h` (KMDF API)
- Bluetooth SDP specification: SDP DataElement encoding (sequence/length type bytes)
