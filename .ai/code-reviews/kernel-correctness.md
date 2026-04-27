# Kernel Correctness Audit — Magic Mouse 2024 Lower Filter

**Date:** 2026-04-27
**Reviewer:** Claude Sonnet 4.6 (static analysis, read-only)
**Scope:** `driver/InputHandler.c`, `driver/Driver.h`, `driver/Driver.c` (context)
**Basis:** WDK/KMDF docs, KMDF completion-routine semantics, Bluetooth Core Spec 5.4 Vol 3 Part B

---

## Findings

### BLOCKER

---

#### BLK-001 — BRB pointer dereferenced without size validation at IRQL DISPATCH_LEVEL
**File:** `InputHandler.c:284-294`, `InputHandler.c:413-422`

`BrbReadHandle`, `BrbReadUlong`, `BrbReadPtr` all cast `(PUCHAR)Brb + Offset` and dereference unconditionally. There is no check that the BRB allocation is at least `Offset + sizeof(field)` bytes large. The only guard is `brb != NULL` (line 288, line 418).

**Why it matters:**
- `BRB_L2CA_ACL_TRANSFER` is the widest struct. `MM_BRB_ACL_BUFFER_MDL_OFFSET = 0x90` means the code requires at least `0x90 + 8 = 0x98` (152) bytes. The BRB size lives at `BRB_HEADER.Length` (offset `0x10`, ULONG). Nothing reads it.
- If the Bluetooth stack (or a future firmware update) uses a narrower BRB variant for any of the handled types, reading past the allocation causes a kernel pool corruption or a bugcheck `0xC5` (DRIVER_CORRUPTED_EXPOOL) at DISPATCH_LEVEL — no recovery.
- The BRB type at `MM_BRB_TYPE_OFFSET = 0x16` is a USHORT read from an opaque pointer. The minimum safe size to even read the type field is `0x18` bytes. There is no Length check before the type read at `InputHandler.c:422`.

**Recommended fix:**
```c
// After brb != NULL check, in HandleBrbSubmit and both completion routines:
ULONG brbLen = BrbReadUlong(brb, 0x10);  // BRB_HEADER.Length
if (brbLen < 0x18) { goto passthrough; } // cannot safely read Type

// Per-type minimum:
//   OPEN_CHANNEL:   0x70 + 8 = 0x78 bytes minimum (handle output field)
//   CLOSE_CHANNEL:  0x78 + 8 = 0x80 bytes minimum
//   ACL_TRANSFER:   0x90 + 8 = 0x98 bytes minimum (MDL field)
```
Add a helper `BrbMinSize(type)` returning the expected minimum; fail-safe to `passthrough` if the actual BRB is smaller.

---

#### BLK-002 — MDL mapped without IRQL check; NormalPagePriority mapping can fail silently
**File:** `InputHandler.c:309`

```c
bufPtr = MmGetSystemAddressForMdlSafe(mdl, NormalPagePriority);
```

**Two sub-issues:**

1. **IRQL**: `MmGetSystemAddressForMdlSafe` must be called at `IRQL <= DISPATCH_LEVEL`. WDF completion routines fire at the IRQL of the lower driver's completion, which for Bluetooth BRBs submitted asynchronously can be `DISPATCH_LEVEL`. That is within contract. However, if any future path calls this from a callback raised above DISPATCH_LEVEL (e.g., an ISR), it will bugcheck. More critically, the MDL must already be locked (non-paged). For BRBs allocated by BthEnum/HidBth, the MDL is expected to describe locked memory, but this is not validated. Calling `MmGetSystemAddressForMdlSafe` on an unlocked MDL is undefined behavior at any IRQL.

