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

// Completion routine for BRB_L2CA_CLOSE_CHANNEL.
// Clears the channel handle from DEVICE_CONTEXT only on NT_SUCCESS — avoids a race
// where a reconnect re-opens before BthEnum finishes tearing down the old channel.
EVT_WDF_REQUEST_COMPLETION_ROUTINE InputHandler_CloseChannelCompletion;

// Completion routine for BRB_L2CA_ACL_TRANSFER.
// Stateless SDP scan + descriptor patch on ACL transfers; no Report 0x12 translation;
// no per-channel branching. Scans every incoming transfer for the SDP attribute 0x0206
// (HIDDescriptorList) byte pattern. If found, replaces the embedded descriptor with
// g_HidDescriptor[] in-place and updates the SDP TLV length fields. All other transfers
// pass through unchanged.
EVT_WDF_REQUEST_COMPLETION_ROUTINE InputHandler_AclCompletion;
