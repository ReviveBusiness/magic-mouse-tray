# E6 + E7c findings — source audit + driver static analysis

**Run:** 2026-04-28 ~12:50
**Goal:** verify what the tray's diagnostic messages actually mean + understand `applewirelessmouse.sys` capabilities, before any state change.

---

## E6 — `MagicMouseTray/MouseBatteryReader.cs` audit

### Detection logic (lines 145–163)
The tray's "unified-apple" path triggers iff `HidP_GetValueCaps` returns a Feature value cap with `UsagePage=0x0006 (Generic Device) + Usage=0x0020 (Battery Strength)`. The `unifiedReportId` is read from the descriptor — not hardcoded.

### Read attempt (lines 209–226)
- `HidD_GetFeature(handle, fbuf, fbuf.Length)` where `fbuf[0] = unifiedReportId` and `fbuf.Length = max(featureLen, 2)`.
- On success + pct in 0–100: log `OK ... battery=N% (unified Feature 0x47)`, return pct.
- On failure: log `FEATURE_BLOCKED ... err={errCode} (Apple driver traps Feature 0x47; needs custom KMDF filter — see PRD-184)` and return -2.

### Critical correction
**The "Apple driver traps Feature 0x47" log message is INFERENTIAL, not measured.** The code logs that string for ANY `HidD_GetFeature` failure, regardless of cause. It assumes the only reason a `HidD_GetFeature(0x47)` call would fail is that Apple's filter is intercepting it — but the filter is not on the v3 mouse PnP stack at all right now (per `bt-stack-snapshot.txt`). So whatever is causing err=87 is NOT a filter trap.

### v1 mouse — works in same code path
Same `HidD_GetFeature(0x47)` call against v1 mouse path returns success (`battery=100% (unified Feature 0x47)` per debug.log 09:33:47). So the call mechanism is correct. Whatever blocks v3 doesn't block v1 — and the difference cannot be the filter (neither device has it on stack).

### Implication for the PRD
- The "Apple driver traps" narrative in PRD-184 is mis-attributed.
- The actual mechanism producing err=87 on v3 needs a different explanation: descriptor declares 0x47 but device doesn't implement it, or some other layer rejects it.
- Tray log line should be reworded — the cause is not yet known.

---

## E7c — `applewirelessmouse.sys` static analysis

| Field | Value |
|---|---|
| File | `C:\Windows\System32\drivers\applewirelessmouse.sys` |
| Format | PE32+ (native x86-64), 8 sections |
| Size | 78 424 bytes |
| Signed | Yes (Microsoft-issued WHQL chain) |
| Framework | KMDF (`WdfVersionBind`, `WdfVersionBindClass`) |
| File version (PE) | 6.1.7700.0 |
| INF version | 6.2.0.0 (dated 2026-04-21) |
| PDB hint | `D:\BWA\B69DF622-5A99-0\AppleWirelessMouseWin-7635\srcroot\x64\Release\AppleWirelessMouse.pdb` |

### Hardcoded VID/PID strings in driver binary
```
VID&000205ac_PID&030d   (v1 Magic Mouse)
VID&000205ac_PID&0310   (Magic Trackpad — guess)
```
**No hardcoded reference to PID&0323 (v3) or PID&0269 (v2) or PID&0239 (keyboard).** The v3/v2 are matched only at INF level. Internal driver logic may dispatch on these PIDs via different mechanism (e.g., compare `WDF_DEVICE_HARDWARE_INFO` numeric VID/PID), but none is visible as an ASCII literal.

### Notable imports (selected)
- `IoBuildDeviceIoControlRequest`, `IofCallDriver`, `IoAllocateIrp`, `IoFreeIrp` — driver builds and dispatches IOCTLs down the stack
- `PsCreateSystemThread`, `PsTerminateSystemThread` — runs a kernel-mode worker thread
- `KeWaitForMultipleObjects`, `KeWaitForSingleObject`, `KeInitializeEvent`, `KeSetEvent` — event-driven worker thread
- `MmGetSystemRoutineAddress` — late-binds a kernel routine by name (escape hatch for newer kernel APIs)
- `RtlQueryRegistryValues` — reads HKR/HKLM/HKU registry values (we see `\Software\Apple Inc.\Mouse` and `\Control Panel\Mouse` references)
- `ObReferenceObjectByHandle`, `PsReferencePrimaryToken`, `ZwQueryInformationToken` — opens handles by ID + queries process tokens

### User-namespace device + symlinks
```
\Device\AppleBluetoothMultitouch
\DosDevices\AppleBluetoothMultitouch    ← user-mode tools can open this
\DosDevices\KeyManager
\DosDevices\KeyAgent
```
Implication: user-mode app can connect to the driver via `\\.\AppleBluetoothMultitouch` and issue IOCTLs. Apple's own "Wireless Diagnostics" or "Magic Utilities"-style tooling probably uses this. The driver is more than a passive filter — it has an exposed control plane.

