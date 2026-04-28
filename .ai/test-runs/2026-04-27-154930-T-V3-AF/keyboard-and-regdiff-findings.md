# Keyboard and Reg-Diff Findings
# M13 Cell — Forensic Mining Report
# Captured: 2026-04-27

---

## 1. BLUF

MAC `e806884b0741` is the BT keyboard (Apple Wireless Keyboard, PID 0x0239, BT name "Trevor's Keyboard"),
confirmed by four independent evidence chains; it carries a stale `applewirelessmouse` LowerFilter on
its BTHENUM HID node — the same incorrect filter that is poisoning the Magic Mouse v3 stack, now also
silently attached to an active, always-on keyboard device.

---

## 2. Keyboard MAC Identification — Evidence Trail

### 2a. BTHPORT device record (pre-cleanup .reg)

Source: `2026-04-27-142015-pre-cleanup.reg` (UTF-16LE decoded)

```
[HKLM\SYSTEM\ControlSet001\Services\BTHPORT\Parameters\Devices\e806884b0741]
"Name"  = hex: 54,72,65,76,6f,72,e2,80,99,73,20,4b,65,79,62,6f,61,72,64,00
           -> "Trevor's Keyboard"
"PID"   = dword:00000239  (0x0239 = Apple Wireless Keyboard gen1/2)
"COD"   = dword:00002540  (Major class 5 = Peripheral; Minor class 16 = Keyboard)
"ManufacturerId" = dword:0000004c  (Apple Inc)
"FingerprintString" = "Fingerprint:03;004C;031C;...;05AC;0239;..."
```

LMP version 3, subversion 0x031C — consistent with BCM20702 chipset, same as
Apple Wireless Keyboard (AA battery, first or second generation).

Reference: pre-cleanup.reg BTHPORT Devices section.

### 2b. CachedServices SDP name decode

Source: pre-cleanup.reg, `e806884b0741\CachedServices\00010000`

Bytes at offset 0x6E: `41,70,70,6c,65,20,57,69,72,65,6c,65,73,73,20,4b,65,79,62,6f,61,72,64`
Decoded: "Apple Wireless Keyboard"

CachedServices blob also contains HID report descriptor bytes with UsagePage 0x07
(Keyboard/Keypad) and Usage 0xE0-0xE7 (modifier keys) — confirmed keyboard HID descriptor.

Reference: pre-cleanup.reg CachedServices section for e806884b0741.

### 2c. pnp-probe.json col01_matches

Source: `m13-phase0/pnp-probe.json:118-121`

```json
{
  "Status": "OK",
  "Class": "Keyboard",
  "FriendlyName": "HID Keyboard Device",
  "InstanceId": "HID\\{00001124-0000-1000-8000-00805F9B34FB}_VID&000205AC_PID&0239&COL01\\A&EAF9D13&2&0000"
}
```

PID 0x0239, VID 0x05AC (Apple). Status=OK means device is enumerated and functioning
as a keyboard at the time of probe (2026-04-27T14:30).

### 2d. Procmon CSV WMI poll pattern

Source: `procmon-filter-validation.CSV`

- `D0C050CC8C4D` (mouse) WMI poll hits: 1,620
- `E806884B0741` (keyboard) WMI poll hits: 810

Keyboard has exactly half the mouse poll count. WMI is polling both at ~1/sec;
the lower count reflects a shorter capture window for keyboard-specific paths.
All keyboard polls are against `BTHENUM\Dev_E806884B0741` (`ConfigFlags` query only).

Reference: procmon-filter-validation.CSV, grep count by MAC.

### 2e. Tray-debug DRIVER_CHECK

Source: `test-3/tray-debug-tail.log:42`

```
[2026-04-27 17:43:44] DRIVER_CHECK unknown_apple_pid=0x0239 bound=False
[2026-04-27 17:43:44] DRIVER_CHECK status=UnknownAppleMouse (PID not in INF)
```

The tray app enumerated a second Apple HID device (PID 0x0239) on the same BT adapter
and reported it as "unknown Apple PID, not bound." This is the keyboard.

### 2f. bthport-discovery.txt sibling summary

Source: `bthport-discovery.txt:186-188`

