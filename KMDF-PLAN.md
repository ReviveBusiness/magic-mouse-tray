---
title: KMDF Driver Plan — Apple Magic Mouse Scroll+Battery
type: plan
status: superseded
created: 2026-04-26
linked_psn: PSN-0001
linked_repo: ReviveBusiness/magic-mouse-tray
superseded_by: PRD-184 M12
---

# KMDF Driver Plan — Apple Magic Mouse Scroll+Battery

> **SUPERSEDED — 2026-04-26**: The LowerFilter + surgical descriptor patch approach described
> in this document was replaced by the **function driver approach in PRD #184 Milestone 12**,
> which is the authoritative implementation plan. This file is retained as a session record of
> the root cause investigation and startup-repair.ps1 bug fixes.
>
> Canonical plan: `Personal/prd/184-magic-mouse-windows-tray-battery-monitor.md` → M12

## BLUF

The existing `applewirelessmouse` LowerFilter works for scroll but strips COL02 (battery) during
fresh device enumeration. A replacement KMDF **function driver** (not a LowerFilter) owns the
full HID descriptor — implementing both scroll and battery collections without stripping either.
See PRD #184 M12 for the implementation plan.

---

## Root Cause Confirmed (2026-04-26 test)

| Test Phase | Result |
|-----------|--------|
| Phase 1: cycle BTHENUM with filter active | Filter loads, scroll works, COL02 stripped |
| Phase 2: driver stack after filter | `HidBth → applewirelessmouse → BthEnum` confirmed |
| Phase 3: outcome | Filter modifies descriptor during HID enumeration, strips battery collection |
| Phase 4: &6& recovery | Cycle without filter → COL01+COL02 restored |

**Core conflict**: `applewirelessmouse` replaces the entire HID descriptor. The replacement
descriptor fixes scroll but omits the second top-level collection (COL02 = battery).

---

## startup-repair.ps1 Bugs Fixed (2026-04-26)

Two bugs identified and fixed in the same session:

### Bug 1 — `/restart-device` after filter restore (lines 123–128, removed)
`pnputil /restart-device` triggers HID descriptor re-processing with the filter active.
Same effect as `/disable+/enable`: strips COL02. Script was logging "REPAIRED" but battery
was immediately broken again. **Removed.**

### Bug 2 — Only Enum key written, not driver instance key (line 121, extended)
PnP reads `LowerFilters` from `Control\Class\{GUID}\NNNN` (driver instance key) during boot,
not from the Enum key. Writing only to Enum key caused persistent error 1077 (never attempted)
at every boot. **Added Step 4b to write both locations.**

### Expected behavior after fix
```
Boot N:   startup-repair detects COL02 missing
          → cycles without filter → COL02 created
          → restores filter to BOTH registry locations (Enum + driver instance key)
          → logs: "REPAIRED: COL02 present. Scroll loads at next reboot."

Boot N+1: PnP reads driver instance key → loads filter
          startup-repair detects COL02 present → "no repair needed"
          → both scroll and battery work
```

---

## Reboot Test Result (ALREADY CONFIRMED — prior sessions)

Error 1077 persists regardless of registry location written (Enum key, driver instance key, both).
H-004 rejected. The applewirelessmouse approach to scroll is exhausted.

**After rebooting from current state** (COL02 present, LowerFilters restored):
- COL02 will persist — battery works
- Filter will NOT load (error 1077) — scroll broken
- startup-repair.ps1 will log "COL02 present — no repair needed" and exit cleanly

KMDF driver is the only remaining path for scroll.

---

## KMDF Driver Architecture

### Position
LowerFilter on `BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0323`
Same stack position as `applewirelessmouse` — proven to intercept descriptor and reports.

### Stack after install
```
HidBth (function driver)
  ↑
applemouse2 (lower filter — NEW, replaces applewirelessmouse)
  ↑
BthEnum (bus driver)
```

### Two interception points

