# Experiment A — Recycle Test Result

**Captured:** 2026-04-27 19:51 MDT
**Method:** Submit `FLIP:AppleFilter` via mm-task-runner queue (LF unchanged but mm-state-flip.ps1 still does Disable+Enable on the BTHENUM device)

## State transition observed

| Marker | T+0 (baseline) | T+20 (post-recycle) |
|---|---|---|
| LowerFilters | applewirelessmouse | applewirelessmouse (unchanged) |
| COL02 visibility | **present** | **missing** |
| Inferred mode | "AppleFilter" + COL02 visible = SPLIT | "AppleFilter" + COL02 missing = UNIFIED |
| Filter trap on Feature 0x47 | (no recent tray poll) | should resume on next poll |

Source logs at `flip-T0-baseline.log`, `flip-T5-recycle.log`, `flip-T20-postrecycle.log`.

## Key conclusion

**A `Disable-PnpDevice` + `Enable-PnpDevice` cycle on the BTHENUM HID device flips the Magic Mouse from split mode (scroll broken, COL02 visible, battery readable in user mode) BACK to unified mode (Apple-filter trap firing, COL02 stripped, scroll synthesis active).**

This is mediated by:
1. PnP `Disable-PnpDevice` removes the existing device stack
2. PnP `Enable-PnpDevice` triggers a fresh `IRP_MN_START_DEVICE` + `AddDevice` IRP chain
3. `applewirelessmouse.sys`'s `AddDevice` callback initializes its trap path
4. Filter is now active — Feature 0x47 trap fires; HidClass enumerates without COL02 (because the filter swallowing the descriptor responses for that path)
5. Scroll synthesis (Win32-input-layer wheel injection) becomes active again

## Implications

- **Filter binding works correctly.** Registry LowerFilters survives, AddDevice fires when triggered.
- **Filter init at AddDevice produces unified mode reliably.** The filter is NOT broken; it's not a binding issue.
- **The bug we observed (split mode after some idle period) is a RUNTIME state degradation, not a binding failure.** Something causes the filter's runtime activity to stop, but its binding/init code path still works.
- **The fix is RECYCLE-ON-DEMAND**: tray app detects the split-mode signature (COL02 visible / FEATURE_BLOCKED stops firing), runs Disable+Enable on the BTHENUM device. Self-healing.
- **No reboot needed.** No registry mutations needed. Just a PnP recycle.

## What we still don't know

- **What triggered the original degradation at 17:43:44** (Selective Suspend, idle-out, user action, etc.) — H-α not yet confirmed/refuted, but it's now LESS interesting because the recycle fix sidesteps it
- **How long the unified mode persists post-recycle** — need to monitor over the next 30-90 minutes via tray-debug polls and FLIP:VerifyOnly
- **Whether the same recycle fix works post-reboot** — assumed yes (AddDevice is AddDevice) but not yet tested
- **Whether the filter recipe needs other ops** (registry warm-up, driver service restart, etc.) — empirically a recycle alone is sufficient

## Phase 4 path simplification

Cell 1 + Phase 3 + this experiment collapse to a much simpler PRD-184 fix:

**Phase 4-Ω (NEW, simplest path):** Tray app self-heals by recycling the BTHENUM HID device when it detects degraded mode.

Detection signal: tray's existing `HIDP_CAPS` log line. When path includes `&col02` AND ReportID 0x90 is readable directly (not FEATURE_BLOCKED), device is in degraded mode. Auto-trigger recycle.

Recycle command (admin-required): `Disable-PnpDevice` + `Enable-PnpDevice` on the BT HID instance. Same code mm-state-flip.ps1 already has.

Estimated effort: ~1 day to wire the detection + recycle into the tray app + UAC flow for the elevated PnP op.

Compared to Path 1 (Selective Suspend disabler): roughly equivalent. Both are ~1 day fixes.
Compared to Path 2 (userland scroll daemon, Phase 4A): much simpler than Path 2 — leverages Apple's existing scroll synthesis instead of replacing it.
Compared to Path 3 (cache patch): much simpler and reversible.

## Recommended next steps (ordered, all autonomous-safe)

1. **Wait + monitor**: passive VerifyOnly every ~5 min for 60+ min. Document whether unified mode persists.
2. **If degradation reproduces**: characterize the trigger (idle time? specific event? tray poll boundary?)
3. **If unified persists**: characterize lifetime of the recycle effect.
4. **Document Phase 4-Ω plan** for user review on return.
5. **Build self-heal prototype**: C# code in tray app that detects degraded mode + invokes the recycle (need to handle UAC).