```
device: e806884b0741
  CachedServices values: 00010000,00010001
  CachedServices subkeys:
```

The discovery script confirmed `e806884b0741` has populated CachedServices (like the mouse)
while `04f13eeede10` and `b2227a7a501b` do not. `04f13eeede10` = "Lesley's Mouse" (older
Apple mouse, FriendlyName decoded from FriendlyName hex: `4c,65,73,6c,65,79...`).
`b2227a7a501b` = HP ENVY 6000 series printer (BLE, no CachedServices).

---

## 3. Keyboard Driver State

### 3a. LowerFilters: applewirelessmouse (incorrect)

Source: pre-cleanup.reg and post-cleanup-v2.reg, keyboard Device Parameters nodes

Both BTHENUM HID node and DIS node for the keyboard carry:

```
"LowerFilters"=hex(7): 61,00,70,00,70,00,6c,00,65,00,77,00,69,00,72,00,65,00,
                        6c,00,65,00,73,00,73,00,6d,00,6f,00,75,00,73,00,65,00,00,00,00,00
-> "applewirelessmouse"
```

This appears on at minimum three keyboard registry paths:
- `BTHENUM\{00001124...}_VID&000205ac_PID&0239\...\Device Parameters`
- `BTHENUM\{00001200...}_VID&000205ac_PID&0239\...\Device Parameters`
- `BTHENUM\Dev_E806884B0741\...\Device Parameters`

### 3b. Service driver: HidBth (correct)

Source: pre-cleanup.reg keyboard BTHENUM Enum section

```
"Service"="HidBth"
"Driver"="{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\\0003"
```

The upper function driver is the standard `HidBth`. The keyboard is actually
working (pnp-probe reports Status=OK, Class=Keyboard). The LowerFilter loads
into the stack silently beneath HidBth, but since `applewirelessmouse` is a KMDF
function driver (not a pure filter), its behavior on a non-mouse device is undefined
and likely a no-op at the keyboard layer — but it is loading unnecessarily.

### 3c. No applewirelesskeyboard driver present

Source: pre-cleanup.reg, broad search for "applewireless"

Only `applewirelessmouse` appears. No `applewirelesskeyboard` service exists.
The keyboard is operating on native `HidBth` + `keyboard.inf` (HID_Keyboard_Inst.NT),
confirmed by three separate `"InfPath"="keyboard.inf"` driver nodes in the Enum tree.

### 3d. Phase 1 cleanup did NOT touch the keyboard

Source: keyboard entry count comparison

- Pre-cleanup keyboard refs (E806884B0741/0239): 186
- Post-cleanup-v2 keyboard refs: 186

The cleanup script targeted only MagicMouse/RAWPDO/0323/applewirelessmouse/HidBth
paths. The keyboard's stale `applewirelessmouse` LowerFilter survived untouched.

---

## 4. Keyboard vs. Mouse Mutual-Exclusion Pattern

The v3 mouse mutual-exclusion pattern (Feature 0x47 blocked by Apple driver trapping
the Feature report) is specific to the custom `applewirelessmouse` KMDF driver being
the function driver on the mouse. The keyboard does NOT exhibit this pattern because:

1. The keyboard function driver is `HidBth` (standard), not `applewirelessmouse`.
2. `applewirelessmouse` on the keyboard is only a LowerFilter; it sits below
   HidBth but does not own the Feature dispatch path.
3. The keyboard has no Feature 0x47 (battery strength) in its report descriptor
   — it exposes battery state via a different mechanism (HID UsagePage 0x06,
   Usage 0x20 in report 0x47, but this is read via the keyboard's own HID path,
   not trapped by the filter).

In short: the keyboard is functioning correctly as a typing device. The stale
LowerFilter is parasitic cargo, not an active fault.

---

## 5. Reg-Diff Insights Beyond "Cleanup Worked"

Source: `m13-phase0/reg-diff.md`

The diff filter was `MagicMouse|RAWPDO|0323|applewirelessmouse|LowerFilters|UpperFilters|BTHPORT|HidBth`.
Unfiltered totals: 22 sections removed, 0 added, 1,261 value-level diff lines.

