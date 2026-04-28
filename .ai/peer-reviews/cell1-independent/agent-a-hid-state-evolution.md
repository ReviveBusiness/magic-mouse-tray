# Cell 1 Independent Forensic Analysis — HID State Evolution
**Cell:** T-V3-AF (AppleFilter mode, Magic Mouse 2024, PID 0x0323, MAC d0c050cc8c4d)
**Analyst:** Agent-A (Independent — no prior conclusion files read)
**Analysis date:** 2026-04-27
**Status:** Complete

---

## Anti-bias declaration

Files intentionally NOT read:
- `cell1-report.md`
- `PSN-0001-hid-battery-driver.yaml`
- `autonomous-agent-team.md` (AP-16+)
- PRD-184 Decisions table

No contamination encountered.

---

## 1. Scroll behaviour across sub-steps

### Instrument signal: WM_MOUSEWHEEL event_count

| Sub-step | event_count | duration_sec | Source |
|---|---|---|---|
| test-1-initial | 0 | 3 | `test-1-initial/wheel-events.json:event_count` |
| test-2-post-repair | 0 | 3 | `test-2-post-repair/wheel-events.json:event_count` |
| test-2b-post-sleep-wake | **6** | 3 | `test-2b-post-sleep-wake/wheel-events.json:event_count` |
| test-3 | 0 | 3 | `test-3/wheel-events.json:event_count` |

### User-reported signal: observation item 2 ("scroll")

| Sub-step | Obs item 2 | Source |
|---|---|---|
| test-1-initial | yes | `test-1-initial/observations.txt:6` |
| test-2-post-repair | yes | `test-2-post-repair/observations.txt:6` |
| test-2b-post-sleep-wake | yes | `test-2b-post-sleep-wake/observations.txt:6` |
| test-3 | **no** | `test-3/observations.txt:8` |

### Divergence analysis

The two signals are **in direct conflict in two sub-steps**:

**test-2b-post-sleep-wake:** The user reports scroll as "yes" (obs item 2 = yes), but the instrument captured 6 WM_MOUSEWHEEL events, all bunched in the last 237ms of the 3-second window (t_ms 2551–2787, `test-2b-post-sleep-wake/wheel-events.json:6–11`). This is consistent with the user's "yes" — scroll is happening but only intermittently or after a delay. The 6 events all carry delta=-120 (one notch each, downward) at a fixed screen position (826, 707), suggesting a single brief gesture burst rather than smooth continuous scroll. The instrument confirms scroll is working, albeiт unreliably or late-starting within the 3-second capture.

**test-3-post-reboot:** The instrument reports 0 events (`test-3/wheel-events.json:event_count=0`), and the user reports scroll as "no" (`test-3/observations.txt:8`). These agree. Additionally, test-3 obs item 3 = "no" (horizontal swipe fails), and item 5 = "yes" (tray polling works) — consistent with COL01 having changed to a different descriptor that no longer includes Apple's wheel synthesis.

**Why the signals can diverge:** The WM_MOUSEWHEEL counter is an objective low-level hook. User-reported "yes/no" for scroll is a subjective binary. A device that generates 6 scroll events in the last 237ms of a 3-second window is technically "working" by both measures, though it may feel unreliable to the user. Conversely, a device that generates 0 events in 3 seconds is unambiguous by both measures. The test-2b case reveals the limitation of the binary user observation — the user said "yes" to what was arguably a marginal scroll that only fired at the tail of the test window.

**Key transition:** Scroll worked (by user report) through test-2b. It failed at test-3 (post-reboot). The scroll disruption correlates exactly with the post-reboot structural change in the HID descriptor.

---

## 2. Battery readability across sub-steps

### Observation item 6 + tray log pattern

