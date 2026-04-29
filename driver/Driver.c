// SPDX-License-Identifier: MIT
#define INITGUID
#include <initguid.h>
#include "Driver.h"
#include "InputHandler.h"

// {94A59AA8-4383-4286-AA4F-34A160F40004}
DEFINE_GUID(GUID_BTHDDI_PROFILE_DRIVER_INTERFACE_LOCAL,
            0x94a59aa8, 0x4383, 0x4286, 0xaa, 0x4f, 0x34, 0xa1, 0x60, 0xf4, 0x0, 0x4);

NTSTATUS
DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath)
{
    WDF_DRIVER_CONFIG config;
    WDF_DRIVER_CONFIG_INIT(&config, EvtDeviceAdd);
    return WdfDriverCreate(DriverObject, RegistryPath, WDF_NO_OBJECT_ATTRIBUTES, &config,
                           WDF_NO_HANDLE);
}

NTSTATUS
EvtDeviceAdd(_In_ WDFDRIVER Driver, _Inout_ PWDFDEVICE_INIT DeviceInit)
{
    UNREFERENCED_PARAMETER(Driver);

    WdfFdoInitSetFilter(DeviceInit);

    WDF_OBJECT_ATTRIBUTES deviceAttributes;
    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&deviceAttributes, DEVICE_CONTEXT);

    WDFDEVICE device;
    NTSTATUS status = WdfDeviceCreate(&DeviceInit, &deviceAttributes, &device);
    if (!NT_SUCCESS(status))
    {
        return status;
    }

    // Initialize spinlock to protect DEVICE_CONTEXT channel-handle fields against
    // concurrent OPEN/CLOSE completion routines on a parallel-dispatch queue.
    PDEVICE_CONTEXT devCtx = GetDeviceContext(device);
    WDF_OBJECT_ATTRIBUTES lockAttr;
    WDF_OBJECT_ATTRIBUTES_INIT(&lockAttr);
    lockAttr.ParentObject = device;
    status = WdfSpinLockCreate(&lockAttr, &devCtx->Lock);
    if (!NT_SUCCESS(status))
    {
        return status;
    }

    // Query the Bluetooth profile driver interface from the underlying bus
    // stack. Provides BthAllocateBrb / BthFreeBrb / BthInitializeBrb / BthReuseBrb,
    // which we use to construct outgoing SET_REPORT BRBs for multi-touch enable.
    // Failure is non-fatal — we just skip the SET_REPORT injection path.
    devCtx->BthIface.Interface.Size = sizeof(BTH_PROFILE_DRIVER_INTERFACE);
    devCtx->BthIface.Interface.Version =
        BTHDDI_PROFILE_DRIVER_INTERFACE_VERSION_FOR_QI;
    NTSTATUS qiStatus = WdfFdoQueryForInterface(
        device,
        &GUID_BTHDDI_PROFILE_DRIVER_INTERFACE_LOCAL,
        (PINTERFACE)&devCtx->BthIface,
        sizeof(BTH_PROFILE_DRIVER_INTERFACE),
        BTHDDI_PROFILE_DRIVER_INTERFACE_VERSION_FOR_QI,
        NULL);
    devCtx->BthIfaceValid = NT_SUCCESS(qiStatus) &&
                            devCtx->BthIface.BthAllocateBrb != NULL &&
                            devCtx->BthIface.BthFreeBrb != NULL;

    // Diagnostic trace work item + 1Hz periodic timer (from InputHandler.c).
    WDF_WORKITEM_CONFIG wiConfig;
    WDF_WORKITEM_CONFIG_INIT(&wiConfig, InputHandler_TraceWorkItemFunc);
    WDF_OBJECT_ATTRIBUTES wiAttr;
    WDF_OBJECT_ATTRIBUTES_INIT(&wiAttr);
    wiAttr.ParentObject = device;
    status = WdfWorkItemCreate(&wiConfig, &wiAttr, &devCtx->TraceWorkItem);
    if (!NT_SUCCESS(status))
    {
        return status;
    }

    WDF_TIMER_CONFIG timerConfig;
    WDF_TIMER_CONFIG_INIT_PERIODIC(&timerConfig,
                                   InputHandler_TraceTimerFunc, 1000);
    WDF_OBJECT_ATTRIBUTES timerAttr;
    WDF_OBJECT_ATTRIBUTES_INIT(&timerAttr);
    timerAttr.ParentObject = device;
    status = WdfTimerCreate(&timerConfig, &timerAttr, &devCtx->TraceTimer);
    if (!NT_SUCCESS(status))
    {
        return status;
    }
    WdfTimerStart(devCtx->TraceTimer, WDF_REL_TIMEOUT_IN_MS(1000));

    // Internal device control queue — handles IRP_MJ_INTERNAL_DEVICE_CONTROL,
    // which carries IOCTL_INTERNAL_BTH_SUBMIT_BRB (0x00410003) from HidBth to BthEnum.
    WDF_IO_QUEUE_CONFIG queueConfig;
    WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(&queueConfig, WdfIoQueueDispatchParallel);
    queueConfig.EvtIoInternalDeviceControl = EvtIoInternalDeviceControl;

    WDFQUEUE queue;
    status = WdfIoQueueCreate(device, &queueConfig, WDF_NO_OBJECT_ATTRIBUTES, &queue);
    return status;
}

VOID EvtIoInternalDeviceControl(_In_ WDFQUEUE Queue, _In_ WDFREQUEST Request,
                                _In_ size_t OutputBufferLength, _In_ size_t InputBufferLength,
                                _In_ ULONG IoControlCode)
{
    UNREFERENCED_PARAMETER(OutputBufferLength);
    UNREFERENCED_PARAMETER(InputBufferLength);

    WDFDEVICE device = WdfIoQueueGetDevice(Queue);

    if (IoControlCode == IOCTL_INTERNAL_BTH_SUBMIT_BRB)
    {
        InputHandler_HandleBrbSubmit(device, Request);
        return;
    }

    // All other IOCTLs pass through untouched.
    WdfRequestFormatRequestUsingCurrentType(Request);
    WDF_REQUEST_SEND_OPTIONS opts;
    WDF_REQUEST_SEND_OPTIONS_INIT(&opts, WDF_REQUEST_SEND_OPTION_SEND_AND_FORGET);
    if (!WdfRequestSend(Request, WdfDeviceGetIoTarget(device), &opts))
    {
        WdfRequestComplete(Request, WdfRequestGetStatus(Request));
    }
}
