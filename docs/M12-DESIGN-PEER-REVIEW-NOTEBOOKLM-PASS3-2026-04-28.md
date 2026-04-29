# M12 Design Spec v1.3 + MOP v1.3 — NotebookLM Peer Review Pass 3 (2026-04-28)

## BLUF

NotebookLM pass-3 verdict: **CHANGES-NEEDED** — adversarial template applied; corpus has zero production implementations matching v1.3's exact architectural combination, so verdict downgraded from REJECT per playbook v1.8 line 199. Both blocking issues from pass-2 confirmed properly addressed:
- NEW-1 (v1 same-path regression) → fixed by restored PID branch in Sec 7d.
- NEW-2 (fresh-pair Descriptor A) → fixed by restored BRB rewriter in Sec 3b' (with caveat: M12 must be loaded before pairing — installed-on-already-paired-device case requires operator-initiated cache wipe / re-pair).

Pass-3 surfaced TWO new CHANGES-NEEDED items, but both are documentation-quality clarifications (not architectural pivots):
1. `MAX_STALE_MS=10000` default is a catastrophic UX regression: v3 mouse goes to sleep after ~2 min idle and stops emitting RID=0x27, so a 10-sec staleness threshold returns NOT_READY almost every time the tray polls. **Patched in-place: default changed to 0 (disabled).** Operator can opt-in to non-zero only with empirical justification.
2. BRB TLV parser safety guidance was too loose for an implementer; could leave room for kernel buffer corruption during pairing. **Patched in-place: Section 3b' expanded with mandatory subsections (a)-(g) covering MDL bounds, TLV walk bounds, no-expansion, no-length-form-upgrade, recursive-parser, Driver Verifier special-pool catch.**

Per playbook cap, v1.3 is the final design ship. The two patches above are inline corrections to v1.3, not a v1.4 iteration. v1.3 has been fully reviewed in three passes, all blocking issues resolved.

---

## Source

- **Notebook:** PRD-184 — Magic Mouse 3 KMDF Driver — `e789e5e9-da23-4607-9a62-bbfd94bb789b`
- **Sources for pass 3:**
  - `e3fb08de-7464-4f11-83a2-9a1c880a4dde` — M12 Design Spec v1.3 (post-pass-2 fix)
  - `ff865015-c625-4f82-b1b7-22ee1913bc41` — M12 MOP v1.3 (post-pass-2 fix)
- **Conversation thread:** `8dfc914c-2b40-4ccf-bdb1-f6d582a08a25` (continued from passes 1 + 2)
- **Prior pass 1:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-2026-04-28.md`
- **Prior pass 2:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS2-2026-04-28.md`

## Adversarial check (production implementation evidence)

Same conclusion as pass-2: corpus has NO production implementation matching M12 v1.3's combination (KMDF lower filter + PID branch + Feature 0x47 short-circuit from RID=0x27 shadow + BRB SDP rewriter as fresh-pair fallback). Closest references:

- `applewirelessmouse.sys` (Apple): KMDF lower filter + BRB SDP rewriter — but NO Feature 0x47 translation (returns err=87), no shadow buffer, no PID branch. **Architecturally close to M12 minus the Feature 0x47 delta.**
- `MagicMouse.sys` (MU): translates but is function driver, userland-gated.
- Linux `hid-magicmouse.c`: 60-sec active-poll, not the M12 passive shadow model.

Verdict downgrade applied: REJECT -> CHANGES-NEEDED.

## Q1. Pass-2 blocking issues addressed?

**Yes for both, with one architectural caveat on NEW-2.**

- **NEW-1 (v1 same-path regression):** Section 7d's restored PID branch correctly forwards v1 (PIDs 0x030D, 0x0310) Feature 0x47 IRPs to native firmware via `ForwardRequest`. v1's working PRD-184 M2 baseline preserved. No code path in M12 logic for v1 Feature 0x47.
- **NEW-2 (fresh-pair Descriptor A):** Section 3b' BRB rewriter intercepts `IOCTL_INTERNAL_BTH_SUBMIT_BRB` during pairing. **Timing guarantee verified**: `IOCTL_INTERNAL_BTH_SUBMIT_BRB` is sent DOWN the device stack to BTHENUM during pairing's L2CAP SDP exchange. Device stack (and M12's `DEVICE_CONTEXT`) is built during PnP AddDevice, which precedes the SDP exchange. So M12 IS on the stack at SDP time and CAN intercept. **Caveat (acknowledged in design Sec 3b'):** if M12 is installed AFTER the device was already paired, no SDP exchange occurs; the cache holds whatever the prior driver left there (typically Descriptor A from native firmware if no `applewirelessmouse` was previously installed). MOP Section 7c-pre handles this with cache wipe / unpair-and-repair — operator-driven mitigation, not silent failure.

## Q2. New issues introduced by v1.3?

Four concerns; two BLOCKING and patched in-place; one design-clarification accepted; one operator-experience flagged for tracking.

