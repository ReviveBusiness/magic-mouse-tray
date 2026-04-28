# M13 Phase 2 — Cell 1 (T-V3-AF) Status Report

**Captured:** 2026-04-27 17:57 MDT
**Author:** Claude (apex/auto)
**Status:** Cell ran end-to-end (test-1 through test-3); HALT before Cell 2 per close-out gate.

## BLUF

Cell 1 (T-V3-AF, AppleFilter mode, full sequence: test-1 → unpair → repair → test-2 → sleep/wake → test-2b → reboot → test-3) ran end-to-end. **Empirical Q7 answer is forming: scroll cannot be delivered through the current COL01 HID descriptor regardless of `applewirelessmouse` filter state — the descriptor lacks `Usage=0x0038` (Wheel).** Battery works because COL02 vendor TLC is independent. Phase 4A (userland scroll daemon) remains the most likely viable production path; 4C (descriptor patch on BTHPORT cache) is the no-userland-daemon alternative.

## Test-3 (post-reboot) verdict

| Behaviour | Result | Evidence |
|---|---|---|
| Pointer movement | ✓ | Manual obs (smooth) + COL01 X/Y declared |
| 2-finger scroll | **✗** | wheel-events.json `event_count: 0` over 3s gesture |
| AC-Pan horizontal | ✗ | Manual obs |
| Left click | ✓ | Manual obs |
| Right click | ✓ | Manual obs |
| Battery via tray | ✓ | Manual obs "Magic Mouse 2024 — 44% — Next 30min"; tray-debug `OK ... battery=44% (split)` |

## Critical artefacts

| Artefact | Path | Notes |
|---|---|---|
| HID probe (test-3) | `test-3/hid-probe.txt` | COL01 InputValueCaps = X (0x30) + Y (0x31) only — no Wheel (0x38). COL02 FeatureValueCaps[0]=ReportID=0x55 vendor (0xFF02) |
| accept-test JSON | `test-3/accept-test.json` | 5/8 PASS. **AC-01 FAIL is a script bug** (queries SDP-service GUID `{00001200-...}` instead of HID-class GUID `{00001124-...}`); ignore. AC-04 FAIL (no Wheel/AC-Pan in COL01 caps) is the real signal. AC-05 PASS (Battery TLC UP=0xFF00 Usage=0x0014 InputLen=3) |
| Wheel-events JSON | `test-3/wheel-events.json` | 0 events / 3s — scroll path has nowhere to deliver wheel data |
| Live driver-state probe | `test-3/live-driver-state.json` | `LowerFilters=["applewirelessmouse"]` on the **correct** HID-class GUID device. `applewirelessmouse` service loaded. COL01 + COL02 both Status=OK Class=Mouse/HIDClass |
| Pre-reboot ETW | `etw-trace-pre-reboot.etl` | 14.5 GB, GeneralProfile from cell start to reboot |
| Post-reboot ETW | `etw-trace-post-reboot.etl` | 1.65 GB, post-login through test-3 |
| Pre-reboot Procmon | `procmon-pre-reboot-Bootlog{,-1..-8}.pml` | 9 files × ~3 GB = 28 GB. Unfiltered. Filter v1 wasn't active for this cell. |
| Post-reboot Procmon | (none — `-SkipProcmon` used) | Decision: avoid further data-volume cost; ETW + filter-validation log already sufficient |
| Filter v1 validation | `procmon-filter-validation.PML` (1.4 MB) | Saved separately during filter dev; proves filter shrinks captures by ~99.99% |

## Bug found in mm-accept-test

`AC-01 Driver bound (LowerFilters)` queries:

```
HKLM\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001200-...}_VID&...&PID&0323\...
```

That's the **Bluetooth Service Discovery** (PnP class) GUID, which never has a `LowerFilters` property. The HID class GUID `{00001124-...}` is where filters bind. Live probe confirmed `LowerFilters=["applewirelessmouse"]` on the correct GUID. Tray's own `DRIVER_CHECK pid=0x0323 LowerFilters=bound` log entry agrees.

**Fix needed in `scripts/mm-accept-test.ps1`** (out-of-scope for this cell): change the GUID literal from `{00001200-0000-1000-8000-00805F9B34FB}` to `{00001124-0000-1000-8000-00805F9B34FB}` for the AC-01 check. Track in PSN-0001 follow-ups.