| Sub-step | Obs item 6 | Tray log pattern | Source |
|---|---|---|---|
| test-1-initial | "Unknown model, battery N/A" | FEATURE_BLOCKED err=87 (pct=-2) every 5 min | `test-1-initial/observations.txt:11`; `test-1-initial/tray-debug-tail.log:5–7` |
| test-2-post-repair | "Unknown Mouse Model, Battery N/A" | FEATURE_BLOCKED err=87 (pct=-2) every 5 min | `test-2-post-repair/observations.txt:11`; `test-2-post-repair/tray-debug-tail.log:3–7` |
| test-2b-post-sleep-wake | "Unknown Mouse Model, Battery N/A" | FEATURE_BLOCKED err=87 (pct=-2) every 5 min | `test-2b-post-sleep-wake/observations.txt:11` |
| test-3 | **"yes / Driver \| Magic Mouse 2024 - 44% - Next 30min"** | **DETECT split-vendor; OK battery=44% (split); POLL pct=44 next_in=00:30:00** | `test-3/observations.txt:11–12`; `test-3/tray-debug-tail.log:41–50` |

**Battery was completely inaccessible in every pre-reboot sub-step.** The tray log pattern is uniform: the tray detects `unified-apple` mode, attempts `HidD_GetFeature(0x47)`, receives `ERROR_INVALID_PARAMETER (87)`, logs `BATTERY_INACCESSIBLE`, and schedules the next poll in 5 minutes (`test-1-initial/tray-debug-tail.log:4–8`).

**Post-reboot (test-3):** The tray detected the device in `split-vendor` mode via COL02 (`test-3/tray-debug-tail.log:44,47`). Battery read via `InRpt 0x90` succeeded: `buf=[0x90 0x04 0x2C]`, yielding 44% (`test-3/hid-probe.txt:70`). Poll interval extended to 30 minutes, consistent with successful read.

### AC-05/AC-06/AC-08 status

| Check | test-1-initial | test-2-post-repair | test-2b-post-sleep-wake | test-3 |
|---|---|---|---|---|
| AC-05 (COL02 vendor battery TLC) | FAIL | FAIL | FAIL | **PASS** |
| AC-06 (Battery read Report 0x90) | FAIL | FAIL | FAIL | **PASS** |
| AC-08 (Tray app battery reading) | FAIL | FAIL | FAIL | **PASS** |

All three battery checks flipped to PASS simultaneously at test-3, and not before. The transition is discrete — there is no partial success. The flip correlates with the reboot and with the appearance of COL02 in the device enumeration.

---

## 3. HID descriptor evolution across sub-steps

### Unified interface: test-1, test-2, test-2b

All three probed sub-steps before reboot present a single HID interface with no COL suffix:

- test-1-initial: `\\?\hid#...pid&0323#a&31e5d054&b&0000#...` (`test-1-initial/hid-probe.txt:3`)
- test-2-post-repair: `\\?\hid#...pid&0323#a&31e5d054&c&0000#...` (`test-2-post-repair/hid-probe.txt:3`)
- test-2b-post-sleep-wake: `\\?\hid#...pid&0323#a&31e5d054&c&0000#...` (`test-2b-post-sleep-wake/hid-probe.txt:3`)

Note: the instance counter incremented from `&b&` to `&c&` after the unpair/repair cycle (visible between test-1 and test-2), indicating BTHENUM re-enumerated the device. The descriptor content is structurally identical across all three.

**InputValueCaps in unified mode (all three pre-reboot test points):**

```
[0] ReportID=0x02 UP=0x0001 Usage=0x0031 (Y)
[1] ReportID=0x02 UP=0x0001 Usage=0x0030 (X)
[2] ReportID=0x02 UP=0x000C Usage=0x0238 (AC Pan)
[3] ReportID=0x02 UP=0x0001 Usage=0x0038 (Wheel)
[4] ReportID=0x27 UP=0x0006 Usage=0x0001 (Generic)
```

COL01 is NOT distinct in this mode — the device presents as a single-TLC mouse (UP=0x0001 Usage=0x0002). Usage 0x0038 (Wheel) IS present at `[3]` under ReportID 0x02 in the unified interface (`test-1-initial/hid-probe.txt:12`). This means the Apple function driver is synthesizing and exposing Wheel in the unified descriptor presented to user-mode, but routing it through report 0x02 rather than declaring a separate COL01.

