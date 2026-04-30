# M12 Senior Driver Review -- 2026-04-28

## BLUF

CHANGES-NEEDED. The architecture is sound and the clean-room approach is correct, but
there are four issues that will cause production failures before a single IRP is
processed: a critical WDF queue dispatch mismatch that exposes a use-after-free on read
completion, a synchronous WdfIoTargetSendIoctlSynchronously call that will deadlock
under Driver Verifier and possibly in production, a missing WdfRequestStopAcknowledge
that guarantees BSOD on device unplug during active poll, and an IoTarget creation gap
that produces a blank descriptor on the first IOCTL_HID_GET_REPORT_DESCRIPTOR call
during AddDevice. None are architectural; all are fixable before implementation begins.

---

## Reviewer perspective

Senior Windows kernel driver developer, 10+ years KMDF experience, shipped HID filter
drivers in production (BT HID, USB HID, two-sided filter chains). Adversarial lens --
looking for what breaks in production, under Driver Verifier, on unplug, and at boot.
The review is keyed against WDF 1.33 API surface (as shipped in EWDK 25H2) with
backward-compat notes for KMDF 1.15 (the design's pinned minimum).

---

## Scope of review

- docs/M12-DESIGN-SPEC.md (untracked in ai/m12-design-prd-mop, generated 2026-04-28,
  38770 bytes, 669 lines, reviewed in full)
- docs/M12-MOP.md -- NOT YET PRODUCED at time of review. MOP-specific comments are
  flagged as provisional.
- Reference material: /tmp/m12-refs/hid-magicmouse.c (Linux GPL-2 reference, 32 KB),
  M12-APPLEWIRELESSMOUSE-FINDINGS.md (Phase 1 Ghidra), M12-REFERENCE-INDEX.md (Phase
  1 references)

---

## Critical issues (BLOCK merge)

### CRIT-1: WDF parallel queue + completion routine = use-after-free on read completion

Location: Section 8 (queue layout) + Section 3b (inbound data flow)

What is wrong:
The design places IOCTL_HID_READ_REPORT on a PARALLEL dispatch queue and says
"M12's EvtIoInternalDeviceControl sees IOCTL_HID_READ_REPORT completion at the
bottom of its parallel queue." There is no IOCTL_HID_READ_REPORT completion routine
defined in the function signatures (Section 9). The design does define
OnReadComplete (EVT_WDF_REQUEST_COMPLETION_ROUTINE) but Section 3b describes
M12 completing the IRP upstream after synthesising a Mode A buffer -- it does NOT
describe forwarding the IRP downward and registering a completion callback.

The actual sequence for a lower filter receiving IOCTL_HID_READ_REPORT is:
  1. HidClass sends IRP DOWN to lower filter's IoInternalDeviceControl handler.
  2. Filter forwards IRP to IoTarget (HidBth) with a completion routine.
  3. Completion routine fires when device delivers data.
  4. Completion routine inspects, translates, then calls WdfRequestComplete upstream.

If the design instead calls WdfRequestForwardToIoQueue to enqueue the read request
while simultaneously forwarding it to the IoTarget, the request object can be
completed by both paths independently -- that is a double-complete UAF.

If the design tries to complete the IRP inside EvtIoInternalDeviceControl BEFORE
forwarding it (i.e., synthesises a response without reading from device), that
contradicts the flow in Section 3b which reads vendor report 0x12 from device output.

The design conflates two incompatible patterns:
  - Pattern A: intercept IRP in EvtIo*, forward to lower target, hook completion.
  - Pattern B: synthesise IRP response in EvtIo* directly from cached data.

Pattern A is required for IOCTL_HID_READ_REPORT (we need actual device data).
Pattern B is required for IOCTL_HID_GET_REPORT_DESCRIPTOR (static buffer).
The design mixes them in the parallel queue description without separating which
IOCTL gets which pattern. This ambiguity will produce wrong code.

Why it breaks production:
Double-complete on a WDFREQUEST with Driver Verifier active = immediate bugcheck
0xC4 (DRIVER_VERIFIER_DETECTED_VIOLATION). Without DV, it is a use-after-free
that corrupts the pool and may not manifest until the third unplug or a HidClass
retry. Silent corruption is worse than a crash.

Recommended fix:
Rewrite Section 8 to explicitly state:
  - IOCTL_HID_READ_REPORT: forward with WdfRequestForwardToIoQueue disabled;
    instead forward directly via WdfIoTargetSendInternalIoctlSynchronously or
    (preferred) async via WdfRequestSend with a completion callback
    (EVT_WDF_REQUEST_COMPLETION_ROUTINE OnReadComplete). The completion callback
    inspects the buffer, translates if report is 0x12/0x29/0x90, then calls
    WdfRequestComplete upstream.
  - IOCTL_HID_GET_REPORT_DESCRIPTOR / IOCTL_HID_GET_DEVICE_DESCRIPTOR / etc.:
    intercept and short-circuit in EvtIo*, complete with static buffer immediately,
    never forward.
Add a data-flow diagram for each IOCTL code showing forward/complete path.

---

### CRIT-2: WdfIoTargetSendIoctlSynchronously in IOCTL dispatch context = deadlock

Location: Section 7b (active-poll path), HandleGetFeature47_ActivePoll pseudocode

What is wrong:
The active-poll path calls WdfIoTargetSendIoctlSynchronously with
WDF_REQUEST_SEND_OPTION_SYNCHRONOUS from inside EvtIoDeviceControl (the
sequential IOCTL queue handler). This is explicitly prohibited by KMDF documentation
for IoTargets whose target lives in the same device stack. The call will:
  a) On a WDM stack that is not marked as synchronous-safe, deadlock the thread
     forever (or until the 500ms timeout fires and returns STATUS_TIMEOUT, but
     ONLY if the timeout is actually honoured -- Bluetooth stacks sometimes do not
     cancel the IRP on timeout).
  b) Under Driver Verifier with Deadlock Detection enabled, immediately bugcheck.
  c) On a power-managed IoTarget, block if the device is in a low-power state
     and you call from DispatchLevel -- impossible here since EvtIoDeviceControl
     is PASSIVE_LEVEL, but the HidBth target transitions to D3 during BT radio
     off events.

