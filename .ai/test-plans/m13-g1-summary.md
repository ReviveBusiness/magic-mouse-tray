# M13 Pre-Execution Gate (G1) — Summary for User Review

**Date:** 2026-04-27 (afternoon)
**Status:** Ready for user approval before Phase 1 executes

## TL;DR

The pre-execution gate did its job. **One of the three Phase 4 hypothesis branches was empirically refuted before we executed**, saving an estimated 4 hours of Phase 2-3 capture work that would have been wasted. Three specialist reviewers + a refreshed-corpus NLM peer-review all surfaced findings that change the plan.

**Recommendation: APPROVE Phase 1 cleanup as-is. REVISE Phase 2-4 with reviewer findings before execution.**

## What was done since you last approved

1. M13 plan written → `.ai/test-plans/m13-baseline-and-cache-test.md`
2. Phase 1 cleanup script → `scripts/mm-phase1-cleanup.ps1` (admin PowerShell, with `-WhatIf` mode)
3. Reg export script → `scripts/mm-reg-export.sh`
4. Test orchestrator → `scripts/mm-test-matrix.sh`
5. NLM corpus refreshed (M13 plan + registry diff report ingested)
6. Three specialist reviewer agents ran in parallel
7. Targeted /peer-review on registry-cache-patch viability

## Reviewer verdicts

| Reviewer | Verdict | Top finding |
|---|---|---|
| Kernel-driver correctness (`mm-review-kernel`) | **CHANGES-NEEDED** | BLK-001: BRB Length not validated before field dereferences (BSOD risk under malformed BRB) |
| BTHPORT patch safety (`mm-review-registry`) | **APPROVE-WITH-CONDITIONS** | Rollback needs second Disable+Enable after registry restore (in-memory state survives registry rollback) |
| Test-matrix adversarial (`mm-review-testmatrix`) | **CHANGES-NEEDED** | Sleep/wake cycle missing from matrix — most common real-world breaking scenario |

Reports at `.ai/code-reviews/{kernel-correctness,bthport-patch-safety,test-matrix-adversarial}.md`.

## Targeted peer-review (NLM)

**Question:** Will patching `BTHPORT\...\CachedServices\00010000` to add wheel/AC-Pan declarations work, given Apple's `applewirelessmouse.sys` synthesizes scroll at runtime?

**Verdict: REJECT** — with three concrete empirical citations:

1. Apple's filter REPACKAGES multi-touch into a proprietary report layout we don't have the schema for. A descriptor patch that doesn't byte-match Apple's runtime output produces silent failure or phantom inputs.
2. Linux `hid-magicmouse.c` proves wheel synthesis happens at the input-event layer (`input_report_rel(REL_WHEEL, step_y)`), not by writing wheel bytes into a HID report. There's no "raw" wheel data to align our descriptor against.
3. MagicUtilities (per the Apr 3 registry backup) **replaced HidBth as function driver** — they did NOT patch the BTHPORT cache. The empirical reference implementation refutes the hypothesis.

**This kills Phase 4B (registry-patch with Apple's filter).** Phase 4C (registry-patch + our own SDP-scanner filter) still viable. Phase 4A (no kernel, userland gesture daemon) viable but needs scroll-quality validation.

## What changes to the plan

### Add before Phase 1

- **Pause Windows Update for 7 days** (`UsoClient.exe PauseUpdate`) — prevents mid-test driver swaps
- **Capture build numbers + driver versions** of `bthport.sys`, `HidBth.sys`, `applewirelessmouse.sys` at start

### Phase 1 — unchanged
The cleanup script `mm-phase1-cleanup.ps1` is good. Has per-step verification + halt-on-fail + `-WhatIf` mode. Approve as-is.

### Phase 2 — add 2 cells + 1 sub-step per existing cell

- New: T-V3-AF-USB (USB-C cable connected during test)
- New: T-V3-NF-USB (same with NoFilter)
- Add to every cell: sleep/wake sub-step (between repair and reboot)
- Add quantitative scroll measurement: `WM_MOUSEWHEEL` event count + per-event timestamp during 3-second 2-finger gesture

### Phase 3 — unchanged

### Phase 4 — collapse to 2 branches (4B is dead)

- **4A**: Remove `applewirelessmouse`. Build userland gesture-to-wheel daemon that reads multi-touch via raw HID. Battery already works in this state.
- **4C**: Fix kernel reviewer findings (BLK-001/002, SF-003) on `5ff866a` SDP-scanner filter. Ship as production. Cache patch optional, only if needed for re-pair-free install.

### Pre-Phase-4 gate

The kernel reviewer findings (BLK-001/002, SF-003) MUST be fixed before any version of our filter is installed for testing. They're real bugs that BSOD the user under specific (rare but possible) BRB conditions.

## Decision points for you

1. **Approve Phase 1 cleanup as-written** (script ready, low risk) — yes/no
2. **Confirm Phase 2 axis additions** (USB-C cells + sleep/wake + WM_MOUSEWHEEL counts) — yes/no
3. **Confirm Phase 4 branch collapse** (4B dead per peer-review, only 4A + 4C remain) — yes/no
4. **Approve fixing kernel bugs (BLK-001/002, SF-003) before any kernel test** — yes/no

If yes to all 4: I'll update the M13 plan to v1.1 with these changes, and we proceed with Phase 1 in your admin shell.

If no/discussion needed on any: tell me which and we iterate.

## Files to skim if you want details

- `.ai/code-reviews/kernel-correctness.md` (29 KB) — BLK/SF findings with file:line + recommended fixes
- `.ai/code-reviews/bthport-patch-safety.md` (21 KB) — registry safety conditions
- `.ai/code-reviews/test-matrix-adversarial.md` (35 KB) — missing axes with rationale
- `.ai/test-plans/m13-baseline-and-cache-test.md` (full plan)

## The win that justifies all this prep

Phase 4B (cache-patch with Apple's filter) seemed like the easiest path. Tonight's overnight session would have spent 4+ hours collecting data to discover it doesn't work via test failure. Instead the pre-execution gate produced an empirical REJECT in 30 minutes of agent + NLM time. This is the playbook working as designed.
