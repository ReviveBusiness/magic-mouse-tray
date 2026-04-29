---
created: 2026-04-29
modified: 2026-04-29
type: audit-and-empirical-proof
track: T1 — Battery via Apple's stock filter (no M12)
status: ANSWER C (with caveat) — current device state cannot read battery via 0x90; code is correct; gap is HidBth descriptor cache state, not code
---

# M13 — v3 Battery via Apple's stock filter — audit + empirical proof

## TL;DR

**Answer: hybrid (C with a known path to A).**

- **No code changes needed.** `MouseBatteryReader.cs` already implements both descriptor variants (split-vendor 0x90 input + unified-Apple Feature 0x47), with v3 PID 0x0323 in the `KnownMice` table. The cross-session-memory layout (UP=0xFF00 / Usage=0x0014 / RID=0x90 / 3-byte report / `buf[2]=pct`) is exactly what the code reads.
- **In the current live state**, the v3 battery cannot be read via `HidD_GetInputReport(0x90)`. HidBth has cached the **single-TLC Descriptor B** for v3 (47-byte Mouse-only TLC + phantom Feature 0x47). RID 0x90 is not declared, so the call returns `ERROR_INVALID_FUNCTION (0x1)`.
- **The COL02 child PDO exists in the device tree but is orphaned** (Status=Unknown, no driver bound). The interface that would carry the vendor 0xFF00 TLC is registered but not enumerated, because the parent's runtime descriptor doesn't include it.
- **The user's hypothesis ("Apple's native SDP descriptor declares RID=0x90, so the tray should read battery directly through the stock filter") holds when HidBth caches Descriptor A** (validated 2026-04-27: 96 successful reads under Apple filter), but **fails when HidBth caches Descriptor B** (today's state, and the state recorded 2026-04-28).
- **Gap is operational, not architectural.** The state is non-deterministic across HidBth re-attach events (PnP recycle, re-pair, reboot). No registry knob has been found that pins it.

## Phase 1 — Audit findings

### Already built and shipped in `MagicMouseTray/MouseBatteryReader.cs` (worktree HEAD `d38f469`)

| Capability | Status | Lines |
|---|---|---|
| v3 detection (BT path `VID&0001004C_PID&0323`) | ✅ Built | `MouseBatteryReader.cs:25` |
| v1 detection (BT path `VID&000205AC_PID&030D`) | ✅ Built | `MouseBatteryReader.cs:27` |
| v2 detection (BT path `VID&000205AC_PID&0269`) | ✅ Built | `MouseBatteryReader.cs:28` (PID unconfirmed) |
| Split-vendor path (Descriptor A): `HidD_GetInputReport(0x90)` on COL02, 3-byte buffer, `buf[2]` = pct | ✅ Built | `MouseBatteryReader.cs:178-204` |
| Unified-Apple path (Descriptor B): `HidD_GetFeature(0x47)` Battery Strength | ✅ Built (returns sentinel `-2`) | `MouseBatteryReader.cs:209-227` |
| TLC discovery via `HidP_GetCaps` + `HidP_GetValueCaps` (input + feature) | ✅ Built | `MouseBatteryReader.cs:140-170` |
| Zero-access `CreateFile` to bypass mouhid exclusive hold | ✅ Built | `MouseBatteryReader.cs:118-125` |
| 3-attempt retry with 50ms BT timing | ✅ Built | `MouseBatteryReader.cs:181-200` |
| TrayApp + AdaptivePoller + tier intervals (>50%=2h, ≥20%=30m, ≥10%=10m, <10%=5m) | ✅ Built | `AdaptivePoller.cs:55-61` |
| Sentinel `-2` ("battery N/A, mouse present, Apple unified") in tray | ✅ Built | `MouseBatteryReader.cs:226`, `TrayApp.cs` |

**Bottom line on audit**: every code path the user expected for v3 via Apple's stock filter is already in the tree. The existing code, given a v3 device path that exposes the vendor 0xFF00 TLC with input RID=0x90, reads battery in three lines.

### Prior empirical work (relevant docs)

