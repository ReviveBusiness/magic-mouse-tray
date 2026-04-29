// SPDX-License-Identifier: MIT
//
// InputHandler — BRB-level interception for Magic Mouse 2024 KMDF lower filter.
//
// Architecture (confirmed 2026-04-27 via static analysis of applewirelessmouse.sys):
//
//   A lower filter below HidBth on the BTHENUM PDO never sees Windows HID IOCTLs
//   (IOCTL_HID_GET_REPORT_DESCRIPTOR, IOCTL_HID_READ_REPORT). These are absorbed by
//   hidclass.sys and never travel down the stack to a lower filter.
//
//   The correct hook point is IOCTL_INTERNAL_BTH_SUBMIT_BRB (0x00410003). HidBth
//   uses this to submit Bluetooth Request Blocks (BRBs) to BthEnum for all L2CAP
//   operations. HID descriptor bytes and input reports both travel via the
//   BRB_L2CA_ACL_TRANSFER type on this path.
//
// L2CAP channel tracking:
//   Apple Magic Mouse opens two L2CAP channels after pairing:
//     1. HID Control (PSM 17) — carries SDP attribute responses and GET_REPORT
//        replies, including the raw HID report descriptor bytes.
//     2. HID Interrupt (PSM 19) — carries pushed input reports (Report 0x12
//        for multi-touch, Report 0x90 for battery).
//
//   This driver tracks channels by order of BRB_L2CA_OPEN_CHANNEL completion:
//     First  → ControlChannelHandle  (descriptor injection target)
//     Second → InterruptChannelHandle (input report translation target)
//
// BRB field offsets (64-bit Windows). All defined in Driver.h as MM_BRB_*_OFFSET
// constants. Do NOT hardcode hex values here — refer to the constants. Values
// were empirically confirmed by static analysis of applewirelessmouse.sys
// (.ai/rev-eng/08f33d7e3ece/findings.md):
//   MM_BRB_TYPE_OFFSET                  = 0x16  (BRB_HEADER.Type)
//   MM_BRB_OPEN_CHANNEL_HANDLE_OFFSET   = 0x70  (after 0x70-byte BRB_HEADER)
//   MM_BRB_CLOSE_CHANNEL_HANDLE_OFFSET  = 0x78  (after BtAddress field)
//   MM_BRB_ACL_CHANNEL_HANDLE_OFFSET    = 0x78
//   MM_BRB_ACL_TRANSFER_FLAGS_OFFSET    = 0x80
//   MM_BRB_ACL_BUFFER_SIZE_OFFSET       = 0x84
//   MM_BRB_ACL_BUFFER_OFFSET            = 0x88
//   MM_BRB_ACL_BUFFER_MDL_OFFSET        = 0x90
//
// HID delivery model:
//   We do NOT translate individual reports. We replace the HID descriptor at
//   SDP-exchange time so HidClass enumerates COL01 (mouse + scroll) and
//   COL02 (vendor battery 0xFF00/0x14) as separate child PDOs. Native Report
//   0x12 multi-touch and Report 0x90 battery then flow through unchanged and
//   HidClass interprets them via our injected descriptor.

#include "InputHandler.h"
#include "HidDescriptor.h"

// ---------------------------------------------------------------------------
// Raw BRB field access helpers
// ---------------------------------------------------------------------------

static FORCEINLINE ULONG_PTR BrbReadHandle(_In_ PVOID Brb, _In_ SIZE_T Offset)
{
    return *(ULONG_PTR *)((PUCHAR)Brb + Offset);
}

static FORCEINLINE ULONG BrbReadUlong(_In_ PVOID Brb, _In_ SIZE_T Offset)
{
    return *(ULONG *)((PUCHAR)Brb + Offset);
}

static FORCEINLINE PVOID BrbReadPtr(_In_ PVOID Brb, _In_ SIZE_T Offset)
{
    return *(PVOID *)((PUCHAR)Brb + Offset);
}

