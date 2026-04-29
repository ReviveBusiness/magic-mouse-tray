# Cell 1 — POST-PHASE-3 FORENSIC FINDING

**The reboot is NOT the failure trigger. A separate transition at 17:43:44 (43 min post-login) flipped the device from unified-mode to split-mode. THAT's when scroll broke.**

## Evidence (tray-debug-tail.log, test-3/)

```
17:11:00  HIDP_CAPS path=...&c&0000  InLen=47 FeatLen=2 TLC=UP:0001/U:0002   (UNIFIED)
17:11:00  FEATURE_BLOCKED err=87 (Apple driver traps Feature 0x47)            (filter ACTIVE)
17:11:00  BATTERY_INACCESSIBLE Apple driver in unified mode
17:11:00  TRAY_UPDATE pct=-2 tooltip="Magic Mouse 2024 - battery N/A"
17:11:00  POLL_SCHEDULED next_in=00:05:00

17:16:00  [same: unified, blocked, N/A]
17:21:00  [same]
17:26:00  [same]
17:31:00  [same]
17:36:00  [same]
17:41:01  [same — last UNIFIED poll]

17:43:44  DRIVER_CHECK pid=0x0323 LowerFilters=bound
17:43:44  HIDP_CAPS path=...&col01...&c&0000  InLen=8 FeatLen=65               (SPLIT — Mouse)
17:43:44  HIDP_CAPS path=...&col02...&c&0001  InLen=3 FeatLen=0 TLC=UP:FF00/U:0014  (SPLIT — Battery)
17:43:44  DETECT split-vendor InputReport=0x90
17:43:44  OK battery=44% (split)
17:43:44  TRAY_UPDATE pct=44 tooltip="44%"
```

## Implications

1. **Apple filter ran fine for 43+ min after reboot.** All 7 tray polls between 17:11 and 17:41 saw unified mode with FEATURE_BLOCKED — that's the filter actively trapping Feature 0x47, which means the filter's setup IS working post-reboot. Scroll synthesis was likely also active during this window (we didn't test).

2. **The user's claim "scroll doesn't work after reboot" was tested at 17:47:48 — AFTER the 17:43:44 flip.** Cell 1's wheel-events.json `event_count=0` reflects the post-flip state, not the post-reboot state. The 30-minute window between login and the flip was UNTESTED for scroll.

3. **The flip is the real failure.** Whatever triggered the transition from unified→split at 17:43:44 is the problem to solve. Not the reboot itself.

## Most likely trigger (ranked)

### H-α — Selective Suspend / D-state idle-out (HIGH confidence)
- BT HID devices typically D2/D3-suspend after 30+ min of no input
- On wake, AddDevice fires for HidClass → re-enumeration → split mode
- applewirelessmouse may not re-establish unified mode after a D-state cycle
- **Timing matches**: 43 min from reboot, falls right between the 17:41:01 last-unified-poll and the next scheduled 17:46:01 poll
- **Refutable by**: actively using the mouse continuously for 60+ min post-reboot. If unified mode persists with active input, idle-suspend is the cause. If it still flips, this hypothesis is wrong.

### H-β — User-triggered re-enumeration (MEDIUM confidence)
- Opening Bluetooth Settings, Device Manager, or running a Procmon/wpr command may trigger PnP re-enumeration
- The user was investigating + running tools at 17:47 (just 4 min after the flip)
- **Refutable by**: replicate the reboot, monitor the transition with focused ETW (m13.wprp), see if any user action correlates with the flip

### H-γ — Apple filter time-out (LOW confidence)
- Speculation: filter has its own idle timeout, falls back to passthrough after X minutes
- No Apple docs to support
- **Refutable by**: extended observation post-reboot with no user activity at all. If flip happens at consistent N minutes, filter timer is the cause.

### H-δ — Some Windows Bluetooth power-policy event (UNKNOWN confidence)
- Windows BT stack may push the device into low-power mode independently
- Selective Suspend is one such mechanism but there are others (e.g., Modern Standby connected-but-suspended state)

## What's needed to disambiguate

**Test 1 (refutes H-α): Active-mouse persistence test.** From a fresh reboot, actively use the mouse continuously (move it every few seconds) for 60+ min. Check if unified mode persists indefinitely. If yes → idle-suspend is the cause.

**Test 2 (refutes H-α also): Disable Selective Suspend, reboot, observe.**
```powershell
# In admin PS post-fresh-reboot, before the 30-min mark:
$bthenum = Get-PnpDevice | Where-Object { $_.InstanceId -match '^BTHENUM\\\{00001124[^\\]*VID&0001004C_PID&0323' } | Select-Object -First 1
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($bthenum.InstanceId)\Device Parameters"
Set-ItemProperty -Path $regPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force
# Then disable+enable to apply
```
If this survives N hours of idle without flipping → Selective Suspend IS the cause.

**Test 3 (refutes H-α + H-γ): Capture the transition with focused ETW.** Use `m13.wprp` (committed in `ce0dd18`) to capture from reboot through the transition. Look for:
- `Microsoft-Windows-Kernel-Power` D-state IRPs to the BT HID device just before the flip
- `Microsoft-Windows-Kernel-PnP` AddDevice/Start events at the flip time
- `Microsoft-Windows-Input-HIDCLASS` enumeration events showing unified→split transition

This is the definitive test. Single 60-min capture answers all three hypotheses.

## Implications for Phase 4

If H-α (Selective Suspend) is correct:
- **Phase 4 simplifies dramatically**: a 1-line registry edit on the BTHENUM device's `SelectiveSuspendEnabled = 0`, applied via tray app on first run + after any re-pair
- **No userland gesture daemon needed**
- **No descriptor patch needed**
- **PRD-184 ships as: existing tray + Selective Suspend disabler**
- Estimated effort: ~1 day to ship

If H-α is refuted (Test 1 fails):
- Fall back to Phase 4A (userland scroll daemon) per Phase 3 analysis
- Estimated effort: 1-3 days

## Path forward (recommended)

1. **Run Test 3 (focused ETW capture)** — definitive, ~60 min wall clock, low risk. Uses m13.wprp already committed. Captures exactly the transition window.
2. **If ETW shows D-state: run Test 2 (disable Selective Suspend)** — confirms the fix in 5 minutes
3. **Ship the fix in tray app** — disable Selective Suspend on detection of Magic Mouse on BTHENUM
4. **Cells 2-6 deferred** — Phase 4 simplifies to "fix Selective Suspend" and the multi-cell axis exploration becomes lower priority.
