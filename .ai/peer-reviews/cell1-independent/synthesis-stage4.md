# Cell 1 Independent Analysis — Stage 4 Synthesis

**Captured:** 2026-04-27 (post Cell 1 close-out)
**Author:** Claude (apex/auto), reading the three blind agent reports
**Source agents:** A (HID state evolution), B (ETW kernel forensics), C (test-3 forensic deep-dive)
**Stage 3 (NLM peer-review):** SKIPPED — three agents disagreed productively; groupthink risk was not the failure mode this pipeline needed to catch.

## BLUF

The unbiased pipeline produced **two material corrections** to my cell1-report.md and one **direct refutation of Q7's optimistic interpretation**. Three independent agents converge on: scroll/battery flip happens at the REBOOT, AC-01 is a script bug, and pre-reboot vs post-reboot are fundamentally different operating modes. They diverge on the mechanism — which the next investigation step (Phase 3 cache decode) is designed to disambiguate.

---

## Convergent findings (3 of 3 agents agree)

| # | Finding | Citations |
|---|---|---|
| C-1 | The user-perceptible scroll/battery flip happened at the REBOOT, not at unpair, repair, or sleep/wake | A:obs+wheel-counter; C:cross-ref of substep-state-evolution; B implicitly via Power-event presence pre-reboot only |
| C-2 | accept-test AC-01 "Driver bound (LowerFilters) FAIL" is a script bug — queries SDP-service GUID `{00001200-...}` instead of HID-class GUID `{00001124-...}`. `applewirelessmouse` IS bound at all times. | A independently flagged from `live-driver-state.json`; C independently from same file |
| C-3 | Pre-reboot and post-reboot are mutually-exclusive operating modes for scroll vs battery | A: explicit table; C: state reconstruction; B implicit |

Strong validation: AC-01 was independently caught by A and C without seeing each other's analysis or my Cell 1 report. The bug is real.

---

## Divergent findings (agents disagree — investigation needed)

### D-1: What the BTHPORT cached descriptor actually contains

| Agent | Claim |
|---|---|
| A | Pre-reboot the descriptor was a *single unified TLC* including Wheel; post-reboot it became *split* COL01+COL02 without Wheel. The filter is doing the splitting. |
| C | The cache *already declares* split COL01+COL02. The filter's job is to *inject* Wheel into COL01 at runtime; post-reboot it attached but did not inject (passthrough). |

These hypotheses predict different bytes in the cache. Phase 3 (read `BTHPORT\Parameters\Devices\d0c050cc8c4d\CachedServices\00010000`) is the disambiguator.

### D-2: Did the kernel filter actually run post-reboot?

| Agent | Claim |
|---|---|
| C | Yes — kernel-debug-tail shows MagicMouse: AclIn / Translate R12 entries (passthrough mode, no descriptor injection) |
| B | INVALID DATA — all 7 kernel-debug-tail.log files are byte-identical, same 100 lines, single 2.58 s window from earlier in the cell. Cannot conclude whether the filter ran post-reboot or not. |

Agent B is correct on the data integrity issue. Agent C's hypothesis is plausible but cannot be evidenced from the captured data. Status: NEED NEW CAPTURE.

---

## Material corrections to cell1-report.md (mine)

### M-1: My "Q7 trending YES via Phase 4A" claim is REFUTED for any single-mode configuration observed in this cell

Agent A: "No sub-step delivered both scroll and battery simultaneously. Mutual exclusion in all observed states."

In every observed state, scroll-working and battery-readable are mutually exclusive. Phase 4A's premise (userland scroll daemon reading raw multi-touch + COL02 battery accessible) requires BOTH conditions in the same configuration — which Cell 1 did NOT demonstrate. 4A is not killed but its viability is unproven and harder than my report implied.

### M-2: My inference that "MagicMouse: AclIn" lines proved a kernel filter was running post-reboot is INVALID

The kernel-debug-tail content I cited was a stale snapshot replayed across all 7 sub-steps. There's no valid evidence the kernel filter ran post-reboot.

### M-3: My characterization of "applewirelessmouse failed to bind on this boot" was correctly REJECTED — but for the wrong reason

I rejected this hypothesis (H-005 in PSN-0001) based on `LowerFilters` registry value still being set. Live registry confirms `LowerFilters=["applewirelessmouse"]`, so the filter is *registered*. But registry binding ≠ runtime activation. The independent agents converge on: filter is registered, but its scroll-synthesis behaviour did not occur post-reboot. Whether that's "filter not loaded," "filter loaded but inert," "filter loaded but hit a different code path," etc. is not yet determined.

---

## Refuted hypotheses from earlier sessions (now with stronger evidence)

