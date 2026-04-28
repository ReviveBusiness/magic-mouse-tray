# Phase E — Consolidated empirical findings

**Status:** All passive data collected (E6, E7c, E9-E18 except E11 cancelled per user). Ready for decision before any intrusive testing.
**Date:** 2026-04-28

---

## TL;DR (3 bullets)

1. **The tray's existing `splitVendorBattery` code path successfully reads v3 mouse battery 96 times on 2026-04-27** between 06:04 and 19:43 — via the **COL02 vendor TLC** HID interface (path `...&pid&0323&col02#...`, ReportID 0x90 Input report, byte 1 = battery %). Bug isn't in the tray.
2. **The v3 mouse's HID descriptor that HidBth serves is fragile** — sometimes it includes the vendor TLC as COL02 (battery readable), sometimes it presents only a single Mouse TLC with a phantom Feature 0x47 that returns err=87. The descriptor flipped between states in a 30-min gap on 2026-04-27 around 19:43→20:13, likely correlating with a Selective Suspend wake-up cycle.
3. **The "Apple driver traps Feature 0x47" log message in the tray is a misnomer** — there is no trap. When HidBth presents the unified-mode descriptor (single Mouse TLC + phantom 0x47), the device simply doesn't back that report ID, so HidD_GetFeature returns err=87. **No filter is doing anything malicious; the descriptor is just the wrong one.**

---

## A. Definitively proven facts

| # | Fact | Evidence |
|---|---|---|
| F1 | v1 Magic Mouse battery readable via standard HID Feature 0x47 | tray log 2026-04-28 09:33:47 `OK ... pid&030d ... battery=100% (unified Feature 0x47)` |
| F2 | **v3 Magic Mouse battery readable via Input 0x90 on COL02 vendor TLC** (the path `vid&0001004c_pid&0323&col02#...`) | tray log 96× successful reads 2026-04-27 06:04-19:43, e.g. `OK ... col02#... battery=44% (split)` |
| F3 | v1 mouse user-perceptible scroll WORKS | user-reported 2026-04-28 |
| F4 | v3 mouse user-perceptible scroll WORKS | user-reported 2026-04-27 |
| F5 | Both v1 and v3 BTHENUM PDOs currently bound to oem0.inf / AppleWirelessMouse.NT v6.2.0.0 (Apple Inc., dated 2026-04-21) with `LowerFilters: applewirelessmouse` | DEVPKEY_Device_LowerFilters dump 2026-04-28 14:12 |
| F6 | applewirelessmouse.sys binary has hardcoded VID/PID strings only for v1 mouse (PID 0x030D) and Magic Trackpad (0x0310) — **no PID 0x0323 hardcoded** | E7c static analysis |
| F7 | Magic Utilities INF (oem53.inf, magicmouse.inf v3.1.5.3, 2024-11-05) was previously bound to v3 mouse with `LowerFilters: MagicMouse` from 2026-03-18 to ~2026-04-17 | E18 event log 410 events |
| F8 | The applewirelessmouse INF v6.2.0.0 was installed 2026-04-21; v3 mouse was paired 2026-03-18 (before INF arrived). Magic Utilities INF was already installed at v3 first-pair time. | E17/E18 |
| F9 | Keyboard's BTHENUM HID PDO has `LowerFilters: applewirelessmouse` in registry but per Configuration log has never STARTED with that filter — registry-only orphan added by INF AddReg side-effect | E18 + Configuration log silent on filter |
| F10 | v3 SDP cache descriptor declares: Mouse TLC (RID 0x12) + Vendor 0xFF02 Feature 0x55 (touchpad mode) + Vendor 0xFF00 outer Collection containing Input 0x90 with standard HID Battery System usages (UP=0x85, U=0x44 AC, U=0x46 Charging, U=0x65 AbsoluteStateOfCharge) | descriptor decode + Linux hid.h confirms standard usage codes |
| F11 | v3 mouse runtime descriptor SOMETIMES enumerates as 2 separate HID children (COL01 mouse + COL02 vendor) — battery readable on COL02 — and SOMETIMES as 1 child with phantom Feature 0x47 — battery returns err=87 | tray log HIDP_CAPS lines before/after 2026-04-27 19:43→20:13 |
| F12 | When COL02 is enumerated: `InLen=3, FeatLen=0, TLC=UP:FF00/U:0014`, ReportID 0x90 Input contains [reportId, flags, pct]. Tray reads `buf[2] = pct` correctly. | tray log line 19:43:45 split-vendor + Linux hid.h cross-check |
| F13 | Polling cadence: tray polls every 5 min when battery state uncertain (-2), 30 min when low, 2 hr when stable. Currently averaging ~5min for v3 (95% FEATURE_BLOCKED) and ~2hr for v1 (100% OK). | E13 |
| F14 | AirPods Pro = audio-only (A2DP/HFP/AVRCP/GATT/AAP). No HID profile. Out of scope. | bthport-discovery + decode |
| F15 | Both v1 and v3 are Apple Magic Mouse but use different battery report semantics: v1 = standard Feature 0x47 (UP=0x06 BatteryStrength), v3 = vendor-wrapped Input 0x90 (UP=0xFF00 outer collection containing standard UP=0x85 Battery System inside) | descriptor decodes + Linux ref |

