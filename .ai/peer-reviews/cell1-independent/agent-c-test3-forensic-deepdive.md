# Agent C — Test-3 Forensic Deep-Dive
**Cell:** T-V3-AF | **Sub-step:** test-3 (post-reboot) | **Analyst role:** Independent forensic; no prior cell conclusions read  
**Date:** 2026-04-27 | **Scope:** test-3 captures + substep-diff cross-reference + M13 success-criteria section only

---

## 1. Test-3 Device State Reconstruction

### 1.1 HID Interfaces Enumerated

The probe (`hid-probe.txt`) found exactly **2 HID interfaces**, both timestamped 17:47:46 — post-reboot collection:

**COL01** — `…col01#a&31e5d054&c&0000…`  
- UsagePage=0x0001 (Generic Desktop), Usage=0x0002 (Mouse)  
- InLen=8, FeatLen=65  
- InputValueCaps (n=2):  
  - [0] ReportID=0x12, UP=0x0001, Usage=0x0030 (X axis), BitSize=16, Range ±2047  
  - [1] ReportID=0x12, UP=0x0001, Usage=0x0031 (Y axis), BitSize=16, Range ±2047  
- FeatureValueCaps (n=1): ReportID=0x55, UP=0xFF02, Usage=0x0055, BitSize=8, Count=64 (vendor feature blob)  
- ButtonCaps=1  
- `hid-probe.txt:7-13`

**COL02** — `…col02#a&31e5d054&c&0001…`  
- UsagePage=0xFF00 (vendor), Usage=0x0014  
- InLen=3, FeatLen=0  
- InputValueCaps (n=1):  
  - [0] ReportID=0x90, UP=0x0085 (Power Device), Usage=0x0065, BitSize=8, Count=1, Range 0–255  
- ButtonCaps=3  
- `hid-probe.txt:52-55`

**Critical observation:** COL01's InputValueCaps contain **only X (0x0030) and Y (0x0031)**. There is no Wheel (Usage=0x0038) and no AC-Pan (UP=0x000C, Usage=0x0238) in the declared value caps. This is the direct cause of scroll failure; see Section 2.

**Report-ID probing results:** All `HidD_GetInputReport` calls against COL01 return `err=1` (ERROR_INVALID_FUNCTION / access denied by exclusive-mode driver). COL02 returns `err=87` (ERROR_INVALID_PARAMETER) on everything *except* Report 0x90, which returns `OK bytes=[90 04 2C 00…]` — 0x2C = 44 decimal, i.e. 44% battery. `hid-probe.txt:63,70`

The err=1 vs err=87 asymmetry is meaningful: err=1 on COL01 input reports means the HID minidriver is refusing input-report reads (exclusive open or unsupported IRP path), while err=87 on COL02 means the report ID doesn't match the declared caps for that interface. Only 0x90 is declared for COL02, and it alone succeeds.

### 1.2 LowerFilters Registry State

`live-driver-state.json` (captured 17:56:45, ~9 minutes after the probe):

- `bthenum_hid_lowerfilters`: `["applewirelessmouse"]` — **present on the BTHENUM HID device node** (`{00001124-…}_VID&0001004C_PID&0323`)  
- `bthenum_sdp_lowerfilters`: NOT_PRESENT on the SDP/DIS node (`{00001200-…}_VID&0001004C_PID&0323`) — `live-driver-state.json:6`

So the LowerFilter is bound to the HID service interface, not to the Device Identification (SDP) interface. The filter survived the reboot in registry — `applewirelessmouse` is still listed. But see AC-01 analysis in Section 2 for why the accept-test script falsely reports this as FAIL.

### 1.3 PnP Device Tree (Relevant Nodes)

From `live-driver-state.json:pnp_devices` — nodes relevant to the Magic Mouse BT path:

| Status | Class | FriendlyName | InstanceId (abbreviated) |
|--------|-------|--------------|--------------------------|
| OK | Mouse | HID-compliant mouse | HID\{00001124-…}_VID&0001004C_PID&0323&COL01 |
| OK | HIDClass | HID-compliant vendor-defined device | HID\{00001124-…}_VID&0001004C_PID&0323&COL02 |
| OK | Bluetooth | Device Identification Service | BTHENUM\{00001200-…}_VID&0001004C_PID&0323 |
| OK | HIDClass | Apple Wireless Mouse | BTHENUM\{00001124-…}_VID&0001004C_PID&0323 |
| Unknown | HIDClass | Magic Mouse 2024 - USB-C | USB\VID_05AC&PID_0323&MI_01 |
| Unknown | Mouse | HID-compliant mouse | HID\{00001124-…}_VID&0001004C_PID&0323 (no COL suffix) |