2. **NormalPagePriority vs HighPagePriority**: `NormalPagePriority` can return NULL under memory pressure (the system's PTEs are exhausted). The code checks `bufPtr == NULL` at line 313 and completes with `status` (SUCCESS) silently — the BRB is passed through unmodified and the SDP descriptor is never patched. This is *functionally safe* (no crash) but silent: the driver reports success while the descriptor injection did not happen. The user sees no battery TLC, no horizontal scroll, with no diagnostic indication.
   `HighPagePriority` should be used for a kernel driver path that must succeed or explicitly fail loudly.

**Recommended fix:**
```c
bufPtr = MmGetSystemAddressForMdlSafe(mdl, HighPagePriority | MdlMappingNoExecute);
if (bufPtr == NULL) {
    DbgPrint("MagicMouse: MDL mapping failed (memory pressure) — descriptor injection skipped\n");
    WdfRequestComplete(Request, STATUS_INSUFFICIENT_RESOURCES);
    return;
}
```
Using `HighPagePriority` reduces (but does not eliminate) the failure probability. Completing with `STATUS_INSUFFICIENT_RESOURCES` allows HidBth to retry rather than silently accepting a zero-payload success.

---

#### BLK-003 — Buffer mutation at completion-routine IRQL without exclusion from concurrent BthEnum reads
**File:** `InputHandler.c:228-253` (`PatchSdpHidDescriptor`), `InputHandler.c:354-362`

The completion routine mutates the ACL transfer buffer in-place using `RtlMoveMemory`, `RtlCopyMemory`, `RtlZeroMemory`. This buffer was allocated by HidBth (the layer above us) and passed down to BthEnum in the BRB. By the time our completion fires, BthEnum has written the received data into the buffer and called IoCompleteRequest — the buffer ownership has logically returned to HidBth.

**The race condition:**
- HidBth submits a BRB with a buffer. BthEnum fills it and completes the IRP.
- Our completion routine is called *before* the IRP is unwound to HidBth.
- HidBth's own completion routine fires *after* ours, in the IRP completion chain.
- If HidBth has a DPC or concurrent thread that reads the buffer based on the *original* `BufferSize` field (captured before the IRP was sent), and we simultaneously modify both the buffer and `BufferSize` (line 357), we have a TOCTOU window.

**In practice:** For this specific use case (SDP attribute response on PSM 1), HidBth submits a synchronous read-and-cache — there is likely no concurrent reader during the completion window. However, the design has no formal exclusion mechanism. If the BthEnum/HidBth interaction ever changes, or if the SDP exchange uses overlapping BRBs (which the spec allows), the mutation is unprotected.

**Additional sub-issue:** `irp->IoStatus.Information = patchedSize` (line 358) is written at completion IRQL. Writing directly to the IRP IoStatus fields in a WDF completion routine is permissible (WDF does not yet propagate the status) but only before `WdfRequestComplete` is called. The ordering is correct here (mutation at line 357-358, complete at line 370) but is fragile — any refactor that calls `WdfRequestComplete` early (e.g., on an error return inside the scan block) would break it.

**Recommended fix:**
- Add a comment explicitly documenting that buffer mutation must complete before `WdfRequestComplete`, and that the IRP ownership model guarantees HidBth has not yet resumed.
- If the BRB submit protocol is ever changed to async/overlapping, a spinlock or interlocked flag must protect the buffer.
- Consider mutating a local copy and updating the MDL/buffer pointer rather than in-place mutation, to eliminate the TOCTOU window entirely.

---

### SHOULD-FIX

---

#### SF-001 — WdfRequestComplete double-complete risk on WdfRequestSend failure path
**File:** `InputHandler.c:433-436`, `InputHandler.c:451-455`

```c
WdfRequestFormatRequestUsingCurrentType(Request);
WdfRequestSetCompletionRoutine(Request, InputHandler_AclCompletion, devCtx);
if (!WdfRequestSend(Request, WdfDeviceGetIoTarget(Device), WDF_NO_SEND_OPTIONS)) {
    WdfRequestComplete(Request, WdfRequestGetStatus(Request));
}
return;
```

If `WdfRequestSend` succeeds, the request is "in flight" and the completion routine will call `WdfRequestComplete`. That is correct. If `WdfRequestSend` fails synchronously (returns FALSE), the code calls `WdfRequestComplete` directly. That is also correct — the WDK guarantee is that if Send returns FALSE, the completion routine will *not* be called.

**However:** `WdfRequestSetCompletionRoutine` has already been called. Per MSDN: if `WdfRequestSend` fails, the framework does not invoke the completion routine. But the completion routine object holds a reference to `devCtx`. If the framework's internal bookkeeping does not clear the completion routine reference on a failed send, there is a theoretical lifetime issue. In practice, WDF guarantees the routine is not called, but the callback object remains registered until `WdfRequestComplete` clears it. This is benign in current code because `devCtx` is owned by the WDFDEVICE and outlives the request.

**True risk:** `WdfRequestGetStatus` after a failed `WdfRequestSend` returns the status of the send failure (e.g., `STATUS_WDF_PAUSED`). In some failure modes this may not be an appropriate status to propagate up to HidBth. Consider using a fixed `STATUS_UNSUCCESSFUL` or caching the original status before `WdfRequestFormatRequestUsingCurrentType`.

**Recommended fix:**
```c
NTSTATUS sendStatus = STATUS_UNSUCCESSFUL;
if (!WdfRequestSend(Request, WdfDeviceGetIoTarget(Device), WDF_NO_SEND_OPTIONS)) {
    sendStatus = WdfRequestGetStatus(Request);
    WdfRequestComplete(Request, sendStatus);
}
```
This is a minor hardening measure; the current code is not incorrect, but the intent is clearer.

---

#### SF-002 — `DescriptorInjected` flag is set nowhere; the "inject once" guard is absent
**File:** `Driver.h:128-129`, `InputHandler.c:344-363`

`DEVICE_CONTEXT.DescriptorInjected` is declared and documented ("TRUE after g_HidDescriptor[] has been injected") but is never set to TRUE anywhere in the codebase. The `InputHandler_AclCompletion` function does not write it. The `ScanForSdpHidDescriptor` pattern is re-run on every incoming ACL transfer.

**Consequence:** Every incoming ACL packet is scanned for the SDP pattern. For a running device, interrupt-channel reports (Report 0x12 at ~60 Hz) are short enough (~14 bytes) that `SDP_SCAN_MIN_LEN = 11` could theoretically match — though the 3-byte header `09 02 06` would need to appear. Performance is the real concern: scanning every 14-byte HID report for an 11-byte SDP pattern at DISPATCH_LEVEL is wasteful. Once the descriptor is injected, subsequent scans should be skipped.

**Also:** `UNREFERENCED_PARAMETER(devCtx)` at line 320 is a smell that the guard logic was removed but the flag was not. The `chanHandle` is also unused (`UNREFERENCED_PARAMETER` at line 319), suggesting the channel-based gating was intentionally removed in favor of blind scanning. The comment at lines 328-343 explains this design choice but the `DescriptorInjected` flag is now vestigial dead state.

**Recommended fix:** Either:
(a) Set `devCtx->DescriptorInjected = TRUE` after successful patch and check it at the top of `InputHandler_AclCompletion` to skip scanning; or
(b) Remove `DescriptorInjected` from `DEVICE_CONTEXT` entirely (and `chanHandle`/`devCtx` usages) to eliminate dead state that confuses future maintainers.

---

#### SF-003 — `PatchSdpHidDescriptor` TLV length fixup uses incorrect byte offsets for framing fields
**File:** `InputHandler.c:241-253`

The SDP framing layout as scanned by `ScanForSdpHidDescriptor`:
```
i+0:  09           SDP_DE_UINT16
i+1:  02           ATTR_HI (0x02)
i+2:  06           ATTR_LO (0x06)
i+3:  35           outer SEQUENCE 1-byte length
i+4:  outer_len
i+5:  35           inner SEQUENCE 1-byte length
i+6:  inner_len
i+7:  08           SDP_DE_UINT8
i+8:  22           HID_RPT_DESC_TYPE
i+9:  25           SDP_DE_TEXT_1B
i+10: desc_len     ← TEXT_STRING length byte
i+11: <desc bytes> ← descriptor starts here; descOffset = i+11
```

`PatchSdpHidDescriptor` receives `descOffset` (= `i+11`). It then writes:
```c
buf[descOffset - 1] = (UCHAR)newDescLen;   // TEXT_STRING len  → i+10  ✓
buf[descOffset - 3] = (UCHAR)(innerPayload); // inner SEQUENCE → i+8   ✗
buf[descOffset - 5] = (UCHAR)(outerPayload); // outer SEQUENCE → i+6   ✓
```

**The inner SEQUENCE length byte is at `descOffset - 5` (= `i+6`), not `descOffset - 3` (= `i+8`).**

`descOffset - 3 = i+8` is the `SDP_DE_UINT8` type byte (`0x08`) — the type tag for the descriptor-type field. Writing the length there corrupts the "Report descriptor" type byte to a computed value (e.g., `0x0A` for a 113-byte descriptor), breaking the SDP attribute structure.

Correct mapping:
| Field | Position | Correct `buf[descOffset - N]` |
|-------|----------|-------------------------------|
| TEXT_STRING length | i+10 | `descOffset - 1` ✓ |
| inner SEQUENCE length | i+6 | `descOffset - 5` ✗ (code writes at - 3) |
| outer SEQUENCE length | i+4 | `descOffset - 7` ✗ (code writes at - 5) |

Both length fixups are off by 2 bytes. The TEXT_STRING length fixup is correct. The inner and outer SEQUENCE length fields are written to wrong positions, corrupting the SDP response.

**This is functionally a blocker-grade bug** — the SDP patch corrupts the framing bytes, which will cause HidBth to reject or misparse the attribute response. However, since the descriptor size does not change when `newDescLen == descLen` (the common case when Apple's descriptor and our replacement are both 113 bytes), the length fixup code path at lines 241-253 is only exercised when sizes differ. If `g_HidDescriptorSize == descLen`, `PatchSdpHidDescriptor` still copies the descriptor correctly (line 238) and the framing bytes are not touched. The bug only triggers when the replacement descriptor is a different size than Apple's original.

**Recommended fix:**
```c
buf[descOffset - 1] = (UCHAR)newDescLen;           // TEXT_STRING length  ✓
buf[descOffset - 5] = (UCHAR)(innerPayload & 0xFF); // inner SEQUENCE length
buf[descOffset - 7] = (UCHAR)(outerPayload & 0xFF); // outer SEQUENCE length
```
Verify against the scanner layout diagram above. Add a static assert or comment table mapping each offset to its field name.

---

#### SF-004 — `innerPayload` calculation is incorrect
**File:** `InputHandler.c:242`

```c
ULONG innerPayload = 2 + 2 + newDescLen;  // 0x08 0x22 + 0x25 LL + descriptor
```

The inner SEQUENCE body contains:
- `08 22` — UINT8 value 0x22 (2 bytes)
- `25 NN` — TEXT_STRING header (2 bytes: type tag + length byte)
- `<NN bytes>` — descriptor (newDescLen bytes)

Total inner SEQUENCE payload = 2 + 2 + newDescLen. The comment says `0x08 0x22 + 0x25 LL + descriptor`. That arithmetic is **correct** — `2 + 2 + N = 4 + N`. So innerPayload is right.

However, the outer SEQUENCE payload is:
```c
ULONG outerPayload = 2 + innerPayload;  // outer wraps inner
```

The outer SEQUENCE body is: `35 LL <innerPayload bytes>` = 1 (type) + 1 (len) + innerPayload = 2 + innerPayload. This is correct.

Retraction: the arithmetic values are correct; the bug in SF-003 is purely the buffer index offsets, not the computed values. This item is withdrawn — no separate fix needed.

---

#### SF-005 — `ScanForSdpHidDescriptor` loop limit is correct but fragile; off-by-one analysis
**File:** `InputHandler.c:166-167`

```c
ULONG limit = bufSize - SDP_SCAN_MIN_LEN;
for (ULONG i = 0; i <= limit; i++) {
```

When `bufSize == SDP_SCAN_MIN_LEN` (exactly 11 bytes), `limit = 0`, so the loop runs once (`i = 0`). The last access in the inner body is `buf[i+10]` = `buf[10]`. With `bufSize = 11`, indices 0..10 are valid. That is correct.

When `bufSize < SDP_SCAN_MIN_LEN` (guarded at line 162-164), the function returns FALSE before the subtraction — so no underflow.

However: later in the loop body, after the `outer_len` and `inner_len` checks, the code accesses `buf[i+10]` (desc_len at offset 10 relative to `i`). The bounds check at line 175 `(ULONG)(i + 5 + outer_len) > bufSize` ensures bytes i+5 through i+4+outer_len are valid. Since outer_len >= 4 (checked at line 174), this guarantees i+8 is valid. The final access `buf[i+10]` requires outer_len >= 6, but the check is only `outer_len >= 4`. If outer_len = 4 or 5, `buf[i+9]` and/or `buf[i+10]` may be out-of-range.

**Concrete scenario:**
- `i = 0`, `bufSize = 14`, `outer_len = 4` (passes check at line 174)
- Check: `0 + 5 + 4 = 9 <= 14` ✓
- Code then reads `buf[9]` (`SDP_DE_TEXT_1B`) and `buf[10]` (`desc_len`).
- With `outer_len = 4`, the declared outer sequence body is bytes [i+5..i+8] = 4 bytes.
- `buf[i+9]` = `buf[9]` is one byte past the declared outer sequence body. The bounds check allowed it only because bufSize (14) is large enough to hold the byte physically — but logically it is outside the outer sequence. This is not an out-of-bounds memory read (the byte exists), but it means we may mis-scan a pattern that is not actually an SDP HIDDescriptorList attribute.

This is a **correctness issue** (false-positive scan match on malformed input) rather than a memory safety issue. On a real device, the SDP response will be well-formed. An adversarial or corrupted BT response could cause a false match leading to a spurious (and incorrect) descriptor injection.

**Recommended fix:** Tighten the outer_len minimum:
```c
if (outer_len < 6) continue;  // must contain: 35 LL 08 22 25 NN (6 bytes minimum for inner)
```

---

### SUGGESTION

---

#### SUG-001 — `MmGetSystemAddressForMdlSafe` does not pass `MdlMappingNoExecute`
**File:** `InputHandler.c:309`

For data buffers (not code), mapping MDL pages as non-executable is a defense-in-depth hardening measure on Windows 8+. The flag is `MdlMappingNoExecute`. This costs nothing and prevents exploit techniques that involve writing shellcode into the data buffer and then jumping to the MDL mapping.

```c
bufPtr = MmGetSystemAddressForMdlSafe(mdl, HighPagePriority | MdlMappingNoExecute);
```

---

#### SUG-002 — `PatchSdpHidDescriptor`: no check that `descOffset >= 7` when fixing outer SEQUENCE
**File:** `InputHandler.c:210`

The guard is `if (descOffset < 6) return FALSE`. After fixing SF-003, the outer SEQUENCE length will be written at `buf[descOffset - 7]`. The guard must be updated to `descOffset < 8` (to safely access `descOffset - 7`). Failing to update this after the SF-003 fix would introduce an under-index write.

**Recommended fix (post SF-003):**
```c
if (descOffset < 8) {
    return FALSE;  // not enough framing bytes before descriptor
}
```

---

#### SUG-003 — `BRB_L2CA_OPEN_CHANNEL_RESPONSE` completion uses `MM_BRB_OPEN_CHANNEL_HANDLE_OFFSET` (0x70); unverified for RESPONSE variant
**File:** `InputHandler.c:396`, `Driver.h:65`

`BRB_L2CA_OPEN_CHANNEL` and `BRB_L2CA_OPEN_CHANNEL_RESPONSE` are dispatched together to `InputHandler_OpenChannelCompletion`. The ChannelHandle is read at `MM_BRB_OPEN_CHANNEL_HANDLE_OFFSET = 0x70` for both.

The rev-eng findings confirm `BRB_L2CA_OPEN_CHANNEL` handle at 0x70. The RESPONSE variant struct layout is not independently confirmed (the comment says "first field after 0x70-byte header" without cross-referencing the RESPONSE struct). If the RESPONSE variant has a different first field (e.g., a PSM or flags field at 0x70), the stored handle would be wrong, causing all subsequent channel identification to fail silently.

Recommend documenting which applewirelessmouse.sys disassembly offset confirms the RESPONSE struct layout, or adding a runtime DbgPrint of the handle value for first-boot tracing.

---

#### SUG-004 — `EvtIoInternalDeviceControl` passes all non-BRB IOCTLs via send-and-forget; filter contract may require completion forwarding for some
**File:** `Driver.c:64-70`

The WDK filter driver contract requires that IOCTLs not handled by the filter are forwarded to the next lower driver. The current code does this correctly via `WDF_REQUEST_SEND_OPTION_SEND_AND_FORGET`. However, for `IRP_MJ_INTERNAL_DEVICE_CONTROL`, certain IOCTLs expect a completion status to be propagated back (e.g., `IOCTL_INTERNAL_BTH_DISCONNECT_DEVICE`). "Send and forget" discards the completion — the filter never calls `WdfRequestComplete`, which is correct only because `WDF_REQUEST_SEND_OPTION_SEND_AND_FORGET` means WDF will complete the request automatically when the lower driver completes it.

This is technically correct per WDF semantics (WDF does complete the original request when the forwarded request completes with send-and-forget). No bug here.

**Note for maintainers:** If a future IRP_MJ_INTERNAL_DEVICE_CONTROL case is added that needs completion-routine inspection (similar to BRB_SUBMIT), it must not use send-and-forget.

---

### NIT

---

#### NIT-001 — `Driver.h` comment (line 22) describes vestigial report-translation design
**File:** `Driver.h:21-25`

The header comment still describes "Report 0x12 → Report 0x01 translation" as the interrupt-channel operation. This was removed in favor of descriptor injection (see `InputHandler.c:114-120`). The comment is misleading to future readers.

---

#### NIT-002 — `HidDescriptor.h` comment mismatch: says "TLC1 + TLC2" but descriptor has three TLCs
**File:** `HidDescriptor.h:5`

```c
// Size of the custom HID report descriptor (TLC1 + TLC2)
```

The descriptor actually contains TLC1 (Mouse), TLC2 (Consumer AC Pan), and TLC3 (Vendor Battery). The comment is stale from a prior revision.

---

#### NIT-003 — `SDP_DESC_MAX_EXPECTED_LEN` sanity cap is UCHAR-incompatible
**File:** `InputHandler.c:153`, `InputHandler.c:188`

```c
#define SDP_DESC_MAX_EXPECTED_LEN 512
UCHAR desc_len = buf[i+10];
if (desc_len > SDP_DESC_MAX_EXPECTED_LEN) continue;
```

`desc_len` is a UCHAR (max 255). `SDP_DESC_MAX_EXPECTED_LEN = 512` can never be exceeded by a UCHAR. The check is always FALSE (a UCHAR is always <= 255 < 512). This is dead code with no correctness impact (the `(ULONG)(i + 11 + desc_len) > bufSize` check at line 189 provides the real bounds guard), but it is misleading.

If a 2-byte length form (SDP_DE_SEQUENCE_2B / TEXT_STRING_2B) is ever needed, this would need to be restructured anyway. The comment at lines 140-143 acknowledges this; the cap should be changed to `255` to be honest about the 1-byte length limitation, or removed.

---

## Summary Table

| ID | Severity | File | Lines | Issue |
|----|----------|------|-------|-------|
| BLK-001 | BLOCKER | InputHandler.c / Driver.h | 284, 413, 422 | BRB raw dereference without Length validation |
| BLK-002 | BLOCKER | InputHandler.c | 309 | MDL mapped with NormalPagePriority; silent failure on memory pressure |
| BLK-003 | BLOCKER | InputHandler.c | 228-253, 354-362 | Buffer mutated in-place without formal exclusion from concurrent BthEnum reads |
| SF-001 | SHOULD-FIX | InputHandler.c | 433-436, 451-455 | Failure-path status propagation from WdfRequestSend could be misleading |
| SF-002 | SHOULD-FIX | Driver.h / InputHandler.c | 128, 319-320 | DescriptorInjected never set; dead state; redundant per-report scanning |
| SF-003 | SHOULD-FIX | InputHandler.c | 247, 253 | SDP TLV length fixup writes to wrong buffer offsets (off by 2 bytes each) |
| SF-005 | SHOULD-FIX | InputHandler.c | 166-189 | outer_len minimum too small; allows out-of-sequence byte reads on malformed input |
| SUG-001 | SUGGESTION | InputHandler.c | 309 | MDL should be mapped MdlMappingNoExecute for defense-in-depth |
| SUG-002 | SUGGESTION | InputHandler.c | 210 | descOffset guard must be updated to < 8 when SF-003 is fixed |
| SUG-003 | SUGGESTION | InputHandler.c | 396 | OPEN_CHANNEL_RESPONSE handle offset unconfirmed vs OPEN_CHANNEL |
| SUG-004 | SUGGESTION | Driver.c | 64-70 | Send-and-forget contract note for future maintainers |
| NIT-001 | NIT | Driver.h | 21-25 | Stale comment describing removed report-translation design |
| NIT-002 | NIT | HidDescriptor.h | 5 | Comment says TLC1+TLC2; descriptor has three TLCs |
| NIT-003 | NIT | InputHandler.c | 153, 188 | SDP_DESC_MAX_EXPECTED_LEN=512 is dead check against UCHAR field |

---

## Per-Audit-Scope Answers

### 1. Memory safety in BRB completion routine

**BRB field reads at offsets `0x16`, `0x78`, `0x80`, `0x84`, `0x88`, `0x90`** (BLK-001): All are raw pointer dereferences with no BRB Length validation. The type field at `0x16` requires a minimum BRB size of `0x18` bytes; the MDL field at `0x90` requires `0x98` bytes. Nothing reads `BRB_HEADER.Length` before these accesses. A truncated or corrupt BRB causes out-of-bounds read, potentially reading pool guard bytes or adjacent allocations — deterministic kernel crash or silent memory corruption.

NULL is checked (line 288) but length is not. Concurrent modification of the BRB by BthEnum after completion is not a risk in the normal single-IRP-in-flight model, but there is no assertion or documentation enforcing that invariant.

### 2. MDL handling correctness

`NormalPagePriority` is wrong for a required kernel-mode data path (BLK-002). The mapping can return NULL under memory pressure; current code silently completes with STATUS_SUCCESS without injecting — degraded operation with no diagnostic. `HighPagePriority | MdlMappingNoExecute` is correct. IRQL is within contract (DISPATCH_LEVEL is acceptable for `MmGetSystemAddressForMdlSafe`), but MDL lock state is not validated before mapping.

### 3. Buffer mutation safety

`PatchSdpHidDescriptor` mutates the buffer at completion IRQL after BthEnum has completed the transfer (BLK-003). The WDK IRP model gives us exclusive ownership of the buffer between BthEnum's IoCompleteRequest and HidBth's completion routine — our filter fires in between. For the single-BRB synchronous SDP exchange, this is safe in practice. However, there is no memory barrier, no spinlock, and no documentation of the ownership invariant. The mutation must complete entirely before `WdfRequestComplete` is called (line 370); that ordering is currently correct. A refactor risk exists.

### 4. WdfRequest lifecycle

`WdfRequestComplete` is called exactly once on all paths (SF-001):
- Failed status → line 277
- NULL BRB → line 289  
- Non-IN transfer → line 298
- NULL buffer+MDL → line 314
- Normal completion → line 370
- WdfRequestSend failure (OPEN_CHANNEL) → line 435
- WdfRequestSend failure (ACL_TRANSFER) → line 454

No double-complete path is present. The ordering of buffer mutation → IRP IoStatus update → WdfRequestComplete is correct. The principal risk (SF-001) is that WdfRequestGetStatus on a failed send may return an internal WDF status code not appropriate for HidBth consumption.

### 5. Memory pressure — g_HidDescriptor[] doesn't fit

If `g_HidDescriptorSize` (113 bytes) is larger than the allocated SDP response buffer, `PatchSdpHidDescriptor` returns FALSE at line 221-223 after the size check. The function has a rollback guarantee: it returns FALSE **before modifying anything** when `newBufSize > bufSize`. The buffer is left fully intact. The completion routine then falls through to `WdfRequestComplete(Request, status)` with the original unpatched buffer — HidBth receives Apple's original descriptor. Functional degradation (no battery TLC, no AC Pan), but no memory corruption, no crash. This path is safe.

### 6. Filter driver responsibilities

`EvtIoInternalDeviceControl` (Driver.c:47-71) intercepts only `IOCTL_INTERNAL_BTH_SUBMIT_BRB`. All other `IRP_MJ_INTERNAL_DEVICE_CONTROL` codes are forwarded via send-and-forget. This is correct for a lower filter that only needs to inspect BRBs. The IRP_MJ_* dispatch table for all other major function codes is handled by the WDF framework default (which forwards filter IRPs down the stack automatically via `WdfFdoInitSetFilter`). No IRP_MJ_INTERNAL_DEVICE_CONTROL cases appear to be silently dropped — send-and-forget correctly forwards with completion status propagation. (See SUG-004 for the nuance on future extensibility.)

### 7. SDP byte-pattern scanner correctness

`ScanForSdpHidDescriptor` (InputHandler.c:155-196): the loop limit `bufSize - SDP_SCAN_MIN_LEN` with `i <= limit` and the subsequent per-match bounds checks at lines 175, 180, 189 correctly prevent out-of-bounds reads for well-formed input. One edge case exists (SF-005): when `outer_len < 6`, bytes `buf[i+9]` and `buf[i+10]` are accessed but lie outside the declared outer sequence body. The bytes are physically within `bufSize` (guaranteed by the limit check), so no memory safety violation occurs, but a false-positive pattern match is possible on malformed input. An adversarial BT peer cannot trigger a crash via this path, only a spurious (and likely harmless) patch attempt.

---

## VERDICT: CHANGES-NEEDED

**Blocking issues requiring fix before shipping:**

1. **BLK-001** — BRB accessed without BRB_HEADER.Length validation. Raw dereference at offsets up to 0x98 on an unvalidated opaque pointer. Fix: read and validate `BRB_HEADER.Length` before any field access; fail-safe to passthrough on undersized BRBs.

2. **BLK-002** — MDL mapped with `NormalPagePriority` causing silent injection failure under memory pressure. Fix: use `HighPagePriority | MdlMappingNoExecute`; complete with `STATUS_INSUFFICIENT_RESOURCES` on NULL return rather than silent STATUS_SUCCESS.

3. **BLK-003** — In-place buffer mutation in completion routine without documented IRP ownership invariant or synchronization. Currently safe for the specific SDP exchange use case; requires explicit documentation and a review gate before any change to async BRB submission patterns.

**SF-003 is operationally dormant** (only triggered when replacement descriptor size differs from original) but is a correctness defect that will produce a broken SDP response if `g_HidDescriptorSize` ever changes from 113 bytes.