---

## B. Fragile-state evidence (the core puzzle)

### Two descriptors observed for v3 from HidBth

**Descriptor A — multi-TLC (COL02 enumerated, battery WORKS via Input 0x90):**

The runtime descriptor matches the SDP cache. The system enumerates two HID device interfaces:
- `&col01#a&31e5d054&c&0000` — Mouse TLC, InLen=8, FeatLen=65, TLC=UP:0001/U:0002
- `&col02#a&31e5d054&c&0001` — Vendor TLC, InLen=3, FeatLen=0, TLC=UP:FF00/U:0014

Tray's `splitVendorBattery` path matches on COL02, calls `HidD_GetInputReport(0x90)`, gets back 3 bytes `[0x90, flags, pct]`, returns `buf[2]`. **Battery=44% returned successfully 96 times.**

**Descriptor B — single-TLC (COL02 GONE, battery err=87):**

The runtime descriptor presented to HidBth changed. Only one HID device interface is enumerated:
- `pid&0323#a&31e5d054&c&0000` (no col suffix) — InLen=47, FeatLen=2, TLC=UP:0001/U:0002

The HID caps tree on this descriptor declares Feature value caps with UP=0x06 + Usage=0x20 (standard Battery Strength). Tray's `unifiedAppleBattery` path matches, calls `HidD_GetFeature(0x47)`, gets err=87 (ERROR_INVALID_PARAMETER). The phantom 0x47 is in the cap table but the device returns no data for it.

### Transition observed at 2026-04-27 19:43:45 → 20:13:45

The 30-min poll gap is the only window in which the state flipped. Per persistence-monitor.log we ran a `FLIP:VerifyOnly` check around 19:51. Selective Suspend likely fired during the idle period, the device woke for the next poll, and HidBth re-fetched the descriptor — but got Descriptor B instead of Descriptor A.

The empirical record shows no tray-initiated recycle, no PnP event, no reboot in that window. The only time-correlated activity was the persistence monitor's verify polls.

### Updated trigger hypothesis (post-system-event-log analysis)

System event log review revealed a **clean correlation** between the descriptor flip and **DeviceSetupManager (DSM)** activity:

| Time | Event |
|---|---|
| 2026-04-27 17:41:30–17:42:25 | System reboot (~55 sec) — confirmed via Kernel-Power/109, Kernel-General/12, EventLog/6005 |
| 17:43:44 | First post-reboot OK battery read (Descriptor A) |
| **19:43:45** | **Last successful battery read (Descriptor A) — 96th OK** |
| **19:50:53** | **DSM "serviced" Magic Mouse container fbdb1973-… — wrote 35 properties** |
| 19:51:00 | DSM serviced again, property heuristics ran |
| 19:51:45 | DSM shut down (uptime 51 sec) |
| **20:13:45** | **First FEATURE_BLOCKED — Descriptor B locked in** |

DSM (Microsoft-Windows-DeviceSetupManager) runs ~every 2 hours processing device metadata. Whatever the 35 properties it wrote at 19:50:53 were, the next HID enumeration produced Descriptor B.

This is **not** Selective Suspend (which fires on every idle period). It's a one-shot DSM property write that happened to invalidate the cached descriptor. Empirically the v3 mouse flipped to Descriptor B and stayed there even through subsequent recycle attempts.

The original "device power state" hypothesis is partially valid — but the trigger is **DSM property-write → PnP re-enumeration → descriptor re-fetch in whatever state the device happens to be in at that moment**. That state is non-deterministic from the host side.

---