The two COL nodes are Status=OK. The parent "Apple Wireless Mouse" BTHENUM node is also OK. The USB-C nodes are all Status=Unknown — expected; mouse is operating via BT, not USB in this test. Drivers loaded: `applewirelessmouse` and `HidBth` — `live-driver-state.json:76-79`.

### 1.4 Kernel Debug Log Analysis

`kernel-debug-tail.log` contains 100 lines spanning timestamps 292.49–295.07 seconds (system uptime-relative DebugView timestamps). Every group of 4 lines follows a fixed pattern:

```
MagicMouse: AclIn chan=… ctrl=… intr=… flags=0x3 sz=9
MagicMouse: Report hdr=0xa1 id=0x12 sz=9 chan=intr
MagicMouse: Translate R12 sz=9
MagicMouse: IOCTL 0x00410003
```

All events: ReportID=0x12, size=9 bytes, arriving on the interrupt channel. The driver is receiving and translating HID reports. The `IOCTL 0x00410003` is the HidClass ioctl for `IOCTL_HID_READ_REPORT` completion — the driver is processing mouse movement/click reports and passing them up the stack.

**Crucially absent:** There are no `MagicMouse: Descriptor injected` lines anywhere in the log. This is why AC-07 fails. The kernel driver is active and translating R12 reports, but it did not inject a modified descriptor at AddDevice time — which is the expected behavior if the filter is installed but either (a) the injection path was not triggered, or (b) the descriptor was served from BTHPORT cache without a filter-side override.

**Timestamp authenticity:** The DebugView timestamps are system-uptime-relative (seconds since boot), not wall-clock. The capture file is a tail of `C:\mm3-debug.log`. The wall-clock of the probe was 17:47:46. The tray log shows the transition to split-COL mode happened at 17:43:44. The kernel log's activity timestamps (292–295s) are consistent with a post-reboot session where system uptime could be ~5 minutes. There is no evidence this is a pre-reboot relic; the kernel is actively delivering R12 interrupt reports in real time at the tail.

### 1.5 Tray App Debug Log

`tray-debug-tail.log` spans 17:11:00 → 17:43:44. Key phases:

**17:11:00 – 17:41:01 (pre-transition, unified-apple mode):**  
Every 5-minute poll: HIDP_CAPS shows InLen=47, FeatLen=2, TLC=UP:0001/U:0002 (single unified interface). The tray detects `Feature=0x47 (Battery Strength)`, gets err=87, logs `BATTERY_INACCESSIBLE`, and updates tooltip to "battery N/A". `tray-debug-tail.log:1-40`

**17:43:44 (transition — split-COL mode detected):**  
- `DRIVER_CHECK pid=0x0323 LowerFilters=bound` — filter present in registry  
- `DRIVER_CHECK unknown_apple_pid=0x0239 bound=False` — checks PID 0x0239 (older MM model), correctly returns false for 0x0323  
- `DRIVER_CHECK status=UnknownAppleMouse (PID not in INF)` — the tray's PID-lookup table doesn't include 0x0323  
- `HIDP_CAPS` now shows COL01 (InLen=8, FeatLen=65) and COL02 (InLen=3, FeatLen=0, TLC=UP:FF00/U:0014)  
- Detects `split-vendor InputReport=0x90`  
- Reads battery: `battery=44%`  
- Tooltip updated: "Magic Mouse 2024 - 44% · Next: 30m"  
- `tray-debug-tail.log:41-50`

The tray detected the post-reboot split enumeration at first-poll opportunity after reboot (17:43:44 wall time, which precedes the 17:47:48 accept-test run).

### 1.6 User Observations (item-by-item)

`observations.txt` — test-3, 17:47:55:

