// SPDX-License-Identifier: MIT
// Magic Mouse 2024 KMDF Lower Filter Driver
// Replaces applewirelessmouse.sys: returns a custom HID descriptor that preserves
// both the scroll collection (COL01) and battery collection (COL02) on every
// enumeration, eliminating the descriptor-strip conflict.
//
// Stack position (between BthEnum and HidBth):
//   HidClass → HidBth → [MagicMouseDriver (this)] → BthEnum
//
// Two interception points:
//   IOCTL_HID_GET_REPORT_DESCRIPTOR: complete immediately with custom descriptor
//   IOCTL_HID_READ_REPORT:           forward + translate Report 0x12 on completion

#pragma once

#include <ntddk.h>
#include <wdf.h>

// HID IOCTL codes (from WDK hidport.h / FILE_DEVICE_KEYBOARD=0x0B, METHOD_NEITHER=3)
// Verified: IOCTL_HID_GET_REPORT_DESCRIPTOR = 0x000B0083 (confirmed by baseline test 2026-04-26)
#ifndef IOCTL_HID_GET_REPORT_DESCRIPTOR
#define IOCTL_HID_GET_REPORT_DESCRIPTOR  0x000B0083UL
#endif
#ifndef IOCTL_HID_READ_REPORT
#define IOCTL_HID_READ_REPORT            0x000B000FUL  // verify at first build
#endif

// Report IDs
#define MM_REPORT_ID_TOUCH    0x12   // Raw multi-touch report from BT device
#define MM_REPORT_ID_MOUSE    0x01   // Standard mouse report ID in our descriptor (TLC1)
#define MM_REPORT_ID_BATTERY  0x90   // Battery report — pass through unchanged (TLC2)

// TLC1 output report layout (what we emit from InputHandler):
//   [0] = 0x01  Report ID
//   [1] = buttons bitmask (bits 0-2: L/R/Middle, bits 3-7: padding)
//   [2] = X delta  (INT8, -127..127, relative)
//   [3] = Y delta  (INT8, -127..127, relative)
//   [4] = Wheel vertical  (INT8, scroll up/down)
//   [5] = Wheel horizontal (INT8, AC Pan, scroll left/right)
#define MM_MOUSE_REPORT_LEN   6

// Device context (reserved for per-device state if needed)
typedef struct _DEVICE_CONTEXT {
    ULONG Reserved;
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, GetDeviceContext)

// Function declarations
DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_DEVICE_ADD EvtDeviceAdd;
EVT_WDF_IO_QUEUE_IO_INTERNAL_DEVICE_CONTROL EvtIoInternalDeviceControl;