The root cause: WdfIoTargetSendIoctlSynchronously sends the IOCTL and WAITS
synchronously. If the lower stack (HidBth) is also waiting for M12 to do something
(e.g. HidClass has a pending request it has sent down that M12 has not yet completed),
you have a wait cycle.

Why it breaks production:
On BT reconnect (common after sleep/wake -- the most common user action with a Magic
Mouse), the sequential queue will have a pending GET_FEATURE call from the tray app.
M12 will block synchronously waiting for the device, while HidClass may be waiting
for M12 to drain its read queue. Deadlock, 500ms timeout, STATUS_TIMEOUT returned
upstream. Tray shows N/A. If the timeout is missed, the thread leaks. Under DV
deadlock detection: BSOD.

Recommended fix:
Convert HandleGetFeature47_ActivePoll to an ASYNC pattern:
  1. In EvtIoDeviceControl, if cache is stale, create a new WDFREQUEST via
     WdfRequestCreate, set a completion callback, send to IoTarget via WdfRequestSend
     (no WDF_REQUEST_SEND_OPTION_SYNCHRONOUS).
  2. Do NOT call WdfRequestComplete on the original GET_FEATURE request yet.
  3. In the completion callback for the 0x90 probe IRP, extract the battery value,
     update cache, complete the original GET_FEATURE request.
  4. Use WdfRequestMarkCancelable on the original GET_FEATURE so it can be
     cancelled if the tray closes the handle while waiting.
  5. Alternatively, use the cached-only approach: if cache is stale, return
     STATUS_DEVICE_BUSY or STATUS_TIMEOUT upstream immediately, and rely on
     the unsolicited Input 0x90 stream (Section 7a) to refresh the cache on
     the next BT input cycle. This is simpler and avoids creating a new IRP
     entirely. The design already acknowledges (OQ-2) that the cache-hit ratio
     may be high enough.

---

### CRIT-3: Missing WdfRequestStopAcknowledge = BSOD on device unplug

Location: Section 3b (inbound data flow), Section 8 (queue layout), Section 11 F10

What is wrong:
The parallel read queue forwards IOCTL_HID_READ_REPORT to the IoTarget. KMDF
requires that when the device is removed (PnP surprise-remove, unplug, BT disconnect),
the framework calls EvtIoStop on any queue that has in-flight requests. The handler
MUST call WdfRequestStopAcknowledge (with or without requeue depending on whether
the request was already forwarded to IoTarget). If EvtIoStop is not registered, the
default behaviour is to let the framework stall waiting for the request to complete
-- except the IoTarget is already gone, so the completion never fires, and the
framework deadlocks during device removal. This manifests as a hung devnode in
Device Manager and eventually a system hang or BSOD during session shutdown or
driver uninstall.

The design defines no EvtIoStop callback anywhere in Sections 8, 9, or 11. F10
acknowledges a "PnP rebalance / stop / remove" scenario but the mitigation is
"brief N/A visible in tray" -- it does not address what happens to in-flight
IOCTL_HID_READ_REPORT requests on the IoTarget when the BT device is removed.

Why it breaks production:
BT disconnect is a normal user action. Magic Mouse goes to sleep after 2 minutes of
inactivity. Every sleep cycle = device removal. If there is a pending read IRP in the
parallel queue at that moment (which there always is -- HidClass keeps one pending
at all times to receive the next input report), the missing EvtIoStop leaves a
stranded IRP attached to a dead IoTarget. The framework's cleanup path hangs.
Observed symptom: Device Manager shows the mouse as "removing" indefinitely; tray
process becomes unkillable; reboot required.

Recommended fix:
Register EvtIoStop on both queues:
  a) For the parallel read queue: in EvtIoStop, call WdfIoTargetCancelSentRequests
     on the IoTarget, then call WdfRequestStopAcknowledge(Request, FALSE) to tell
     the framework to not requeue (the request will be completed with STATUS_CANCELLED
     by the IoTarget cancel). OR if the request was not yet forwarded, call
     WdfRequestStopAcknowledge(Request, TRUE) to requeue for later.
  b) For the sequential IOCTL queue: in EvtIoStop, call WdfRequestStopAcknowledge
     (the IOCTL handlers are short and PASSIVE_LEVEL so they will drain quickly).
  c) Register EvtDeviceSelfManagedIoSuspend and call WdfIoTargetStop on the IoTarget
     before the PnP remove IRP is processed.

---

### CRIT-4: IoTarget not ready at first IOCTL_HID_GET_REPORT_DESCRIPTOR

Location: Section 3b (descriptor delivery), Section 11 F2, EvtDeviceAdd flow

