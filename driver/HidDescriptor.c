// SPDX-License-Identifier: MIT
//
// Custom HID report descriptor for Apple Magic Mouse 2024 (PID 0x0323).
//
// Three top-level collections (TLCs) — all with explicit Report IDs:
//
//   TLC1 (Report ID 0x01) — Generic Desktop Mouse (0x01/0x02)
//     3 buttons + X/Y + vertical wheel
//     InputReportByteLength = 4  ([buttons, X, Y, WheelV])
//     Full report buffer: [0x01, buttons, X, Y, WheelV]
//     Owned exclusively by mouhid.sys. TranslateTouch() emits this.
//
//   TLC2 (Report ID 0x02) — Consumer Control (0x0C/0x01)
//     AC Pan (0x0238) — horizontal scroll only
//     InputReportByteLength = 1  ([WheelH])
//     Full report buffer: [0x02, WheelH]
//     Opened shared by the Windows HID consumer driver. TranslateTouch()
//     emits this for horizontal scroll.
//     NOTE: AC Pan MUST be in a separate Consumer TLC. Mouse TLCs are
//     opened exclusive by mouhid; Consumer TLCs are shared. Windows does
//     not permit mixing usage pages with conflicting access modes in one TLC.
//
//   TLC3 (Report ID 0x90) — Vendor-Defined Battery (0xFF00/0x14)
//     Matches raw BT device battery report exactly.
//     InputReportByteLength = 2  ([flags, battery_%])
//     Full report buffer: [0x90, flags, battery_%]
//     MagicMouseTray enumerates by UsagePage=0xFF00, Usage=0x14 and reads
//     buf[2] = battery% via HidD_GetInputReport — works regardless of
//     whether this is COL02 or COL03.
//
// Total descriptor size: 113 bytes (64 + 24 + 25)

#include "HidDescriptor.h"

const UCHAR g_HidDescriptor[] = {
    // ----------------------------------------------------------------
    // TLC1: Generic Desktop Mouse (Usage Page 0x01, Usage 0x02)
    // Report ID 0x01 | InputReportByteLength = 4
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

    // Vertical scroll wheel — INT8 relative (Generic Desktop Wheel 0x38)
    0x09, 0x38,        //     Usage (Wheel)
    0x15, 0x81,        //     Logical Minimum (-127)
    0x25, 0x7F,        //     Logical Maximum (127)
    0x75, 0x08,        //     Report Size (8)
    0x95, 0x01,        //     Report Count (1)
    0x81, 0x06,        //     Input (Data, Variable, Relative)

    0xC0,              //   End Collection (Physical)
    0xC0,              // End Collection (Application)

    // ----------------------------------------------------------------
    // TLC2: Consumer Control (Usage Page 0x0C, Usage 0x01)
    // Report ID 0x02 | InputReportByteLength = 1
    // AC Pan (0x0238) is the horizontal scroll axis. Must live in its own
    // Consumer TLC — cannot be nested inside the exclusive Mouse TLC above.
    // ----------------------------------------------------------------
    0x05, 0x0C,        // Usage Page (Consumer Devices)
    0x09, 0x01,        // Usage (Consumer Control)
    0xA1, 0x01,        // Collection (Application)
    0x85, 0x02,        //   Report ID (2)
    0x0A, 0x38, 0x02,  //   Usage (AC Pan 0x0238) — 2-byte extended usage, little-endian
    0x15, 0x81,        //   Logical Minimum (-127)
    0x25, 0x7F,        //   Logical Maximum (127)
    0x75, 0x08,        //   Report Size (8)
    0x95, 0x01,        //   Report Count (1)
    0x81, 0x06,        //   Input (Data, Variable, Relative)
    0xC0,              // End Collection (Application)

    // ----------------------------------------------------------------
    // TLC3: Vendor-Defined Battery (Usage Page 0xFF00, Usage 0x14)
    // Report ID 0x90 — matches raw BT device battery report exactly.
    // MagicMouseTray reads buf[2] = battery% via HidD_GetInputReport.
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
    // NOTE: This function intercepts IOCTL_HID_GET_REPORT_DESCRIPTOR using
    // METHOD_NEITHER (output in Irp->UserBuffer). This interception mechanism
    // is PENDING REVISION — a lower filter below HidBth does not receive this
    // IOCTL (absorbed by hidclass.sys). The correct approach is BRB-level
    // interception of the Bluetooth HID descriptor exchange. See plan Phase 3.
    PIRP irp = WdfRequestWdmGetIrp(Request);
    PVOID outBuffer = irp->UserBuffer;

    if (outBuffer == NULL) {
        WdfRequestComplete(Request, STATUS_INVALID_PARAMETER);
        return;
    }

    if (OutputBufferLength < g_HidDescriptorSize) {
        irp->IoStatus.Information = g_HidDescriptorSize;
        WdfRequestComplete(Request, STATUS_BUFFER_TOO_SMALL);
        return;
    }

    RtlCopyMemory(outBuffer, g_HidDescriptor, g_HidDescriptorSize);
    irp->IoStatus.Information = g_HidDescriptorSize;
    WdfRequestComplete(Request, STATUS_SUCCESS);
}
