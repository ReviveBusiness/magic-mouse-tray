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

// ---------------------------------------------------------------------------
// Report 0x12 translation helpers
// ---------------------------------------------------------------------------

// Report 0x12 (MOUSE2_REPORT_ID) layout per Linux hid-magicmouse.c.
// PID 0323 assumed identical to MagicMouse2 format — verify on first test run.
//
//   data[0]          = 0x12  (Report ID)
//   data[1]          = button state (bit 0 = left, bit 1 = right)
//   data[2]          = touch count + click force
//   data[3..13]      = header (11 bytes)
//   data[14 + i*8 .. 14 + i*8 + 7] = touch block i (8 bytes):
//     tdata[0..1]: X encoding — (tdata[1]<<28 | tdata[0]<<20)>>20 (signed 12-bit)
//     tdata[2..3]: Y encoding — -((tdata[2]<<24 | tdata[1]<<16)>>20) (signed 12-bit)
//     tdata[5]:    size (bits 0-5), touch state high (bits 6-7)
//     tdata[6]:    tracking id (bits 0-3), orientation (bits 2-7)
//     tdata[7]:    touch state flags — high nibble: 0x30=START, 0x40=DRAG, 0x00=NONE
// Header byte count between Report ID and first touch block.
//   PID 0x0265 (Magic Mouse 2): 14 bytes
//   PID 0x0323 (Magic Mouse 2024): 7 bytes
// Empirically derived from packet sizes observed via DebugView:
//   sz=9  total = 0xA1 + Report 0x12 + 7 header bytes + 0 touch blocks (idle/release)
//   sz=17 total = above + 1 touch block (single finger)
//   sz=25 total = above + 2 touch blocks (two finger gesture)
#define TOUCH2_HEADER     7
#define TOUCH2_BLOCK      8
#define TOUCH_START    0x30
#define TOUCH_DRAG     0x40
#define SCALE_POINTER     4   // divisor: 100ths-of-mm → approximate screen delta
#define SCALE_SCROLL      8   // divisor: 100ths-of-mm → scroll step

static FORCEINLINE INT8
ClampInt8(INT32 v)
{
    if (v >  127) return  127;
    if (v < -127) return -127;
    return (INT8)v;
}

// Decode signed 12-bit X from two touch bytes (Linux formula)
static FORCEINLINE INT32
TouchX(PUCHAR t)
{
    return (INT32)((((UINT32)t[1] << 28) | ((UINT32)t[0] << 20))) >> 20;
}

// Decode signed 12-bit Y from two touch bytes (Linux formula, negated for Windows coords)
static FORCEINLINE INT32
TouchY(PUCHAR t)
{
    return -((INT32)((((UINT32)t[2] << 24) | ((UINT32)t[1] << 16))) >> 20);
}

