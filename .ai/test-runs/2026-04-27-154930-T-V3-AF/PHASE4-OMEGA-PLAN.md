# Phase 4-Ω — Tray-app self-heal via PnP recycle

**Status:** Recommended path post-Cell-1-experiment. Awaiting user approval.
**Author:** Claude (apex/auto, autonomous session 2026-04-27 evening)
**Effort estimate:** ~1 day of dev work + 1 day of validation
**Empirical basis:** `exp-a-recycle/finding.md` — confirmed `Disable-PnpDevice` + `Enable-PnpDevice` reliably flips device split→unified

## BLUF

The Apple `applewirelessmouse` filter is not broken — it goes inert at runtime under conditions we don't yet fully understand (probably power-state / Selective Suspend). A simple PnP recycle of the BTHENUM HID device re-fires `AddDevice`, which re-initializes the filter into active/unified mode. Tray app self-heals by detecting the inert state and triggering the recycle automatically.

This path is simpler than Phase 4A (userland scroll daemon), Phase 4C (cache patch), AND the Selective Suspend disabler approach. It leverages the filter Apple already ships, requires no kernel work, no descriptor mutation, no power-policy mutation. Single-purpose PnP recycle + cooldown.

## Detection (already in place)

`MouseBatteryReader.GetBatteryLevel()` already distinguishes the two modes:

| Tray observation | What it means | Action needed |
|---|---|---|
| Returns `>= 0` (actual percentage) | Split mode (filter inert). Battery readable; scroll likely broken. | TRIGGER RECYCLE |
| Returns `-2` (battery N/A) | Unified mode (filter active). Battery N/A; scroll synthesis live. | DO NOTHING — healthy |
| Returns `-1` (no mouse) | Mouse disconnected | DO NOTHING (or sleep) |

The existing log lines `BATTERY_INACCESSIBLE Apple driver in unified mode` and `OK ... battery=N% (split)` are the existing signals. Self-heal hooks off the `(split)` outcome.

## Recycle command (admin-required)

```powershell
$bthenum = Get-PnpDevice -Class HIDClass | Where-Object {
    $_.InstanceId -match '^BTHENUM\\\{00001124[^\\]*VID&0001004C_PID&0323'
} | Select-Object -First 1
Disable-PnpDevice -InstanceId $bthenum.InstanceId -Confirm:$false
Start-Sleep -Seconds 3
Enable-PnpDevice -InstanceId $bthenum.InstanceId -Confirm:$false
# ~5 sec total. Mouse temporarily unresponsive during the cycle.
```

## Implementation choices

The tray runs in user context; `Disable-PnpDevice` needs admin. Three options:

### Option A — Self-heal via existing scheduled-task pattern
Reuse the existing `MM-Dev-Cycle` infrastructure (or a dedicated `MagicMouseTray-SelfHeal` scheduled task). Tray writes a "RECYCLE" request to a queue file; scheduled task picks it up and runs admin recycle.

**Pros:** Mirrors existing dev infrastructure; well-tested pattern.
**Cons:** Requires installing the scheduled task at first run + handling the install UAC prompt.

### Option B — Self-heal via UAC-elevated helper on demand
Tray spawns a UAC-elevated helper process (the recycle PowerShell script) when split mode is detected. User sees one UAC prompt per recycle.

**Pros:** Simplest; no scheduled task install.
**Cons:** UAC prompt every recycle is annoying; may interrupt user workflow.

### Option C — Self-heal via SCM-managed Windows Service (admin-elevated daemon)
Install a small Windows service at first run (or part of installer); tray IPC's to it.

**Pros:** No UAC; service runs as SYSTEM.
**Cons:** Heavyweight; service installation needs admin once at install; more attack surface.

**Recommended: Option A.** Aligns with `startup-repair.ps1` pattern already in the repo.

## Implementation sketch (Option A)

### New files
- `MagicMouseTray/SelfHealManager.cs` — detects split mode + manages cooldown + queues recycle
- `MagicMouseTray/RecycleRequester.cs` — writes the request file + triggers scheduled task
- `scripts/mm-tray-selfheal-task-install.ps1` — installs the scheduled task at first run (one UAC prompt, persistent)
- `scripts/mm-tray-selfheal.ps1` — admin script the scheduled task invokes; does `Disable-PnpDevice` + `Enable-PnpDevice`

### Modified files
- `MagicMouseTray/AdaptivePoller.cs` — call `SelfHealManager.OnPollResult(pct, name)` after each poll
- `MagicMouseTray/MouseBatteryReader.cs` — no changes needed; detection signal already present