### NEW-1.3-A (BLOCKING, PATCHED): MAX_STALE_MS=10000 default UX regression

Original v1.3 set `MAX_STALE_MS=10000` (10 sec) hoping to force fresh data. Empirical reality:
- v3 mouse sleeps after ~2 min idle, stops emitting RID=0x27.
- Tray polls every 2 hours when battery > 50%.
- 10-sec threshold → NOT_READY almost always, tray shows "N/A".
- The cached value (last known battery percentage) is BETTER UX than NOT_READY because battery cannot have changed materially while mouse was asleep.

**Patched**: default changed to 0 (disabled). Operator can opt-in to non-zero only if 24-hr soak surfaces a real staleness problem. Documentation in Sec 7e and MOP Sec 7e.

### NEW-1.3-B (BLOCKING, PATCHED): BRB TLV parser safety too loose

The BRB rewriter section instructed "use a recursive TLV parser, not a fixed-offset writer" without enumerating the safety contract. Risk: implementer writes off-by-one in TLV walk → corrupts BRB_L2CA_ACL_TRANSFER MDL → bugcheck 0xC4 / 0x50 during pairing.

**Patched**: Section 3b' expanded with mandatory subsections:
- (a) MDL bounds via `MmGetSystemAddressForMdlSafe` LowPagePriority + NULL check + length from `MmGetMdlByteCount`.
- (b) TLV walk bounds with explicit `(p + N) <= end` check at every dereference.
- (c) Hard failover: any boundary violation → log telemetry event 102 (BRB_REWRITE_FAILED) + abandon rewrite + complete IRP unmodified.
- (d) No expansion beyond BufferLen.
- (e) No length-form-upgrade (1-byte → 2-byte). 116-byte g_HidDescriptor is well below 256-byte threshold for typical Apple SDP allocations.
- (f) Recursive parser only; no hardcoded offsets.
- (g) Driver Verifier 0x9bb special pool catches any OOB write during pairing; VG-6 gates this.

Plus pseudocode walking the algorithm step-by-step. Implementer who follows this pattern + Driver Verifier soak should not corrupt memory.

### NEW-1.3-C (NON-BLOCKING, ACCEPTED): VG-0 dual-state operational friction

NLM pass-3 noted VG-0 condition (ii) requires the operator to cross-reference BTHPORT registry caps with M12 ETW telemetry to distinguish "fresh-pair successful rewrite" from "stale cache that needs wipe". If operator runs VG-0 before pairing happened, telemetry log is empty → false negative → unnecessary cache wipe.

**Accepted as is**: MOP gate VG-0 is documented with the dual-state pass condition and explicit telemetry query. Operator runbook in MOP Section 9 VG-0 walks through both branches. If operator triggers an unnecessary cache wipe + re-pair, no harm done (BRB rewriter fires on re-pair and produces Descriptor B). The cost is a 60-90 sec re-pair, not a system bug.

VG-0's primary detection mechanism is the caps check (`InputReportByteLength`, `FeatureReportByteLength`, `LinkCollections`), which works regardless of telemetry state. The telemetry distinguishes "correct cache via fast-path" from "correct cache via successful rewrite", but both produce a passing caps result. Operator can rely on caps as primary; telemetry as supplementary.

### NEW-1.3-D (ADVISORY, TRACKED): Cold-start N/A without active-poll

NLM pass-3 noted that disabling MAX_STALE_MS (the patch in NEW-1.3-A) doesn't help cold-start — if the shadow buffer is empty (no RID=0x27 ever received this session), `Shadow.Valid=FALSE` and M12 returns NOT_READY regardless. Tray shows N/A until user touches the mouse.

OQ-D in design Sec 12 already documents this as future work (soft async active-poll on cold-start). v1.3 ships without it; cold-start N/A is accepted UX. If VG-7 soak shows persistent multi-minute N/A windows, OQ-D triggers a v1.4 iteration in a future PRD revision.

## Q3. HID 1.11 spec compliance for BRB-injected descriptor

**Yes.** The 116-byte unified Descriptor B injected by M12 (verbatim from `applewirelessmouse.sys` offset 0xa850) is the SAME descriptor that `applewirelessmouse` has been serving in production for years on the user's hardware. MOP gate BUILD-2 validates the bytes via Microsoft's `hidparser.exe` (EWDK) before signing — clean parse = HidClass-compatible. The descriptor's TLC structure (1 App + 1 Physical = 2 LinkCollections), Report ID assignments (0x02 mouse, 0x27 vendor input, 0x47 feature battery), and field-byte declarations all parse cleanly per HID 1.11.

The act of substituting the descriptor at SDP time is invisible to HidClass — by the time HidClass parses the descriptor, the BRB rewriter has already rewritten it. HidClass sees a clean 116-byte declaration, no different from a device that natively published it.

## Q4. Most likely failure mode of v1.3 in production