// ---------------------------------------------------------------------------
// Channel tracking
// ---------------------------------------------------------------------------

static VOID StoreChannelHandle(_Inout_ PDEVICE_CONTEXT Ctx, _In_ ULONG_PTR Handle)
{
    if (Handle == 0)
        return;

    WdfSpinLockAcquire(Ctx->Lock);
    if (Ctx->ChannelCount == 0)
    {
        Ctx->ControlChannelHandle = Handle;
    }
    else if (Ctx->ChannelCount == 1)
    {
        Ctx->InterruptChannelHandle = Handle;
    }
    Ctx->ChannelCount++;
    WdfSpinLockRelease(Ctx->Lock);
}

static VOID ClearChannelHandle(_Inout_ PDEVICE_CONTEXT Ctx, _In_ ULONG_PTR Handle)
{
    if (Handle == 0)
        return;

    WdfSpinLockAcquire(Ctx->Lock);
    if (Ctx->ControlChannelHandle == Handle)
    {
        Ctx->ControlChannelHandle = 0;
        if (Ctx->ChannelCount > 0)
            Ctx->ChannelCount--;
    }
    else if (Ctx->InterruptChannelHandle == Handle)
    {
        Ctx->InterruptChannelHandle = 0;
        if (Ctx->ChannelCount > 0)
            Ctx->ChannelCount--;
    }
    WdfSpinLockRelease(Ctx->Lock);
}

// Note: a previous Report 0x12 -> Report 0x01 in-place translator
// (TranslateReport12, TouchX, TouchY, ClampInt8 + TOUCH2_*/SCALE_* macros) was
// removed in favour of the SDP descriptor-injection approach below. It was
// unreachable from the new AclCompletion path and cannot become reachable
// without re-architecting around report rewriting. If multi-touch parsing is
// ever needed again (e.g. for inertial-scroll synthesis), recover the function
// from git history (commit 5ff866a^ -- pre-port state).

// ---------------------------------------------------------------------------
// SDP HIDDescriptorList scanner + patcher
//
// Architecture (confirmed by static analysis of applewirelessmouse.sys —
// signature byte 09 02 06 appears 9 times in .text/.rdata):
//   HidBth fetches the device's HID descriptor via SDP/L2CAP during pairing.
//   The descriptor arrives embedded in an SDP attribute response on PSM 1.
//   Our lower filter intercepts the BRB_L2CA_ACL_TRANSFER carrying that
//   response and rewrites the embedded descriptor bytes.
//
// Byte pattern (Bluetooth Core Spec 5.4 Vol 3 Part B §3.3 / §4.4 / §5.1.9):
//   09 02 06     — SDP AttributeID (UINT16) = 0x0206 (HIDDescriptorList)
//   35 LL        — outer SEQUENCE, 1-byte length form
//     35 LL      — inner SEQUENCE (one entry), 1-byte length form
//       08 22    — UINT8 value 0x22 = "Report descriptor"
//       25 NN    — TEXT_STRING, 1-byte length form, NN bytes follow
//         <NN bytes> = embedded HID descriptor
//
// Apple's device uses 1-byte SEQUENCE length headers (0x35). If a future
// firmware uses 0x36 (2-byte length) for larger descriptors, this scanner
// returns FALSE and we fall through without patching — safe degradation.
// ---------------------------------------------------------------------------

#define SDP_DE_UINT16 0x09
#define SDP_DE_SEQUENCE_1B 0x35
#define SDP_DE_UINT8 0x08
#define SDP_DE_TEXT_1B 0x25
#define SDP_ATTR_HID_DESC_LIST_HI 0x02
#define SDP_ATTR_HID_DESC_LIST_LO 0x06
#define HID_RPT_DESC_TYPE 0x22
#define SDP_SCAN_MIN_LEN 11           // minimum bytes to match the pattern
#define SDP_DESC_MAX_EXPECTED_LEN 512 // sanity cap on declared descriptor length

