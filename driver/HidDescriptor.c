// SPDX-License-Identifier: MIT
//
// Custom HID report descriptor for Apple Magic Mouse 2024 (PID 0x0323).
//
// Empirical basis (2026-04-29 reverse engineering):
//   Apple's applewirelessmouse.sys binary contains a 116-byte HID descriptor
//   at offset 0xA850 declaring the Mouse TLC with Report ID 0x02 and AC Pan
//   (Consumer 0x0238) embedded INSIDE the Mouse TLC alongside X/Y/Wheel.
//   The Magic Mouse 2024 firmware natively synthesizes scroll deltas and
//   emits them on RID=0x02 — Apple's filter does NO command injection,
//   only descriptor replacement. We mirror that exact pattern.
//
// Two top-level collections:
//
//   TLC1 (Report ID 0x02) — Generic Desktop Mouse (0x01/0x02)
//     5 buttons + INT8 X/Y + INT8 AC Pan + INT8 Wheel
//     Full report buffer: [0x02, buttons, X, Y, AC_Pan, WheelV] = 6 bytes
//     mouhid.sys consumes; AC Pan within a Mouse TLC produces WM_MOUSEHWHEEL.
//
//   TLC2 (Report ID 0x90) — Vendor-Defined Battery (0xFF00/0x14)
//     2 input bytes [flags, battery%]
//     Full report buffer: [0x90, flags, battery_%] = 3 bytes
//     MagicMouseTray reads buf[2] = battery% via HidD_GetInputReport.
//
// Note: the previous 3-TLC layout (RID=0x01 Mouse / RID=0x02 Consumer-only /
// RID=0x90 Vendor) did not match Apple's working pattern. The firmware
// emits RID=0x02 frames natively; declaring RID=0x01 produced a phantom
// COL01 that mouhid opened exclusive but the device never wrote to,
// blocking scroll. This descriptor declares ONE Mouse TLC at RID=0x02
// with AC Pan + Wheel embedded, mirroring Apple's binary.

#include "HidDescriptor.h"

const UCHAR g_HidDescriptor[] = {
    // ----------------------------------------------------------------
    // TLC1: Generic Desktop Mouse (Usage Page 0x01, Usage 0x02)
    // Report ID 0x02 | InputReportByteLength = 5 ([buttons, X, Y, ACPan, Wheel])
    // ----------------------------------------------------------------
    0x05, 0x01,       // Usage Page (Generic Desktop)
    0x09, 0x02,       // Usage (Mouse)
    0xA1, 0x01,       // Collection (Application)
    0x85, 0x02,       //   Report ID (2)

    0x09, 0x01,       //   Usage (Pointer)
    0xA1, 0x00,       //   Collection (Physical)

    // 5 buttons — 5 × 1-bit fields + 3-bit padding = 1 byte
    0x05, 0x09,       //     Usage Page (Button)
    0x19, 0x01,       //     Usage Minimum (Button 1)
    0x29, 0x05,       //     Usage Maximum (Button 5)
    0x15, 0x00,       //     Logical Minimum (0)
    0x25, 0x01,       //     Logical Maximum (1)
    0x75, 0x01,       //     Report Size (1)
    0x95, 0x05,       //     Report Count (5)
    0x81, 0x02,       //     Input (Data, Variable, Absolute)
    0x75, 0x03,       //     Report Size (3) — padding
    0x95, 0x01,       //     Report Count (1)
    0x81, 0x03,       //     Input (Constant)

    // X / Y — INT8 relative
    0x05, 0x01,       //     Usage Page (Generic Desktop)
    0x09, 0x30,       //     Usage (X)
    0x09, 0x31,       //     Usage (Y)
    0x15, 0x81,       //     Logical Minimum (-127)
    0x25, 0x7F,       //     Logical Maximum (127)
    0x75, 0x08,       //     Report Size (8)
    0x95, 0x02,       //     Report Count (2)
    0x81, 0x06,       //     Input (Data, Variable, Relative)

    // AC Pan (Consumer 0x0238) — INT8 relative, embedded inside Mouse TLC
    // per Apple's binary descriptor. Produces WM_MOUSEHWHEEL.
    0x05, 0x0C,       //     Usage Page (Consumer Devices)
    0x0A, 0x38, 0x02, //     Usage (AC Pan 0x0238) — 2-byte extended usage
    0x15, 0x81,       //     Logical Minimum (-127)
    0x25, 0x7F,       //     Logical Maximum (127)
    0x75, 0x08,       //     Report Size (8)
    0x95, 0x01,       //     Report Count (1)
    0x81, 0x06,       //     Input (Data, Variable, Relative)

    // Vertical Wheel (Generic Desktop 0x38) — INT8 relative
    0x05, 0x01,       //     Usage Page (Generic Desktop)
    0x09, 0x38,       //     Usage (Wheel)
    0x15, 0x81,       //     Logical Minimum (-127)
    0x25, 0x7F,       //     Logical Maximum (127)
    0x75, 0x08,       //     Report Size (8)
    0x95, 0x01,       //     Report Count (1)
    0x81, 0x06,       //     Input (Data, Variable, Relative)

    0xC0,             //   End Collection (Physical)
    0xC0,             // End Collection (Application)

    // ----------------------------------------------------------------
    // TLC2: Vendor-Defined Battery (Usage Page 0xFF00, Usage 0x14)
    // Report ID 0x90 — matches raw BT device battery report.
    // MagicMouseTray reads buf[2] = battery% via HidD_GetInputReport.
    // ----------------------------------------------------------------
    0x06, 0x00, 0xFF, // Usage Page (Vendor-Defined 0xFF00)
    0x09, 0x14,       // Usage (0x14)
    0xA1, 0x01,       // Collection (Application)
    0x85, 0x90,       //   Report ID (0x90)
    0x09, 0x01,       //   Usage (0x01) — flags byte
    0x09, 0x02,       //   Usage (0x02) — battery% byte
    0x15, 0x00,       //   Logical Minimum (0)
    0x26, 0xFF, 0x00, //   Logical Maximum (255)
    0x75, 0x08,       //   Report Size (8)
    0x95, 0x02,       //   Report Count (2)
    0x81, 0x02,       //   Input (Data, Variable, Absolute)
    0xC0,             // End Collection
};

const ULONG g_HidDescriptorSize = sizeof(g_HidDescriptor);