## Empirical answers to plan questions

| Q | Plan question | Cell 1 answer |
|---|---|---|
| Q1 | Does v3 BTHPORT cached descriptor declare COL02 (UP=0xFF00 U=0x0014)? | **YES** — battery TLC visible to user-mode probe; HidD_GetFeature on Report 0x90 gets to a different error code (`err=1`) than other report IDs (`err=87`), suggesting the report ID is recognized |
| Q2 | Does cached descriptor declare wheel/AC-Pan? | **NO** for COL01 ValueCaps as presented to HidClass. Whether the cache itself has them or applewirelessmouse strips them is Phase 3 work (cache decode) |
| Q3 | With `applewirelessmouse` as function driver, what reaches HidClass? | COL01: X/Y only. COL02: vendor battery TLC. Apple's filter present but COL01 wheel not in caps |
| Q4 | NoFilter mode battery? | Deferred to T-V3-NF (Cell 2) — but Cell 1 already shows battery readable while applewirelessmouse is bound, so the more interesting question is whether NoFilter changes anything |
| Q5 | Does descriptor patch yield COL01-with-scroll + COL02-with-battery? | Phase 3/4 work |
| Q6 | v1 mouse architecture comparison? | Deferred to T-V1-AF (Cell 5) |
| Q7 | Can scroll+battery ship without a kernel driver? | **Trending toward YES via Phase 4A** — battery works without one (COL02), scroll requires either descriptor patch (Phase 4C) OR userland daemon synthesizing wheel events from raw multi-touch |

## Known issues caught during the cell

1. **Procmon UNC `/BackingFile` rolls over to D:\Users\Lesley\Desktop\Bootlog-N.pml** instead of writing to the requested UNC path. 9 rollover files at 3 GB each accumulated. Filter v1 (PMF + Drop Filtered Events) cuts this 99.99% but wasn't active for cell 1; will be for cells 2-6.
2. **Procmon Boot Logging was inadvertently active** at start of cell 1 (this is a separate setting that creates a Bootlog.pml on each system boot). Disabled by user before reboot per Cell 1 close-out.
3. **`mm-accept-test.ps1` AC-01 queries wrong GUID** (see above). False negative; ignore until script fixed.
4. **Cell unpair/repair sub-step did NOT wipe `LowerFilters`** — this contradicts an earlier hypothesis from PSN-0001 sessions. The filter binding survived unpair/repair and reboot. The actual scroll-broken cause is descriptor-level (no wheel usage), not filter-binding.

## Outstanding / decisions before Cell 2 (T-V3-NF)

| # | Item | Required for | Status |
|---|---|---|---|
| 1 | Wire `m13-procmon-filter.PMF` into `mm-phase2-reboot-helper.ps1` postreboot | Cell 2+ | **DONE** (commit 52c4753, validated on filter test) |
| 2 | Filter v2: add `Path contains BTHPORT`, `\Device\BTHENUM`, `\Driver\applewirelessmouse`, `\Driver\HidBth`; consider Operation=RegSetValue Include + `Process Name is wmiprvse.exe` Exclude | Phase 4 / cells where kernel I/O matters | **PENDING** (filter v1 fit-for-purpose for state-transition data) |
| 3 | Switch wpr GeneralProfile → focused `logman` trace (HIDClass, BTH-BTHPORT, Kernel-PnP) | Cell 2+ data volume control | **PENDING** (would reduce 1.6 GB ETW per cell to ~100-500 MB) |
| 4 | Enable BT btsnoop logging (`HKLM\...\BTHport\Parameters VerboseOn=1`) | Phase 4 entry | **PENDING** — schedule before Phase 4 |
| 5 | Fix `mm-accept-test.ps1` AC-01 GUID | All future cells (avoid false-negative noise) | **PENDING** (small fix, tracking) |
| 6 | Disable Procmon Boot Logging | Already done by user | **DONE** |
| 7 | Investigate stale `MagicMouse:*` kernel debug log content | Cell 1 follow-up — was it from a previous experiment? | **PENDING** — check `/mnt/c/mm3-debug.log` provenance |