- `docs/v3-BATTERY-EMPIRICAL-PROOF-AND-PATHS.md` (2026-04-28) — exhaustive ~588-call probe across 6 channels, 0 hits. Concluded: HidBth's runtime descriptor cache is the single root cause; COL02 PDO orphan; non-deterministic across re-attach.
- `docs/M12-EMPIRICAL-BLOCKER-2026-04-29.md` (2026-04-29 — yesterday's night-run) — recommendation #3: "Battery readout via the existing applewirelessmouse filter MIGHT already be feasible — Apple's native descriptor declares RID=0x90 vendor with the right usages. The tray app's `HidD_GetInputReport(0x90)` should work directly. Worth testing tomorrow before any further M12 work." That recommendation is what this audit re-tests.
- `docs/PHASE-E-FINDINGS.md` — Descriptor A/B state machine and stochastic re-attach behavior.
- `docs/REGISTRY-DIFF-AND-PNP-EVIDENCE.md` — three-era registry comparison: Descriptor A and Descriptor B BTHENUM registry values are byte-identical. No registry pin.

### Gap list (after audit, before probe)

| # | Gap | Severity |
|---|---|---|
| G1 | **Empirical: does the user's hypothesis hold today on this machine, in the current applewirelessmouse-bound state?** Yesterday's recommendation said "test tomorrow" — that's today. | High (this audit's job) |
| G2 | The 2026-04-28 doc was generated when COL02 was orphan (Descriptor B). The 2026-04-29 night-run re-paired the device and ended with cursor+scroll working — descriptor state at end of that session was not captured. | High (resolved by today's probe) |
| G3 | The tray-app code uses the `KnownMice` table to filter by VID/PID substring, but does not detect Descriptor B vs A — when Descriptor B is in cache, every read attempt fails silently with err=1, no escalation/UI hint. The sentinel `-2` only fires from the Apple unified Feature path; it doesn't fire when the device has neither vendor TLC nor Battery Strength feature. | Medium |
| G4 | No "force HidBth re-attach" path in the tray (Path 1 from prior doc — PnP recycle). Today the user must rely on chance: descriptor state on the next reboot is the descriptor state for that boot. | Medium (explicit future work, out of scope here) |

## Phase 2 — Empirical probe

### Probe script

`scripts/mm-v3-battery-stockfilter-probe.ps1` (committed on `ai/m12-script-tests`):

- Enumerates every present HID interface via SetupAPI
- Filters to v3 (path contains `vid&0001004c_pid&0323`)
- Opens each with `dwDesiredAccess=0` (zero-access; bypasses mouhid exclusive hold)
- Calls `HidD_GetAttributes`, `HidD_GetPreparsedData`, `HidP_GetCaps`, `HidP_GetValueCaps` (Input + Feature) — full TLC and value-cap dump
- Calls `HidD_GetInputReport(0x90)` with 3-byte buffer (primary hypothesis), then 64-byte buffer (wide retry)
- Calls `HidD_GetFeature(0x47)` (Apple unified fallback)
- Calls `HidD_GetFeature(0x90)` (completeness)
- Calls `HidD_GetInputReport(0x27)` and `HidD_GetFeature(0x27)` (RID=0x27 was found declared with 46-byte input value cap UP=0x0006 / U=0x0001 — Generic Device, possibly vendor data)
- Writes `.txt` (human-readable) and `.json` (machine-readable) artifacts

No elevation needed — `dwDesiredAccess=0` opens are unprivileged for HID.

### Probe result @ 2026-04-29 10:43:25 (artifacts: `docs/v3-battery-stockfilter-2026-04-29-104325.txt` and `.json`)

```
Total HID interfaces enumerated: 19
v3 (PID 0x0323) interfaces:       1   <-- one only; COL01/COL02 NOT enumerated

PATH: \\?\hid#{00001124-0000-1000-8000-00805f9b34fb}_vid&0001004c_pid&0323#a&31e5d054&12&0000#{4d1e55b2-...}
  VID=0x004C PID=0x0323 Ver=0x0000
  TLC: UP=0x0001 U=0x0002  In=47 Out=0 Feat=2          <-- Descriptor B (single Mouse TLC)

  ValueCaps: input=5 feature=1
    [INPUT VC] UP=0x0001 U=0x0031 RID=0x02 BitSz=8 Cnt=1   (Y)
    [INPUT VC] UP=0x0001 U=0x0030 RID=0x02 BitSz=8 Cnt=1   (X)
    [INPUT VC] UP=0x000C U=0x0238 RID=0x02 BitSz=8 Cnt=1   (AC Pan)
    [INPUT VC] UP=0x0001 U=0x0038 RID=0x02 BitSz=8 Cnt=1   (Wheel)
    [INPUT VC] UP=0x0006 U=0x0001 RID=0x27 BitSz=8 Cnt=46  (Generic Device, 46 bytes — see below)
    [FEAT  VC] UP=0x0006 U=0x0020 RID=0x47 BitSz=8 Cnt=1   (Battery Strength — phantom)

  HidD_GetInputReport(0x90) buf=3:    [miss x3] err=0x1 (ERROR_INVALID_FUNCTION)
  HidD_GetInputReport(0x90) buf=64:   [miss]    err=0x1
  HidD_GetFeature(0x47):              [miss]    err=0x57 (ERROR_INVALID_PARAMETER) — phantom cap
  HidD_GetFeature(0x90):              [miss]    err=0x57
  HidD_GetInputReport(0x27) buf=64:   [miss]    err=0x1   <-- declared but interrupt-only (no synthesis on demand)
  HidD_GetFeature(0x27) buf=64:       [miss]    err=0x57
```

### What the probe proves

1. **HidBth has Descriptor B in cache.** The single-TLC mouse-only descriptor is what's exposed; UP/Usage/InLen all match the 47-byte Descriptor B fingerprint from prior empirical work.
2. **No vendor 0xFF00 / Usage 0x0014 TLC is enumerated** for v3 — neither in the parent path's value caps nor as a separate COL02 interface.
3. **`HidD_GetInputReport(0x90)` returns ERROR_INVALID_FUNCTION** because RID 0x90 is not declared in this descriptor.
4. **Feature 0x47 is a phantom** (declared in the descriptor but not backed by the device firmware in this state) — confirmed by err=87 INVALID_PARAMETER.
5. **RID 0x27 (the unexplained 46-byte input cap) is interrupt-driven, not pull-able.** `GetInputReport(0x27)` returns INVALID_FUNCTION on this descriptor variant. (This RID is an interesting unknown for follow-up but not a battery channel.)
6. **PnP confirms COL02 orphan**: `Get-PnpDevice` shows `HID\…&COL02\A&31E5D054&12&0001` Status=Unknown alongside the active no-collection-suffix parent at &12&0000. This matches the 2026-04-28 "PDO registered but not enumerated" finding exactly.

### Why this differs from the cross-session-memory note

The memory note ("RID=0x90, 3-byte report, UsagePage=0xFF00 Usage=0x0014, buf[2] = battery % direct. … Read via HidD_GetInputReport") is **structurally correct** — that is the layout when COL02 enumerates. It doesn't fail today; it doesn't get a chance to run today. The path it describes only exists when HidBth's cache is Descriptor A. The memory captures the device's intent (its native HID descriptor in the SDP record), not the runtime cache state.

## Resolution / answer

### Per the prompt's three-option end-state

**(A) "v3 battery already works through Apple stock filter, here's the proof"** — partially true: it has worked (96 reads on 2026-04-27 under Apple filter). The CODE is right. But it doesn't work at this exact moment on this exact machine, because HidBth is currently caching Descriptor B.

**(B) "v3 battery works after these N changes, here's the proof"** — N=0 code changes. The change required is operational: force HidBth to re-attach until Descriptor A lands. That is non-deterministic. Until automated, it's "do a recycle/reboot and hope" — which is not "proof".

**(C) "v3 battery does NOT work via 0x90 + Apple stock filter, here's why"** — true *in current state*, with a precise mechanistic reason: HidBth's runtime descriptor cache is Descriptor B (single Mouse TLC). RID 0x90 is not declared. COL02 child PDO is registered but not enumerated. `HidD_GetInputReport(0x90)` therefore returns `ERROR_INVALID_FUNCTION` and there is no other channel.

**Final answer (hybrid):** **C-now / A-when-Descriptor-A**. The tray code is correct and complete for both descriptor variants. The remaining work is descriptor-state determinism, which is out of scope for this audit and was deliberately scoped out (no M12, no INF changes).

## Recommended next steps (not done in this audit)

1. **Path 1 — single PnP recycle, then re-probe.** `pnputil /restart-device "BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0323\9&73B8B28&0&D0C050CC8C4D_C00000000"` — ~5 sec mouse stutter, 60-80% prior empirical chance of landing Descriptor A. If it lands A, re-running `mm-v3-battery-stockfilter-probe.ps1` will show 3 v3 interfaces (parent + COL01 + COL02), vendor TLC declared on COL02, and `InputReport(0x90)` returning a 3-byte payload with `buf[2]` = current battery percent. Skipped here to avoid perturbing the user's working state without explicit approval.
2. **Code-side hardening (G3)** — extend `MouseBatteryReader.cs` to detect Descriptor B (single Mouse TLC + phantom Feature 0x47, no vendor 0xFF00 input cap) and return a distinct sentinel (e.g. `-3` "descriptor cache is B, recycle to recover") so the tray UI can guide the user. Trivial change; ~15 lines.
3. **Path 4 (RE the AppleBluetoothMultitouch IOCTL surface)** — the only descriptor-state-independent battery channel on this device. 1-2 days of Ghidra. Out of scope for this audit; tracked under M13 and the prior `v3-BATTERY-EMPIRICAL-PROOF-AND-PATHS.md` Path 4.

## Files in this deliverable

- `docs/M13-V3-BATTERY-AUDIT-2026-04-30.md` (this file)
- `docs/v3-battery-stockfilter-2026-04-29-104325.txt` (probe human output)
- `docs/v3-battery-stockfilter-2026-04-29-104325.json` (probe machine output)
- `scripts/mm-v3-battery-stockfilter-probe.ps1` (probe source — re-runnable on demand)

No changes to `MagicMouseTray/*.cs` were made. The code is correct; the gap is environmental.