Feature 0x47 is declared as a FeatureValueCap (`test-1-initial/hid-probe.txt:15`) but all `HidD_GetFeature` calls return err=87 (ERROR_INVALID_PARAMETER), confirming the driver intercepts and blocks feature access at the kernel level.

### Split interface: test-3 (post-reboot)

After reboot, the probe finds TWO interfaces (`test-3/hid-probe.txt:2–4`):

- COL01: `\\?\hid#...pid&0323&col01#a&31e5d054&c&0000#...`
  - UP=0x0001 Usage=0x0002, InLen=8, FeatLen=65
  - InputValueCaps: ReportID=0x12, Y (0x0031) and X (0x0030) only — **Usage 0x0038 (Wheel) is absent** (`test-3/hid-probe.txt:9–11`)
  - FeatureValueCap: ReportID=0x55, UP=0xFF02 (vendor) — not battery-related
  
- COL02: `\\?\hid#...pid&0323&col02#a&31e5d054&c&0001#...`
  - UP=0xFF00 Usage=0x0014, InLen=3 — vendor battery TLC
  - InputValueCap: ReportID=0x90, UP=0x0085 Usage=0x0065 (Battery)
  - InRpt 0x90 returns OK: `[90 04 2C 00...]` = 44% (`test-3/hid-probe.txt:70`)

**Critical finding on Wheel (0x0038):** In the unified pre-reboot descriptor, Wheel appears under the single-TLC interface. In the post-reboot split state, COL01 contains only X and Y — Wheel is absent. The AC-04 check in test-3 fails with: "No Wheel/ACPan in COL01 ValueCaps. Found: [UP=0x0001,U=0x0031; UP=0x0001,U=0x0030]" (`test-3/accept-test.json:checks[3].detail`). This means the reboot triggered a mode change where `applewirelessmouse` exposes a different (reduced) COL01 descriptor that lacks wheel synthesis, while simultaneously exposing COL02 with battery.

**COL02 appearance:** COL02 was absent in all pre-reboot sub-steps (AC-02/AC-03 FAIL on all three). It appeared only at test-3. The `live-driver-state.json` confirms both COL01 (Status=OK, Class=Mouse) and COL02 (Status=OK, Class=HIDClass) are present post-reboot (`test-3/live-driver-state.json:pnp_devices[1,2]`).

---

## 4. Accept-test cross-reference table

| Check | test-1-initial | test-2-post-repair | test-2b-post-sleep-wake | test-3 | Flip? |
|---|---|---|---|---|---|
| AC-01 Driver bound (LowerFilters) | FAIL | FAIL | FAIL | FAIL | No flip |
| AC-02 COL01 enumerated+Started | FAIL | FAIL | FAIL | **PASS** | Flip at test-3 |
| AC-03 COL02 enumerated+Started | FAIL | FAIL | FAIL | **PASS** | Flip at test-3 |
| AC-04 COL01 scroll usage declared | FAIL | FAIL | FAIL | FAIL | No flip |
| AC-05 COL02 vendor battery TLC | FAIL | FAIL | FAIL | **PASS** | Flip at test-3 |
| AC-06 Battery read (Report 0x90) | FAIL | FAIL | FAIL | **PASS** | Flip at test-3 |
| AC-07 Kernel debug marker | FAIL | FAIL | FAIL | FAIL | No flip |
| AC-08 Tray app battery reading | FAIL | FAIL | FAIL | **PASS** | Flip at test-3 |

### Flip hypotheses (one sentence per flip)

**AC-02 (FAIL→PASS at test-3):** The reboot caused `applewirelessmouse` + HidBth to re-enumerate the device in split mode, creating a distinct COL01 PDO that pnputil now recognises as a separate HID child device (`test-3/live-driver-state.json:pnp_devices[1]`).

**AC-03 (FAIL→PASS at test-3):** Same reboot re-enumeration event that created COL01 also surfaced COL02 as a second child PDO, likely because the BTHPORT cached descriptor always contained a COL02 entry that the pre-reboot driver path was suppressing or not splitting (`test-3/live-driver-state.json:pnp_devices[2]`).