What is wrong:
Section 3b says "HidClass issues IOCTL_HID_GET_REPORT_DESCRIPTOR down the stack
at device init." Section 11 F2 acknowledges this race: "AddDevice race: HidClass
calls GET_REPORT_DESCRIPTOR before IoTarget is up." The mitigation is: "Initialise
g_HidDescriptor[] as static const; queue IoTarget creation in EvtDevicePrepareHardware."

The problem is that KMDF's EvtDevicePrepareHardware fires AFTER EvtDeviceAdd returns.
HidClass is a FDO that issues IOCTL_HID_GET_REPORT_DESCRIPTOR as part of its own
EvtDeviceAdd processing -- which runs AFTER the filter's EvtDeviceAdd but BEFORE
EvtDevicePrepareHardware of the filter fires. The ordering is:

  1. Filter EvtDeviceAdd -- M12 sets up queues, returns STATUS_SUCCESS.
  2. HidClass EvtDeviceAdd -- HidClass issues GET_REPORT_DESCRIPTOR down to M12.
  3. M12's EvtIoDeviceControl handles GET_REPORT_DESCRIPTOR -- if IoTarget not yet
     initialised, what does the code do?
  4. Filter EvtDevicePrepareHardware -- IoTarget created here.

The static g_HidDescriptor[] mitigates this correctly FOR THE DESCRIPTOR CONTENT
(the design is right that a static buffer is safe). But Section 3b also says M12
"bypasses" the downstream descriptor fetch -- meaning it must NOT forward this IOCTL
to the lower IoTarget. If the code tries to forward it when IoTarget is NULL, that
is a NULL dereference BSOD.

The design does not specify what the code does when IoTarget is NULL. The pseudocode
in Section 7c (ForwardRequest) accesses ctx->IoTarget without a NULL check. If
ForwardRequest is called for a non-descriptor IOCTL during the window before
EvtDevicePrepareHardware (e.g., GET_DEVICE_ATTRIBUTES, GET_DEVICE_DESCRIPTOR), and
IoTarget is not yet populated, that is a NULL dereference.

Why it breaks production:
The GET_REPORT_DESCRIPTOR handling itself is safe (static buffer, no IoTarget needed).
But GET_DEVICE_DESCRIPTOR and GET_DEVICE_ATTRIBUTES (also issued by HidClass during
AddDevice) will reach the ForwardRequest path with a NULL IoTarget if the design does
not defend against it. NULL dereference in kernel mode = bugcheck 0x50 or 0x3B.

Recommended fix:
  a) In ForwardRequest, add an NT_ASSERT / early-out: if IoTarget is NULL, complete
     request with STATUS_DEVICE_NOT_READY.
  b) Mark IoTarget as an optional field initialised to NULL in DEVICE_CONTEXT;
     check for NULL before any use.
  c) Consider moving IoTarget creation into EvtDeviceAdd after WdfFdoInitSetFilter,
     using WdfDeviceGetIoTarget(device) to obtain the default IoTarget (which is
     always valid after EvtDeviceAdd). For a lower filter, the default IoTarget
     IS the lower device -- no separate initialisation required in
     EvtDevicePrepareHardware. This eliminates the race entirely.

---

## Major issues (CHANGES-NEEDED)

### MAJ-1: Descriptor byte layout discrepancy: Mode A vs applewirelessmouse.sys

Location: Sections 5, 5a; Phase 1 findings (M12-APPLEWIRELESSMOUSE-FINDINGS.md)

The design's descriptor (Section 5a) targets the Magic Utilities Mode A layout:
8-bit X/Y, 16-bit Wheel, 16-bit AC Pan, Resolution Multiplier Feature reports
RID 0x03 and 0x04. This is correct per the empirical capture.

However, the applewirelessmouse.sys descriptor (Phase 1, Section Q3) uses a
DIFFERENT layout: 8-bit Wheel, 8-bit AC Pan, NO Resolution Multiplier features,
vendor bit in input report, Feature 0x47 declared. The design explicitly chooses
the MU Mode A layout over the Apple Mode B layout. This is a deliberate choice
with known tradeoff (scroll wheel precision).

The review concern is this sentence in Section 5b: "No Feature 0x47 in the
descriptor." Combined with Section 7c: tray calls HidD_GetFeature(0x47) and
HidClass passes the IOCTL down even if the descriptor does not declare it.

Empirically (Phase 1 finding): when applewirelessmouse.sys declares Feature 0x47
in its descriptor but does NOT intercept the IRP, the result is err=87. The design
plans to intercept the IRP in the completion path -- but if the descriptor does NOT
declare the ReportID, will HidClass even pass the IOCTL down?

HidClass's behaviour: HidClass validates the ReportID against the parsed descriptor
before issuing IOCTL_HID_GET_FEATURE downstream. If 0x47 is not in the preparsed
data, HidClass will return ERROR_INVALID_PARAMETER to the caller before the IOCTL
ever reaches M12. The tray's HidD_GetFeature(0x47) call will fail at the HidClass
level, never reaching M12's intercept code.

Recommended fix:
Add Feature 0x47 to the Mode A descriptor (following the applewirelessmouse.sys
pattern, Section Q3 of Phase 1 findings). The descriptor byte sequence is available
verbatim: "05 06 09 20 85 47 15 00 25 64 75 08 95 01 B1 A2". This does NOT break
the Mode A scroll -- it adds 8 bytes to the descriptor. OQ-3 partially addresses
this but the design does not resolve it -- it defers to "confirm during MOP step
VG-1." This should be resolved in the design, not left open, because the
implementation decision (declare vs not declare 0x47 in descriptor) changes the
IRP routing path.