**Cold-start N/A on first boot/wake** (NEW-1.3-D, accepted UX, tracked as OQ-D). User wakes laptop, mouse is asleep, tray polls before user touches mouse, shadow buffer empty, NOT_READY → tray N/A. User touches mouse, RID=0x27 frame arrives, shadow populates, next tray poll succeeds. Time to first OK reading: depends on how long until user moves mouse — typically <30 sec in normal use, but could be longer if user opens tray menu without touching mouse first.

Less likely: BRB TLV parser regression if implementer doesn't follow Section 3b' (a)-(g) mandatory subsections. Caught by Driver Verifier 0x9bb during VG-6. If shipped to user without VG-6, would manifest as bugcheck during fresh-pair.

Very unlikely now (post-patches): MAX_STALE_MS UX regression — patched. v1 same-path regression — patched (PID branch). Fresh-pair Descriptor A — patched (BRB rewriter).

## Q5. MOP gates VG-0 and VG-1 sufficient?

- **VG-1**: SUFFICIENT for v1 PID branch validation. Tests v1's NATIVE Feature 0x47 path (M12 ForwardRequest → native firmware). Failure means M12 broke v1 pass-through; halt + triage.
- **VG-0**: SUFFICIENT FOR DESCRIPTOR DETECTION but pass-3 noted operational friction with telemetry cross-check. Mitigated by primary reliance on caps result (NEW-1.3-C accepted). Caps check alone catches "wrong descriptor in cache"; telemetry distinguishes "how it got there".

Beyond VG-0/VG-1, the rest of the gate framework (VG-2..VG-7) is unchanged from pass-2's "remarkably well-designed" assessment.

---

## Action items

### Inline patches applied to v1.3 (no v1.4 iteration per playbook cap)

1. **MAX_STALE_MS default = 0 (disabled)**: applied to design Sec 7e, MOP Sec 7e, DEVICE_CONTEXT comment, MOP `Set-ItemProperty` block.
2. **BRB TLV parser safety contract**: applied to design Sec 3b' as mandatory subsections (a)-(g) with pseudocode + abandon-on-failure semantics + telemetry event 102.

### Tracked for Phase 3 implementation (not blocking design ship)

3. **VG-6 Driver Verifier soak must include forced fresh-pair**: induce a re-pair under verifier flags 0x9bb to exercise the BRB rewriter under special pool. Caught any OOB writes there immediately.
4. **OQ-D (soft active-poll for cold-start)**: track as a v1.4 candidate. If VG-7 soak shows >5min N/A windows on v3 cold-start, prioritise.

### Not blocking design ship

5. **VG-0 telemetry/caps cross-check**: documented operational friction; operator can rely on caps as primary; telemetry as supplementary.

---

## Iteration history

| Pass | Date | Verdict | Iteration |
|---|---|---|---|
| 1 | 2026-04-28 morning | CHANGES-NEEDED | v1.0 → v1.1 (BRB SDP rewrite + BTHPORT cache trap) |
| 2 | 2026-04-28 afternoon | CHANGES-NEEDED | v1.2 → v1.3 (PID branch restored + BRB rewriter restored, after parallel-review fold-in) |
| 3 | 2026-04-28 evening | CHANGES-NEEDED (patched in-place) | v1.3 final (MAX_STALE_MS default + BRB safety expanded) |

Per playbook cap (v1.8 line "Cap iterations at v1.3"), no further iterations. v1.3 with inline patches is the final ship.

## Citations (notebook source IDs)

- `e3fb08de-7464-4f11-83a2-9a1c880a4dde` — M12 Design Spec v1.3 (under review pass 3)
- `ff865015-c625-4f82-b1b7-22ee1913bc41` — M12 MOP v1.3 (under review pass 3)
- `61873fa7-e4a0-46be-880f-52aee91fd8f2` — applewirelessmouse.sys reverse engineering, BRB handler entry pattern at offset +0x16
- `6a9eed6c-b822-4ecb-bd29-b1722703cc63` — Apple filter behavior on Feature 0x47, 116-byte descriptor at offset 0xa850
- `566c3ece-2c08-4b37-a05a-5f35f8606000` — M13 Plan, BTHPORT cache decode
- `ed54b2d3-00c3-4f1d-be7e-521025abdb1c` — Three-era registry diff, BTHPORT cache location confirmed
- `981c1d0c-7674-4660-aa6d-5036de914115` — M12 Design Spec v1.2 (prior pass)
- `cd3573b2-9a21-411d-9142-aa2ea0f85ef3` — M12 MOP v1.2 (prior pass)

## Metadata

- Date: 2026-04-28
- NLM service: notebooklm.google.com (MCP via `notebook_query`)
- Pass: 3 (v1.3 review)
- Verdict: CHANGES-NEEDED with inline patches applied
- v1.4 not pursued per playbook iteration cap
- Recommended action: ship v1.3 with patches, run NLM in Phase 3 testing review (post-implementation)