### Cooldown logic
Don't recycle on every split detection:
- Recycle at most once per 5 minutes (avoid loops if recycle doesn't fix)
- After recycle, wait 30 sec before re-polling (let PnP settle)
- After recycle, if next poll STILL shows split → log warning, wait 30 min before retrying (escalate or give up)
- After recycle succeeds (next poll shows unified) → reset cooldown

### Acceptance criteria
1. After a fresh install, tray shows healthy unified mode
2. If device degrades to split (after idle / sleep / etc.), within one poll cycle (max 30 min) tray triggers recycle
3. Within 60 sec of recycle, device returns to unified mode (verified via tray log)
4. User-perceptible scroll resumes working post-recycle
5. No infinite recycle loops in any test scenario

### Validation tests (post-implementation)
1. **Idle test:** install, leave host idle 60 min, verify tray detects + recycles
2. **Reboot test:** install, reboot, verify tray detects + recycles within first 30 min after login
3. **Manual unpair/repair test:** unpair via BT settings, repair, verify recycle
4. **Sleep/wake test:** sleep host, wake, verify recycle if needed
5. **No false-positive test:** verify tray does NOT recycle when in healthy unified mode (60+ min observation)

## What this DOES NOT solve

- **Why** the filter goes inert post-idle/post-reboot (the underlying bug in `applewirelessmouse.sys` or its interaction with Windows BT power policy). Self-heal is a band-aid; the root cause stays unfixed.
- **The brief mouse interruption** (~5 sec) every time the recycle fires. If degradation is frequent, user notices.
- **Multi-mouse scenarios** (paired Magic Mouse v1 + v2 simultaneously). Self-heal would target whichever instance the tray detected first.
- **Other Apple HID quirks** (cold-boot pair-and-trust, BT firmware updates, etc.). Self-heal only addresses the unified→split regression.

## Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Recycle disrupts user workflow | High | Low | Show toast notification "Repairing scroll..."; complete in 5 sec |
| Recycle loop if degradation reproduces immediately after recycle | Low | Medium | Cooldown + escalation logic; give up after 3 consecutive failures |
| Scheduled-task install fails | Low | High | Detect install failure; fall back to Option B (UAC prompt) |
| Recycle doesn't actually fix it on the user's hardware | Low | High | Validation test #2 + #4 cover this; if it fails, fall back to Phase 4A (userland scroll daemon) |
| Apple ships a driver update that changes the trap behavior | Low | Medium | Self-heal still works at AddDevice; only descriptor mutation would break |

## Open questions (need answers before implementation)

1. **What's the right detection signal cadence?** AdaptivePoller polls at 2h/30m/10m/5m based on battery level. We probably want a faster healthcheck cadence (every 5 min regardless of battery) for the scroll path. Decision: separate health-poll thread at fixed 5-min interval.
2. **Should recycle be opt-in (settings menu) or always-on?** Default: always-on. Users can disable in tray settings if undesired.
3. **Should the recycle scheduled task run as SYSTEM or as the user (with HighestAvailable)?** Mirroring `MM-Dev-Cycle`: HighestAvailable + InteractiveToken — runs in user session at admin level.

## Phase 4-Ω vs alternatives — final comparison

| Path | Effort | Reliability | User Experience | Maintenance |
|---|---|---|---|---|
| **4-Ω Self-heal recycle** | 1 day | High (verified empirically) | One brief interruption per degradation event | Low |
| 4A Userland scroll daemon | 1-3 days | Medium (raw HID access uncertain) | None visible if works | Medium (gesture parser maintenance) |
| 4C Cache patch | 1-2 days | Medium (patch may interact with filter) | None visible if works | High (re-apply on every re-pair) |
| Selective-Suspend disabler | 1 day | Unknown (H-α not yet validated) | None visible | Low |

## Recommended decision

**Ship Phase 4-Ω.** It's the simplest path with the highest reliability based on empirical evidence. Falls back gracefully to Phase 4A if degradation proves to recycle-loop. Selective Suspend disabler can be a stacked optimization on top (try less often) if H-α holds.

## Approval items for user

1. **Phase 4-Ω as the primary PRD-184 fix path** — yes/no?
2. **Option A (existing scheduled-task pattern) for elevation** — yes/no? (vs Option B/C)
3. **Always-on self-heal default** (with opt-out in settings menu) — yes/no?
4. **5-min health-check cadence** (independent of battery poll cadence) — yes/no? (or different interval?)
5. **Authorize implementation** to begin once approvals on 1-4 are received.
