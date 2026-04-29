---
created: 2026-04-29
type: notebooklm-query-template
purpose: Next session uses this to query the M12/M13 corpus before re-running AUTO_START / state-flip experiments
status: ready-to-paste
---

# NotebookLM query — paste this into `/notebooklm` next session

## Query 1 — AUTO_START history

```
On the applewirelessmouse.sys kernel driver (Apple's Bluetooth lower filter for
Magic Mouse on Windows), has anyone in this corpus previously tried changing
the Service start type from DEMAND_START (Start=3) to AUTO_START (Start=2)?

Specifically I need to know:

1. Was the change actually applied to the registry
   (HKLM\SYSTEM\CurrentControlSet\Services\applewirelessmouse\Start), or was
   it only proposed/discussed?

2. If applied, what was the empirical result on the next reboot?
   - Did the Magic Mouse 2024 v3 (PID 0x0323) come up with Descriptor A
     (multi-TLC: COL01 mouse RID=0x12 + COL02 vendor battery RID=0x90 with
     UsagePage=0xFF00 Usage=0x0014) or Descriptor B (single Mouse TLC,
     RID=0x02, InputReportByteLength=47)?
   - Did scroll work?
   - Did HidD_GetInputReport(0x90) return a 3-byte battery payload, or err=1?

3. What was the rationale for trying it, and what was the conclusion or
   recommendation? Was a follow-up experiment recommended?

Cite the specific document filename (e.g. PHASE-E-FINDINGS.md, M12-MOP.md,
v3-BATTERY-EMPIRICAL-PROOF-AND-PATHS.md) and date for each claim. If the
corpus does NOT contain this experiment, say so explicitly — do not infer.
```

## Query 2 — Automatic A→B transition during standby/PnP scan

```
On the same Magic Mouse 2024 v3 setup with applewirelessmouse.sys bound,
the user observed an automatic Descriptor A → Descriptor B transition while
the mouse was in BT power-saver mode and no manual recycle / re-pair / reboot
was performed. The trigger was suspected to be a Windows PnP device-discovery
scan or a DeviceSetupManager (DSM) event firing during the idle window.

From this corpus:

1. What is the documented mechanism for this automatic transition? Was it
   correlated with a specific Event Log source (DeviceSetupManager,
   Microsoft-Windows-Bluetooth-Policy, BTHPORT, HidBth)?

2. What time-correlated events were captured (e.g. DSM property-write,
   Selective Suspend wake, BT reconnect after standby)?

3. Has anyone established whether the transition is reproducible on demand,
   or only opportunistic? Cite any persistence-monitor logs or test runs.

4. Is there any documented mitigation that keeps Descriptor A through a
   standby/wake cycle? (e.g. Selective Suspend disable on the BT HID PDO,
   power-management policy change, registry pin)

Cite filenames and dates. Be specific about whether each claim is empirical
(probe-confirmed) or theoretical (reasoning only).
```

## Query 3 — Scroll vs battery trade-off

```
This corpus discusses two HidBth descriptor variants for Magic Mouse 2024 v3:

- Descriptor A — multi-TLC, COL01 mouse with RID=0x12 (multi-touch), COL02
  vendor battery with RID=0x90 / UP=0xFF00 / U=0x0014. Battery readable via
  HidD_GetInputReport(0x90). Scroll behavior unclear without
  applewirelessmouse mediating RID=0x12.

- Descriptor B — single Mouse TLC, RID=0x02 with embedded X/Y/AC-Pan/Wheel
  fields, InputReportByteLength=47. Scroll works natively via the firmware's
  RID=0x02 path (no Feature 0x55 needed). Battery RID=0x90 not declared.

Question: under Descriptor A with applewirelessmouse loaded, does scroll
work? Specifically:

1. Has anyone empirically tested scroll on v3 in Descriptor A state with
   Apple's stock applewirelessmouse filter loaded (no MagicUtilities, no
   M12)?

2. Does applewirelessmouse send Feature Report 0x55 (the multi-touch enable
   that MagicUtilities' MagicMouse.sys sends from userland) to enable
   scroll on RID=0x12, or does it only handle RID=0x02 / Descriptor B?

3. Is there any empirical data showing Descriptor A + scroll-working at
   the same time on Apple's stock filter? (The session today observed
   A=battery/no-scroll, B=scroll/no-battery — is that the only observed
   pattern, or has anyone seen A+scroll?)

Cite filenames and dates. If conflicting reports exist across runs, list
them with dates.
```

## After running the queries

If NotebookLM returns conclusive prior outcomes:
- Skip the AUTO_START experiment, document the prior conclusion in
  `M13-V3-BATTERY-AUDIT-2026-04-30.md` Phase 6 ("AUTO_START already tested,
  see <citation>"), and commit.

If NotebookLM returns ambiguous / no-prior-attempt:
- Plan the AUTO_START experiment as a separate gated change. Pre-flight:
  back up registry value, document rollback (`sc config applewirelessmouse
  start= demand`), test plan (boot → probe v1+v3 → scroll test → battery
  read).