## Recommended Phase 4 path

Given Cell 1's findings:

- **4A (no kernel + userland gesture daemon)**: high confidence. Battery works without intervention. Scroll requires reading raw Report 0x12 from the BT HID device (mouhid exclusivity is the blocker for direct user-mode HID reads — but raw input via `RegisterRawInputDevices` may work, or via a small kernel filter that surfaces the raw data to user-mode). Userland daemon then `SendInput`s `WM_MOUSEWHEEL` events.
- **4C (SDP-scanner filter + descriptor patch)**: medium confidence. The scanner filter is in tree (commit `5ff866a`); kernel reviewer findings BLK-001/002, SF-003 must be fixed first (G1 #3 deferred — re-evaluate after Cell 2 ETW shows whether real BRBs trigger malformed conditions).

Either path satisfies Q7. Phase 3 (descriptor decode) still informs which is cheaper.

## What this cell did NOT prove

- v1 mouse behaviour (different PID, deferred to Cell 5)
- USB-C cell behaviour (deferred to Cells 3-4)
- NoFilter mode comparison (Cell 2)
- Actual cache contents (Phase 3)

Halting per the per-phase close-out gate. Block 1 next.

## Corrections (post Phase 3)

The following material errors in this report were identified via independent multi-agent forensic analysis (3 blind agents + synthesis) and superseded by Phase 3 cache decode (commit 6b4453e).

**M-1**: My "Q7 trending YES via Phase 4A" was directionally correct but for the wrong reason. I described the mechanism vaguely. Phase 3 confirms YES via 4A, but the mechanism is specifically: userland reads raw Report 0x12 multi-touch data + injects wheel events via SendInput WM_MOUSEWHEEL. This is the same pattern as Linux hid-magicmouse.c at the Win32 input layer -- NOT anything related to descriptor augmentation or filter behavior.
Source: phase3-cache-decoded.md

**M-2**: My section "MagicMouse: AclIn lines prove kernel filter running post-reboot" was based on kernel-debug-tail content that Agent B identified as stale duplicate data from a prior capture window -- not post-reboot evidence. The content was from an earlier session and was inadvertently included in the Cell 1 analysis window. The AclIn conclusion is invalid.
Source: agent-b-independent-report.md (Agent B finding: stale duplicate data)

**M-3**: My H-005 rejection stated "Real failure mode is descriptor-level." This was directionally wrong. Phase 3 confirms LowerFilters binding DOES survive reboot (consistent with my finding), but the correct mechanism is: the RUNTIME BEHAVIOR of applewirelessmouse (Win32-layer input injection + Feature report trapping) goes inert post-reboot, despite the filter being loaded. The failure is runtime behavior becoming inert, NOT a descriptor-level issue as I originally stated. H-005 status: REJECTED, but with a corrected mechanism.
Source: phase3-cache-decoded.md, synthesis-stage4.md

**M-4**: NEW correction not in original report. My initial reading of "battery N/A pre-reboot, 44% post-reboot" as device behavior was wrong. The cache HAS battery data (Report 0x90 confirmed in Phase 3 decode). What changes pre/post-reboot is whether applewirelessmouse blocks Feature 0x47 reads. When filter active (pre-reboot) = Feature trap blocks battery reads (FEATURE_BLOCKED err=87). When filter inert (post-reboot) = cache surfaces unmodified, battery readable at 44%. One mechanism (Feature trap) explains both the err=87 blocking and the post-reboot recovery.
Source: phase3-cache-decoded.md (Report 0x90 on UP=0xFF00 U=0x14 confirmed in cache)

## Post-Phase-4-investigation corrections (2026-04-27 evening)

**M-5** (NEW): Phase 4-Omega alone does NOT enable battery-while-scrolling. State A (recycle target) has scroll-works + battery-N/A. Mutual exclusion is fundamental to Apple's filter design when the filter is active. Phase 4A or 4C required for both features simultaneously.

**M-6** (NEW): Experiment A persistence monitor confirmed State A holds at least 65 min idle. Cell 1's '43-min flip' may have been triggered by orchestrator activity rather than passive idle-out. Selective Suspend hypothesis (H-alpha) remains unconfirmed but moot given recycle availability.