**AC-05 (FAIL→PASS at test-3):** COL02 reaching user-mode exposure for the first time allowed the accept-test to confirm the vendor battery TLC (UP=0xFF00, Usage=0x0014) at `test-3/hid-probe.txt:52`.

**AC-06 (FAIL→PASS at test-3):** With COL02 accessible, `HidD_GetInputReport(0x90)` succeeded, returning `[0x90 0x04 0x2C]` = 44% — the battery report is available via input path, not feature path (`test-3/accept-test.json:checks[5].detail`).

**AC-08 (FAIL→PASS at test-3):** The tray app detected the `split-vendor` enumeration pattern at 17:43:44, switched from unified-apple path to COL02 input report polling, and successfully read 44% (`test-3/tray-debug-tail.log:47–49`).

**AC-01 (persistent FAIL):** The accept-test script queries the BTHENUM SDP service GUID path (`{00001200-...}`) for LowerFilters, but `live-driver-state.json` confirms that LowerFilters exists on the HID service GUID path (`{00001124-...}`), not the SDP path — this is a script bug querying the wrong registry key (`test-3/live-driver-state.json:bthenum_hid_lowerfilters=["applewirelessmouse"]` vs `bthenum_sdp_lowerfilters=NOT_PRESENT`).

**AC-04 (persistent FAIL):** COL01 in split mode presents only X/Y (ReportID 0x12, 16-bit values) without Wheel or AC-Pan — the split descriptor Apple exposes post-reboot does not include wheel synthesis usages, which is the root cause of scroll failing in test-3 (`test-3/accept-test.json:checks[3].detail`).

**AC-07 (persistent FAIL):** No "MagicMouse: Descriptor injected" marker appears in `C:\mm3-debug.log` across any sub-step — the custom filter driver that would inject a modified descriptor was never loaded throughout this cell; kernel debug shows only R12 translation activity from the existing Apple driver.

---

## 5. live-driver-state.json analysis (test-3 only)

The post-reboot registry/PnP probe (`test-3/live-driver-state.json`) reveals:

**LowerFilters state:**
- `bthenum_hid_lowerfilters: ["applewirelessmouse"]` — the filter IS bound at the correct HID BTHENUM device, not the SDP service node.
- `bthenum_sdp_lowerfilters: NOT_PRESENT` — the SDP service node has no LowerFilters, which is correct and expected.

**PnP device list:** Post-reboot shows both COL01 (Status=OK, Class=Mouse, "HID-compliant mouse") and COL02 (Status=OK, Class=HIDClass, "HID-compliant vendor-defined device") are active and started. The parent BTHENUM device ("Apple Wireless Mouse", Class=HIDClass, Status=OK) is present. USB devices (VID_05AC&PID_0323) appear with Status=Unknown, indicating the USB path is not the active connection.

**Drivers loaded:** Both `applewirelessmouse` and `HidBth` are listed as loaded services (`test-3/live-driver-state.json:drivers_loaded`).

**Interpretation vs. "AppleFilter active":** The expected profile for "AppleFilter active" is: `applewirelessmouse` in LowerFilters on the BTHENUM HID device, COL01 enumerated with scroll+mouse usages, COL02 absent. The actual post-reboot state is: `applewirelessmouse` in LowerFilters (confirmed), COL01 present (confirmed), COL02 present (unexpected for standard AppleFilter — this means the filter is in a split-descriptor mode rather than unified mode). This is NOT the standard AppleFilter unified state seen pre-reboot.

**Interpretation vs. "AppleFilter not active":** Without the filter, HidBth would enumerate raw COL01 (X/Y only, no scroll) and possibly COL02. The post-reboot state has `applewirelessmouse` bound but presenting a split layout — this is consistent with a mode transition in the Apple driver triggered by some reboot-time condition, not with the filter being absent.

**Critical observation:** The tray-debug shows that at 17:11:00–17:41:01, the tray was still seeing the old unified-apple path on the `&c&0000` instance (no COL suffix) and getting FEATURE_BLOCKED (`test-3/tray-debug-tail.log:1–40`). At 17:43:44, it detected `LowerFilters=bound` and `split-vendor` mode on COL02 (`test-3/tray-debug-tail.log:41–48`). This means the driver state transitioned sometime between the reboot-login and 17:43:44 — the tray caught the transition live. The accept-test ran at 17:47:48 and saw the split state.

