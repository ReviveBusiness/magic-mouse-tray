// SPDX-License-Identifier: MIT
#pragma once
#include "Driver.h"

// Forward IOCTL_HID_READ_REPORT to BthEnum with a completion routine.
// The completion routine translates Report 0x12 (raw multi-touch) → Report 0x01
// (standard mouse: X/Y + vertical/horizontal scroll). Report 0x90 passes through.
VOID InputHandler_ForwardWithCompletion(_In_ WDFDEVICE Device, _In_ WDFREQUEST Request);

// Completion routine — called when BthEnum delivers a raw BT HID report.
EVT_WDF_REQUEST_COMPLETION_ROUTINE InputHandler_OnReadComplete;
