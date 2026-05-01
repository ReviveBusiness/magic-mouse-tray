// SPDX-License-Identifier: MIT
#include "Driver.h"
#include "InputHandler.h"   // SdpRewrite_Process

// --------------------------------------------------------------------------
// DriverEntry
// --------------------------------------------------------------------------

NTSTATUS
DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath)
{
    WDF_DRIVER_CONFIG config;
    WDF_DRIVER_CONFIG_INIT(&config, EvtDeviceAdd);
    return WdfDriverCreate(DriverObject, RegistryPath, WDF_NO_OBJECT_ATTRIBUTES,
                           &config, WDF_NO_HANDLE);
}

// --------------------------------------------------------------------------
// EvtDeviceAdd — bind as lower filter, read config, start diagnostic timer
// --------------------------------------------------------------------------

NTSTATUS
EvtDeviceAdd(_In_ WDFDRIVER Driver, _Inout_ PWDFDEVICE_INIT DeviceInit)
{
    UNREFERENCED_PARAMETER(Driver);

    WdfFdoInitSetFilter(DeviceInit);

    WDF_OBJECT_ATTRIBUTES devAttr;
    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&devAttr, DEVICE_CONTEXT);

    WDFDEVICE device;
    NTSTATUS status = WdfDeviceCreate(&DeviceInit, &devAttr, &device);
    if (!NT_SUCCESS(status)) { return status; }

    PDEVICE_CONTEXT ctx = GetDeviceContext(device);

    WDF_OBJECT_ATTRIBUTES lockAttr;
    WDF_OBJECT_ATTRIBUTES_INIT(&lockAttr);
    lockAttr.ParentObject = device;
    status = WdfSpinLockCreate(&lockAttr, &ctx->Lock);
    if (!NT_SUCCESS(status)) { return status; }

    // Read EnableInjection from Parameters registry subkey.
    // Default TRUE — missing key/value means "enabled".
    ctx->EnableInjection = TRUE;
    {
        WDFKEY paramsKey = NULL;
        NTSTATUS ks = WdfDriverOpenParametersRegistryKey(
            Driver, KEY_READ, WDF_NO_OBJECT_ATTRIBUTES, &paramsKey);
        if (NT_SUCCESS(ks) && paramsKey != NULL)
        {
            ULONG val = 1;
            UNICODE_STRING valName;
            RtlInitUnicodeString(&valName, L"EnableInjection");
            NTSTATUS vs = WdfRegistryQueryULong(paramsKey, &valName, &val);
            if (NT_SUCCESS(vs))
            {
                ctx->EnableInjection = (val != 0);
            }
            WdfRegistryClose(paramsKey);
        }
    }

    DbgPrint("M13: AddDevice — EnableInjection=%d\n", ctx->EnableInjection);

    // Diagnostic 1 Hz timer (parent = device, fires M13_DiagTimerFunc)
    WDF_TIMER_CONFIG timerCfg;
    WDF_TIMER_CONFIG_INIT_PERIODIC(&timerCfg, M13_DiagTimerFunc, 1000);
    WDF_OBJECT_ATTRIBUTES timerAttr;
    WDF_OBJECT_ATTRIBUTES_INIT(&timerAttr);
    timerAttr.ParentObject = device;
    status = WdfTimerCreate(&timerCfg, &timerAttr, &ctx->DiagTimer);
    if (!NT_SUCCESS(status)) { return status; }

    // Work item for PASSIVE_LEVEL registry writes (parent = device)
    WDF_WORKITEM_CONFIG wiCfg;
    WDF_WORKITEM_CONFIG_INIT(&wiCfg, M13_DiagWorkItemFunc);
    WDF_OBJECT_ATTRIBUTES wiAttr;
    WDF_OBJECT_ATTRIBUTES_INIT(&wiAttr);
    wiAttr.ParentObject = device;
    status = WdfWorkItemCreate(&wiCfg, &wiAttr, &ctx->DiagWorkItem);
    if (!NT_SUCCESS(status)) { return status; }

    WdfTimerStart(ctx->DiagTimer, WDF_REL_TIMEOUT_IN_MS(1000));

    // Default I/O queue — parallel dispatch.
    // EvtIoDeviceControl: intercept IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE (0x410210)
    //   sent as IRP_MJ_DEVICE_CONTROL by applewirelessmouse.sys/HidBth.sys.
    // EvtIoInternalDeviceControl: same intercept via IRP_MJ_INTERNAL_DEVICE_CONTROL
    //   (covers both dispatch types; only one fires per request).
    // EvtIoDefault: passthrough for all other IRP types (READ, WRITE, etc.)
    //   so we don't break the device stack for non-SDP traffic.
    WDF_IO_QUEUE_CONFIG qCfg;
    WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(&qCfg, WdfIoQueueDispatchParallel);
    qCfg.EvtIoDeviceControl         = EvtIoDeviceControl;
    qCfg.EvtIoInternalDeviceControl = EvtIoInternalDeviceControl;
    qCfg.EvtIoDefault               = EvtIoDefault;
    WDFQUEUE queue;
    return WdfIoQueueCreate(device, &qCfg, WDF_NO_OBJECT_ATTRIBUTES, &queue);
}

