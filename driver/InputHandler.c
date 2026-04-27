// SPDX-License-Identifier: MIT
//
// InputHandler — translates raw Apple Magic Mouse BT HID reports.
//
// Raw BT device sends two report types:
//   Report 0x12 — multi-touch: 14-byte header + N × 9-byte touch records
//   Report 0x90 — battery:     [0x90, flags, battery%]
//
// We translate 0x12 → Report 0x01 (standard mouse format matching TLC1 descriptor).
// Report 0x90 passes through unchanged (TLC2 descriptor matches exactly).
//
// TODO: Fill in TranslateTouch() once TouchpadProbe.ps1 output is captured.
//   Run: scripts\TouchpadProbe.ps1 (elevated, on Windows, mouse connected)
//   Move finger while it runs — capture Report 0x12 raw hex to docs\
//   Then port Linux hid-magicmouse.c touch parsing to TranslateTouch().
//
// Reference: drivers/hid/hid-magicmouse.c in the Linux kernel
//   MOUSE2_REPORT_ID = 0x12
//   Each touch record: x(int16), y(int16), touch_state(u8), size(u8), pressure(u8), ...
//   Scroll: accumulate Y delta across 1-finger moves; emit on threshold.

#include "InputHandler.h"

// Minimum report length to attempt 0x12 parsing (9-byte header minimum)
#define MM_TOUCH_REPORT_MIN_LEN   9

// Bytes per touch record in Report 0x12 (from Linux hid-magicmouse.c MOUSE2 format)
// TODO: verify exact byte layout against TouchpadProbe.ps1 output
#define MM_TOUCH_RECORD_BYTES     9

// Header bytes before first touch record in Report 0x12
#define MM_TOUCH_HEADER_BYTES     9

// Signed byte clamp to INT8 range
static INT8 ClampToInt8(INT32 val) {
    if (val > 127)  return 127;
    if (val < -127) return -127;
    return (INT8)val;
}

// TODO: Implement using actual Report 0x12 byte layout from TouchpadProbe output.
// Signature kept minimal — extend as needed for multi-finger gestures.
static VOID
TranslateTouch(
    _In_reads_bytes_(reportLen) PUCHAR reportBuf,
    _In_  ULONG  reportLen,
    _Out_ PUCHAR outBuf6)  // 6-byte output: [0x01, buttons, X, Y, WheelV, WheelH]
{
    UNREFERENCED_PARAMETER(reportLen);

    // Zero the output report
    RtlZeroMemory(outBuf6, MM_MOUSE_REPORT_LEN);
    outBuf6[0] = MM_REPORT_ID_MOUSE;

    // TODO: Parse reportBuf per Linux hid-magicmouse.c MOUSE2_REPORT_ID handling.
    //
    // Reference layout (verify with TouchpadProbe.ps1):
    //   reportBuf[0] = 0x12 (Report ID)
    //   reportBuf[1] = buttons bitmask (bit 0 = left click)
    //   reportBuf[2] = ? (possibly click force / number of touches)
    //   reportBuf[3..8] = rest of header
    //   reportBuf[9 + i*9 .. 9 + i*9 + 8] = touch record i:
    //     [0..1] = X (INT16 little-endian, unit: 100ths of mm)
    //     [2..3] = Y (INT16 little-endian, unit: 100ths of mm)
    //     [4]    = tracking ID + touch flags
    //     [5]    = touch size
    //     [6..8] = other data
    //
    // Basic single-finger implementation:
    //   nTouches = (reportLen - MM_TOUCH_HEADER_BYTES) / MM_TOUCH_RECORD_BYTES;
    //   if (nTouches == 1) {
    //       INT16 rawX = (INT16)(reportBuf[10] << 8 | reportBuf[9]);
    //       INT16 rawY = (INT16)(reportBuf[12] << 8 | reportBuf[11]);
    //       outBuf6[2] = ClampToInt8(rawX / SCALE);  // X pointer
    //       outBuf6[3] = ClampToInt8(rawY / SCALE);  // Y pointer
    //   } else if (nTouches == 2) {
    //       // Two-finger scroll: accumulate Y → WheelV, X → WheelH
    //   }
    //
    // Pass through button state from report header byte 1:
    outBuf6[1] = (reportBuf[1] & 0x01);  // left button — assume bit 0
}

VOID
InputHandler_ForwardWithCompletion(
    _In_ WDFDEVICE  Device,
    _In_ WDFREQUEST Request)
{
    WdfRequestFormatRequestUsingCurrentType(Request);
    WdfRequestSetCompletionRoutine(Request, InputHandler_OnReadComplete, Device);

    if (!WdfRequestSend(Request, WdfDeviceGetIoTarget(Device), WDF_NO_SEND_OPTIONS)) {
        WdfRequestComplete(Request, WdfRequestGetStatus(Request));
    }
}

VOID
InputHandler_OnReadComplete(
    _In_ WDFREQUEST                     Request,
    _In_ WDFIOTARGET                    Target,
    _In_ PWDF_REQUEST_COMPLETION_PARAMS Params,
    _In_ WDFCONTEXT                     Context)
{
    UNREFERENCED_PARAMETER(Target);
    UNREFERENCED_PARAMETER(Context);

    NTSTATUS status = Params->IoStatus.Status;
    if (!NT_SUCCESS(status)) {
        WdfRequestComplete(Request, status);
        return;
    }

    ULONG reportLen = (ULONG)Params->IoStatus.Information;
    if (reportLen < 1) {
        WdfRequestComplete(Request, status);
        return;
    }

    // Report buffer is in Irp->UserBuffer for METHOD_NEITHER IOCTL_HID_READ_REPORT
    PIRP irp = WdfRequestWdmGetIrp(Request);
    PUCHAR data = (PUCHAR)irp->UserBuffer;
    if (data == NULL) {
        WdfRequestComplete(Request, STATUS_INVALID_PARAMETER);
        return;
    }

    UCHAR reportId = data[0];

    if (reportId == MM_REPORT_ID_TOUCH && reportLen >= MM_TOUCH_REPORT_MIN_LEN) {
        // Translate raw multi-touch → standard mouse report in place
        UCHAR translated[MM_MOUSE_REPORT_LEN];
        TranslateTouch(data, reportLen, translated);
        RtlCopyMemory(data, translated, MM_MOUSE_REPORT_LEN);
        Params->IoStatus.Information = MM_MOUSE_REPORT_LEN;
        irp->IoStatus.Information    = MM_MOUSE_REPORT_LEN;
    }
    // Report 0x90 (battery) and any others pass through unchanged

    WdfRequestComplete(Request, status);
}