static BOOLEAN ScanForSdpHidDescriptor(_In_reads_bytes_(bufSize) PUCHAR buf, _In_ ULONG bufSize,
                                       _Out_ PULONG outOffset, _Out_ PULONG outLen)
{
    if (buf == NULL || bufSize < SDP_SCAN_MIN_LEN)
    {
        return FALSE;
    }

    ULONG limit = bufSize - SDP_SCAN_MIN_LEN;
    for (ULONG i = 0; i <= limit; i++)
    {
        if (buf[i] != SDP_DE_UINT16)
            continue;
        if (buf[i + 1] != SDP_ATTR_HID_DESC_LIST_HI)
            continue;
        if (buf[i + 2] != SDP_ATTR_HID_DESC_LIST_LO)
            continue;
        if (buf[i + 3] != SDP_DE_SEQUENCE_1B)
            continue;

        UCHAR outerLen = buf[i + 4];
        if (outerLen < 4)
            continue;
        if ((ULONG)(i + 5 + outerLen) > bufSize)
            continue;

        if (buf[i + 5] != SDP_DE_SEQUENCE_1B)
            continue;
        UCHAR innerLen = buf[i + 6];
        if (innerLen < 4)
            continue;
        if ((ULONG)(i + 7 + innerLen) > bufSize)
            continue;

        if (buf[i + 7] != SDP_DE_UINT8)
            continue;
        if (buf[i + 8] != HID_RPT_DESC_TYPE)
            continue;
        if (buf[i + 9] != SDP_DE_TEXT_1B)
            continue;

        UCHAR descLen = buf[i + 10];
        if (descLen == 0)
            continue;
        if (descLen > SDP_DESC_MAX_EXPECTED_LEN)
            continue;
        if ((ULONG)(i + 11 + descLen) > bufSize)
            continue;

        *outOffset = i + 11;
        *outLen = descLen;
        return TRUE;
    }
    return FALSE;
}

// Replaces the embedded descriptor at descOffset (length descLen) with
// g_HidDescriptor[]. Updates the SDP TLV length bytes at [descOffset-1],
// [descOffset-5], [descOffset-7]. All invariant checks are performed before
// any buffer mutation — this function is all-or-nothing: on FALSE the buffer
// is left completely unmodified; on TRUE the patch is fully applied.
static BOOLEAN PatchSdpHidDescriptor(_Inout_updates_bytes_(bufSize) PUCHAR buf, _In_ ULONG bufSize,
                                     _In_ ULONG descOffset, _In_ ULONG descLen,
                                     _Out_ PULONG newBufUsed)
{
    // Validate ALL invariants before any buffer mutation.
    // descOffset >= 8 ensures [descOffset-7] is in bounds (outer SEQUENCE length byte).
    if (descOffset < 8)
    {
        return FALSE; // not enough framing bytes before descriptor
    }

    ULONG newDescLen = g_HidDescriptorSize;

    // Validate SDP TLV length fields fit in 1-byte length form (0x35 encoding).
    if (newDescLen > 0xFF)
    {
        return FALSE;
    }
    ULONG innerPayload = 2 + 2 + newDescLen; // 0x08 0x22 + 0x25 LL + descriptor
    if (innerPayload > 0xFF)
    {
        DbgPrint("MagicMouse: SDP patch SKIPPED - inner length overflow (%lu)\n", innerPayload);
        return FALSE;
    }
    ULONG outerPayload = 2 + innerPayload; // outer SEQUENCE wraps inner SEQUENCE entry
    if (outerPayload > 0xFF)
    {
        DbgPrint("MagicMouse: SDP patch SKIPPED - outer length overflow (%lu)\n", outerPayload);
        return FALSE;
    }

    ULONG tailOffset = descOffset + descLen;
    ULONG tailBytes = bufSize - tailOffset;
    ULONG newBufSize = descOffset + newDescLen + tailBytes;

    if (newBufSize > bufSize)
    {
        DbgPrint("MagicMouse: SDP patch SKIPPED - buffer too small "
                 "(need %lu, have %lu). Force re-pair to grow buffer.\n",
                 newBufSize, bufSize);
        return FALSE;
    }

    // All invariants satisfied — now mutate the buffer.
    if (newDescLen != descLen)
    {
        ULONG newTailOffset = descOffset + newDescLen;
        if (tailBytes > 0)
        {
            RtlMoveMemory(buf + newTailOffset, buf + tailOffset, tailBytes);
        }
        if (newDescLen < descLen)
        {
            ULONG gapStart = newTailOffset + tailBytes;
            ULONG gapLen = descLen - newDescLen;
            RtlZeroMemory(buf + gapStart, gapLen);
        }
    }

    RtlCopyMemory(buf + descOffset, g_HidDescriptor, newDescLen);

    // SDP TLV length-byte fixups (1-byte length form).
    // Layout relative to descOffset (= i+11, where i is the match position):
    //   descOffset-1 : TEXT_STRING 1-byte length (0x25 NN) — NN = desc_len
    //   descOffset-5 : inner SEQUENCE 1-byte length (0x35 LL) — LL covers 08 22 25 NN <desc>
    //   descOffset-7 : outer SEQUENCE 1-byte length (0x35 LL) — LL covers inner seq entry
    buf[descOffset - 1] = (UCHAR)newDescLen;   // TEXT_STRING len (i+10)
    buf[descOffset - 5] = (UCHAR)innerPayload; // inner SEQUENCE len (i+6)
    buf[descOffset - 7] = (UCHAR)outerPayload; // outer SEQUENCE len (i+4)

    *newBufUsed = descOffset + newDescLen + tailBytes;
    return TRUE;
}