---

## 6. Independent verdict on M13 Q1–Q7

**Q1: Does the v3 BTHPORT cached descriptor already declare COL02 (UP=0xFF00 U=0x0014)?**
**INSUFFICIENT-DATA** — The cached descriptor was never directly decoded in this cell. The post-reboot appearance of COL02 is consistent with it being present in the cache, but this cell does not include a Phase 3 cache-decode run.

**Q2: Does the v3 cached descriptor declare any wheel/AC-Pan usages?**
**INSUFFICIENT-DATA** — Same reason. The unified pre-reboot descriptor exposed Wheel (0x0038) and AC-Pan (0x0238) via `applewirelessmouse`, but whether these are in the cache blob vs. synthesized by the driver cannot be determined from this cell's artefacts alone.

**Q3: With `applewirelessmouse` as function driver, what subset of the cached descriptor reaches HidClass?**
**CONFIRMED (partially):** Pre-reboot unified mode: single TLC, Wheel present, no COL02 (`test-1-initial/hid-probe.txt:8–15`). Post-reboot split mode: COL01 with X/Y only (no Wheel), COL02 with vendor battery (`test-3/hid-probe.txt:7–55`). Both are subsets delivered by `applewirelessmouse`, but under different enumeration paths. The driver presents different descriptor views depending on the boot/reconnect path.

**Q4: With `applewirelessmouse` removed (NoFilter mode), does battery work?**
**INSUFFICIENT-DATA** — NoFilter mode was not tested in Cell 1 (this is cell T-V3-AF, AppleFilter only). No basis to answer.

**Q5: Does patching the cached descriptor to add COL02 + reload result in both COL01 (scroll) and COL02 (battery) visible?**
**INSUFFICIENT-DATA** — No cache patch was applied in this cell.

**Q6: Does the v1 mouse exhibit the same architecture or different?**
**INSUFFICIENT-DATA** — v1 mouse not tested in this cell.

**Q7: Can we deliver scroll+battery on v3 without writing a kernel driver?**
**REFUTED (for the post-reboot split state):** Post-reboot, battery works (44% read successfully) but scroll is broken — COL01 in split mode lacks Wheel usage (`test-3/accept-test.json:AC-04 FAIL`). Pre-reboot, scroll works but battery is inaccessible. No single configuration observed in this cell delivers both simultaneously. The evidence establishes a mutual exclusion in the currently observed states: the mode that gives battery (post-reboot split) breaks scroll; the mode that gives scroll (pre-reboot unified) blocks battery.

---

## 7. Hypothesis ranking

### H1: `applewirelessmouse` exposes different descriptor views depending on whether it loads from a cold boot vs. a BT reconnect-only event
**STRONGLY-SUPPORTED**

Evidence: Pre-reboot sub-steps (initial, post-repair, post-sleep-wake) all present unified-TLC mode. Post-reboot presents split-TLC mode. The unpair/repair cycle changed the instance counter (`&b&` → `&c&`) but not the descriptor layout, confirming that unpair+repair alone does not trigger the split. Only the reboot caused the change. The sleep/wake sub-step (S3 suspend/resume, not a full boot) also preserved unified mode. This is consistent with the split behavior requiring a full driver load at boot via the registry-backed driver stack, whereas BT reconnects re-use the already-loaded driver state.

### H2: AC-01 (Driver bound LowerFilters) is a test-script bug, not a real failure
**STRONGLY-SUPPORTED**

Evidence: `live-driver-state.json:bthenum_hid_lowerfilters=["applewirelessmouse"]` confirms the filter IS present (`test-3/live-driver-state.json:line 4`). AC-01 queries the SDP GUID path `{00001200-...}` but `live-driver-state.json:bthenum_sdp_lowerfilters=NOT_PRESENT` confirms that path correctly has no LowerFilters. The accept-test queries the wrong GUID. This means AC-01 reports FAIL across all four test sub-steps even when the filter is demonstrably bound.