| IRP | Direction | Action |
|-----|-----------|--------|
| `IOCTL_HID_GET_REPORT_DESCRIPTOR` | Completion (return from below) | Surgical descriptor patch: fix scroll items in COL01, preserve all bytes from COL02 collection start onward |
| `IOCTL_HID_READ_REPORT` | Completion (return from below) | Translate Apple multi-touch report data to standard scroll axis deltas |

### Descriptor patch strategy

```
Raw descriptor structure (Magic Mouse):
  [COL01 bytes] = mouse collection (pointer, scroll, buttons)
  [COL02 bytes] = battery collection (Report ID 0x90, vendor usage)

FindBatteryCollectionOffset() scans for the second top-level Collection(Application) item.
PatchScrollItems() modifies only bytes [0, col02Offset) — never touches battery bytes.
HidBth sees: fixed scroll collection + intact battery collection → creates COL01 + COL02.
```

---

## Implementation Steps

### Step A — Capture raw HID descriptor (before any filter)
Uninstall `applewirelessmouse` or temporarily remove from LowerFilters (no device restart).
Use USB Device Tree Viewer or HID Descriptor Tool on the BTHENUM HID device.
Save hex bytes → `raw-descriptor.bin`.

### Step B — Capture patched descriptor (with applewirelessmouse active)
With filter in device stack, export descriptor again → `patched-descriptor.bin`.
Diff the two: every changed byte is what `PatchScrollItems()` must replicate.

### Step C — Capture raw input reports
With filter uninstalled, run raw HID read loop on COL01 while moving finger on mouse surface.
Identify: which Report ID carries touch delta data, byte offsets for X/Y velocity.
This is what `TranslateTouchToScroll()` needs to implement.

### Step D — Build and test skeleton
1. Create project: WDK + VS, Kernel-Mode Driver (KMDF), x64
2. Set `StartType = SERVICE_DEMAND_START` in INF
3. Enable test signing: `bcdedit /set testsigning on`
4. Sign with test cert (same process as `applewirelessmouse`)
5. Install: `pnputil /add-driver applemouse2.inf /install`
6. Verify: `sc query applemouse2` RUNNING, filter appears in `devcon stack`

### Step E — Fill stubs with captured data
Implement `PatchScrollItems()` using Step B diff.
Implement `TranslateTouchToScroll()` using Step C captures.
Test: scroll works + battery reads in MagicMouseTray.

### Step F — Unpair/re-pair test
Unpair mouse from Bluetooth, re-pair, verify both scroll and battery work without
any manual recovery steps. This is the definitive pass criterion.

---

## Key Files

| File | Purpose |
|------|---------|
| `applemouse2.c` | KMDF driver source (skeleton ready — stubs need fill-in) |
| `applemouse2.inf` | INF for LowerFilter installation (ready) |
| `startup-repair.ps1` | Fixed: removed /restart-device, added driver instance key write |
| `PSN-0001-hid-battery-driver.yaml` | Problem session notes (update after reboot test) |

---

## Why This Is Architecturally Correct

- Single driver handles both scroll and battery natively
- No &6& recovery needed after install — descriptor is correct on first enumeration
- Survives unpair/re-pair (fresh enumeration handled correctly)
- `startup-repair.ps1` becomes monitoring-only — logs a warning if COL02 is missing, never auto-repairs
- Matches how Magic Utilities achieves scroll+battery on the same device

---

## Open Questions After Reboot Test — RESOLVED

All three questions answered by testing (sessions prior to 2026-04-27):

1. Does `applewirelessmouse` load at boot with driver instance key set? → **NO** (H-004 REJECTED — error 1077 persists regardless of registry location. PnP does not call AddDevice on BTHENUM device reuse at boot.)
2. Is two-boot convergence acceptable for daily use? → **NO** — scroll never works with this approach. KMDF function driver (PRD #184 M12) is required.
3. Does `startup-repair.ps1` detect the correct BTHENUM instance after unpair/re-pair? → **YES** — confirmed by testing.
