// SPDX-License-Identifier: MIT
//
// Custom HID report descriptor for Apple Magic Mouse 2024 (PID 0x0323).
//
// Replaces the descriptor provided by the raw BT device to ensure both
// collections are always present regardless of filter state:
//
//   TLC1 (Report ID 0x01) — Generic Desktop Mouse
//     Pointer + 3 buttons + X/Y relative + vertical wheel + horizontal scroll (AC Pan)
//     InputReportByteLength = 6  ([0x01, buttons, X, Y, WheelV, WheelH])
//
//   TLC2 (Report ID 0x90) — Vendor-Defined Battery
//     Matches raw BT device battery report exactly:
//     InputReportByteLength = 3  ([0x90, flags, battery_%])
//     MagicMouseTray reads buf[2] = battery% via HidD_GetInputReport on COL02.
//
// Design notes:
//   - Both TLCs declare explicit Report IDs (required when any TLC uses one).
//   - TLC1 format is compatible with mouhid.sys (standard Windows mouse driver).
//   - TLC2 is pass-through: Report 0x90 from BT device is forwarded unchanged.
//   - InputHandler translates raw Report 0x12 (multi-touch) → Report 0x01.

#include "HidDescriptor.h"

const UCHAR g_HidDescriptor[] = {
    // ----------------------------------------------------------------
    // TLC1: Generic Desktop Mouse (Usage Page 0x01, Usage 0x02)
    // ----------------------------------------------------------------
    0x05, 0x01,        // Usage Page (Generic Desktop)
    0x09, 0x02,        // Usage (Mouse)
    0xA1, 0x01,        // Collection (Application)
    0x85, 0x01,        //   Report ID (1)

    0x09, 0x01,        //   Usage (Pointer)
    0xA1, 0x00,        //   Collection (Physical)

    // 3 buttons — 3 × 1-bit fields + 5-bit padding = 1 byte
    0x05, 0x09,        //     Usage Page (Button)
    0x19, 0x01,        //     Usage Minimum (Button 1 — left)
    0x29, 0x03,        //     Usage Maximum (Button 3 — middle)
    0x15, 0x00,        //     Logical Minimum (0)
    0x25, 0x01,        //     Logical Maximum (1)
    0x75, 0x01,        //     Report Size (1)
    0x95, 0x03,        //     Report Count (3)
    0x81, 0x02,        //     Input (Data, Variable, Absolute)
    0x75, 0x05,        //     Report Size (5) — padding
    0x95, 0x01,        //     Report Count (1)
    0x81, 0x03,        //     Input (Constant)

    // X and Y — 2 × INT8 relative axes
    0x05, 0x01,        //     Usage Page (Generic Desktop)
    0x09, 0x30,        //     Usage (X)
    0x09, 0x31,        //     Usage (Y)
    0x15, 0x81,        //     Logical Minimum (-127)
    0x25, 0x7F,        //     Logical Maximum (127)
    0x75, 0x08,        //     Report Size (8)
    0x95, 0x02,        //     Report Count (2)
    0x81, 0x06,        //     Input (Data, Variable, Relative)

    // Vertical scroll wheel — INT8 relative
    0x09, 0x38,        //     Usage (Wheel)
    0x15, 0x81,        //     Logical Minimum (-127)
    0x25, 0x7F,        //     Logical Maximum (127)
    0x75, 0x08,        //     Report Size (8)
    0x95, 0x01,        //     Report Count (1)
    0x81, 0x06,        //     Input (Data, Variable, Relative)

    // Horizontal scroll — INT8 relative (Consumer page, AC Pan usage 0x0238)
    0x05, 0x0C,        //     Usage Page (Consumer Devices)
    0x0A, 0x38, 0x02,  //     Usage (0x0238 AC Pan) — 2-byte extended usage
    0x15, 0x81,        //     Logical Minimum (-127)
    0x25, 0x7F,        //     Logical Maximum (127)
    0x75, 0x08,        //     Report Size (8)
    0x95, 0x01,        //     Report Count (1)
    0x81, 0x06,        //     Input (Data, Variable, Relative)

    0xC0,              //   End Collection (Physical)
    0xC0,              // End Collection (Application)

    // ----------------------------------------------------------------
    // TLC2: Vendor-Defined Battery (Usage Page 0xFF00, Usage 0x14)
    // Report ID 0x90 — matches raw BT device battery report exactly.
    // MagicMouseTray reads buf[2] = battery% via HidD_GetInputReport(COL02).
    // ----------------------------------------------------------------
    0x06, 0x00, 0xFF,  // Usage Page (Vendor-Defined 0xFF00)
    0x09, 0x14,        // Usage (0x14)
    0xA1, 0x01,        // Collection (Application)
    0x85, 0x90,        //   Report ID (0x90)
    0x09, 0x01,        //   Usage (0x01) — flags byte
    0x09, 0x02,        //   Usage (0x02) — battery% byte
    0x15, 0x00,        //   Logical Minimum (0)
    0x26, 0xFF, 0x00,  //   Logical Maximum (255)
    0x75, 0x08,        //   Report Size (8)
    0x95, 0x02,        //   Report Count (2)
    0x81, 0x02,        //   Input (Data, Variable, Absolute)
    0xC0,              // End Collection
};

const ULONG g_HidDescriptorSize = sizeof(g_HidDescriptor);

VOID
HidDescriptor_Handle(
    _In_ WDFREQUEST Request,
    _In_ size_t     OutputBufferLength)
{
    // IOCTL_HID_GET_REPORT_DESCRIPTOR uses METHOD_NEITHER.
    // Output buffer is in Irp->UserBuffer; length is from the IRP stack location.
    PIRP irp = WdfRequestWdmGetIrp(Request);
    PVOID outBuffer = irp->UserBuffer;

    if (outBuffer == NULL) {
        WdfRequestComplete(Request, STATUS_INVALID_PARAMETER);
        return;
    }

    if (OutputBufferLength < g_HidDescriptorSize) {
        // Caller passed insufficient buffer — tell it how much is needed
        irp->IoStatus.Information = g_HidDescriptorSize;
        WdfRequestComplete(Request, STATUS_BUFFER_TOO_SMALL);
        return;
    }

    RtlCopyMemory(outBuffer, g_HidDescriptor, g_HidDescriptorSize);
    irp->IoStatus.Information = g_HidDescriptorSize;
    WdfRequestComplete(Request, STATUS_SUCCESS);
}