1. (pointer movement) — yes  
2. (2-finger vertical scroll) — **no**  
3. (2-finger horizontal AC-Pan) — **no**  
4. (left click) — yes  
5. (right click) — yes  
6. (battery) — **yes** — "Driver | Magic Mouse 2024 - 44% - Next 30min"  
`observations.txt:6-12`

### 1.7 Wheel Events

`wheel-events.json`: `event_count=0`, `duration_sec=3`, captured 17:47:55. Zero WM_MOUSEWHEEL events during a 3-second 2-finger gesture. Scroll is definitively broken — not intermittent.

---

## 2. AC-Check Pass/Fail Analysis

| Check | Result | Assessment |
|-------|--------|------------|
| AC-01 | FAIL | **Script bug — false negative** |
| AC-02 | PASS | Real pass — COL01 Status=Started confirmed |
| AC-03 | PASS | Real pass — COL02 Status=Started confirmed |
| AC-04 | FAIL | **Real failure** — Wheel/AC-Pan genuinely absent |
| AC-05 | PASS | Real pass — COL02 vendor battery TLC confirmed |
| AC-06 | PASS | Real pass — 0x90 read returns 44% |
| AC-07 | FAIL | Real failure — no injection marker (driver not injecting descriptor) |
| AC-08 | PASS | Real pass — tray read battery at 17:43:44 |

### AC-01 — Script Bug (False Negative)

AC-01 detail: `"Cannot read registry at HKLM:\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001200-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\…: The property 'LowerFilters' cannot be found"`  
`accept-test.json:15`

The script is querying the `{00001200-…}` (Device Identification / SDP) GUID path. That is the wrong node. The actual LowerFilters registry entry is on the `{00001124-…}` (HID) GUID path — as confirmed by `live-driver-state.json:bthenum_hid_lowerfilters=["applewirelessmouse"]`. The LowerFilter is present and correct; the AC-01 script is querying the wrong GUID. This is a script bug, not a real failure. The filter is bound.

### AC-04 — Real Failure

AC-04 detail: `"No Wheel/ACPan in COL01 ValueCaps. Found: [UP=0x0001,U=0x0031; UP=0x0001,U=0x0030]"`  
`accept-test.json:33-34`

Cross-confirmed by `hid-probe.txt:10-11`: COL01 InputValueCaps contain only Usage=0x0031 (Y) and Usage=0x0030 (X). Wheel (0x0038) and AC-Pan (UP=0x000C, 0x0238) are absent. This is a genuine descriptor-level absence, not a runtime issue.

### AC-07 — Real Failure (Driver Inert Post-Reboot)

The `mm3-debug.log` contains no `MagicMouse: Descriptor injected` line. The kernel log shows the driver is active (translating R12 reports) but never ran the descriptor-injection code path. This indicates the filter driver loaded and attached but did not replace the descriptor — it is receiving and forwarding reports, which is consistent with it being either (a) in passthrough mode, or (b) using a descriptor path that does not produce this log marker.

---

## 3. Cross-Reference Against Sub-Step State Evolution

### 3.1 HID Enumeration Changes at Sub-step Boundaries

`substep-state-evolution.md` — State table:

- test-1-initial through test-2b-post-sleep-wake: `(no probe)` for COL01/COL02 — the HID probe tool was not run in earlier sub-steps.  
- test-3: COL01 shows `0x30(X), 0x31(Y), 0x55(?)`, COL02 shows `0x65(?)`.

The sub-step diff tool did not have probe data from earlier steps, so we cannot directly compare descriptor content across sub-steps. The first point where we have explicit proof of the COL01/COL02 split enumeration is test-3. However, the tray log reveals timing: the tray was seeing a **unified single interface** (InLen=47, one TLC) from 17:11:00 to 17:41:01 (all pre-reboot polls), and then saw split COL01+COL02 at 17:43:44 (post-reboot first poll). The enumeration structure changed at the reboot boundary. `tray-debug-tail.log:5,44-46`

### 3.2 Wheel-Event Count Changes

| Sub-step | Wheel events |
|----------|-------------|
| test-1-initial | 0 |
| test-2-post-repair | 0 |
| test-2b-post-sleep-wake | **6** |
| test-3 | **0** |

`substep-state-evolution.md:35-40`