The 1,261 value-level lines are far more than the ~40 lines captured in the filtered diff.
The excess ~1,220 lines are kernel-timestamp and transient noise (LastSeen, LastConnected,
ConnectionCount, WDF counters, Perfmon baseline deltas) that change between any two
registry exports separated by minutes regardless of driver activity.

Key structural finding the filter deliberately excluded: the diff shows MagicMouseDriver
Enum key still contained `"0"="BTHENUM\\{00001124...}_VID&0001004c_PID&0323\\..."` as
its service enumeration entry (reg-diff.md:57,90). This confirms MagicMouseDriver was
loaded and had claimed a device instance at the time of the pre-cleanup snapshot, then
was fully deregistered post-cleanup. No analogous entry exists for the keyboard — the
keyboard was never claimed by MagicMouseDriver.

The diff does NOT reveal any non-mouse-related structural changes. The only non-obvious
signal is that the `applewirelessmouse` service entry and its Enum subkey were both
present pre-cleanup and absent post-cleanup (reg-diff.md:16-19, 26-29), which means
the applewirelessmouse LowerFilter on the keyboard BTHENUM nodes now points to a
service binary that no longer has a Services\ entry. This is a dangling filter reference
and warrants cleanup in Phase 4.

---

## 6. Gaps and Next-Step Commands

### What we do NOT know

1. **Keyboard CachedServices contents**: bthport-discovery.txt walked only `d0c050cc8c4d`.
   The keyboard's CachedServices blob was recovered from the .reg backup (SDP record),
   but a live decode via the discovery script has not been run.

2. **Keyboard HID descriptor in split mode**: After the Phase 1 repair sequence, the
   discovery script was not re-run against the keyboard MAC. We do not know if the
   keyboard CachedServices match the static .reg backup blob after reconnect.

3. **Whether applewirelessmouse LowerFilter loads successfully at boot** given that
   the Service entry was deleted by Phase 1. This could cause a benign "driver not found"
   boot warning for the keyboard's BTHENUM node, or it could cause a startup error on
   reconnect (ConfigFlags non-zero). The post-cleanup ConfigFlags query in the procmon
   CSV returned `Data: 0` at capture time, but the service was still present then.

### Commands to fill gaps (admin required)

```powershell
# Fill gap 1: decode keyboard CachedServices live
.\scripts\mm-bthport-discover.ps1 -Mac e806884b0741

# Fill gap 3: check keyboard ConfigFlags after next boot
reg query "HKLM\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&0239\9&73b8b28&0&E806884B0741_C00000000" /v ConfigFlags
```

---

## 7. Implications for PRD-184 Phase 4

The keyboard finding adds one confirmed action item and one risk flag to Phase 4:

**Action item**: The Phase 4 cleanup scope must include removing the stale
`applewirelessmouse` LowerFilter from the keyboard's BTHENUM Device Parameters nodes
(three paths listed in section 3a). These were NOT cleaned in Phase 1 because the diff
filter matched only PID 0323 paths.

**Risk flag**: If Phase 4 leaves the keyboard LowerFilter in place after the
applewirelessmouse service binary is gone, the next keyboard BT reconnect may log a
PnP start error (CM_PROB_FAILED_DRIVER_ENTRY = 0x27) on the keyboard node. This will
not affect keyboard function (HidBth is the function driver and will still bind), but
it produces an error in Device Manager and could confuse future diagnostics.

**No change to mouse Phase 4 path**: The keyboard data confirms that the mutual-exclusion
problem is entirely mouse-specific. The recommended Phase 4 KMDF filter approach for
PID 0x0323 does not need to account for or protect the keyboard stack.

---

## Appendix: All 4 Paired Devices

| MAC | Identity | Type | CachedServices |
|-----|----------|------|----------------|
| `d0c050cc8c4d` | Magic Mouse (2024, PID 0x0323) | BT Classic | Yes (walked) |
| `e806884b0741` | Trevor's Keyboard (Apple Wireless, PID 0x0239) | BT Classic | Yes (from .reg) |
| `04f13eeede10` | Lesley's Mouse (older Apple Magic Mouse) | BT Classic | No |
| `b2227a7a501b` | HP ENVY 6000 series printer | BLE | No |