---

### MAJ-2: Scroll algorithm signed integer promotion bug

Location: Section 6c (scroll synthesis), Step 4

The design's scroll algorithm pseudocode:

  step_x /= (64 - scroll_speed) * scroll_accel;

scroll_speed is typed as UCHAR (0..63). (64 - scroll_speed) can produce a value
of 1 to 64. scroll_accel is INT (1..4). The division result is assigned back to
step_x which is INT.

The Linux original uses int scroll_speed (signed). The design uses UCHAR (unsigned).
In C, UCHAR promoted to INT in arithmetic. (64 - (UCHAR)scroll_speed) is fine.
But scroll_speed could be set to 0 via registry: then (64 - 0) * 4 = 256. Step
is divided by 256 -- at 12-bit touch coordinates (max +/-2048) that produces step=0
for all but the fastest gestures. Scroll becomes non-functional at speed=0.

Worse: scroll_speed is read from registry at EvtDeviceAdd. If an adversarial user
sets MagicMouseDriver\Parameters\ScrollSpeed to 64 (or any value >=64), (64 - 64)
= 0. Division by zero in kernel mode = bugcheck 0xC4 or undefined behaviour.

Recommended fix:
  a) Clamp ScrollSpeed at read time: if (val >= 64) val = 32; (default)
  b) Assert: ASSERT((64 - ctx->ScrollSpeed) > 0);
  c) Or use the Linux idiom: check step == 0 before dividing (the Linux code
     checks step_x != 0 BEFORE the scroll_speed division, not after, meaning
     it only divides if step_x is already nonzero -- re-read Section 6c, the
     design's pseudocode inverts this order).

The Linux code: step_x /= (64 - scroll_speed) * scroll_accel; then checks
if (step_x != 0). The design's pseudocode says "step_x /= ..." without a
pre-divide check. If scroll_speed is max valid value 63 then divisor is 1*1=1
(fine). But registry can be set to 64 or higher.

---

### MAJ-3: WdfRequestRetrieveInputBuffer used for IOCTL_HID_GET_FEATURE output buffer

Location: Section 7c (PID branch pseudocode)

The pseudocode:
  NTSTATUS s = WdfRequestRetrieveInputBuffer(req, sizeof(*pkt), (PVOID*)&pkt, NULL);

IOCTL_HID_GET_FEATURE is METHOD_OUT_DIRECT (or METHOD_BUFFERED depending on the
hidclass IOCTL definition). For the HID internal IOCTLs, the transfer packet
(HID_XFER_PACKET) is passed as the output buffer, not the input buffer.
WdfRequestRetrieveInputBuffer retrieves the system buffer for the input side.
The correct call for IOCTL_HID_GET_FEATURE at the filter level is:
WdfRequestRetrieveOutputBuffer (to get the HID_XFER_PACKET that HidClass placed
in the output buffer) OR WdfRequestGetParameters to inspect the Type3InputBuffer
for NEITHER-method IOCTLs.

The internal HID IOCTLs (IOCTL_HID_GET_FEATURE, IOCTL_HID_READ_REPORT, etc.)
are IRP_MJ_INTERNAL_DEVICE_CONTROL, METHOD_NEITHER. The packet pointer is in
Parameters.Others.Arg1 (Type3InputBuffer). Using WdfRequestRetrieveInputBuffer
returns STATUS_BUFFER_TOO_SMALL or garbage -- it is the wrong API.

Recommended fix:
For METHOD_NEITHER internal IOCTLs, retrieve the packet via:
  WDF_REQUEST_PARAMETERS params;
  WDF_REQUEST_PARAMETERS_INIT(&params);
  WdfRequestGetParameters(req, &params);
  HID_XFER_PACKET *pkt = (HID_XFER_PACKET *)params.Parameters.Others.Arg1;
Then validate pkt != NULL and pkt->reportBufferLen >= required size.

This is the standard pattern for HID filter drivers handling internal IOCTLs.
The Linux driver doesn't deal with this (it uses a completely different IRP model)
so the design has no reference implementation to catch this.

---

### MAJ-4: Battery active-poll uses IOCTL_HID_GET_INPUT_REPORT; v3 does not back RID 0x90 as Input

Location: Section 7b (active-poll path)

The design says: "M12 issues a downstream IOCTL_HID_GET_INPUT_REPORT for ReportID
0x90." Phase 1 findings (M12-APPLEWIRELESSMOUSE-FINDINGS.md, Section Q4) say v3
firmware does NOT respond to Feature 0x47 feature requests. The design infers v3
backs RID 0x90 as a GET_INPUT_REPORT -- but this is an open question, not a
confirmed fact.

More specifically: in applewirelessmouse.sys, Feature 0x47 is declared in the
descriptor with B1 A2 (Feature, Data, Variable, Absolute). The tray calls
HidD_GetFeature(0x47). The result is err=87. The design interprets this as "the
device doesn't back Feature 0x47, but DOES back Input 0x90 -- we can poll 0x90
instead." The evidence for "DOES back Input 0x90" is Section 7a: "When v3 emits
an unsolicited Input report 0x90..." This implies 0x90 is unsolicited (pushed
by device), not polled.

