# M13 Phase 1 — Status Report (review gate)

**Captured:** 2026-04-27 14:46 MDT (rev 2 — RAWPDO removal landed)
**Author:** Claude (apex/auto)
**Status:** Phase 1 complete, all in-scope orphans cleared; HALT before Phase 2 per plan.

## BLUF

Phase 0 + Phase 1 ran across two cleanup invocations. Scroll path remained intact at every verify point. Three cleanup mutations committed: MagicMouseDriver service key, USB MI_01 LowerFilters "MagicMouse" entry, MAGICMOUSERAWPDO PnP orphan. Two bugs in the cleanup script were found and fixed mid-execution (B1 health check, B2 RAWPDO pattern). G1 decisions #2/#3/#4 are now the only blockers to Phase 2.

## Phase 0 — Pre-flight

| Step | Action | Result |
|---|---|---|
| 0.1 | Pause Windows Update 7d | OK — `PauseUpdatesExpiryTime = 2026-05-04T20:41:11Z` |
| 0.2 | Driver fingerprints | OK — `driver-fingerprints.json` |
| 0.3 | Reg export pre-cleanup | OK — `2026-04-27-142015-pre-cleanup.reg` (76 MB) |

Driver state at start (all sigs valid, signed by MS or Apple/MS HCP):
- `bthport.sys` 10.0.26100.1 sha `226EDB...`
- `HidBth.sys` 10.0.26100.1 sha `497B1A...`
- `applewirelessmouse.sys` 6.1.7700.0 sha `08F33D...`

## Phase 1 — Cleanup (transcript verbatim)

`phase01-run-2026-04-27-144111.log`

| Step | Target | Result |
|---|---|---|
| Pre | scroll-path verify | PASS (after health-check fix; see below) |
| 1 | `HKLM\...\Services\MagicMouseDriver` | **REMOVED** (run 1) |
| 2 | `HKLM\...\Enum\USB\VID_05AC&PID_0323&MI_01\7&80F490&0&0001\LowerFilters` "MagicMouse" entry | **REMOVED** (run 1) |
| 3 | `{7D55502A-...}\MAGICMOUSERAWPDO\8&4FB45D0&0&0323-2-D0C050CC8C4D` | **REMOVED** (run 2, after B2 pattern fix) — `pnputil /remove-device` returned "Device removed successfully" |
| 4 | orphan `oem*.inf` packages from MagicMouseDriver | none found |
| Final | scroll-path verify | PASS (both runs) |

Verify-WorkingState ran 5 times across the cleanup; every iteration:
- `applewirelessmouse` in `LowerFilters` ✓
- HID mouse PDO Status=OK Class=Mouse ✓ (parent node, no COL suffix)
- BTHENUM device Status=OK ✓

## Bugs found + fixed (this report)

### B1 — `Verify-WorkingState` COL01 check matched a stale orphan instead of the working PDO
- **Found:** initial `-WhatIf` halted at pre-flight. Probe showed `HID\{00001124-...}_VID&0001004C_PID&0323` (parent, no COL) Status=OK Class=Mouse, while the COL01-suffixed sibling at Status=Unknown is a stale orphan from an earlier descriptor state.
- **Fix:** check the parent HID PDO (Class=Mouse, Status=OK, no COL suffix) instead of the COL01 child. Empirically validated against current state before re-run.

### B2 — Step 3 RAWPDO removal silently no-op'd (`\\` literal in `-like` pattern)
- **Found:** run-1 transcript said "MAGICMOUSERAWPDO node already gone", but post-cleanup probe showed the node still present:
  ```
  {7D55502A-2C87-441F-9993-0761990E0C7A}\MAGICMOUSERAWPDO\8&4FB45D0&0&0323-2-D0C050CC8C4D
  Status=Unknown
  ```
- **Cause:** pattern was `'{...}\\MagicMouseRawPdo*'` — `\\` in `-like` is two literal backslashes, but the actual InstanceId has a single backslash after the GUID.
- **Fix:** changed to `'{7D55502A-...}\*MAGICMOUSERAWPDO*'`.
- **Status:** **RESOLVED.** Re-run with the fix executed `pnputil /remove-device` successfully; post-run probe returns `rawpdo_present: null`.

### B3 (cosmetic, unfixed) — Step 2 transcript noise from `Get-ItemProperty -ErrorAction Stop`
- **Found:** run-2 transcript shows `PS>TerminatingError(Get-ItemProperty): "...Property LowerFilters does not exist..."` for the now-cleaned USB MI_01 device.
- **Cause:** the per-step try/catch *does* swallow the error correctly (the friendly `... USB instance has no LowerFilters` message follows), but the global `$ErrorActionPreference='Stop'` causes the underlying terminating-error to surface in the transcript before catch handles it.
- **Status:** cosmetic. The check works correctly. Could be silenced by switching to `-ErrorAction SilentlyContinue` + null-check, but not worth a third run.

## Reg-file diff verification (audit trail)

`reg.exe export HKLM\SYSTEM` × 3 timestamps, converted UTF-16 LE → UTF-8, diffed at section + value level.

