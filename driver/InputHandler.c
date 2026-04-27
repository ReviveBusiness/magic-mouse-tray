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
// BRB field offsets (64-bit Windows, confirmed from static analysis unless noted TODO):
//   BRB_HEADER.Type:                       +0x16  confirmed
//   BRB_L2CA_OPEN/CLOSE.ChannelHandle:     +0x20  TODO: verify vs bthddi.h
//   BRB_L2CA_ACL_TRANSFER.ChannelHandle:   +0x78  confirmed
//   BRB_L2CA_ACL_TRANSFER.TransferFlags:   +0x28  TODO: verify
//   BRB_L2CA_ACL_TRANSFER.BufferSize:      +0x2C  TODO: verify
//   BRB_L2CA_ACL_TRANSFER.Buffer:          +0x30  TODO: verify
//   BRB_L2CA_ACL_TRANSFER.BufferMDL:       +0x38  TODO: verify
//
// Report translation output:
//   Report 0x12 → Report 0x01 [reportId, buttons, X, Y, WheelV] (TLC1, 5 bytes)
//   Report 0x90 → unchanged                                       (TLC3)
//   Horizontal scroll (AC Pan) → Report 0x02 delivery TBD (Phase 3.5)

#include "InputHandler.h"
#include "HidDescriptor.h"

// ---------------------------------------------------------------------------
// Raw BRB field access helpers
// ---------------------------------------------------------------------------

static FORCEINLINE ULONG_PTR
BrbReadHandle(
    _In_ PVOID  Brb,
    _In_ SIZE_T Offset)
{
    return *(ULONG_PTR *)((PUCHAR)Brb + Offset);
}

static FORCEINLINE ULONG
BrbReadUlong(
    _In_ PVOID  Brb,
    _In_ SIZE_T Offset)
{
    return *(ULONG *)((PUCHAR)Brb + Offset);
}

static FORCEINLINE PVOID
BrbReadPtr(
    _In_ PVOID  Brb,
    _In_ SIZE_T Offset)
{
    return *(PVOID *)((PUCHAR)Brb + Offset);
}

// ---------------------------------------------------------------------------
// Channel tracking
// ---------------------------------------------------------------------------

static VOID
StoreChannelHandle(
    _Inout_ PDEVICE_CONTEXT Ctx,
    _In_    ULONG_PTR       Handle)
{
    if (Handle == 0) return;

    if (Ctx->ChannelCount == 0) {
        Ctx->ControlChannelHandle = Handle;
    } else if (Ctx->ChannelCount == 1) {
        Ctx->InterruptChannelHandle = Handle;
    }
    Ctx->ChannelCount++;
}