IOCTL_HID_GET_INPUT_REPORT is a synchronous request to the device to send a
specific input report. If v3 pushes 0x90 unsolicited but does NOT respond to
GET_INPUT_REPORT for 0x90, the active-poll path returns STATUS_TIMEOUT every time.
OQ-2 acknowledges this uncertainty. The design leaves it open. The concern is that
the active-poll pseudocode (Section 7b) will be coded before this is empirically
confirmed, and if the GET_INPUT_REPORT path fails, the fallback to STATUS_NOT_FOUND
upstream means the tray never sees battery on a cold start (no cached value yet,
active poll fails).

Recommended fix:
This is an open question that must be resolved empirically before implementation
(not after, as the design currently stages it). The resolution changes whether the
active-poll path should:
  a) Use GET_INPUT_REPORT for 0x90 (if device responds synchronously), OR
  b) Use a short wait loop on the cached 0x90 Input from the input stream (Section
     7a), triggering a keepalive if none received in last N seconds (simpler and
     avoids the IRP creation entirely).
Mark this as a design-resolution gate, not an implementation-time question.

---

### MAJ-5: No pool tag declared anywhere in the design

Location: Sections 9, 10 (function signatures, data structures)

The design mentions ExAllocatePoolWithTag (Phase 1 reference import list) but
defines no pool tag in any data structure or function signature. For a KMDF driver,
WDF objects are auto-tagged by the framework. But any manual allocations
(e.g. a scratch buffer for the 0x90 probe, a copy of the HID_XFER_PACKET for async
use) need explicit tags.

Without pool tags, pool leak debugging (WinDbg !poolused, !pool) cannot isolate
M12 allocations. Driver Verifier's pool tracking cannot attribute allocations.

Recommended fix:
Define in Driver.h:
  #define MM_POOL_TAG 'MmMM'   /* 4-char tag: MmMM (Magic Mouse) */
Require all ExAllocatePoolWithTag calls to use this tag.
Add to Section 9 or 10 as a project constant.

---

### MAJ-6: IOCTL_HID_GET_REPORT_DESCRIPTOR bypass does not confirm downstream call is suppressed

Location: Section 3b (descriptor delivery), Section 4c (class)

The design says "HidBth's downstream descriptor fetch is bypassed for this IOCTL."
In a lower-filter architecture, M12 sits BELOW HidClass. HidClass sends
IOCTL_HID_GET_REPORT_DESCRIPTOR DOWN to M12. M12 must complete this IRP with the
static descriptor WITHOUT forwarding it further down to HidBth. The design confirms
this intent ("M12 intercepts, returns static descriptor").

The concern is the ForwardRequest function: if it blindly forwards any unmatched
IOCTL, a coding error where the GET_REPORT_DESCRIPTOR case is accidentally
omitted from the switch statement will result in M12 forwarding it to HidBth, which
returns the native (Mode B) descriptor. HidClass then sees Mode B instead of Mode A.
The tray sees 8-bit scroll wheel instead of 16-bit, and battery fails. This is a
silent misbehavior, not a crash -- it will be hard to diagnose.

Recommended fix:
  a) The switch on IOCTL code in EvtIoDeviceControl should have a DEFAULT case that
     logs the unexpected IOCTL code at TRACE_LEVEL_WARNING before forwarding.
  b) Add a debug-build ASSERT that the switch handles every IOCTL code documented
     in Section 8.
  c) Consider an explicit "do-not-forward" list: if the IOCTL is one of the four
     static-buffer IOCTLs, ASSERT that it was handled before reaching ForwardRequest.

---

## Minor issues (suggestions)

### MIN-1: HID_DESCRIPTOR vs HID_DEVICE_ATTRIBUTES -- two separate exports for v1 and v3

Section 9 declares:
  extern const HID_DEVICE_ATTRIBUTES g_HidDeviceAttributes_v1;
  extern const HID_DEVICE_ATTRIBUTES g_HidDeviceAttributes_v3;

Two separate static attributes structures implies the VID/PID reported upstream
varies by device. This is correct (the upstream HidClass needs the real VID/PID
for WinUSB/HidD identification). But if the driver also overrides the IOCTL_HID_GET_
DEVICE_ATTRIBUTES response with one of these static structures, it is lying to
HidClass about the device's VID/PID -- which breaks any userland code that identifies
the device by VID/PID via HidD_GetAttributes. The tray's existing VID/PID matching
code may or may not tolerate this. Recommend passing VID/PID through from the real
device attributes rather than declaring them statically, unless there is an
empirically confirmed reason to override.

### MIN-2: Descriptor byte layout: Logical Min/Max for Wheel is encoded as 3 bytes

Section 5a:
  15 81 FF         Logical Min (-32767, 16-bit)
  25 7F FF         Logical Max (32767)

HID 1.11 encoding rules: a 16-bit signed Logical Minimum requires the 3-byte form
(0x15 is 1-byte-follows; 0x16 is 2-bytes-follow). The correct encoding for -32767
(0xFF81) is: 16 81 FF (LOGICAL_MINIMUM with 2 bytes following). 15 81 FF is actually
LOGICAL_MINIMUM (1 byte = 0x81 = -127) followed by 0xFF as garbage. The descriptor
bytes are wrong for the 16-bit Wheel and AC Pan fields.

Check against the empirical HID capture at .ai/test-runs/2026-04-27-154930-T-V3-AF/
hid-descriptor-full-v3-col01.txt. Validate with hidparser.exe as specified in
Section 5a -- the validator should catch this. Ensure the implementation uses the
capture-verified bytes, not the spec's hand-written pseudobytes.

