// SPDX-License-Identifier: MIT
// Magic Mouse 2024 KMDF Lower Filter Driver
//
// Stack position (lower filter between BthEnum and HidBth):
//   HidClass → HidBth → [MagicMouseDriver (this)] → BthEnum
//
// Interception mechanism (confirmed 2026-04-27 via static analysis of applewirelessmouse.sys):
//
//   IOCTL_HID_GET_REPORT_DESCRIPTOR and IOCTL_HID_READ_REPORT are upward-facing
//   Windows HID IOCTLs absorbed by hidclass.sys. They never reach a lower filter
//   below HidBth. This driver does NOT intercept those IOCTLs.
//
//   The correct interception point is IOCTL_INTERNAL_BTH_SUBMIT_BRB (0x00410003) —
//   the Bluetooth Request Block submit IOCTL. All L2CAP data (HID descriptor bytes
//   and input reports) travels via BRB_L2CA_ACL_TRANSFER on this path.
//
// HID descriptor delivery:
//   g_HidDescriptor[] (3 TLCs: Mouse + Consumer AC-Pan + Vendor Battery) is injected
//   into any BRB_L2CA_ACL_TRANSFER buffer containing the SDP HIDDescriptorList attribute
//   (0x0206) byte pattern. Descriptor injection happens at SDP-exchange time (pairing).
//   User must unpair and re-pair after filter install for the new descriptor to take effect.

#pragma once

#include <ntddk.h>
#include <wdf.h>

// ---------------------------------------------------------------------------
// Bluetooth BRB submit IOCTL
// ---------------------------------------------------------------------------

// IOCTL_INTERNAL_BTH_SUBMIT_BRB — private internal version (NOT the public 0x0041002B).
// CTL_CODE(FILE_DEVICE_BLUETOOTH=0x41, Function=0, METHOD_NEITHER=3, FILE_ANY_ACCESS=0)
// Confirmed via static analysis of applewirelessmouse.sys SHA-256 08F33D7E...
#define IOCTL_INTERNAL_BTH_SUBMIT_BRB 0x00410003UL

// BRB types handled by this driver (from bthddi.h BRB_TYPE enum)
#define BRB_L2CA_OPEN_CHANNEL 0x0102
#define BRB_L2CA_OPEN_CHANNEL_RESPONSE 0x0103
#define BRB_L2CA_CLOSE_CHANNEL 0x0104
#define BRB_L2CA_ACL_TRANSFER 0x0105

// ---------------------------------------------------------------------------
// BRB field offsets (64-bit Windows)
// ---------------------------------------------------------------------------

// BRB_HEADER layout — public fields 0x00-0x1F; internal fields 0x20-0x6F (private).
// Total header size: 0x70 bytes (verified via static analysis of applewirelessmouse.sys).
//   +0x00  LIST_ENTRY.Flink  (8 bytes)
//   +0x08  LIST_ENTRY.Blink  (8 bytes)
//   +0x10  Length            (ULONG) ← declared allocation size of this BRB
//   +0x14  Version           (USHORT)
//   +0x16  Type              (USHORT) ← dispatch here
//   +0x18  Status            (ULONG)
//   +0x1C  Reserved          (ULONG)
//   +0x20..0x6F  internal BthEnum state (not in public bthddi.h)
#define MM_BRB_LENGTH_OFFSET 0x10 // BRB_HEADER.Length — validate before field access
#define MM_BRB_TYPE_OFFSET 0x16

// BRB_L2CA_OPEN_CHANNEL — ChannelHandle at first field after 0x70-byte header.
//   Output parameter: BthEnum populates it when the L2CAP connection is established.
#define MM_BRB_OPEN_CHANNEL_HANDLE_OFFSET 0x70

// BRB_L2CA_CLOSE_CHANNEL — ChannelHandle after header + 8-byte BtAddress field.
//   Input parameter: caller provides the handle of the channel to tear down.
#define MM_BRB_CLOSE_CHANNEL_HANDLE_OFFSET 0x78

// BRB_L2CA_ACL_TRANSFER field offsets (verified via static analysis of applewirelessmouse.sys):
//   +0x70  BtAddress       (BTH_ADDR = ULONGLONG)
//   +0x78  ChannelHandle   (L2CAP_CHANNEL_HANDLE = PVOID)
//   +0x80  TransferFlags   (ULONG)
//   +0x84  BufferSize      (ULONG)
//   +0x88  Buffer          (PVOID; NULL when MDL path is used)
//   +0x90  BufferMDL       (PMDL;  NULL when Buffer path is used)
#define MM_BRB_ACL_CHANNEL_HANDLE_OFFSET 0x78
#define MM_BRB_ACL_TRANSFER_FLAGS_OFFSET 0x80
#define MM_BRB_ACL_BUFFER_SIZE_OFFSET 0x84
#define MM_BRB_ACL_BUFFER_OFFSET 0x88
#define MM_BRB_ACL_BUFFER_MDL_OFFSET 0x90

// TransferFlags bit: data flows device → host (incoming read).
// From bthddi.h: ACL_TRANSFER_DIRECTION_IN = 0x00000001
#define MM_ACL_TRANSFER_IN 0x00000001UL