### Registry footprint
```
\Registry\User\<sid>\Control Panel\Mouse     SwapMouseButtons
\Registry\User\<sid>\Software\Apple Inc.\Mouse   EnableTwoButtonClick
```
Driver reads per-user mouse settings. That implies it personalizes button-mapping behaviour per logged-in user (ContextMenu vs. Primary on right-click, etc.).

### Two extra DosDevice symlinks (`KeyManager`, `KeyAgent`)
Suggests the driver also handles a key-management / authentication channel — possibly device pairing keys or a feature licence handshake. NOT mouse-related on its face. Worth noting; not investigated further.

---

## INF — what binds to what

`applewirelessmouse.inf` `[Apple.NTamd64]` binds the filter to:
```
BTHENUM\{00001124-…-00805f9b34fb}_VID&000205ac_PID&030d   v1 Magic Mouse
BTHENUM\{00001124-…-00805f9b34fb}_VID&000205ac_PID&0310   Magic Trackpad
BTHENUM\{00001124-…-00805f9b34fb}_VID&0001004c_PID&0269   v2 Magic Mouse
BTHENUM\{00001124-…-00805f9b34fb}_VID&0001004c_PID&0323   v3 Magic Mouse
```

Filter installed via:
```
[AppleWirelessMouse.NT.HW.AddReg]
HKR,,"LowerFilters",0x00010000,"applewirelessmouse"
```

ServiceType=KERNEL_DRIVER, StartType=SERVICE_DEMAND_START — so PnP loads it on-demand when first matching device arrives.

### Two anomalies

1. **Keyboard (PID 0x0239) is NOT in INF** — yet snapshot shows its BTHENUM HID PDO has `LowerFilters=applewirelessmouse`. This LowerFilter ref must have been installed by some OTHER INF (older Apple BootCamp package? legacy "Apple Wireless Keyboard" filter? user-edited registry?). Worth digging into the keyboard's PnP install history.

2. **v3 mouse (PID 0x0323) IS in INF, yet snapshot shows NO LowerFilter on its current PDO**. Implies the device was paired before the INF was installed, OR the binding was de-installed. PnP doesn't re-evaluate INF for a known device — once the binding is set, it sticks.

---

## v3 mouse cache descriptor (re-decoded carefully)

135-byte descriptor from BTHPORT SDP cache — CONFIRMED via byte-by-byte walk:

```
Mouse TLC, ReportID 0x12: 2 buttons + X/Y (16-bit each)
Vendor 0xFF02 Feature, ReportID 0x55: 64-byte touchpad mode
Vendor 0xFF00 outer collection, ReportID 0x90:
  Inside, UP=0x84 (Power Device) + UP=0x85 (Battery System) Input items
```

**No Feature 0x47 anywhere in cached descriptor.** Yet tray's runtime `HidP_GetValueCaps` finds one. Therefore: runtime kernel descriptor != SDP cache descriptor. Hypothesis: HidBth re-issues `HID_GET_HID_DESCRIPTOR` IRP at AddDevice, fetching a different descriptor than the SDP-time cache; OR Apple's filter (during a previous unified-mode session) mutated the kernel descriptor and that mutation persisted somehow.

Cleanest test: capture the runtime descriptor that `HidD_GetPreparsedData` returns for v3 right now and compare byte-for-byte with the cache.

---

## Updated assumption table (post E6+E7c)

| # | Original assumption | Status after E6+E7c |
|---|---|---|
| A1 | v1 scroll depends on driver loaded into kernel | UNCHANGED — needs E1 |
| A2 | Tray's "Apple driver traps" log accurate | **DISPROVEN** — log is inferential, mis-attributed; filter not on v3 stack |
| A3 | err=87 on v3 = filter trap | **DISPROVEN** — filter not on stack; root cause of err=87 unknown, needs E5 |
| A4 | Phase 4-Ω recycle restores v3 battery | UNCHANGED — needs E4 |
| A5 | Keyboard battery readable via Feature 0x47 | UNCHANGED — needs E3 |
| A6 | v3 Feature 0x90 readable when filter bound | UNCHANGED — needs E5b |
| A7 | Filter binding = scroll synth + battery translation | NUANCED — driver may not v3-aware (no v3 PID hardcoded), so binding may not give battery translation; needs E4 |

## New questions raised

| # | Question |
|---|---|
| Q1 | Why does v3 runtime descriptor have Feature 0x47 when SDP cache doesn't? |
| Q2 | Where did keyboard's LowerFilter ref come from (no INF entry for 0x0239)? |
| Q3 | Does the driver's binary logic have ANY v3-specific code (since no hardcoded PID&0323 string)? |
| Q4 | What does `\DosDevices\KeyManager` / `\DosDevices\KeyAgent` do? Apple mouse pairing keys? |