// ---------------------------------------------------------------------------
// ACL transfer completion routine
// ---------------------------------------------------------------------------

VOID InputHandler_AclCompletion(_In_ WDFREQUEST Request, _In_ WDFIOTARGET Target,
                                _In_ PWDF_REQUEST_COMPLETION_PARAMS Params, _In_ WDFCONTEXT Context)
{
    UNREFERENCED_PARAMETER(Target);
    UNREFERENCED_PARAMETER(Context);

    NTSTATUS status = Params->IoStatus.Status;

    if (!NT_SUCCESS(status))
    {
        WdfRequestComplete(Request, status);
        return;
    }

    // Recover the BRB pointer from per-request context (stashed before WdfRequestSend).
    // Do not re-read from the IRP stack location — WDF may have advanced the stack
    // past our layer before invoking this completion, making IoGetCurrentIrpStackLocation
    // return the lower driver's slot rather than ours.
    PMM_REQUEST_CONTEXT reqCtx = GetRequestContext(Request);
    PVOID brb = (reqCtx != NULL) ? reqCtx->Brb : NULL;
    PIRP irp = WdfRequestWdmGetIrp(Request);

    if (brb == NULL)
    {
        WdfRequestComplete(Request, STATUS_INVALID_PARAMETER);
        return;
    }

    ULONG flags = BrbReadUlong(brb, MM_BRB_ACL_TRANSFER_FLAGS_OFFSET);

    // Only process device → host data
    if (!(flags & MM_ACL_TRANSFER_IN))
    {
        WdfRequestComplete(Request, status);
        return;
    }

    ULONG bufSize = BrbReadUlong(brb, MM_BRB_ACL_BUFFER_SIZE_OFFSET);
    PVOID bufPtr = BrbReadPtr(brb, MM_BRB_ACL_BUFFER_OFFSET);

    if (bufPtr == NULL)
    {
        // MDL path — map the MDL to get a system-space pointer
        PMDL mdl = (PMDL)BrbReadPtr(brb, MM_BRB_ACL_BUFFER_MDL_OFFSET);
        if (mdl != NULL)
        {
            bufPtr = MmGetSystemAddressForMdlSafe(mdl, NormalPagePriority);
        }
    }

    if (bufPtr == NULL || bufSize == 0)
    {
        WdfRequestComplete(Request, status);
        return;
    }

    // BRB length validation: verify the BRB allocation covers all fields we read/write.
    // BRB_HEADER.Length is at offset 0x10 (MM_BRB_LENGTH_OFFSET).
    ULONG brbLen = BrbReadUlong(brb, MM_BRB_LENGTH_OFFSET);
    if (brbLen < MM_BRB_ACL_BUFFER_MDL_OFFSET + sizeof(PVOID))
    {
        // BRB is too short — skip processing, pass through unchanged.
        WdfRequestComplete(Request, status);
        return;
    }

    PUCHAR data = (PUCHAR)bufPtr;

    // -----------------------------------------------------------------------
    // SDP HIDDescriptorList interception (PSM 1, descriptor-injection path)
    //
    // We scan EVERY incoming ACL transfer for the SDP attribute-0x0206 byte
    // pattern, regardless of which L2CAP channel it arrived on. This catches
    // the descriptor delivery during the SDP exchange (PSM 1) without us
    // having to track SDP channel handles separately.
    //
    // If the pattern is found, we replace the embedded HID descriptor with
    // g_HidDescriptor[] (111 bytes, 3 TLCs: Mouse with Wheel + Consumer
    // AC-Pan + Vendor Battery 0xFF00/0x14). HidBth then caches our descriptor
    // and creates COL01 (mouse with scroll) AND COL02 (vendor battery) child
    // PDOs — both work simultaneously.
    //
    // For interrupt-channel input reports (post-pairing), pattern won't match
    // (those are short HID-only packets), so we fall through harmlessly with
    // no modification.
    //
    // CAVEAT: SDP exchange happens during pairing. For an already-paired
    // device, HidBth has cached the descriptor and won't re-fetch via SDP.
    // User must force unpair + re-pair after filter install for the new
    // descriptor to take effect.
    // -----------------------------------------------------------------------
    {
        ULONG descOffset = 0;
        ULONG descLen = 0;
        if (ScanForSdpHidDescriptor(data, bufSize, &descOffset, &descLen))
        {
            DbgPrint("MagicMouse: SDP HIDDescriptorList found at offset %lu "
                     "(orig len %lu), patching with custom descriptor (%lu bytes)\n",
                     descOffset, descLen, g_HidDescriptorSize);

            ULONG newBufUsed = 0;
            if (PatchSdpHidDescriptor(data, bufSize, descOffset, descLen, &newBufUsed))
            {
                // brbLen >= MM_BRB_ACL_BUFFER_SIZE_OFFSET + sizeof(ULONG) is implied
                // by the outer brbLen >= 0x98 gate (offset 0x84 + 4 = 0x88 < 0x98).
                *(ULONG *)((PUCHAR)brb + MM_BRB_ACL_BUFFER_SIZE_OFFSET) = newBufUsed;
                irp->IoStatus.Information = newBufUsed;
                DbgPrint("MagicMouse: Descriptor injected, new transfer size = %lu bytes\n",
                         newBufUsed);
            }
        }
    }
    // Report-translation path REMOVED — replaced by descriptor injection above.
    // The native device emits Report 0x12 multi-touch frames; with our injected
    // descriptor declaring TLC1 to consume Report 0x12 with Wheel/AC-Pan usages,
    // HidClass will interpret the same on-the-wire bytes correctly without us
    // having to rewrite individual reports. See HidDescriptor.c TLC1.

    WdfRequestComplete(Request, status);
}

