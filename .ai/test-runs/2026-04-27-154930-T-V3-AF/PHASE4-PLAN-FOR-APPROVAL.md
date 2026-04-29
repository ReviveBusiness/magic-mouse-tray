# PRD-184 — Phase 4 Plan (for user approval)

**Status:** Ready for review
**Author:** Claude (apex/auto, autonomous session 2026-04-27 evening)
**Approval gate:** This plan must be approved before any Phase 4 work begins.

## BLUF

Cell 1 + Phase 3 cache decode + tray-debug timeline analysis collapse the Phase 4 problem space from "build a kernel filter" or "userland scroll daemon" to **"figure out why Apple's filter goes inert ~43 minutes after reboot, then make it not."** The most likely cause (per timing + tray-poll evidence) is Selective Suspend on the BT HID device. If true, the fix is a 1-line registry change. If not, fall back to a userland scroll daemon.

The plan: **prove or refute Selective Suspend with a single focused ETW capture, then ship the simplest fix that actually works.**

## What we know FOR CERTAIN (empirical evidence)

| Fact | Evidence |
|---|---|
| The BTHPORT cache for d0c050cc8c4d declares Mouse (X+Y, **no Wheel**) + Vendor Feature + Vendor Battery (Report 0x90) | Phase 3 decode at `phase3-cache-decoded.md`, raw blob at `blob_cache_00010000.bin`, decoder at `/tmp/mm-decode-cache.py` |
| `applewirelessmouse` does NOT add Wheel to the descriptor; it must inject wheel events at the Win32 input layer (Linux `hid-magicmouse.c` pattern via `input_report_rel(REL_WHEEL, ...)` equivalent) | Cache lacks Wheel; Wheel can only come from somewhere else; consistent with Linux reference implementation |
| `applewirelessmouse` ALSO traps Feature 0x47 (which the tray polls for battery) — this trap correlates 1:1 with "filter active" mode | Tray-debug FEATURE_BLOCKED err=87 entries at every 5-min poll while filter is active; `BATTERY_INACCESSIBLE Apple driver in unified mode` markers |
| The reboot itself does NOT break scroll | tray-debug at `test-3/tray-debug-tail.log` shows the filter was actively trapping for ~43 minutes post-login (entries from 17:11:00 through 17:41:01), all in unified mode |
| A separate transition at 17:43:44 flipped the device from unified → split mode | Same log: at 17:43:44, HidClass paths change from `_pid&0323#a&31e5d054&c&0000` (unified) to `&col01...&c&0000` + `&col02...&c&0001` (split). Battery becomes readable; trap stops firing |
| LowerFilters survives reboot | live-driver-state.json (test-3): `LowerFilters=["applewirelessmouse"]` on HID-class GUID device |
| accept-test AC-01 has been a script bug all along — queries SDP-service GUID instead of HID-class GUID | substep-state-evolution.md cross-confirmed by Agents A and C; fix landed in `ce0dd18` |
| Battery is in the cache (Report 0x90 with vendor TLC UP=0xFF00 U=0x14) and works UNCONDITIONALLY in split mode | Phase 3 decode + test-3 tray reads battery=44% post-flip |

## What we DON'T know yet (the central mystery)

**What triggered the unified→split flip at 17:43:44?** Three candidates with empirical weight:

| H | Hypothesis | Evidence weight | Why |
|---|---|---|---|
| H-α | Selective Suspend / D-state idle-out (BT HID device went to low-power, woke without filter re-init) | **HIGH** | Timing matches typical 30-min Selective Suspend window; the flip happened during a tray poll cycle (between 17:41:01 and 17:46:01 scheduled), suggesting the device was idle then woke |
| H-β | User-triggered re-enumeration (Bluetooth Settings opened, Procmon launched, Refresh Now clicked) | MEDIUM | The user WAS investigating tools at 17:47, only 4 min after the flip; correlation possible |
| H-γ | applewirelessmouse internal time-out | LOW | Speculation; no Apple docs support; would be consistent but has no positive evidence |

## Three Phase 4 paths, ranked by cost-if-correct

### Path 1 — Disable Selective Suspend (assume H-α correct)
**Mechanism:** BTHENUM HID device's registry has a `SelectiveSuspendEnabled` value (or equivalent power policy). Setting it to 0 prevents D-state idle-out; filter stays operative indefinitely.

**Implementation:**
```powershell
# Triggered by tray app on first detection of Magic Mouse, after every re-pair
$bthenum = Get-PnpDevice | Where-Object {
    $_.InstanceId -match '^BTHENUM\\\{00001124[^\\]*VID&0001004C_PID&0323'
} | Select-Object -First 1
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($bthenum.InstanceId)\Device Parameters"
Set-ItemProperty -Path $regPath -Name "SelectiveSuspendEnabled" -Value 0 -Type DWord -Force
# May also need DeviceSelectiveSuspend, IdleEnable, etc. — full set TBD
Disable-PnpDevice -InstanceId $bthenum.InstanceId -Confirm:$false
Enable-PnpDevice  -InstanceId $bthenum.InstanceId -Confirm:$false
```

**Effort:** ~1 day. Just adds a method to existing tray app + tests.

