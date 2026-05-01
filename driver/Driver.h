// SPDX-License-Identifier: MIT
//
// M13 — Magic Mouse 2024 KMDF lower filter, SDP descriptor injection.
//
// Stack position (lower filter between BTHENUM and HidBth):
//   HidClass → HidBth → [M13 (this)] → BTHENUM
//
// Mechanism (confirmed 2026-04-30 by Ghidra RE of applewirelessmouse.sys
// SHA-256 08F33D7E... FUN_14000A440):
//
//   Apple's driver intercepts IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE (0x410210)
//   in a completion routine and rewrites SDP attribute 0x0206 (HIDDescriptorList)
//   with its own 116-byte descriptor. M13 replicates this mechanism but injects
//   Descriptor C — RID=0x02 scroll mouse + RID=0x90 vendor battery — giving
//   both scroll AND battery readout on Magic Mouse 2024 (PID 0x0323).
//
// Why M12 failed:
//   M12 intercepted IOCTL_INTERNAL_BTH_SUBMIT_BRB (0x410003). BRB submits carry
//   L2CAP connection/transfer traffic but NOT the SDP attribute response that
//   carries the HID descriptor. The SDP layer is above that. Wrong IOCTL.

#pragma once

#include <ntddk.h>
#include <wdf.h>

// 'M13D' little-endian — pool tag for all M13 allocations
#define M13_POOL_TAG 'D31M'

// IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE
// CTL_CODE(FILE_DEVICE_BLUETOOTH=0x41, Function=0x84, METHOD_BUFFERED=0, FILE_ANY_ACCESS=0)
// Confirmed via RE: FUN_14000A440 checks Irp+0xB8+0x18 (IoControlCode) against this value.
#define IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE 0x00410210UL

// --------------------------------------------------------------------------
// Device context — per-device state
// --------------------------------------------------------------------------

typedef struct _DEVICE_CONTEXT
{
    WDFSPINLOCK Lock;   // protects all mutable fields below

    // Configuration: read from Services\MagicMouseDriver\Parameters at AddDevice.
    // Default TRUE (inject) if Parameters key or value is absent.
    BOOLEAN EnableInjection;

    // Diagnostic counters (inspectable via Services\MagicMouseDriver\Diag).
    ULONG   IoctlInterceptCount;   // 0x410210 IOCTLs intercepted
    ULONG   SdpScanHits;           // attribute 0x0206 pattern found in buffer
    ULONG   SdpPatchSuccess;       // descriptor replacement succeeded
    ULONG   LastSdpBufSize;        // size of most recent SDP output buffer
    ULONG   LastPatchStatus;       // NTSTATUS of most recent PatchSdpHidDescriptor
    UCHAR   LastSdpBytes[64];      // first 64 raw bytes of most recent SDP buffer

    WDFTIMER    DiagTimer;         // 1 Hz periodic
    WDFWORKITEM DiagWorkItem;      // PASSIVE_LEVEL flush to registry

} DEVICE_CONTEXT, *PDEVICE_CONTEXT;

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, GetDeviceContext)

// --------------------------------------------------------------------------
// Function declarations
// --------------------------------------------------------------------------

DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_DEVICE_ADD               EvtDeviceAdd;
EVT_WDF_IO_QUEUE_IO_INTERNAL_DEVICE_CONTROL EvtIoInternalDeviceControl;
EVT_WDF_IO_QUEUE_IO_DEVICE_CONTROL      EvtIoDeviceControl;
EVT_WDF_IO_QUEUE_IO_DEFAULT             EvtIoDefault;
EVT_WDF_REQUEST_COMPLETION_ROUTINE      OnSdpQueryComplete;
EVT_WDF_TIMER                           M13_DiagTimerFunc;
EVT_WDF_WORKITEM                        M13_DiagWorkItemFunc;