Scroll was non-functional at test-1 and test-2, then briefly worked at test-2b (6 events in 3 seconds — a meaningful scroll gesture). After the reboot, scroll broke again (0 events). The sleep/wake transition at test-2b temporarily restored scroll; the reboot at test-3 broke it again.

### 3.3 When Did "Scroll Works" First Flip?

- test-1-initial obs item 2: "yes" — `substep-state-evolution.md:51`  
- test-2-post-repair obs item 2: "yes" — `substep-state-evolution.md:66`  
- test-2b-post-sleep-wake obs item 2: "yes" — `substep-state-evolution.md:79`  
- test-3 obs item 2: **"no"** — `substep-state-evolution.md:101`

The first "no" for scroll appears at test-3 (post-reboot). The human observed scroll working through test-2b. Scroll broke between the sleep/wake → reboot transition. The wheel-event data aligns: 6 events at test-2b, 0 at test-3.

**Note on test-1 and test-2:** Both show obs item 2 = "yes" but wheel events = 0. This is an observation/instrument discrepancy. The human reported scroll working, but the WM_MOUSEWHEEL counter captured nothing. Possible explanations: the AppleFilter driver delivers scroll via a different message path (e.g., WM_VSCROLL or raw HID reports direct to the focused window), or the wheel counter hook was not positioned correctly in those earlier sub-steps. The quantitative metric and subjective observation diverge at test-1 and test-2.

### 3.4 Battery Flip

- test-1 through test-2b: obs item 6 shows "Unknown model, battery N/A" / "Unknown Mouse Model, Battery N/A"  
- test-3: obs item 6 shows "yes" — "Driver | Magic Mouse 2024 - 44% - Next 30min"  
`substep-state-evolution.md:56,71,86,104-105`

Battery flipped from N/A to readable at the test-3 boundary (post-reboot). The tray log confirms this: the transition from unified-mode (Feature 0x47 blocked, battery inaccessible) to split-COL mode (Report 0x90 readable, 44%) occurred at 17:43:44 post-reboot, before the accept-test ran. `tray-debug-tail.log:41-50`

AC-check deltas confirm: AC-05 (battery TLC), AC-06 (battery read), AC-08 (tray reading) all flipped from FAIL to PASS exclusively at test-3. `substep-state-evolution.md:28-31`

---

## 4. Hypothesis Analysis — Where Did the State Change?

### H1: BTHPORT Cached Descriptor Changed (Registry-Side)

**Evidence for:** The enumeration structure flipped at the reboot boundary — from a single unified HID interface (InLen=47) to two split COL interfaces (COL01 InLen=8 + COL02 InLen=3). Reboot is when BTHPORT re-reads its cached descriptor from `HKLM\…\BTHPORT\Parameters\Devices\<mac>\CachedServices\00010000` and presents it to HidBth. If something modified the cached descriptor between test-2b and the reboot, or if the driver presented the cached descriptor differently on cold-boot vs on resume-from-sleep, this would explain the split.

**Evidence against:** Sleep/wake (test-2b) did not break scroll — if BTHPORT cache was the source, sleep/wake (which does NOT re-run AddDevice per M13 plan section "Sleep/wake sub-step rationale") should have preserved the pre-sleep state. The fact that scroll worked at test-2b but broke after reboot points to AddDevice being the critical path, not cache content alone.

**Verdict:** Plausible but not confirmed. Descriptor content across sub-steps is not directly comparable due to missing probe data in earlier steps.

### H2: HidBth Binding Difference After Reboot

**Evidence for:** HidBth is listed as loaded (`live-driver-state.json:78`). Post-reboot AddDevice runs HidBth fresh with the cached descriptor. If HidBth parses the cached descriptor differently than it did during a live session's resume, or if the filter installs in a slightly different order relative to HidBth's AddDevice, the descriptor presented to HidClass could differ. The split COL enumeration (COL01 + COL02) is exactly what HidBth-alone produces when the cached descriptor declares multiple top-level collections.

**Evidence against:** The descriptor content (COL01 lacking Wheel) is the same fundamental problem regardless of binding order. HidBth binding to the correct node is confirmed (Apple Wireless Mouse node Status=OK).

**Verdict:** HidBth binding is intact. The binding itself is not the source of the scroll break — the descriptor content is.