**Risk:** Low. Reversible. Worst case: doesn't fix it, we move to Path 2.

**Ships if:** H-α holds + the registry path actually controls the BT HID device's power policy.

### Path 2 — Userland gesture-to-wheel daemon (Phase 4A from M13 plan)
**Mechanism:** Bypass `applewirelessmouse` entirely. Read raw multi-touch from Report 0x12 via RawInput or a small kernel-mode helper that surfaces the data to user-mode. Translate finger-Y deltas to wheel events. Inject via `SendInput`.

**Implementation:**
- Subscribe to raw HID reports for the BT mouse
- Parse Report 0x12 (touchpad multi-touch — already documented in cache decode)
- Detect 1-finger drag on the surface (scroll gesture)
- Compute wheel delta = -finger_y_delta * sensitivity
- `SendInput INPUT_MOUSE wheel_delta=N`

**Effort:** 1-3 days. Multi-touch parsing, gesture detection, smoothing.

**Risk:** Medium. Depends on whether RawInput gives us Report 0x12 (`mouhid` may have exclusive access — known issue from Cell 1 hid-probe `err=5` on COL01 reads). May need a small kernel helper to surface the raw data.

**Ships if:** RawInput access works OR we accept the kernel-helper dependency.

### Path 3 — BTHPORT cache patch + Wheel injection (Phase 4C from M13 plan)
**Mechanism:** Patch the cached HID descriptor to add Wheel + AC-Pan items to the Mouse Application Collection. Force HidBth to re-read the cache via disable+enable BTHENUM. HidClass then has wheel value caps; whoever supplies the wheel data (filter or daemon) has a delivery slot.

**Implementation:**
- Phase 3 decode pinpoints the insertion point (after Y usage in Mouse TLC, before EndCollection)
- Insert ~18 bytes: `09 38 15 81 25 7F 75 08 95 01 81 06 05 0c 0a 38 02 81 06`
- Recompute SDP TLV length bytes (NN at offset 175 in the 351-byte blob, LL at outer SEQUENCE start)
- Backup cache, write patched cache, force re-enum, test
- Auto-rollback on failure

**Effort:** 1-2 days for the patch tool + tests.

**Risk:** HIGHEST of the three. Cache invalidates on every re-pair (need re-apply on every pair). Apple's filter (when active) may behave unpredictably with a non-standard descriptor. Possible silent failure modes.

**Ships if:** Patch is robust AND a wheel-data source exists (which means we still need Path 2's daemon OR the filter to play nice). Path 3 ALONE doesn't ship — it's complementary to Path 2.

## Recommended sequence

1. **Validation step (1-2 hours wall clock, 60 min capture):** Use focused `m13.wprp` (committed in `ce0dd18`) to capture from a fresh reboot through 60+ minutes. Provides definitive evidence on H-α (Selective Suspend) vs other triggers. **Disambiguates Path 1 viability.**

2. **If Validation says H-α correct (Selective Suspend):** Ship Path 1. Done in ~1 day. PRD-184 closes.

3. **If Validation refutes H-α:** Ship Path 2 (userland daemon). 1-3 days. PRD-184 closes.

4. **Path 3 stays in the toolbox** for future-proofing if Apple changes their filter's behavior, but is not the primary path.

## Approval items for the user

I need explicit approval (yes/no on each) before proceeding:

1. **Validation step**: re-run a Cell-1-like sequence with `m13.wprp` ETW profile + leave the host idle for 60+ min post-reboot to capture the unified→split transition. **Cost:** ~2-3 hours of your time including reboot. Output: definitive answer on H-α.
2. **Conditional Path 1 ship**: if Validation confirms Selective Suspend, ship a Selective-Suspend-disabler in the tray app. Estimated 1 day of work; I draft the C# changes for you to review.
3. **Conditional Path 2 ship**: if Validation refutes H-α, design + prototype the userland scroll daemon. Estimated 1-3 days; I'd want to scope the design before committing — flagged for separate approval at that point.
4. **Cells 2-6 deprioritized**: T-V3-NF, USB-C cells, V1 cells become "defense-in-depth confirmation data" rather than blocking. They run only if Path 1 + Path 2 both fail.

## Files I've produced this autonomous session

- Phase 3 decoder + outputs: `scripts/mm-bthport-discover.ps1`, `scripts/mm-bthport-read.ps1`, `.ai/test-runs/.../bthport-discovery.{txt,json}`, `blob_cache_00010000.bin`, `phase3-cache-decoded.md` (commit `6b4453e`)
- Toolings fixes: AC-01 GUID, kernel-log rotation, m13.wprp focused ETW (Subagent X commit `ce0dd18`)
- Forensic timeline finding: `cell1-finding-unified-to-split-flip.md` (this commit)
- This plan: `PHASE4-PLAN-FOR-APPROVAL.md`
- Subagent Y is still running close-out updates: PSN-0001 v1.4.0, plan v1.4, playbook v1.5, issue comments, /prd update-progress to v1.21.0 (commit pending)

## Halting

I'll send you a `/sms` ping with the headline + this file's path. Halting on the approval gate. No further mutations until you respond.
