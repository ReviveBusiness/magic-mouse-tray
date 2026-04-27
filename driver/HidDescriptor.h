// SPDX-License-Identifier: MIT
#pragma once
#include "Driver.h"

// Size of the custom HID report descriptor (TLC1 + TLC2)
extern const UCHAR  g_HidDescriptor[];
extern const ULONG  g_HidDescriptorSize;

VOID HidDescriptor_Handle(_In_ WDFREQUEST Request, _In_ size_t OutputBufferLength);