// ---------------------------------------------------------------------------
// CLOSE_CHANNEL completion — clear the channel handle only after BthEnum confirms
// ---------------------------------------------------------------------------

VOID InputHandler_CloseChannelCompletion(_In_ WDFREQUEST Request, _In_ WDFIOTARGET Target,
                                         _In_ PWDF_REQUEST_COMPLETION_PARAMS Params,
                                         _In_ WDFCONTEXT Context)
{
    UNREFERENCED_PARAMETER(Target);

    NTSTATUS status = Params->IoStatus.Status;
    PDEVICE_CONTEXT devCtx = (PDEVICE_CONTEXT)Context;

    // Only clear the handle if BthEnum successfully completed the close.
    // If we cleared it before forwarding, a reconnect racing against this close
    // could open a new channel while we still hold the old handle slot.
    if (NT_SUCCESS(status))
    {
        PMM_REQUEST_CONTEXT reqCtx = GetRequestContext(Request);
        PVOID brb = (reqCtx != NULL) ? reqCtx->Brb : NULL;
        if (brb != NULL)
        {
            // BRB length guard: ChannelHandle is at 0x78; verify BRB covers 0x78+8.
            ULONG brbLen = BrbReadUlong(brb, MM_BRB_LENGTH_OFFSET);
            if (brbLen >= MM_BRB_CLOSE_CHANNEL_HANDLE_OFFSET + sizeof(ULONG_PTR))
            {
                ULONG_PTR handle = BrbReadHandle(brb, MM_BRB_CLOSE_CHANNEL_HANDLE_OFFSET);
                ClearChannelHandle(devCtx, handle);
            }
        }
    }

    WdfRequestComplete(Request, status);
}