// --------------------------------------------------------------------------
// EvtIoInternalDeviceControl
//
// Intercepts IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE (0x410210) and forwards
// it with a completion routine to rewrite the SDP output buffer.
// All other IOCTLs pass through send-and-forget.
// --------------------------------------------------------------------------

VOID
EvtIoInternalDeviceControl(_In_ WDFQUEUE Queue, _In_ WDFREQUEST Request,
                            _In_ size_t OutputBufferLength, _In_ size_t InputBufferLength,
                            _In_ ULONG IoControlCode)
{
    UNREFERENCED_PARAMETER(OutputBufferLength);
    UNREFERENCED_PARAMETER(InputBufferLength);

    WDFDEVICE    device = WdfIoQueueGetDevice(Queue);
    PDEVICE_CONTEXT ctx = GetDeviceContext(device);
    WDFIOTARGET  target = WdfDeviceGetIoTarget(device);

    if (IoControlCode == IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE &&
        ctx != NULL && ctx->EnableInjection)
    {
        WdfSpinLockAcquire(ctx->Lock);
        ctx->IoctlInterceptCount++;
        WdfSpinLockRelease(ctx->Lock);

        // Forward with our completion routine so we can rewrite the output buffer.
        WdfRequestFormatRequestUsingCurrentType(Request);
        WdfRequestSetCompletionRoutine(Request, OnSdpQueryComplete, ctx);
        if (!WdfRequestSend(Request, target, WDF_NO_SEND_OPTIONS))
        {
            WdfRequestComplete(Request, WdfRequestGetStatus(Request));
        }
        return;
    }

    // Passthrough — send-and-forget.
    WdfRequestFormatRequestUsingCurrentType(Request);
    WDF_REQUEST_SEND_OPTIONS opts;
    WDF_REQUEST_SEND_OPTIONS_INIT(&opts, WDF_REQUEST_SEND_OPTION_SEND_AND_FORGET);
    if (!WdfRequestSend(Request, target, &opts))
    {
        WdfRequestComplete(Request, WdfRequestGetStatus(Request));
    }
}

// --------------------------------------------------------------------------
// EvtIoDeviceControl — IRP_MJ_DEVICE_CONTROL intercept
//
// IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE is sent by applewirelessmouse.sys
// via IRP_MJ_DEVICE_CONTROL. Same logic as EvtIoInternalDeviceControl.
// --------------------------------------------------------------------------

VOID
EvtIoDeviceControl(_In_ WDFQUEUE Queue, _In_ WDFREQUEST Request,
                   _In_ size_t OutputBufferLength, _In_ size_t InputBufferLength,
                   _In_ ULONG IoControlCode)
{
    UNREFERENCED_PARAMETER(OutputBufferLength);
    UNREFERENCED_PARAMETER(InputBufferLength);

    WDFDEVICE    device = WdfIoQueueGetDevice(Queue);
    PDEVICE_CONTEXT ctx = GetDeviceContext(device);
    WDFIOTARGET  target = WdfDeviceGetIoTarget(device);

    if (IoControlCode == IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE &&
        ctx != NULL && ctx->EnableInjection)
    {
        WdfSpinLockAcquire(ctx->Lock);
        ctx->IoctlInterceptCount++;
        WdfSpinLockRelease(ctx->Lock);

        WdfRequestFormatRequestUsingCurrentType(Request);
        WdfRequestSetCompletionRoutine(Request, OnSdpQueryComplete, ctx);
        if (!WdfRequestSend(Request, target, WDF_NO_SEND_OPTIONS))
        {
            WdfRequestComplete(Request, WdfRequestGetStatus(Request));
        }
        return;
    }

    WdfRequestFormatRequestUsingCurrentType(Request);
    WDF_REQUEST_SEND_OPTIONS opts;
    WDF_REQUEST_SEND_OPTIONS_INIT(&opts, WDF_REQUEST_SEND_OPTION_SEND_AND_FORGET);
    if (!WdfRequestSend(Request, target, &opts))
    {
        WdfRequestComplete(Request, WdfRequestGetStatus(Request));
    }
}