### MIN-3: TOUCH_STATE constants diverge from Linux source on state mask

Section 6a describes:
  tdata[7]: touch_state (low 4 bits: 0x10=hover/start, 0x20=transition,
             0x30=START, 0x40=DRAG)

Linux source (hid-magicmouse.c):
  #define TOUCH_STATE_MASK  0xf0   <-- HIGH 4 bits, not low 4 bits
  #define TOUCH_STATE_START 0x30
  #define TOUCH_STATE_DRAG  0x40

The mask is 0xf0 (high nibble), not 0x0f (low nibble). The design's comment
"low 4 bits" is wrong. The state field in tdata[7] is extracted as
(tdata[7] & TOUCH_STATE_MASK) = (tdata[7] & 0xf0). Implementation must use 0xf0.
This is a comment bug, not necessarily a code bug, but it will cause implementers
to write the wrong mask if they follow the spec.

### MIN-4: Tunable registry key path not namespaced under driver service key

Section 6c describes: "HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\
Parameters" for scroll tuning. This is correct per KMDF convention. No issue --
noting for completeness that this matches the KMDF registry path conventions and
is safe.

### MIN-5: INF FLG_ADDREG_APPEND vs FLG_ADDREG_TYPE_MULTI_SZ

Section 4b:
  HKR,,"LowerFilters",0x00010008,"MagicMouseDriver"

0x00010008 = FLG_ADDREG_TYPE_MULTI_SZ (0x00010000) | FLG_ADDREG_APPEND (0x00000008)

This is the correct flag for appending to an existing MULTI_SZ list -- it adds
MagicMouseDriver to any existing filters rather than replacing them. This is the
right pattern. However: if applewirelessmouse is still in LowerFilters from a
previous install (a real scenario during upgrade), both filters will be on the stack.
The design acknowledges this in F11, but the INF flag does not help purge the old
entry. The MOP (not yet produced) needs an explicit step to remove applewirelessmouse
from LowerFilters before M12 install. Flag it here as a MOP dependency.

---

## What the design got RIGHT

1. **Architecture choice: lower filter, not upper filter.** Lower filter is correct
   for descriptor mutation. Upper filter cannot intercept IOCTL_HID_GET_REPORT_
   DESCRIPTOR (that IOCTL goes to the function driver, not up the stack). The
   empirical evidence (MU, applewirelessmouse both use lower filter) is correctly
   applied. APPROVE for this decision.

2. **WdfFdoInitSetFilter placement.** Calling WdfFdoInitSetFilter in EvtDeviceAdd
   before WdfDeviceCreate is the correct KMDF pattern for filter drivers. This
   ensures M12 is not the power-policy owner. Correct.

3. **Static descriptor buffer for IOCTL_HID_GET_REPORT_DESCRIPTOR.** Using a
   static const array removes all race conditions from the descriptor delivery
   path. HidParser.exe pre-validation gate (F7) is excellent defensive practice.

4. **PID branch at EvtDeviceAdd time.** Reading the PID once at AddDevice and
   caching it in DEVICE_CONTEXT eliminates per-IRP PID lookups. The pattern is
   correct and the implementation detail (WdfDeviceQueryProperty + HardwareID) is
   the right API.

5. **KSPIN_LOCK for battery cache.** Using a spin lock for the battery cache
   read/write is the correct primitive at DISPATCH_LEVEL. The design's
   KeAcquireSpinLock / KeReleaseSpinLock pattern is correct. The sequential IOCTL
   queue provides additional serialization for the GET_FEATURE path.

6. **Failure mode table (Section 11).** The F1-F12 enumeration is thorough. F2
   (descriptor race), F7 (pre-install validation), F11 (filter rank conflict) and
   F12 (KMDF version skew) show real production awareness. Good engineering.

7. **INF Include/Needs pattern.** Using "Include=input.inf,hidbth.inf" and
   "Needs=HID_Inst.NT,HID_Inst.NT.Services" to inherit HidClass registration is
   correct and matches both MU and applewirelessmouse. This ensures HidClass is
   the function driver of record.

8. **KMDF 1.15 pinned minimum.** Pinning to KMDF 1.15 (Windows 10 era) instead
   of 1.33 avoids breaking on older W10 installs and matches the MU reference.
   Correct.

9. **Open questions catalogue (Section 12).** OQ-1 through OQ-5 are honest and
   correctly flagged as empirical questions. The discipline of NOT answering them
   before measurement is exactly right (anti-pattern AP-17: no premature delivery
   claim). OQ-2 (unsolicited 0x90 vs polled) and OQ-5 (Resolution Multiplier
   feature return value) are the most consequential.

10. **Clean-room legal framework.** The DMCA/Canada/EU interoperability exemption
    citations are specific and correct. The design correctly distinguishes
    "algorithm description" (allowed) from "source or binary copy" (prohibited).
    The AP-22/AP-23 anti-patterns are embedded in the design rationale. Correct.

---

## Specific topics reviewed (with verdict per topic)

### 1. KMDF queue dispatch type -- sequential vs parallel for IOCTL handling