// ---------------------------------------------------------------------------
// OPEN_CHANNEL completion — store the new channel handle
// ---------------------------------------------------------------------------

VOID InputHandler_OpenChannelCompletion(_In_ WDFREQUEST Request, _In_ WDFIOTARGET Target,
                                        _In_ PWDF_REQUEST_COMPLETION_PARAMS Params,
                                        _In_ WDFCONTEXT Context)
{
    UNREFERENCED_PARAMETER(Target);

    NTSTATUS status = Params->IoStatus.Status;
    PDEVICE_CONTEXT devCtx = (PDEVICE_CONTEXT)Context;

    // Only record the channel if the open succeeded.
    // Recover BRB from per-request context (stashed before WdfRequestSend).
    if (NT_SUCCESS(status))
    {
        PMM_REQUEST_CONTEXT reqCtx = GetRequestContext(Request);
        PVOID brb = (reqCtx != NULL) ? reqCtx->Brb : NULL;

        if (brb != NULL)
        {
            // BRB length guard: ChannelHandle is at 0x70; verify BRB covers 0x70+8.
            ULONG brbLen = BrbReadUlong(brb, MM_BRB_LENGTH_OFFSET);
            if (brbLen >= MM_BRB_OPEN_CHANNEL_HANDLE_OFFSET + sizeof(ULONG_PTR))
            {
                ULONG_PTR handle = BrbReadHandle(brb, MM_BRB_OPEN_CHANNEL_HANDLE_OFFSET);
                StoreChannelHandle(devCtx, handle);
            }
        }
    }

    WdfRequestComplete(Request, status);
}

// ---------------------------------------------------------------------------
// Main BRB submit dispatch
// ---------------------------------------------------------------------------