// ---------------------------------------------------------------------------
// Magic Mouse 2024 RID=0x12 multi-touch frame layout (per hid-magicmouse.c)
// ---------------------------------------------------------------------------
//   buf[0]    = 0x12 (RID)
//   buf[3..4] = body X delta (INT16 LE) — optical sensor / whole-mouse motion
//   buf[5..6] = body Y delta (INT16 LE)
//   buf[7]    = clicks
//   buf[8..13]= header padding (14 bytes total)
//   buf[14+]  = N x 8-byte touch blocks (touch surface fingertip positions)
//
// Touch block (8 bytes): 12-bit signed X and Y (bit-packed across tdata[0,7,3]),
// state in upper nibble of tdata[7]. Linux's magicmouse_emit_touch:
//   x =  (((INT32)tdata[7] << 28) | ((INT32)tdata[0] << 20)) >> 20;
//   y = -(((INT32)tdata[3] << 24) | ((INT32)tdata[7] << 16)) >> 20;
#define MM_REPORT_ID_TOUCH       0x12
#define MM_REPORT_ID_MOUSE       0x01
#define MM_TOUCH_HEADER_BYTES    14
#define MM_TOUCH_BLOCK_BYTES     8
#define MM_MOUSE_REPORT_BYTES    5     // [RID, buttons, X, Y, wheel] per descriptor TLC1
#define MM_WHEEL_DELTA_DIVIDER   8     // touch-Y units per wheel detent (tunable)

// ---------------------------------------------------------------------------
// Report IDs
// ---------------------------------------------------------------------------

#define MM_REPORT_ID_TOUCH 0x12    // Raw Apple multi-touch (device → host)
#define MM_REPORT_ID_MOUSE 0x01    // TLC1 standard mouse report (emitted)
#define MM_REPORT_ID_CONSUMER 0x02 // TLC2 AC Pan / horizontal scroll (emitted)
#define MM_REPORT_ID_BATTERY 0x90  // TLC3 vendor battery — pass through

// TLC1 mouse report buffer: [0x01, buttons, X, Y, WheelV] = 5 bytes
//   InputReportByteLength = 4 (per descriptor, excludes report ID byte)
#define MM_MOUSE_REPORT_LEN 5

// TLC2 consumer report buffer: [0x02, WheelH] = 2 bytes
//   InputReportByteLength = 1
#define MM_CONSUMER_REPORT_LEN 2

// Minimum Report 0x12 length for parsing (header bytes before first touch block)
#define MM_TOUCH_REPORT_MIN_LEN 14

// ---------------------------------------------------------------------------
// Device context
// ---------------------------------------------------------------------------

// Per-device state shared across BRB completion routines.
// SMP safety: Lock must be held when reading or writing channel handle fields.
// The queue is WdfIoQueueDispatchParallel, so OPEN and CLOSE completions can
// race on a multi-core system without a spinlock.
typedef struct _DEVICE_CONTEXT
{
    // Spinlock protecting all mutable fields below.
    // Initialized in EvtDeviceAdd via WdfSpinLockCreate.
    WDFSPINLOCK Lock;

    // L2CAP channel handles — populated on BRB_L2CA_OPEN_CHANNEL completion.
    // Convention: first channel opened = HID control (PSM 17, descriptor traffic).
    //             second channel       = HID interrupt (PSM 19, input report stream).
    // Cleared to 0 on the corresponding BRB_L2CA_CLOSE_CHANNEL completion.
    ULONG_PTR ControlChannelHandle;
    ULONG_PTR InterruptChannelHandle;

    // Count of channels successfully opened. Used to assign control vs. interrupt slot.
    // Incremented in the OPEN_CHANNEL completion routine.
    ULONG ChannelCount;

    // Touch-surface scroll synthesis state.
    // Magic Mouse 2024 reports scroll input via RID=0x12 multi-touch frames
    // carrying per-finger Y positions in 8-byte touch blocks at offset 14+.
    // We compute the average Y across all reported touches, compare to the
    // previous frame's average, and emit the delta as a synthetic mouse-wheel
    // event in a rewritten RID=0x01 report. HasLastTouch resets to FALSE on
    // a frame with zero touches (finger lifted) so the next touch-down does
    // not produce a spurious wheel jump from stale state.
    INT32   LastAvgTouchY;
    BOOLEAN HasLastTouch;

} DEVICE_CONTEXT, *PDEVICE_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, GetDeviceContext)

// Per-request context: stash BRB pointer before WdfRequestSend so completion
// routines recover it safely without re-reading the IRP stack location (which
// WDF may advance past our layer before invoking our completion).
// Note: DevCtx is intentionally absent — completion routines receive it via
// the Context parameter passed to WdfRequestSetCompletionRoutine.
typedef struct _MM_REQUEST_CONTEXT
{
    PVOID Brb;
} MM_REQUEST_CONTEXT, *PMM_REQUEST_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(MM_REQUEST_CONTEXT, GetRequestContext)

// ---------------------------------------------------------------------------
// Function declarations
// ---------------------------------------------------------------------------

DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_DEVICE_ADD EvtDeviceAdd;
EVT_WDF_IO_QUEUE_IO_INTERNAL_DEVICE_CONTROL EvtIoInternalDeviceControl;