Verdict: PARTIALLY CORRECT, see CRIT-1.
Sequential for GET_FEATURE / GET_DESCRIPTOR: correct. Parallel for READ_REPORT:
correct in principle but the interaction between the parallel queue and the
completion-routine forwarding pattern is underspecified and will produce either
a double-complete or a missed completion. The queue layout section needs explicit
per-IOCTL data-flow documentation. The function signature OnReadComplete exists
but is disconnected from the queue's async forwarding pattern in the prose.

### 2. IRP cancellation handling -- WdfRequestStopAcknowledge / WdfRequestComplete
       races on PnP teardown

Verdict: MISSING. CRIT-3.
No EvtIoStop defined. The parallel read queue will leak stranded IRPs on BT
disconnect. This is a guaranteed regression path in normal use (mouse goes to
sleep, BT disconnects, in-flight read IRP stranded). Must be added.

### 3. IOCTL input buffer validation -- bounds checks before RtlCopyMemory?
       METHOD_BUFFERED vs METHOD_NEITHER handling?

Verdict: PARTIALLY WRONG. MAJ-3.
The internal HID IOCTLs are METHOD_NEITHER (IRP_MJ_INTERNAL_DEVICE_CONTROL).
The design uses WdfRequestRetrieveInputBuffer, which is incorrect for this
IOCTL class. Bounds checking intent is present (outLen < 2 checks in Section
7a/7b) but the buffer retrieval API is wrong. For the descriptor path
(IOCTL_HID_GET_REPORT_DESCRIPTOR), WdfRequestRetrieveOutputBuffer is appropriate.
For the HID_XFER_PACKET path, WdfRequestGetParameters / Arg1 is required.

### 4. HID filter chain semantics -- IRP_MJ_INTERNAL_DEVICE_CONTROL forwarding?
       Lower-driver target acquisition pattern?

Verdict: CONCEPTUALLY CORRECT, mechanically underspecified.
The design correctly identifies M12 as a lower filter that intercepts
IRP_MJ_INTERNAL_DEVICE_CONTROL (via EvtIoInternalDeviceControl). The IoTarget
acquisition pattern is assigned to EvtDevicePrepareHardware / EvtDeviceAdd (CRIT-4
notes the timing issue). Using WdfDeviceGetIoTarget(device) in EvtDeviceAdd to
obtain the default lower target is the simplest correct approach and would close
CRIT-4. Not explicitly stated in the design.

### 5. Buffer overflow surface -- vendor input report 0x12 parsing (46-byte blob);
       is offset bounds-checked?

Verdict: ADEQUATE for the scrolling path; UNRESOLVED for battery extraction.
The 0x12 scroll report size validation (Section 6a) mirrors the Linux pattern
exactly and is correct: size check before any offset access, npoints <= 15 cap.
No buffer overflow on the scroll translation path.

The battery path reads from RID 0x27 (46-byte vendor blob). The design does NOT
specify the byte offset for battery percentage extraction in the 0x27 report -- this
is OQ-1 (open question). Phase 1 findings note the descriptor declares Min=1 Max=65
(not 0-100) suggesting a translation formula. No bounds check exists in the design
because the offset is not yet known. This means the implementation will contain
placeholder logic that must be filled in empirically. The bounds check should be
specified once OQ-1 is resolved: "if (offset >= 46) drop; pct = translate(buf[offset])."

### 6. Kernel pool tags -- design declares any?

Verdict: NOT DECLARED. MAJ-5.
No pool tag defined anywhere in the design. For a production driver, this is
a required debugging aid. Easy fix: add #define MM_POOL_TAG 'MmMM' to Driver.h.

### 7. Driver Verifier compatibility -- known patterns that DV will flag?

Verdict: THREE PATTERNS WILL FLAG. CRIT-2, CRIT-3, CRIT-4.
CRIT-2 (synchronous IoTarget send from IOCTL dispatch) will trigger DV deadlock
detection. CRIT-3 (missing EvtIoStop) will trigger DV IRP tracking. CRIT-4
(NULL IoTarget access) will trigger DV invalid IRQL / null reference checks.
Additionally, if the code uses ExAllocatePoolWithTag with NonPagedPool on KMDF 1.33,
DV will flag -- use NonPagedPoolNx (execute-disable). Design does not specify pool
type anywhere; add to guidance.

### 8. PnP rebalance / stop / remove handling -- does the design handle device
       unplug mid-IOCTL?

Verdict: INADEQUATE. CRIT-3.
Section 11 F10 mentions "PnP rebalance / stop / remove" and says "brief N/A" as
mitigation. The actual KMDF requirement (EvtIoStop, WdfRequestStopAcknowledge,
WdfIoTargetStop) is not addressed. This is a production gap, not a cosmetic one.

### 9. Build harness -- EWDK vs WDK11; signtool flags; INF version check

Verdict: ADEQUATE IN PRINCIPLE, UNVERIFIABLE (MOP not yet produced).
Section 11 F7 specifies "hidparser.exe from EWDK samples" as a pre-build gate.
Section 11 F12 specifies KMDF 1.15 pinned in vcxproj. Section 4 specifies INF
structure correctly. The MOP was not produced at review time, so signtool flags,
INF version check, and EWDK vs WDK11 choice cannot be verified. Provisional:
signtool should use /fd SHA256 /tr (RFC 3161 timestamp) /td SHA256 -- NOT /t
(legacy timestamp) which is SHA1 and rejected by Windows kernel at load time for
test-signed drivers on W11 22H2+.

### 10. MOP runnability -- are the MOP commands literally executable?