// --------------------------------------------------------------------------
// EvtIoDefault — passthrough for all non-IOCTL I/O requests
//
// WDF filter drivers with a default queue must explicitly forward any IRP
// types not otherwise handled (READ, WRITE, etc.) or WDF completes them
// with STATUS_INVALID_DEVICE_REQUEST, breaking the device.
// --------------------------------------------------------------------------

VOID
EvtIoDefault(_In_ WDFQUEUE Queue, _In_ WDFREQUEST Request)
{
    WDFDEVICE   device = WdfIoQueueGetDevice(Queue);
    WDFIOTARGET target = WdfDeviceGetIoTarget(device);

    WdfRequestFormatRequestUsingCurrentType(Request);
    WDF_REQUEST_SEND_OPTIONS opts;
    WDF_REQUEST_SEND_OPTIONS_INIT(&opts, WDF_REQUEST_SEND_OPTION_SEND_AND_FORGET);
    if (!WdfRequestSend(Request, target, &opts))
    {
        WdfRequestComplete(Request, WdfRequestGetStatus(Request));
    }
}

// --------------------------------------------------------------------------
// OnSdpQueryComplete — completion routine for IOCTL 0x410210
//
// Retrieves the SDP attribute response buffer, calls SdpRewrite_Process to
// find and replace the HIDDescriptorList (attribute 0x0206), then completes
// the request. If rewrite is not applicable (attribute not found, or buffer
// parse fails), completes with the original unmodified buffer and status.
// --------------------------------------------------------------------------

VOID
OnSdpQueryComplete(_In_ WDFREQUEST Request, _In_ WDFIOTARGET Target,
                   _In_ PWDF_REQUEST_COMPLETION_PARAMS Params, _In_ WDFCONTEXT Context)
{
    UNREFERENCED_PARAMETER(Target);

    PDEVICE_CONTEXT ctx    = (PDEVICE_CONTEXT)Context;
    NTSTATUS        status = Params->IoStatus.Status;

    if (!NT_SUCCESS(status) || ctx == NULL)
    {
        WdfRequestComplete(Request, status);
        return;
    }

    // METHOD_BUFFERED: output buffer is Irp->AssociatedIrp.SystemBuffer.
    PVOID  buf         = NULL;
    size_t bufAllocLen = 0;
    NTSTATUS rs = WdfRequestRetrieveOutputBuffer(Request, 1, &buf, &bufAllocLen);
    if (!NT_SUCCESS(rs) || buf == NULL)
    {
        WdfRequestComplete(Request, status);
        return;
    }

    // IoStatus.Information = bytes actually written by lower driver.
    size_t sdpLen = Params->IoStatus.Information;
    if (sdpLen == 0 || sdpLen > bufAllocLen)
    {
        WdfRequestComplete(Request, status);
        return;
    }

    // Snapshot first 64 bytes + buffer size for offline diagnosis.
    WdfSpinLockAcquire(ctx->Lock);
    ctx->LastSdpBufSize = (ULONG)sdpLen;
    ULONG snapLen = (sdpLen < 64) ? (ULONG)sdpLen : 64;
    RtlCopyMemory(ctx->LastSdpBytes, buf, snapLen);
    if (snapLen < 64) RtlZeroMemory(ctx->LastSdpBytes + snapLen, 64 - snapLen);
    WdfSpinLockRelease(ctx->Lock);

    // Attempt descriptor rewrite.
    ULONG    newLen      = (ULONG)sdpLen;
    NTSTATUS patchStatus = SdpRewrite_Process((PUCHAR)buf, (ULONG)sdpLen, &newLen);

    // Update diagnostic counters.
    WdfSpinLockAcquire(ctx->Lock);
    ctx->LastPatchStatus = (ULONG)patchStatus;
    if (patchStatus == STATUS_SUCCESS)
    {
        ctx->SdpScanHits++;
        ctx->SdpPatchSuccess++;
    }
    else if (patchStatus == STATUS_MORE_PROCESSING_REQUIRED)
    {
        // Pattern found but patch validation failed.
        ctx->SdpScanHits++;
    }
    // STATUS_NOT_FOUND: no HIDDescriptorList in this buffer — normal, no counter.
    WdfSpinLockRelease(ctx->Lock);

    // If patch shrunk the buffer, update IoStatus.Information for the caller.
    if (patchStatus == STATUS_SUCCESS && newLen != (ULONG)sdpLen)
    {
        WdfRequestSetInformation(Request, (ULONG_PTR)newLen);
    }

    WdfRequestComplete(Request, status);
}