### H3: applewirelessmouse Filter Running But Inert Post-Reboot

**Evidence for:** The kernel log shows `MagicMouse: Translate R12` happening repeatedly — the driver is processing reports. But no `Descriptor injected` marker was ever emitted. The driver is in a state where it processes incoming reports (AclIn → R12 translation) but did not inject a modified descriptor at AddDevice time. This is consistent with the filter attaching to the device stack but not having its descriptor-injection code path triggered — perhaps because it only injects when it sees a specific descriptor pattern, and the descriptor it saw post-reboot was already split (COL01 + COL02) rather than unified.

**Evidence for (tray):** Pre-reboot, the tray saw a unified interface (one HID node, InLen=47) with Feature=0x47. Post-reboot, the tray saw split COL01+COL02. This is the opposite of what the filter should produce if its job is to split a unified descriptor. Either: (a) the filter ran before the split occurred and the split is its output, or (b) BTHPORT already cached a split descriptor and the filter is passthrough. The absence of `Descriptor injected` in the kernel log strongly favors (b).

**Evidence against:** If the filter injected a descriptor, the kernel log would contain the injection marker. Its absence is the strongest evidence the filter did not perform descriptor injection post-reboot.

**Verdict:** Most consistent with the data. The filter loaded, attached, and processes reports, but did not inject a descriptor — it is passthrough in this configuration. Scroll is absent because the cached/presented descriptor lacks Wheel usage, and the filter is not adding it.

### H4: Power-State Issue (Selective Suspend / D2)

**Evidence for:** err=1 on all COL01 input-report reads could indicate the device is in a low-power state where the interrupt pipe is not accepting IRP_MJ_READ. Selective suspend would remove the interrupt endpoint.

**Evidence against:** The kernel debug log shows continuous `AclIn` events with real report data (R12, sz=9) at ~1Hz frequency. A device in D2/selective suspend would not be delivering ACL interrupt reports. The mouse is clearly awake and active. Battery reads succeed on COL02 (Report 0x90). The err=1 on COL01 input reports is more likely exclusive-mode enforcement (the Mouse class driver holds an exclusive open on COL01) than a power-state issue. `kernel-debug-tail.log:1-4`

**Verdict:** Ruled out. Device is fully awake and delivering reports.

---

## 5. Most Parsimonious Explanation

Here is the simplest explanation that fits all the test-3 data and the sub-step diff without contradiction:

**The reboot triggered a cold-boot AddDevice sequence where BTHPORT presented the cached HID descriptor to HidBth. That cached descriptor already declares two top-level collections — COL01 (mouse X/Y, ReportID 0x12) and COL02 (vendor battery, ReportID 0x90) — resulting in the split enumeration the tray detected post-reboot. The applewirelessmouse filter driver loaded and attached to the device stack, but found a descriptor that didn't match its expected unified-mouse pattern, so it passed through without injecting a modified descriptor. As a result, COL01 presents only X/Y (no Wheel, no AC-Pan), and scroll is broken. Battery works because COL02 is natively present in the cached descriptor and accessible via Report 0x90.**

The pre-reboot state (test-1 through test-2b) was a unified single HID interface where applewirelessmouse was performing scroll synthesis. The tray confirms this: "unified-apple Feature=0x47" mode, battery inaccessible, scroll working (subjectively confirmed by user for test-1 through test-2b). Post-reboot, something in the BTHPORT cache or the driver initialization order produced a split descriptor. The filter driver, not finding its expected unified descriptor, ran in passthrough mode — delivering split COL01/COL02 but not synthesizing scroll.

Why scroll worked at test-2b (sleep/wake) but not test-3 (reboot): sleep/wake does not re-run AddDevice. The driver stack persisted from the pre-sleep unified state, so the filter continued in its scroll-synthesis mode. The reboot forced a fresh AddDevice, which picked up the split-descriptor state.

---

## 6. What the Data Refutes

**Refuted: Battery was always inaccessible in AppleFilter mode.** AC-06 PASS + tray 44% reading at 17:43:44 + user obs item 6 = "yes" confirm battery is fully readable post-reboot in AppleFilter mode. The pre-reboot inaccessibility was specific to the unified-interface state. `accept-test.json:45-47`, `tray-debug-tail.log:47-49`