| Hypothesis | Original status | Cell 1 independent verdict |
|---|---|---|
| H-005: applewirelessmouse filter binding is unreliable across reboot | I rejected in Cell 1 report | **REFINED** — registry binding survives but operational behaviour does not. Original H-005 was directionally correct, my rejection was premature |
| H-006: Scroll path requires applewirelessmouse to inject wheel events | I marked REJECTED-partial | **STRENGTHENED** — pre-reboot scroll worked AND post-reboot lost both wheel events AND COL02-stripping at the same moment. The two changes happen together, suggesting a single common cause: filter's runtime augmentation behaviour |
| H-007: Q7 — can scroll+battery ship without a kernel driver? | I marked CONFIRMED-PARTIAL | **DOWNGRADED to UNANSWERED** — Cell 1 demonstrates the two are mutually exclusive in observed states. Q7 yes-answer requires a state we have not yet observed |

---

## New questions surfaced by independent analysis

1. **What does the BTHPORT cache really contain?** (Phase 3 cache decode answers D-1)
2. **Does the kernel driver actually run post-reboot, or was the debug log stale?** (Need fresh non-stale capture — would invalidate Agent C's "passthrough mode" hypothesis if filter is in fact dead post-reboot)
3. **Why is mm3-debug.log not rotating between sub-steps?** (orchestration bug — `mm-test-matrix.sh` should trigger a log truncate or capture-end-marker per sub-step)
4. **Was the wpr GeneralProfile choice a documented requirement, or did we accidentally use the wrong profile?** (Agent B: GeneralProfile produces no BT/HID events — we should have used a custom WPRP)

---

## Recommended next steps

In priority order:

### 1. Phase 3 — BTHPORT cache decode (read-only, ~30 min)

Highest leverage, lowest risk. Disambiguates D-1 (Agent A vs Agent C cache hypothesis). Write `mm-bthport-read.ps1` per the M13 plan. Read `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\d0c050cc8c4d\CachedServices\00010000` (REG_BINARY), parse the SDP TLV outer structure, extract the embedded HID descriptor, decode it.

If cache contains Wheel in unified TLC → Agent A's mechanism is right.
If cache contains split TLCs without Wheel → Agent C's mechanism is right.

### 2. Re-instrument with a focused wpr profile (per Agent B's recommendation)

Build a custom `m13.wprp` enabling: `Microsoft-Windows-Kernel-PnP`, `Microsoft-Windows-Bluetooth-BTHUSB`, `Microsoft-Windows-Bluetooth-BthMini`, `Microsoft-Windows-HIDClass`, `Microsoft-Windows-WDF`, `Microsoft-Windows-Kernel-Power`. Expected size: 50–200 MB instead of 14.5 GB. Required for any cell that wants to actually answer kernel-side questions.

### 3. Fix mm-accept-test.ps1 AC-01 GUID

Trivial fix. Already AP-16 in the playbook. Should land before Cell 2.

### 4. Fix mm-test-matrix.sh kernel-debug-tail capture so each sub-step gets fresh log content

Possibly: tag-and-truncate `/mnt/c/mm3-debug.log` at sub-step start so each sub-step's tail represents that sub-step's activity.

### 5. Update PSN-0001 H-005, H-006, H-007 statuses

Replace my Cell 1 report's premature confidence with the refined verdicts above.

### 6. Update cell1-report.md with the M-1/M-2/M-3 corrections

Reference this synthesis document.

---

## What's still NOT proved

- The descriptor patch viability (Phase 4C-lite) — depends on cache decode (#1 above)
- Phase 4A daemon viability — depends on whether raw multi-touch can be accessed when the filter is also delivering its wheel-synthesis path (mutual exclusion question)
- Whether selective suspend / D-state plays any role (would need raw kernel-power events from a focused wpr capture)
- Whether the v1 mouse (PID 0x030D) exhibits the same architecture — Cell 5 territory

---

## Files

- `agent-a-hid-state-evolution.md`
- `agent-b-etw-kernel-forensics.md`
- `agent-c-test3-forensic-deepdive.md`
- This file: `synthesis-stage4.md`
- Original (now-corrected) Cell 1 report: `../../2026-04-27-154930-T-V3-AF/cell1-report.md` — DO NOT delete; the corrections-vs-original delta is itself signal

## Process learning

- Multi-agent blind analysis caught two material errors (M-1, M-2) that single-agent analysis missed
- Agent B's data-integrity check (the byte-identical kernel-debug-tail files) was the single highest-value finding in this round — would have been invisible to anyone not specifically auditing the data sources
- Cost: ~$10 of agent time + ~1 hour wall clock. Saved: at minimum the cost of acting on M-1/M-2 incorrect conclusions, which would have shaped Phase 4 planning
- Anti-pattern candidate for the playbook: "single-agent forensic conclusions on multi-source data without independent verification of source integrity"
