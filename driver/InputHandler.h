// SPDX-License-Identifier: MIT
#pragma once
#include "Driver.h"

// Handle IRP_MJ_INTERNAL_DEVICE_CONTROL with IOCTL_INTERNAL_BTH_SUBMIT_BRB (0x00410003).
// Reads BRB_HEADER.Type from the BRB at Parameters.Others.Argument1 and dispatches:
//   BRB_L2CA_OPEN_CHANNEL / OPEN_CHANNEL_RESPONSE → forward + completion to store handle
//   BRB_L2CA_CLOSE_CHANNEL → read and clear stored handle, forward
//   BRB_L2CA_ACL_TRANSFER  → forward + completion to intercept/translate data buffer
//   All others             → pass through (send-and-forget)
VOID InputHandler_HandleBrbSubmit(_In_ WDFDEVICE Device, _In_ WDFREQUEST Request);

// Completion routine for BRB_L2CA_OPEN_CHANNEL and BRB_L2CA_OPEN_CHANNEL_RESPONSE.
// Reads the output ChannelHandle from the completed BRB and stores it in DEVICE_CONTEXT.
// First open → ControlChannelHandle. Second → InterruptChannelHandle.
EVT_WDF_REQUEST_COMPLETION_ROUTINE InputHandler_OpenChannelCompletion;

// Completion routine for BRB_L2CA_ACL_TRANSFER.
// - Incoming data on ControlChannel:  inject g_HidDescriptor[] (first occurrence only).
// - Incoming data on InterruptChannel: translate Report 0x12 → Report 0x01 (TLC1 mouse).
// - All other data: pass through unchanged.
EVT_WDF_REQUEST_COMPLETION_ROUTINE InputHandler_AclCompletion;