## C. What this means for architecture decisions

### The tray code is already correct

`MouseBatteryReader.cs` has both code paths and switches between them based on the runtime descriptor:
- `splitVendorBattery` for COL02-enumerated state (Input 0x90)
- `unifiedAppleBattery` for single-TLC state (Feature 0x47, currently always fails)

It does the right thing both ways. We just need to keep the device in the multi-TLC descriptor state.

### The "Apple driver traps Feature 0x47" log message is wrong

It should say: "Feature 0x47 declared in cap table but device returned err=87; this happens when the runtime HID descriptor is in single-TLC mode (no vendor 0xFF00 child enumerated). Try a PnP recycle or unpair-repair to refresh HidBth's cached descriptor."

### Phase 4-Ω self-heal needs to be re-thought

The current self-heal trigger on degradation does a BTHENUM Disable+Enable. Empirical evidence from 2026-04-27:
- BEFORE 17:43:44 recycle: descriptor unknown, scroll was failing per user report
- AFTER 17:43:44 recycle: Descriptor A (multi-TLC), battery + scroll working
- AROUND 19:43→20:13: descriptor flipped to B (likely Selective Suspend wake), battery broken

So a recycle CAN restore Descriptor A — but the device can subsequently flip to B without us knowing. Self-heal as designed targets the wrong signal.

### Three viable architectures (all empirically validated paths)

**Option Z — Userland-only, descriptor-aware (recommended)**
- Keep the existing tray code paths (already correct).
- Add a periodic check: if `splitVendorBattery` was previously detected and now isn't, run a self-heal recycle.
- Disable Selective Suspend on the v3 BTHENUM HID PDO (registry: `SelectiveSuspendEnabled = 0` already set per snapshot). May need additional power-policy mutation.
- No new driver, no Magic Utilities license.
- **Cost: ~1 day to add the COL02-disappearance detector. Probably the right answer.**

**Option Y — Pin descriptor via INF rewrite**
- Investigate whether a custom INF can force HidBth to use a static descriptor.
- Requires Apple-class driver development and signing.
- **Cost: 1-2 weeks. Brittle.**

**Option X — Magic Utilities (user has ruled this out)**
- Vendor product, paid subscription.
- Empirically had v3 binding from 2026-03-18 onwards.
- **Ruled out by user.**

---

## D. Files produced in Phase E (passive)

```
docs/
├── PHASE-E-EMPIRICAL-PLAN.md            (the plan)
├── PHASE-E-FINDINGS.md                  (this file)
├── research-findings.md                 (NotebookLM 150-source synthesis)
└── mm3-pre-validation-baseline-2026-04-26.md  (preexisting)

.ai/test-runs/2026-04-27-154930-T-V3-AF/
├── E6-E7c-findings.md                   (source audit + driver static analysis)
├── E18-pnp-eventlog-narrative.md        (driver/filter timeline 2025-11-24 → 2026-04-28)
├── pnp-eventlog.{txt,json}              (138 PnP/UserPnp events)
├── devmgr-dump-*.json                   (11 per-device DEVPKEY dumps)
├── devmgr-dump-summary.md               (one-table summary)
├── devmgr-drivers.txt                   (pnputil /enum-drivers)
├── devmgr-devices.txt                   (pnputil /enum-devices /class HID/Mouse/Keyboard/Bluetooth)
├── bthport-discovery-{04f13eeede10,b2227a7a501b,d0c050cc8c4d,e806884b0741,38c43a5f7a5f}.{txt,json}
├── bthport-discovery-index.txt
├── multi-device-cache-comparison.md
├── multi-device-analysis.md
├── bt-stack-snapshot.{txt,json}
├── bt-battery-probe.{txt,json}
├── hid-feature-read.{txt,json}
├── keyboard-and-regdiff-findings.md
└── exp-a-recycle/persistence-monitor.log
```

---

## E. Recommended next step (gated)

Before any intrusive testing, the cleanest action is:

1. **Execute one PnP recycle on v3 BTHENUM** — tests whether we can deterministically restore Descriptor A (multi-TLC). If yes → Option Z is unblocked.
2. **Then disable Selective Suspend on v3** to see if it stays in Descriptor A long-term.
3. **THEN** decide whether to ship the COL02-disappearance detector to the tray (small change) or move on.

Estimated time including verification: 30 min. No code changes, no service modifications, fully reversible.

**Approval needed to proceed.**
