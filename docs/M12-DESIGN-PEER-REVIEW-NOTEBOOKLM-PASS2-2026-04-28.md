# M12 Design Spec v1.2 + MOP v1.2 — NotebookLM Peer Review Pass 2 (2026-04-28)

## BLUF

NotebookLM pass-2 verdict: **CHANGES-NEEDED** — adversarial template applied; corpus has zero production implementations matching the M12 v1.2 architecture exactly (pure-kernel KMDF lower filter + Feature 0x47 short-circuit completion + RID=0x27 shadow-buffer tap, no descriptor mutation, no active polling), so verdict is downgraded from REJECT per playbook v1.8 line 199. All four senior driver-dev critical issues (CRIT-1 UAF, CRIT-2 deadlock, CRIT-3 BSOD-on-disconnect, CRIT-4 NULL IoTarget) are confirmed properly addressed in v1.2. HID 1.11 §7.2 compliance for Feature 0x47 inline completion is confirmed. Two NEW blocking issues introduced by v1.2's aggressive simplification: (1) the same-path-for-v1-and-v3 (Section 7d) regresses v1's working Feature 0x47 — v1 firmware natively backs 0x47, but v1.2 force-routes v1 through an unverified RID=0x27 shadow buffer that may have a different battery byte layout; (2) abandoning BRB-level descriptor mutation creates a fresh-pair compatibility risk: a user pairing the mouse AFTER M12 install (no `applewirelessmouse` to do the prior mutation) gets the device's native Descriptor A in the BTHPORT cache, which doesn't declare Feature 0x47 and HidClass will reject `HidD_GetFeature(0x47)` at the parsing layer. Two non-blocking concerns: BATTERY_OFFSET=1 is a hypothesis that may surface garbage data if the byte maps to a touch coordinate; cold-start with idle mouse may show N/A indefinitely until user input triggers a 0x27 frame. MOP v1.2 gates VG-0..VG-7 are called "remarkably well-designed" and adequately catch all four risks before soak completion, but the blocking architectural fixes should land in v1.3 before any code is written.

---

## Source

- **Notebook:** PRD-184 — Magic Mouse 3 KMDF Driver — `e789e5e9-da23-4607-9a62-bbfd94bb789b`
- **New sources for pass 2:**
  - `981c1d0c-7674-4660-aa6d-5036de914115` — M12 Design Spec v1.2 (39 KB)
  - `cd3573b2-9a21-411d-9142-aa2ea0f85ef3` — M12 MOP v1.2 (20 KB)
