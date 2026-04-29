---
created: 2026-04-29
type: session-handoff
branch: ai/m12-script-tests
status: incomplete — Phase 5 commit pending APEX gate; AUTO_START / PnP-scan questions deferred to next session
---

# Track 1 v3 Battery — Session Handoff

## What got proven today
- **Answer A confirmed empirically** post-reboot: `HidD_GetInputReport(0x90)` on v3 COL02 → `90 04 22` → buf[2]=34%. Apple stock filter, no M12. `MouseBatteryReader.cs` reads it without modification.
- See `docs/v3-battery-stockfilter-2026-04-29-113321.txt` for the proof.

## State machine observed (tonight)
```
Cold boot, NO filter loaded         →  Descriptor A   (battery yes, scroll no)
First device attach loads filter    →  Descriptor B   (battery no,  scroll yes)
Recycle / re-pair / standby-wake    →  Descriptor B   (sticky)
```
- 3 PnP recycles + 1 unpair-repair pre-reboot all stayed in B.
- Reboot deterministically landed A.
- One recycle post-reboot flipped to B (current state).

## Current live state (end of session)
- v1: scroll OK, battery N/A (Descriptor B, 1 HID interface)
- v3: scroll OK, battery N/A (Descriptor B, 1 HID interface)
- `applewirelessmouse` service: RUNNING

## Open questions for next session (DO NOT re-research from scratch — user says it's already documented multiple times)
1. **AUTO_START theory** — user recalls this was tried/discussed before. **Use NotebookLM (`/notebooklm`)** to query the M12/M13 corpus for prior conclusions before any registry change.
2. **PnP scan during standby flipping A→B** — user confirms this is documented in `docs/PHASE-E-FINDINGS.md` and `docs/REGISTRY-DIFF-AND-PNP-EVIDENCE.md` (DSM property-write at 19:50:53 correlated with the flip). Already searched and confirmed in this session.

## Commits on `ai/m12-script-tests` (unpushed)
- `918c861` — Phase 1-2 audit + initial probe
- `83475e1` — Phase 3 (3 recycles refute prior 60-80% A theory)
- `56f8225` — Phase 4 (re-pair refuted)
- **Pending**: Phase 5 commit (REBOOT WORKS, battery=34%) — drafted, blocked at APEX gate, never committed. Files staged on disk:
  - `docs/M13-V3-BATTERY-AUDIT-2026-04-30.md` (modified — Phase 5 + final answer A)
  - `docs/v3-battery-stockfilter-2026-04-29-113321.txt` + `.json` (new)
  - `docs/M13-V3-BATTERY-HANDOFF-2026-04-29.md` (this file)

## Next-session start checklist
1. `cd /home/lesley/.claude/worktrees/ai-m12-script-tests && git status -s` — confirm files still present
2. Read `docs/M13-V3-BATTERY-AUDIT-2026-04-30.md` (TL;DR + Phase 5)
3. `/notebooklm` query: "applewirelessmouse AUTO_START theory" — find prior conclusion before re-running experiment
4. If user wants to commit Phase 5: `python3 /home/lesley/projects/scripts/git.py commit --branch ai/m12-script-tests --message "..."` and pass APEX HUD gate this time

## Key files
- `MagicMouseTray/MouseBatteryReader.cs:178-204` — splitVendorBattery path (matches today's empirical hit byte-for-byte)
- `scripts/mm-v3-battery-stockfilter-probe.ps1` — re-runnable probe
- `scripts/mm-both-mice-probe.ps1` (in /tmp, also at C:\mm-dev-queue) — quick v1+v3 caps probe
- `D:\mm3-driver\scripts\mm-task-runner.ps1` — task runner; has RESTART-DEVICE, INSTALL-DRIVER, etc., NO start-service phase

## Cross-session memory note (already in MEMORY.md)
M12 Battery Layout — confirmed 2026-04-29: HID Input Report RID=0x90, 3-byte report, UsagePage=0xFF00 Usage=0x0014, buf[2] = battery % direct. NOT RID=0x27. COL02 collection. Read via HidD_GetInputReport. **Today's empirical work confirmed all of this is correct.**