// --------------------------------------------------------------------------
// Diagnostic timer + work item — 1 Hz flush to registry
//
// Registry path: HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Diag
//
// Keys written (read with Get-ItemProperty in PowerShell to verify driver):
//   IoctlInterceptCount  REG_DWORD  — 0x410210 IOCTLs seen
//   SdpScanHits          REG_DWORD  — attribute 0x0206 found
//   SdpPatchSuccess      REG_DWORD  — descriptor replaced successfully
//   LastSdpBufSize       REG_DWORD  — size of last SDP buffer
//   LastPatchStatusHex   REG_DWORD  — NTSTATUS of last patch attempt
//   LastSdpBytes         REG_BINARY — first 64 bytes of last SDP buffer
// --------------------------------------------------------------------------

VOID M13_DiagTimerFunc(_In_ WDFTIMER Timer)
{
    WDFDEVICE device = (WDFDEVICE)WdfTimerGetParentObject(Timer);
    PDEVICE_CONTEXT ctx = GetDeviceContext(device);
    if (ctx != NULL && ctx->DiagWorkItem != NULL)
        WdfWorkItemEnqueue(ctx->DiagWorkItem);
}

VOID M13_DiagWorkItemFunc(_In_ WDFWORKITEM WorkItem)
{
    WDFDEVICE device = (WDFDEVICE)WdfWorkItemGetParentObject(WorkItem);
    PDEVICE_CONTEXT ctx = GetDeviceContext(device);
    if (ctx == NULL) return;

    // Snapshot under lock, then write registry at PASSIVE_LEVEL unlocked.
    ULONG ictlCount, scanHits, patchOk, lastSize, lastStatus;
    UCHAR lastBytes[64];
    WdfSpinLockAcquire(ctx->Lock);
    ictlCount  = ctx->IoctlInterceptCount;
    scanHits   = ctx->SdpScanHits;
    patchOk    = ctx->SdpPatchSuccess;
    lastSize   = ctx->LastSdpBufSize;
    lastStatus = ctx->LastPatchStatus;
    RtlCopyMemory(lastBytes, ctx->LastSdpBytes, 64);
    WdfSpinLockRelease(ctx->Lock);

    UNICODE_STRING keyPath;
    RtlInitUnicodeString(&keyPath,
        L"\\Registry\\Machine\\SYSTEM\\CurrentControlSet\\Services\\MagicMouseDriver\\Diag");
    OBJECT_ATTRIBUTES attr;
    InitializeObjectAttributes(&attr, &keyPath,
                               OBJ_CASE_INSENSITIVE | OBJ_KERNEL_HANDLE, NULL, NULL);
    HANDLE key   = NULL;
    ULONG  disp  = 0;
    if (!NT_SUCCESS(ZwCreateKey(&key, KEY_WRITE, &attr, 0, NULL,
                                REG_OPTION_NON_VOLATILE, &disp))) return;

    UNICODE_STRING n;

#define SET_DWORD(Name, Val) \
    RtlInitUnicodeString(&n, Name); \
    ZwSetValueKey(key, &n, 0, REG_DWORD, &(Val), sizeof(ULONG))

    SET_DWORD(L"IoctlInterceptCount", ictlCount);
    SET_DWORD(L"SdpScanHits",         scanHits);
    SET_DWORD(L"SdpPatchSuccess",     patchOk);
    SET_DWORD(L"LastSdpBufSize",      lastSize);
    SET_DWORD(L"LastPatchStatusHex",  lastStatus);

#undef SET_DWORD

    RtlInitUnicodeString(&n, L"LastSdpBytes");
    ZwSetValueKey(key, &n, 0, REG_BINARY, lastBytes, 64);

    ZwClose(key);
}