- **Conversation thread:** `8dfc914c-2b40-4ccf-bdb1-f6d582a08a25` (continued from pass 1)
- **Prior pass 1 verdict:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-2026-04-28.md`

## Adversarial check (production implementation evidence)

NLM enumerated production references in the corpus and concluded NONE match the v1.2 architectural combination exactly (shadow-buffer-only, no descriptor mutation, no active poll):

| Reference | Filter type | In-IRP F0x47 translation? | Active polling? | Descriptor mutation? | Match for v1.2? |
|---|---|---|---|---|---|
| Apple `applewirelessmouse.sys` | lower filter | **NO** (passive pass-through, returns err=87) | NO | YES (mutates to unified Descriptor B) | NO |
| Magic Utilities `MagicMouse.sys` | function driver | YES (via custom PDO IOCTL) | YES (private IOCTL) | YES (Mode A) | NO (userland-gated, function driver) |
| Linux `hid-magicmouse.c` | n/a (Linux kernel) | n/a (different battery model) | YES (60-sec timer via `hid_hw_request`) | YES (`magicmouse_report_fixup`) | NO (Linux, not KMDF) |
| **M12 v1.2 (proposed)** | lower filter | YES (short-circuit from shadow) | NO | NO | — |

Verdict downgrade applied: REJECT -> CHANGES-NEEDED, conditional on resolving the two blocking architectural issues.

## Q1. Are senior driver-dev CRIT-1..CRIT-4 properly addressed in v1.2?

**Yes — all four critical issues are properly addressed.**

- **CRIT-1 (parallel-queue UAF on read completion):** ADDRESSED. M12 no longer completes `IOCTL_HID_READ_REPORT` IRPs. Completion routine is a passive read-only tap that runs AFTER the IoTarget completes the IRP upstream; M12 never modifies the IRP buffer or re-completes (Sec 3b Flow 1, Sec 7b). Double-complete surface eliminated.
- **CRIT-2 (sync IoTarget send deadlock):** ADDRESSED. Active-poll path REMOVED entirely; Feature 0x47 is short-circuited inline from shadow buffer (Sec 7c). No `WdfIoTargetSendIoctlSynchronously`. Driver Verifier deadlock-detection cannot fire.
- **CRIT-3 (missing EvtIoStop = BSOD on BT disconnect):** ADDRESSED. EvtIoStop registered on both queues (Sec 8a), EvtDeviceSelfManagedIoSuspend stops the IoTarget and invalidates the shadow buffer (Sec 8b). VG-6 (forced disable under Driver Verifier 0x9bb) gates this empirically.
- **CRIT-4 (NULL IoTarget before EvtDevicePrepareHardware):** ADDRESSED. M12 uses `WdfDeviceGetIoTarget(device)` which returns the default lower IoTarget — valid immediately after `WdfDeviceCreate` returns, no separate IoTarget creation in EvtDevicePrepareHardware (Sec 3a). NULL-deref window eliminated.

## Q2. Is the shadow-buffer + short-circuit IRP architecture HID-spec-compliant?

**Yes.** Per HID 1.11 §7.2 GET_REPORT, the host requests a Feature report and the device (or stack) returns a buffer matching the descriptor declaration. Descriptor B declares Feature 0x47 with `Logical Min=0, Max=100, Size=8, Count=1` — total 1 byte payload + 1 byte Report ID = 2 bytes on-wire. M12 v1.2 completes the IRP inline with `[0x47, percentage_byte]` and `WdfRequestSetInformation(req, 2)` — exactly matches the descriptor declaration and HidClass parsing expectations. The HID spec does not prohibit a filter from synthesising the Feature report; the only requirement is buffer conformance to the declared field structure, which v1.2 satisfies.

## Q3. NEW issues introduced by v1.2 vs v1.1

The simplifications in v1.2 introduce four high-risk vectors that were not present (or not as severe) in v1.1:

### NEW-1 (BLOCKING): Same-path-for-v1-and-v3 regresses v1's working Feature 0x47

v1.2 Section 7d collapses the v1/v3 PID branch in v1.1 — both PIDs now route Feature 0x47 through the same shadow-buffer short-circuit. **v1's firmware natively backs Feature 0x47** (per applewirelessmouse findings + empirical: tray currently reads v1 battery via `HidD_GetFeature(0x47)` against the native v1 firmware path; this is the working baseline from PRD-184 M2). v1.2 force-intercepts that working path and re-routes it through M12's RID=0x27 shadow buffer. Failure modes:

- v1's RID=0x27 vendor blob layout may differ from v3 (different firmware era, different fields, different battery byte position). Even if v1 emits 0x27 frames, BATTERY_OFFSET=1 may map to non-battery data on v1.
- v1 may emit RID=0x27 less frequently than v3, so cold-start N/A windows widen.
- v1 may not emit RID=0x27 AT ALL in normal operation (RID=0x27 is the descriptor's vendor-blob declaration, but the device firmware ultimately decides what to push — v1 firmware may simply never have used it because it had a working Feature 0x47 channel already).

If v1 doesn't emit 0x27, M12 always returns `STATUS_DEVICE_NOT_READY` for v1 Feature 0x47 — and the tray that previously worked loses battery readout entirely. **VG-1 (v1 regression baseline) catches this**, but only after install. Better to fix in design.

### NEW-2 (BLOCKING): No descriptor mutation = fresh-pair compatibility risk

v1.2 abandons BRB-level descriptor mutation (Sec 3b'). Reasoning: cached SDP descriptor from prior `applewirelessmouse` install is already Descriptor B (unified, declares 0x47), so no mutation needed. Risk: a user who pairs the mouse AFTER M12 install (no `applewirelessmouse` previously, or a fresh BTHPORT cache) gets the device's NATIVE descriptor — which according to `M12-APPLEWIRELESSMOUSE-FINDINGS` Q3 is the multi-TLC Descriptor A (COL01: Mouse, COL02: Vendor TLC with 0x90 Input). HidClass parses Descriptor A; **0x47 is not declared**, HidD_GetFeature(0x47) returns ERROR_INVALID_PARAMETER at the HidClass layer before reaching M12. The intercept never fires. Tray N/A.

This breaks the assumption "BTHPORT cache always serves Descriptor B". The cache contains B because applewirelessmouse mutated it during pairing. M12 v1.2 doesn't do that mutation. Therefore on fresh-pair (post-uninstall-of-applewirelessmouse, or first-time pair on a fresh Windows install with M12 already present), the cache will serve A.

VG-0 catches this — the caps check fails and operator triggers Section 7c-pre cache wipe + unpair/re-pair. **But re-pair just makes HidBth re-fetch the device's native Descriptor A — which is still A, not B.** There is no path from "fresh pair with M12-only" to a Descriptor-B BTHPORT cache without a descriptor-mutation step.

### NEW-3 (NON-BLOCKING): BATTERY_OFFSET=1 may surface garbage data

v1.2 ships with `BATTERY_OFFSET=1` (first byte after RID) as a hypothesis. RID=0x27 empirical capture was BLOCKED — actual offset unknown. If offset 1 maps to (e.g.) a touch X-coordinate, the tray will see wildly fluctuating "battery" values every time the user moves the mouse. VG-4 (empirical offset confirmation at known battery levels) catches this — diff at 100% vs 20% reveals the right offset. Non-blocking because the registry tunable + VG-4 gate are designed for this.

### NEW-4 (NON-BLOCKING): Cold-start N/A indefinite if mouse idle

If the mouse is idle (e.g., user wakes laptop and tray polls before any input), no RID=0x27 frame in shadow yet → STATUS_DEVICE_NOT_READY → tray N/A until user moves mouse. v1.1's active-poll path covered this; v1.2 removed it. Mitigation: tray's adaptive poll interval already retries every minute or so when result is stale; user input on the mouse would then trigger a 0x27 frame and warm the cache. Acceptable but worth noting. FirstBootPolicy=1 (return [0x47, 0x00]) is misleading — better policy is to leave the tray showing N/A until real data arrives.

## Q4. Most likely failure mode of v1.2 in production

**Total battery failure on first VG-1 run** due to the v1 same-path issue (NEW-1) compounded by BATTERY_OFFSET=1 hypothesis (NEW-3). Both v1 and v3 read the same byte from each device's RID=0x27 shadow; if either mouse's offset is wrong, that mouse's tray shows garbage. Most likely scenario: v1 has been working for weeks via native Feature 0x47, M12 install force-routes it through the shadow buffer, v1 either stops emitting 0x27 (because firmware doesn't normally) or emits it with a different layout than v3 — and VG-1 fails. Halts the entire MOP at VG-1.

Less likely (but more catastrophic): fresh-pair scenario (NEW-2) where a user replaces a mouse and re-pairs after M12 is already installed. Both mice show N/A forever because BTHPORT cache has Descriptor A, HidClass rejects 0x47 GET_FEATURE before M12 sees it.

## Q5. Are MOP gates VG-0..VG-7 sufficient?

**Yes — the MOP gate framework is well-designed and catches all four risks before soak completion.**

- **VG-0** catches NEW-2 (fresh-pair Descriptor A) at the caps check before any tray restart. PASS = applewirelessmouse-baseline cache (Descriptor B). FAIL = halt + invalidate cache + re-pair (but per NEW-2 analysis, re-pair alone won't move A → B without descriptor mutation; this is a design fix, not a MOP fix).
- **VG-1** catches NEW-1 (v1 regression) within 30 sec. Fast, decisive.
- **VG-2** catches NEW-4 (v3 cold-start) within 60 sec — operator should physically use the mouse to warm the cache before this gate.
- **VG-4** catches NEW-3 (BATTERY_OFFSET hypothesis) — empirical confirmation at two known battery levels.
- **VG-5** confirms pool tag wiring (MAJ-5).
- **VG-6** confirms EvtIoStop wiring under Driver Verifier (CRIT-3).
- **VG-7** 24-hr soak with explicit BT sleep/wake cycles — catches CRIT-3 regression, long-term cache freshness, BSOD risk.

The gate sequence is correct: caps -> v1 regression -> v3 outcome -> scroll -> empirical -> pool -> verifier -> soak. Each gate is fast (≤60 sec) except VG-7 (24 hr); failure halts before next gate. Fast feedback loops.

---

## Action items (must address before user PRD approval)

### Blocking — must fix in v1.3 before any code is written

1. **Restore PID branch for Feature 0x47 (NEW-1 fix):** v1 (PID 0x030D / 0x0310) must pass `IOCTL_HID_GET_FEATURE` for 0x47 directly downstream to the native firmware path. Only v3 (PID 0x0323) gets the shadow-buffer short-circuit. Update Section 7d + Section 7c pseudocode to add a PID switch. v1 path is identical to applewirelessmouse-baseline (no M12 code in the IRP path at all for v1). v1's working battery readout is preserved; v3's broken Feature 0x47 is fixed by M12.

2. **Restore BRB-level descriptor mutation as fallback (NEW-2 fix):** When VG-0 detects the cached SDP descriptor is the device's native multi-TLC Descriptor A (no Feature 0x47), M12 must rewrite it at the BRB level (per v1.1 design Sec 3b) to inject a unified descriptor that DOES declare Feature 0x47. Two paths:
   - **Minimum:** preserve v1.1's BRB-level rewrite logic as a "fresh-pair" path; M12 only fires when VG-0 would otherwise fail. Operator runs Section 7c-pre cache wipe → device re-pairs → M12 BRB-intercept rewrites SDP HIDDescriptorList → cache populates with applewirelessmouse-equivalent Descriptor B → VG-0 passes.
   - **Maximum:** M12 always rewrites, so M12 doesn't depend on `applewirelessmouse` ghost in the BTHPORT cache for any installation scenario.
   - Recommendation: minimum path. Keeps v1.2's simplification benefits when the cache is already correct, adds defensive rewriting only for fresh-pair edge case.

### Non-blocking — track in Phase 3 testing

3. **VG-4 must run at TWO known battery levels** (e.g., 100% and 20% via charging cycle) — already specified in MOP v1.2 but emphasised here. BATTERY_OFFSET=1 default is a hypothesis; ship behaviour must be "tray shows N/A until VG-4 completes and registry is updated".

4. **FirstBootPolicy default = 0 (NOT_READY) confirmed correct.** The alternative (return [0x47, 0x00] = 0%) is worse — would surface a false low-battery alert in the tray. Stay with NOT_READY.

### Advisory — consider for v1.3 if iteration warranted

5. **Add a soft active-poll for cold-start ONLY:** If v3 RID=0x27 doesn't arrive within N seconds of EvtDeviceAdd (e.g., user wakes laptop with idle mouse), M12 could issue a single downstream `IOCTL_HID_GET_INPUT_REPORT` for 0x90 to wake the firmware. This brings back CRIT-2 risk if not done carefully (must be async, must hold a request reference, must time out short). Recommended only if VG-7 soak surfaces persistent N/A windows >5min.

6. **Consider a `MAX_STALE_MS` registry tunable** with default 10000 (10 sec): if shadow timestamp older than that, return STATUS_DEVICE_NOT_READY rather than serve potentially stale percentage. Forces fresh data within 10 sec or surfaces the staleness to the tray.

---

## Decision

User can choose:

- **(a) Iterate to v1.3** addressing blocking #1 + #2 above. Estimated ~15 min documentation work in this session. Then re-run NLM pass-3.
- **(b) Ship v1.2 as-is** and treat blocking issues as Phase 3 implementation surprises (NOT recommended — both are easy doc fixes; better to land them now than during v1 regression triage).

Iteration to v1.3 is the recommended path. Time budget allows it within this session (~16 min elapsed of 90 min cap).

---

## Citations (notebook source IDs)

- `981c1d0c-7674-4660-aa6d-5036de914115` — M12 Design Spec v1.2 (under review pass 2)
- `cd3573b2-9a21-411d-9142-aa2ea0f85ef3` — M12 MOP v1.2 (under review pass 2)
- `61873fa7-e4a0-46be-880f-52aee91fd8f2` — applewirelessmouse.sys reverse engineering, BRB handler pattern, IOCTL_INTERNAL_BTH_SUBMIT_BRB hits
- `6a9eed6c-b822-4ecb-bd29-b1722703cc63` — Apple filter behavior on Feature 0x47 (descriptor declares cap, device returns err=87, no active trap), 116-byte descriptor at offset 0xa850
- `bbd3dc75-9f6d-44b9-8c16-af3b3117fc5d` — M12 empirical capture inventory + HID 1.11/1.4 spec citation
- `8ff5daf6-7dd6-47bc-ad9e-f83b3620baae` — Session 12 corrected plan; Two Descriptor States for v3 (A multi-TLC battery / B unified scroll, mutually exclusive)
- `d4d270d7-f6e3-4f54-a36f-4f4ca811bb81` — Three-driver architecture comparison
- `db786fac-3997-425b-aff1-d3d783e48840` + `88ca7a3d-49a4-4367-8cd3-8d5985da51c0` — Linux hid-magicmouse.c 60-sec polling pattern (refutes v1.2's "no active poll needed" claim for non-USB-C / passive devices)
- `91be9e8a-bf77-49f1-b827-e3c8b0f2a3ae` — HID 1.11 spec compliance reference

## Metadata

- Date: 2026-04-28
- NLM service: notebooklm.google.com (MCP via `notebook_query`)
- Pass: 2 (v1.2 review)
- Verdict: CHANGES-NEEDED (downgraded from REJECT per adversarial template — no production implementation exactly matches M12 v1.2 architecture combination)
- Two blocking issues NEW in v1.2 (not present in v1.1): collapsed v1/v3 PID branch + abandoned descriptor mutation
- Recommended action: iterate to v1.3 within this session