Verdict: NOT YET PRODUCED. Cannot assess.
The MOP was not present at review time. This item must be re-evaluated when Phase 2
produces M12-MOP.md. Flag for re-review.

---

## External T2 verdict (if obtained)

NOT OBTAINED. riley delegate was not invoked. The analysis in this document is
based on direct reading of the design spec, Phase 1 Ghidra findings, Linux
hid-magicmouse.c source, and KMDF API knowledge. The external T2 step was skipped
per the mission's early-exit condition ("riley delegate unavailable or skipped --
proceed with own analysis").

---

## Open questions for the design author

1. **Q1 [from CRIT-1]:** Which IRP handling pattern governs IOCTL_HID_READ_REPORT:
   (A) forward to IoTarget with async completion callback that translates and
   completes upstream, or (B) some other mechanism? The design's current prose
   is ambiguous. An explicit sequence diagram or numbered pseudocode for the
   read-report path would close this.

2. **Q2 [from CRIT-2]:** Is the active-poll path (HandleGetFeature47_ActivePoll)
   required to be synchronous from the perspective of the tray app? If the tray
   can tolerate a STATUS_DEVICE_BUSY response and will retry, the synchronous poll
   can be eliminated entirely and the cached-input path (Section 7a) is sufficient.
   This would also resolve MAJ-4.

3. **Q3 [from MAJ-1 / OQ-3]:** Does HidClass pass IOCTL_HID_GET_FEATURE for a
   ReportID that is not in the descriptor's preparsed data? If not, Feature 0x47
   MUST be declared in the Mode A descriptor. This must be confirmed against
   hidclass.sys behavior (ETW trace or kernel debugger) before the descriptor
   bytes are finalised.

4. **Q4 [from Phase 1 OQ-1]:** What is the battery byte offset and translation
   formula for the RID 0x27 vendor blob? The design cannot be implemented without
   this. The Phase 1 findings note Min=1 Max=65 in the descriptor, suggesting
   a non-trivial formula. This is the highest-priority empirical measurement.

5. **Q5 [from MIN-2]:** Are the descriptor bytes in Section 5a hand-written or
   copy-verified from the empirical capture? Specifically, the 16-bit Logical
   Min/Max encoding (15 vs 16 prefix byte) needs byte-by-byte comparison against
   the capture file before those bytes are hardcoded in HidDescriptor.c.

---

## Recommendations to incorporate in iteration round

Prioritized top 5:

1. **[CRIT-1 fix]** Rewrite Section 8 to separate IOCTL_HID_READ_REPORT forwarding
   (async, with completion callback) from static-response IOCTLs (immediate complete,
   no IoTarget access). Add an explicit data-flow diagram for each IOCTL code.
   This is the most architecturally impactful change and affects InputHandler.c
   and IoctlHandlers.c scope.

2. **[CRIT-3 fix]** Add EvtIoStop to Section 9 function signatures. Add EvtDeviceSelf-
   ManagedIoSuspend to call WdfIoTargetStop. Document in Section 8 which queue gets
   which stop behavior. This is a kernel-safety requirement, not optional.

3. **[CRIT-2 fix]** Remove WdfIoTargetSendIoctlSynchronously from the active-poll
   path. Either convert to async (with original request held pending) or eliminate
   the active-poll path entirely in favor of cache-only with unsolicited 0x90 input.
   Decision drives Section 7b pseudocode and the IoctlHandlers.c scope.

4. **[MAJ-1 / MAJ-3 combined fix]** Resolve OQ-3 (does HidClass gate on descriptor?)
   and correct the IOCTL buffer retrieval API (WdfRequestGetParameters / Arg1 for
   METHOD_NEITHER, not WdfRequestRetrieveInputBuffer). These two fixes often travel
   together in HID filter implementations and should be resolved in one design pass.

5. **[MAJ-2 + MIN-3 combined]** Clamp ScrollSpeed input (prevent divide-by-zero),
   correct TOUCH_STATE_MASK to 0xf0 (not 0x0f), and verify all descriptor bytes
   against empirical capture (MIN-2). These are implementation correctness fixes
   that should be locked down before InputHandler.c coding begins.

---

## References

- HID 1.11 / Usage Tables 1.4 -- /tmp/m12-refs/hid1_11.pdf, /tmp/m12-refs/hut1_4.pdf
- Linux hid-magicmouse.c -- /tmp/m12-refs/hid-magicmouse.c (GPL-2 read-only)
- M12 reference index -- docs/M12-REFERENCE-INDEX.md
  (worktree: /home/lesley/.claude/worktrees/ai-m12-references/docs/)
- Phase 1 applewirelessmouse findings -- docs/M12-APPLEWIRELESSMOUSE-FINDINGS.md
  (worktree: /home/lesley/.claude/worktrees/ai-m12-ghidra-applewirelessmouse/docs/)
- M12 design spec reviewed -- docs/M12-DESIGN-SPEC.md
  (worktree: /home/lesley/.claude/worktrees/ai-m12-design-prd-mop/docs/, untracked)
- KMDF documentation -- https://learn.microsoft.com/en-us/windows-hardware/drivers/wdf/
- WdfIoTargetSendIoctlSynchronously restrictions --
  https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdfiotarget/
  nf-wdfiotarget-wdfiotargetsendioctlsynchronously
- HID internal IOCTL METHOD_NEITHER -- MSDN IRP_MJ_INTERNAL_DEVICE_CONTROL,
  HID_XFER_PACKET retrieval via Parameters.Others.Arg1