// Translate Report 0x12 into Report 0x01 in-place.
// Also extracts horizontal scroll value (for future Report 0x02 emission).
// Returns FALSE if the buffer is too short to parse.
static BOOLEAN
TranslateReport12(
    _Inout_updates_bytes_(bufSize) PUCHAR  buf,
    _In_                           ULONG   bufSize,
    _Out_opt_                      PINT8   outWheelH,
    _Out_                          PULONG  outReportLen)
{
    *outReportLen = 0;
    if (outWheelH) *outWheelH = 0;

    if (bufSize < (ULONG)(TOUCH2_HEADER + 1)) {
        return FALSE;
    }

    UCHAR  buttons = buf[1] & 0x03;
    ULONG  nBlocks = (bufSize - TOUCH2_HEADER) / TOUCH2_BLOCK;
    INT8   x = 0, y = 0, wheelV = 0, wheelH = 0;

    if (nBlocks >= 1) {
        PUCHAR t = &buf[TOUCH2_HEADER];
        INT32  rawX = TouchX(t);
        INT32  rawY = TouchY(t);
        UCHAR  state = t[7] & 0xF0;

        if (nBlocks == 1) {
            // Single finger — pointer movement
            x = ClampInt8(rawX / SCALE_POINTER);
            y = ClampInt8(rawY / SCALE_POINTER);
        } else {
            // Two or more fingers — scroll gesture
            if (state == TOUCH_START || state == TOUCH_DRAG) {
                wheelV = ClampInt8(rawY / SCALE_SCROLL);
                wheelH = ClampInt8(rawX / SCALE_SCROLL);
            }
        }
    }

    // Write Report 0x01 into the same buffer (5 bytes, in-place)
    buf[0] = MM_REPORT_ID_MOUSE;
    buf[1] = buttons;
    buf[2] = (UCHAR)x;
    buf[3] = (UCHAR)y;
    buf[4] = (UCHAR)wheelV;

    if (outWheelH) *outWheelH = wheelH;
    *outReportLen = MM_MOUSE_REPORT_LEN;
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

    // -----------------------------------------------------------------------
    // Control channel: inject custom HID descriptor once per connection
    // -----------------------------------------------------------------------
    if (chanHandle == devCtx->ControlChannelHandle && !devCtx->DescriptorInjected) {
        // The SDP HIDDescriptorList attribute response contains the raw HID
        // descriptor bytes embedded in the SDP TLV payload. We locate the start
        // of the HID descriptor by scanning for the Generic Desktop Usage Page
        // preamble (0x05 0x01) within the first 256 bytes of the buffer.
        //
        // TODO: After the EWDK build is available, capture a WinDbg trace during
        // BT connect to confirm the exact byte offset within the SDP response
        // where the HID descriptor begins. If the device's raw descriptor does NOT
        // start with 0x05 0x01 (Generic Desktop), adjust the scan pattern.
        ULONG  scanLen = (bufSize < 256) ? bufSize : 256;
        ULONG  injectAt = ULONG_MAX;

        for (ULONG i = 0; i + 1 < scanLen; i++) {
            if (data[i] == 0x05 && data[i + 1] == 0x01) {
                injectAt = i;
                break;
            }
        }

        if (injectAt != ULONG_MAX &&
            (injectAt + g_HidDescriptorSize) <= bufSize) {
            RtlCopyMemory(data + injectAt, g_HidDescriptor, g_HidDescriptorSize);
            devCtx->DescriptorInjected = TRUE;
        }
    }
    // -----------------------------------------------------------------------
    // Interrupt channel: translate Report 0x12
    //
    // BT HID protocol: every L2CAP interrupt-channel input packet is prefixed
    // with a single transport header byte:
    //   0xA1 = HID Transaction (DATA) | HID Type (INPUT)
    // The actual HID Report ID is at data[1], NOT data[0]. This was empirically
    // confirmed: every packet on the interrupt channel showed data[0]==0xA1.
    // Without this fix, the Report ID check below was ALWAYS false.
    //
    // We pass (data + 1, bufSize - 1) to TranslateReport12 so the function sees
    // a clean Report 0x12 buffer at offset 0. The translated Report 0x01 is
    // written in-place starting at data[1], preserving the 0xA1 transport byte
    // at data[0]. IoStatus.Information is set to newLen + 1 to include 0xA1.
    // -----------------------------------------------------------------------
    else if (chanHandle == devCtx->InterruptChannelHandle &&
             bufSize >= 2 &&
             data[0] == 0xA1 &&
             data[1] == MM_REPORT_ID_TOUCH) {

        ULONG  newLen  = 0;
        INT8   wheelH  = 0;

        if (TranslateReport12(data + 1, bufSize - 1, &wheelH, &newLen)) {
            irp->IoStatus.Information = newLen + 1;  // +1 for 0xA1 transport byte

            // Horizontal scroll (wheelH != 0) requires Report 0x02 on TLC2.
            // Delivering a second HID report from this completion requires a
            // separate IRP submission into the HidBth read queue — deferred to
            // Phase 3.5. For now, horizontal scroll is silently discarded.
            UNREFERENCED_PARAMETER(wheelH);
        }
        // Report 0x90 (battery) and unknown IDs fall through unchanged
    }

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