### H3: The post-reboot split state represents `applewirelessmouse` presenting the raw BTHPORT cache layout rather than Apple's synthesized unified layout
**WEAK-EVIDENCE**

The split COL01+COL02 structure (COL01 with X/Y only, COL02 with vendor battery) looks like what HidBth alone would present from a two-TLC cache blob. Post-reboot, the filter may be forwarding the cache descriptor without modification rather than presenting its synthesized unified view. However, this cannot be confirmed without cache decode (Phase 3 data not available in this cell).

### H4: The 6-event wheel burst in test-2b represents transient scroll after sleep/wake, which degraded before the 3-second window was fully active
**WEAK-EVIDENCE**

All 6 events cluster at t_ms 2551–2787, with nothing in the first 2.5 seconds (`test-2b-post-sleep-wake/wheel-events.json:6–11`). This is consistent with a delayed BT reconnect after S3 resume, where the mouse needed time to re-establish the HID interrupt channel. The user reported "yes" to scroll, which is technically accurate for those 6 events but may overstate reliability. Whether this represents a genuine timing issue vs. the user simply waiting longer before gesturing cannot be determined from this data alone.

### H5: The reboot-triggered split state is deterministic and reproducible, not a transient artifact
**WEAK-EVIDENCE**

Only one reboot was performed in this cell. The data shows a clear before/after split correlated with reboot, but a single data point cannot establish reproducibility. The tray log shows the split state persisting from at least 17:43:44 through the accept-test at 17:47:48, but whether it would revert on the next sleep/wake or BT reconnect is unknown.

---

## 8. What the data does NOT prove

**8a. That the BTHPORT cached descriptor contains COL02 natively.** Post-reboot COL02 appearing is consistent with the cached descriptor having COL02, but `applewirelessmouse` might also synthesize COL02 from SDP attributes without cache data. The cache blob was not decoded in this cell.

**8b. That scroll broke because of the split descriptor mode specifically, rather than some other reboot-time state change.** COL01 in split mode lacks Wheel (`test-3/accept-test.json:AC-04 FAIL`), and wheel-events.json shows 0 events. But we do not have direct evidence that the kernel driver itself stopped translating R12 reports into WM_MOUSEWHEEL — the kernel debug log is the same static pre-reboot file across all sub-steps (all kernel-debug-tail.log files are byte-for-byte identical, lines 00018494–00018593, timestamps 292.49–295.07 seconds, clearly a single captured tail replicated). No post-reboot kernel debug data is available.

**8c. That sleep/wake alone cannot trigger the split state.** This cell ran sleep/wake and found unified mode was preserved. But the sleep/wake here was performed before the reboot that finally triggered the split. If sleep/wake were performed after a cold boot where the split was already active, the outcome might differ. One sleep/wake data point is insufficient.

**8d. That AC-01 ever represented a real driver binding failure.** All AC-01 FAIL results across all four test sub-steps are now best explained by the script querying the wrong registry path (`{00001200-...}` SDP vs. `{00001124-...}` HID). There is no evidence in this cell that `applewirelessmouse` was ever absent from LowerFilters after the initial setup.

**8e. That the 44% battery reading in test-3 is from a fresh HID poll vs. a cached value.** The tray transitioned from unified-apple to split-vendor and immediately read 44% at 17:43:44. Whether that value was read fresh via Report 0x90 or came from a prior device state is consistent with the data but cannot be distinguished from a single read without a comparison poll.

---

## Metadata

- **Files read:** 35 artefact files
- **Files intentionally skipped:** 4 (per anti-bias rules)
- **Reboot sub-step files:** 0 (directory exists, no log files — empty)
- **Kernel debug logs:** All 7 sub-steps share the same 101-line tail (lines 00018494–00018593, ts 292.49–295.07), indicating the DebugView tail was captured once pre-reboot and copied verbatim across sub-steps. No new kernel debug data was captured post-reboot.
- **Evidence quality:** Strong for scroll/battery behavioral changes; moderate for descriptor mechanism; weak for cache-level attribution.