static VOID
ClearChannelHandle(
    _Inout_ PDEVICE_CONTEXT Ctx,
    _In_    ULONG_PTR       Handle)
{
    if (Handle == 0) return;

    if (Ctx->ControlChannelHandle == Handle) {
        Ctx->ControlChannelHandle = 0;
        Ctx->DescriptorInjected   = FALSE;
        if (Ctx->ChannelCount > 0) Ctx->ChannelCount--;
    } else if (Ctx->InterruptChannelHandle == Handle) {
        Ctx->InterruptChannelHandle = 0;
        if (Ctx->ChannelCount > 0) Ctx->ChannelCount--;
    }
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

#define SDP_DE_UINT16             0x09
#define SDP_DE_SEQUENCE_1B        0x35
#define SDP_DE_UINT8              0x08
#define SDP_DE_TEXT_1B            0x25
#define SDP_ATTR_HID_DESC_LIST_HI 0x02
#define SDP_ATTR_HID_DESC_LIST_LO 0x06
#define HID_RPT_DESC_TYPE         0x22
#define SDP_SCAN_MIN_LEN          11      // minimum bytes to match the pattern
#define SDP_DESC_MAX_EXPECTED_LEN 512     // sanity cap on declared descriptor length

static BOOLEAN
ScanForSdpHidDescriptor(
    _In_reads_bytes_(bufSize) PUCHAR  buf,
    _In_                      ULONG   bufSize,
    _Out_                     PULONG  outOffset,
    _Out_                     PULONG  outLen)
{
    if (buf == NULL || bufSize < SDP_SCAN_MIN_LEN) {
        return FALSE;
    }

    ULONG limit = bufSize - SDP_SCAN_MIN_LEN;
    for (ULONG i = 0; i <= limit; i++) {
        if (buf[i]   != SDP_DE_UINT16              ) continue;
        if (buf[i+1] != SDP_ATTR_HID_DESC_LIST_HI  ) continue;
        if (buf[i+2] != SDP_ATTR_HID_DESC_LIST_LO  ) continue;
        if (buf[i+3] != SDP_DE_SEQUENCE_1B         ) continue;

        UCHAR outer_len = buf[i+4];
        if (outer_len < 4)                            continue;
        if ((ULONG)(i + 5 + outer_len) > bufSize)     continue;

        if (buf[i+5] != SDP_DE_SEQUENCE_1B)           continue;
        UCHAR inner_len = buf[i+6];
        if (inner_len < 4)                            continue;
        if ((ULONG)(i + 7 + inner_len) > bufSize)     continue;

        if (buf[i+7] != SDP_DE_UINT8)                 continue;
        if (buf[i+8] != HID_RPT_DESC_TYPE)            continue;
        if (buf[i+9] != SDP_DE_TEXT_1B)               continue;

        UCHAR desc_len = buf[i+10];
        if (desc_len == 0)                            continue;
        if (desc_len > SDP_DESC_MAX_EXPECTED_LEN)     continue;
        if ((ULONG)(i + 11 + desc_len) > bufSize)     continue;

        *outOffset = i + 11;
        *outLen    = desc_len;
        return TRUE;
    }
    return FALSE;
}

// Replaces the embedded descriptor at descOffset (length descLen) with
// g_HidDescriptor[]. Updates the SDP TLV length bytes at [descOffset-1],
// [descOffset-3], [descOffset-5]. If our descriptor is larger than the
// allocated buffer can hold, returns FALSE without modifying anything.
static BOOLEAN
PatchSdpHidDescriptor(
    _Inout_updates_bytes_(bufSize) PUCHAR buf,
    _In_                           ULONG  bufSize,
    _In_                           ULONG  descOffset,
    _In_                           ULONG  descLen,
    _Out_                          PULONG newBufUsed)
{
    if (descOffset < 6) {
        return FALSE;  // not enough framing bytes before descriptor
    }

    ULONG newDescLen = g_HidDescriptorSize;
    ULONG tailOffset = descOffset + descLen;
    ULONG tailBytes  = bufSize - tailOffset;
    ULONG newBufSize = descOffset + newDescLen + tailBytes;

    if (newBufSize > bufSize) {
        DbgPrint("MagicMouse: SDP patch SKIPPED - buffer too small "
                 "(need %lu, have %lu). Force re-pair to grow buffer.\n",
                 newBufSize, bufSize);
        return FALSE;
    }

    if (newDescLen != descLen) {
        ULONG newTailOffset = descOffset + newDescLen;
        if (tailBytes > 0) {
            RtlMoveMemory(buf + newTailOffset, buf + tailOffset, tailBytes);
        }
        if (newDescLen < descLen) {
            ULONG gapStart = newTailOffset + tailBytes;
            ULONG gapLen   = descLen - newDescLen;
            RtlZeroMemory(buf + gapStart, gapLen);
        }
    }

    RtlCopyMemory(buf + descOffset, g_HidDescriptor, newDescLen);

    // SDP TLV length-byte fixups (1-byte length form).
    buf[descOffset - 1] = (UCHAR)newDescLen;                          // TEXT_STRING len
    ULONG innerPayload = 2 + 2 + newDescLen;                          // 0x08 0x22 + 0x25 LL + descriptor
    if (innerPayload > 0xFF) {
        DbgPrint("MagicMouse: SDP patch - inner SEQUENCE length overflow (%lu)\n",
                 innerPayload);
    }
    buf[descOffset - 3] = (UCHAR)(innerPayload & 0xFF);               // inner SEQUENCE len
    ULONG outerPayload = 2 + innerPayload;                            // outer SEQUENCE wraps inner
    if (outerPayload > 0xFF) {
        DbgPrint("MagicMouse: SDP patch - outer SEQUENCE length overflow (%lu)\n",
                 outerPayload);
    }
    buf[descOffset - 5] = (UCHAR)(outerPayload & 0xFF);               // outer SEQUENCE len

    *newBufUsed = descOffset + newDescLen + tailBytes;
    return TRUE;
}

// ---------------------------------------------------------------------------
// ACL transfer completion routine
// ---------------------------------------------------------------------------

VOID
InputHandler_AclCompletion(
    _In_ WDFREQUEST                     Request,
    _In_ WDFIOTARGET                    Target,
    _In_ PWDF_REQUEST_COMPLETION_PARAMS Params,
    _In_ WDFCONTEXT                     Context)
{
    UNREFERENCED_PARAMETER(Target);

    NTSTATUS        status = Params->IoStatus.Status;
    PDEVICE_CONTEXT devCtx = (PDEVICE_CONTEXT)Context;

    if (!NT_SUCCESS(status)) {
        WdfRequestComplete(Request, status);
        return;
    }

    // Re-read the BRB from the IRP stack.
    // After WdfRequestFormatRequestUsingCurrentType + WdfRequestSend, our stack
    // location is current again when this completion fires (IoAdvanceIrpStackLocation
    // unwinds the IRP back to our level before calling the WDF completion routine).
    PIRP irp = WdfRequestWdmGetIrp(Request);
    PIO_STACK_LOCATION stack = IoGetCurrentIrpStackLocation(irp);
    PVOID brb = stack->Parameters.Others.Argument1;

    if (brb == NULL) {
        WdfRequestComplete(Request, STATUS_INVALID_PARAMETER);
        return;
    }

    ULONG_PTR chanHandle = BrbReadHandle(brb, MM_BRB_ACL_CHANNEL_HANDLE_OFFSET);
    ULONG     flags      = BrbReadUlong(brb,  MM_BRB_ACL_TRANSFER_FLAGS_OFFSET);

    // Only process device → host data
    if (!(flags & MM_ACL_TRANSFER_IN)) {
        WdfRequestComplete(Request, status);
        return;
    }

    ULONG bufSize = BrbReadUlong(brb, MM_BRB_ACL_BUFFER_SIZE_OFFSET);
    PVOID bufPtr  = BrbReadPtr(brb,  MM_BRB_ACL_BUFFER_OFFSET);

    if (bufPtr == NULL) {
        // MDL path — map the MDL to get a system-space pointer
        PMDL mdl = (PMDL)BrbReadPtr(brb, MM_BRB_ACL_BUFFER_MDL_OFFSET);
        if (mdl != NULL) {
            bufPtr = MmGetSystemAddressForMdlSafe(mdl, NormalPagePriority);
        }
    }

    if (bufPtr == NULL || bufSize == 0) {
        WdfRequestComplete(Request, status);
        return;
    }

    PUCHAR data = (PUCHAR)bufPtr;
    UNREFERENCED_PARAMETER(chanHandle);
    UNREFERENCED_PARAMETER(devCtx);

    // -----------------------------------------------------------------------
    // SDP HIDDescriptorList interception (PSM 1, descriptor-injection path)
    //
    // We scan EVERY incoming ACL transfer for the SDP attribute-0x0206 byte
    // pattern, regardless of which L2CAP channel it arrived on. This catches
    // the descriptor delivery during the SDP exchange (PSM 1) without us
    // having to track SDP channel handles separately.
    //
    // If the pattern is found, we replace the embedded HID descriptor with
    // g_HidDescriptor[] (113 bytes, 3 TLCs: Mouse with Wheel + Consumer
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
        ULONG descLen    = 0;
        if (ScanForSdpHidDescriptor(data, bufSize, &descOffset, &descLen)) {
            DbgPrint("MagicMouse: SDP HIDDescriptorList found at offset %lu "
                     "(orig len %lu), patching with custom descriptor (%lu bytes)\n",
                     descOffset, descLen, g_HidDescriptorSize);

            ULONG newBufUsed = 0;
            if (PatchSdpHidDescriptor(data, bufSize, descOffset, descLen, &newBufUsed)) {
                // Update BRB BufferSize so HidBth sees the patched transfer length
                ULONG patchedSize = newBufUsed;
                *(ULONG *)((PUCHAR)brb + MM_BRB_ACL_BUFFER_SIZE_OFFSET) = patchedSize;
                irp->IoStatus.Information = patchedSize;
                DbgPrint("MagicMouse: Descriptor injected, new transfer size = %lu bytes\n",
                         patchedSize);
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
// OPEN_CHANNEL completion — store the new channel handle
// ---------------------------------------------------------------------------

VOID
InputHandler_OpenChannelCompletion(
    _In_ WDFREQUEST                     Request,
    _In_ WDFIOTARGET                    Target,
    _In_ PWDF_REQUEST_COMPLETION_PARAMS Params,
    _In_ WDFCONTEXT                     Context)
{
    UNREFERENCED_PARAMETER(Target);

    NTSTATUS        status = Params->IoStatus.Status;
    PDEVICE_CONTEXT devCtx = (PDEVICE_CONTEXT)Context;

    // Only record the channel if the open succeeded
    if (NT_SUCCESS(status)) {
        PIRP irp = WdfRequestWdmGetIrp(Request);
        PIO_STACK_LOCATION stack = IoGetCurrentIrpStackLocation(irp);
        PVOID brb = stack->Parameters.Others.Argument1;

        if (brb != NULL) {
            ULONG_PTR handle = BrbReadHandle(brb, MM_BRB_OPEN_CHANNEL_HANDLE_OFFSET);
            StoreChannelHandle(devCtx, handle);
        }
    }

    WdfRequestComplete(Request, status);
}

// ---------------------------------------------------------------------------
// Main BRB submit dispatch
// ---------------------------------------------------------------------------

VOID
InputHandler_HandleBrbSubmit(
    _In_ WDFDEVICE  Device,
    _In_ WDFREQUEST Request)
{
    PIRP irp = WdfRequestWdmGetIrp(Request);
    PIO_STACK_LOCATION stack = IoGetCurrentIrpStackLocation(irp);
    PVOID brb = stack->Parameters.Others.Argument1;
    PDEVICE_CONTEXT devCtx = GetDeviceContext(Device);

    if (brb == NULL) {
        goto passthrough;
    }

    USHORT brbType = *(USHORT *)((PUCHAR)brb + MM_BRB_TYPE_OFFSET);

    switch (brbType) {

    // Forward OPEN_CHANNEL with a completion routine to capture the output ChannelHandle.
    case BRB_L2CA_OPEN_CHANNEL:
    case BRB_L2CA_OPEN_CHANNEL_RESPONSE:
        WdfRequestFormatRequestUsingCurrentType(Request);
        WdfRequestSetCompletionRoutine(Request,
                                       InputHandler_OpenChannelCompletion,
                                       devCtx);
        if (!WdfRequestSend(Request, WdfDeviceGetIoTarget(Device),
                            WDF_NO_SEND_OPTIONS)) {
            WdfRequestComplete(Request, WdfRequestGetStatus(Request));
        }
        return;

    // Read the ChannelHandle input before forwarding (it's the channel to close).
    case BRB_L2CA_CLOSE_CHANNEL: {
        ULONG_PTR handle = BrbReadHandle(brb, MM_BRB_CLOSE_CHANNEL_HANDLE_OFFSET);
        ClearChannelHandle(devCtx, handle);
        goto passthrough;
    }

    // Forward ACL transfers with a completion routine to intercept the data buffer.
    case BRB_L2CA_ACL_TRANSFER:
        WdfRequestFormatRequestUsingCurrentType(Request);
        WdfRequestSetCompletionRoutine(Request,
                                       InputHandler_AclCompletion,
                                       devCtx);
        if (!WdfRequestSend(Request, WdfDeviceGetIoTarget(Device),
                            WDF_NO_SEND_OPTIONS)) {
            WdfRequestComplete(Request, WdfRequestGetStatus(Request));
        }
        return;

    default:
        goto passthrough;
    }

passthrough:
    WdfRequestFormatRequestUsingCurrentType(Request);
    WDF_REQUEST_SEND_OPTIONS opts;
    WDF_REQUEST_SEND_OPTIONS_INIT(&opts, WDF_REQUEST_SEND_OPTION_SEND_AND_FORGET);
    if (!WdfRequestSend(Request, WdfDeviceGetIoTarget(Device), &opts)) {
        WdfRequestComplete(Request, WdfRequestGetStatus(Request));
    }
}