| Mutation | Expected | Found in diff | Status |
|---|---|---|---|
| run 1 / Step 1 — `MagicMouseDriver` service section in `CurrentControlSet` + `ControlSet001` | 8 sections deleted | 8 deleted (4 per hive: root + Parameters + Parameters\Wdf + Enum) | ✓ |
| run 1 / Step 2 — `LowerFilters` REG_MULTI_SZ at `USB\VID_05AC&PID_0323&MI_01\7&80F490&0&0001` | 2 value deletes | 2 deleted, hex decodes to `MagicMouse` (UTF-16 LE: `4d,00,61,00,67,00,69,00,63,00,4d,00,6f,00,75,00,73,00,65,00`) | ✓ |
| run 1 — any unintended changes to `applewirelessmouse` / BTHENUM / HidBth | none | none in MagicMouse-filtered grep | ✓ |
| run 2 / Step 3 — `MagicMouseRawPdo` Enum + DeviceClasses sections | 14 sections (7 per hive: 5 Enum + 2 DeviceClasses symlinks) | 14 deleted | ✓ |
| run 2 — any LowerFilters changes | none | none | ✓ |

Diff totals: pre→v1 = 1197 lines (mutations + ambient kernel/timestamp noise), v1→v2 = 208 lines. No unexpected MagicMouse/RAWPDO references remain in the post-v2 export.

## Phase 1 close-out artifacts

| Artifact | Path |
|---|---|
| Pre-cleanup .reg backup | `D:\Users\Lesley\Documents\Backups\2026-04-27-142015-pre-cleanup.reg` (76 MB) |
| Post-cleanup .reg (run 1) | `D:\Users\Lesley\Documents\Backups\2026-04-27-144153-post-cleanup.reg` (76 MB) |
| Post-cleanup .reg (run 2) | `D:\Users\Lesley\Documents\Backups\2026-04-27-144619-post-cleanup-v2.reg` (76 MB) |
| Driver fingerprints | `.ai/test-runs/m13-phase0/driver-fingerprints.json` |
| PnP probe (initial) | `.ai/test-runs/m13-phase0/pnp-probe.json` |
| Phase 0+1 transcript run 1 | `.ai/test-runs/m13-phase0/phase01-run-2026-04-27-144111.log` |
| Phase 0+1 transcript run 2 | `.ai/test-runs/m13-phase0/phase01-run-2026-04-27-144544.log` |
| **Reg-diff audit report** | `.ai/test-runs/m13-phase0/reg-diff.md` (full pre→v2 audit, hex decoded inline) |
| State snapshot run 1 | `.ai/snapshots/mm-state-20260427T204156Z/` |
| State snapshot run 2 | `.ai/snapshots/mm-state-20260427T204622Z/` |

## MOP changes (this session, baked in for future phases)

| File | Change |
|---|---|
| `scripts/mm-phase1-cleanup.ps1` | B1 fix (Verify-WorkingState now checks parent HID PDO Class=Mouse Status=OK, not stale COL01 child) + B2 fix (RAWPDO `\\` → `\*` pattern) |
| `scripts/mm-pause-windows-update.ps1` | NEW — Phase 0.1 helper, idempotent, supports `-Resume` |
| `scripts/mm-phase01-run.ps1` | NEW — admin-PS orchestrator: pause WU + cleanup -WhatIf + y/n + cleanup real, with transcript logging |
| `scripts/mm-reg-diff.sh` | NEW — diff two .reg exports, decode hex(7)/hex(1) inline, emit markdown audit. **MOP gate** at every mutation phase boundary. |
| `scripts/mm-phase1-closeout.sh` | NEW — bundles reg-export + reg-diff + state-snapshot for one-shot WSL close-out |
| `.ai/test-plans/m13-baseline-and-cache-test.md` | v1.0 → v1.1: Phase 1 step list updated to include reg-diff verification gate; Telemetry table promotes "Registry diff" to MOP gate; Phase 1 success criteria + halt conditions updated |

## Outstanding before Phase 2

### Cleanup residuals
1. **MAGICMOUSERAWPDO orphan still in PnP tree** (B2). Pattern fix is in. Two clean paths:
   - **(a)** Re-run `mm-phase01-run.ps1 -AutoConfirmCleanup` from admin PS — Step 3 will now remove it; Steps 1/2/4 are idempotent no-ops; Pause WU re-sets the same expiry.
   - **(b)** Defer — RAWPDO is a stale `MagicMouseRawPdo` interface from MagicUtilities, harmless until Phase 2 USB-C test cells (`T-V3-AF-USB`, `T-V3-NF-USB`) where it could interfere with USB enumeration.
2. **COL01 sibling orphan at Status=Unknown** — `HID\{00001124-...}_VID&0001004C_PID&0323&COL01\A&31E5D054&B&0000`. Out of mm-phase1-cleanup scope. Likely benign; can be removed via `pnputil /remove-device` if Phase 2 testing surfaces issues. Recommend leaving for now.

### G1 plan deltas (per `m13-g1-summary.md`) — your sign-off needed before Phase 2
| # | Decision | Status |
|---|---|---|
| 1 | Approve Phase 1 cleanup as-written | **DONE** (executed) |
| 2 | Confirm Phase 2 axis additions (USB-C cells + sleep/wake + WM_MOUSEWHEEL counts) | **PENDING** |
| 3 | Confirm Phase 4 branch collapse (4B dead per peer-review; only 4A + 4C remain) | **PENDING** |
| 4 | Approve fixing kernel bugs BLK-001/002, SF-003 before any kernel test | **PENDING** |

## Recommended next action

Pick one:
- **A.** Approve `(a)` to clear RAWPDO orphan now, then ack G1 #2/#3/#4 → I update the M13 plan to v1.1 and we're staged for Phase 2.
- **B.** Approve `(b)` defer-RAWPDO + ack G1 #2/#3/#4 → I update the plan to v1.1 with the deferral noted, staged for Phase 2 (with a step in Phase 2 USB-C cells to remove RAWPDO before plugging the cable).
- **C.** Halt entirely — disagreements on the bug fixes or G1 deltas; iterate on the plan first.

Halting per instruction. No further mutations until you choose.