**Refuted: The filter is not installed post-reboot.** AC-01 is a false negative due to wrong GUID in the script. `live-driver-state.json:bthenum_hid_lowerfilters` confirms applewirelessmouse is still in LowerFilters.

**Refuted: Scroll failure is a power-state / selective-suspend issue.** Kernel log shows continuous real interrupt reports; device is fully awake and communicating. `kernel-debug-tail.log:1-4`

**Refuted: COL01 and COL02 not enumerated post-reboot.** AC-02 and AC-03 both PASS; pnp_devices shows both COL01 (Mouse, OK) and COL02 (HIDClass, OK). `accept-test.json:19-28`

**Refuted: The wheel-event counter tool was broken at test-3.** The tool captured 6 events at test-2b (working scroll) and 0 at test-3 (broken scroll). The tool is functioning; the absence of events is real. `substep-state-evolution.md:37-39`

**Refuted: The kernel driver is not running at all.** The kernel debug log shows the driver actively processing AclIn and Translate R12 sequences. It is loaded, attached, and forwarding reports. It simply did not inject a descriptor. `kernel-debug-tail.log:1-4`

---

## 7. Recommended Additional Captures

**One 5-minute instrumentation pass priority: Registry export of the BTHPORT cached descriptor immediately post-reboot (before any driver interaction).**

Specifically:

1. `reg export "HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\d0c050cc8c4d" bthport-cache-post-reboot.reg` — capture the full device node including `CachedServices\00010000` REG_BINARY blob.

2. Parse the SDP TLV from that blob (attribute 0x0206, HIDDescriptorList) using `mm-bthport-read.ps1` (referenced in M13 Phase 3) — decode the embedded HID descriptor to check: does it declare COL01 + COL02 natively, or just COL01?

3. Compare the decoded descriptor's COL01 report definition against what `hid-probe.txt` shows — does the cache declare Wheel usage (0x0038) or not?

This single capture answers the two remaining open questions:

- **Is Wheel usage absent from the cached descriptor itself?** If yes, applewirelessmouse must be synthesizing it (and stopped doing so post-reboot). If no, applewirelessmouse is stripping it.
- **Does the cache natively declare COL02?** If yes, the post-reboot split enumeration is a direct read from cache. If no, HidBth or the filter is synthesizing it from somewhere else.

This directly disambiguates H1 (cache content) from H3 (filter passthrough behavior) and gives the M13 Phase 3 data needed to answer Q1, Q2, Q3 from the success criteria.

---

## Anti-bias Attestation

The following files were **not read** during this analysis:  
- `cell1-report.md`  
- `PSN-0001-hid-battery-driver.yaml`  
- `.ai/playbooks/autonomous-agent-team.md`  
- PRD-184 Decisions table  

No contamination encountered.

---

## 200-Word Summary

**Post-reboot (test-3) state:** The Magic Mouse split into two HID collections — COL01 (mouse X/Y only, no Wheel) and COL02 (vendor battery, Report 0x90 = 44%). Both Status=OK. `applewirelessmouse` is in LowerFilters (AC-01 is a false negative — wrong GUID in script). The kernel driver is active and translating R12 reports but never emitted a "Descriptor injected" marker, indicating it ran in passthrough mode. Battery is fully readable (AC-05, AC-06, AC-08 all PASS). Scroll is definitively broken: 0 wheel events in 3 seconds, user obs item 2 = "no".

**Cross-reference finding:** Scroll worked subjectively through test-2b (sleep/wake), broke at test-3 (reboot). Wheel-event counter confirms: 6 events at test-2b, 0 at test-3. Battery flipped from N/A to 44% at the reboot boundary — the opposite direction from scroll.

**Root cause hypothesis:** The BTHPORT cached descriptor already declares two TLCs (COL01 + COL02). Post-reboot AddDevice served this split descriptor to HidBth directly. `applewirelessmouse` attached but did not inject a descriptor (no marker, passthrough mode), so COL01 has only X/Y — no Wheel. Scroll synthesis stopped; battery became accessible.

**Priority next capture:** Decode the BTHPORT cache blob to confirm whether COL01 in the cache declares Wheel (0x0038) or not. That single data point disambiguates whether the filter is supposed to add Wheel (and failed), or whether the cache never had it.
