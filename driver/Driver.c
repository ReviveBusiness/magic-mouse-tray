// SPDX-License-Identifier: MIT
#include "Driver.h"
#include "HidDescriptor.h"
#include "InputHandler.h"

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