VOID InputHandler_HandleBrbSubmit(_In_ WDFDEVICE Device, _In_ WDFREQUEST Request)
{
    PIRP irp = WdfRequestWdmGetIrp(Request);
    PIO_STACK_LOCATION stack = IoGetCurrentIrpStackLocation(irp);
    PVOID brb = stack->Parameters.Others.Argument1;
    PDEVICE_CONTEXT devCtx = GetDeviceContext(Device);

    if (brb == NULL)
    {
        goto passthrough;
    }

    USHORT brbType = *(USHORT *)((PUCHAR)brb + MM_BRB_TYPE_OFFSET);

    switch (brbType)
    {

    // Forward OPEN_CHANNEL with a completion routine to capture the output ChannelHandle.
    case BRB_L2CA_OPEN_CHANNEL:
    case BRB_L2CA_OPEN_CHANNEL_RESPONSE: {
        WDF_OBJECT_ATTRIBUTES reqAttr;
        WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&reqAttr, MM_REQUEST_CONTEXT);
        NTSTATUS allocStatus = WdfObjectAllocateContext(Request, &reqAttr, NULL);
        if (!NT_SUCCESS(allocStatus))
        {
            // Cannot track this request — degrade to pure passthrough.
            DbgPrint("M12: context alloc failed (%x); passthrough\n", allocStatus);
            goto passthrough;
        }
        PMM_REQUEST_CONTEXT reqCtx = GetRequestContext(Request);
        reqCtx->Brb = brb;
        WdfRequestFormatRequestUsingCurrentType(Request);
        WdfRequestSetCompletionRoutine(Request, InputHandler_OpenChannelCompletion, devCtx);
        if (!WdfRequestSend(Request, WdfDeviceGetIoTarget(Device), WDF_NO_SEND_OPTIONS))
        {
            WdfRequestComplete(Request, WdfRequestGetStatus(Request));
        }
        return;
    }

    // Forward CLOSE_CHANNEL with a completion routine so we only clear the handle
    // after BthEnum confirms the close (prevents a race where a reconnect opens a
    // new channel before the close completes if we cleared the handle prematurely).
    case BRB_L2CA_CLOSE_CHANNEL: {
        WDF_OBJECT_ATTRIBUTES reqAttr;
        WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&reqAttr, MM_REQUEST_CONTEXT);
        NTSTATUS allocStatus = WdfObjectAllocateContext(Request, &reqAttr, NULL);
        if (!NT_SUCCESS(allocStatus))
        {
            // Cannot track this request — degrade to pure passthrough.
            DbgPrint("M12: context alloc failed (%x); passthrough\n", allocStatus);
            goto passthrough;
        }
        PMM_REQUEST_CONTEXT reqCtx = GetRequestContext(Request);
        reqCtx->Brb = brb;
        WdfRequestFormatRequestUsingCurrentType(Request);
        WdfRequestSetCompletionRoutine(Request, InputHandler_CloseChannelCompletion, devCtx);
        if (!WdfRequestSend(Request, WdfDeviceGetIoTarget(Device), WDF_NO_SEND_OPTIONS))
        {
            WdfRequestComplete(Request, WdfRequestGetStatus(Request));
        }
        return;
    }

    // Forward ACL transfers with a completion routine to intercept the data buffer.
    case BRB_L2CA_ACL_TRANSFER: {
        WDF_OBJECT_ATTRIBUTES reqAttr;
        WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&reqAttr, MM_REQUEST_CONTEXT);
        NTSTATUS allocStatus = WdfObjectAllocateContext(Request, &reqAttr, NULL);
        if (!NT_SUCCESS(allocStatus))
        {
            // Cannot track this request — degrade to pure passthrough.
            DbgPrint("M12: context alloc failed (%x); passthrough\n", allocStatus);
            goto passthrough;
        }
        PMM_REQUEST_CONTEXT reqCtx = GetRequestContext(Request);
        reqCtx->Brb = brb;
        WdfRequestFormatRequestUsingCurrentType(Request);
        WdfRequestSetCompletionRoutine(Request, InputHandler_AclCompletion, devCtx);
        if (!WdfRequestSend(Request, WdfDeviceGetIoTarget(Device), WDF_NO_SEND_OPTIONS))
        {
            WdfRequestComplete(Request, WdfRequestGetStatus(Request));
        }
        return;
    }

    default:
        goto passthrough;
    }

passthrough:
    WdfRequestFormatRequestUsingCurrentType(Request);
    WDF_REQUEST_SEND_OPTIONS opts;
    WDF_REQUEST_SEND_OPTIONS_INIT(&opts, WDF_REQUEST_SEND_OPTION_SEND_AND_FORGET);
    if (!WdfRequestSend(Request, WdfDeviceGetIoTarget(Device), &opts))
    {
        WdfRequestComplete(Request, WdfRequestGetStatus(Request));
    }
}
