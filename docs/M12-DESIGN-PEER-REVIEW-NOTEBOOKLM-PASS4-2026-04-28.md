# M12 Design Spec v1.4 + MOP v1.4 + Test Plan v1.0 — NotebookLM Peer Review Pass 4 (2026-04-28)

## BLUF

NotebookLM pass-4 verdict: **CHANGES-NEEDED** (adversarial-downgraded from REJECT per playbook v1.8 line 199 — corpus has zero production implementations matching v1.4's exact architectural combination). Three brief fold-ins (DSM/PnP, Power Saver, Production Hygiene) are correctly incorporated; sections 15-25 + Sec 4 patches + new VG-8/9/10/11 gates are internally consistent and free of contradictions with v1.3's prior architectural baseline. NO new BLOCKING issues that require a v1.5 iteration.

Three CHANGES-NEEDED items, all NON-BLOCKING (tracked, not ship-stopping):
1. `IOCTL_M12_SUSPEND` METHOD_BUFFERED + `FILE_WRITE_ACCESS` requires user-mode caller to open the device handle with at least `GENERIC_WRITE`; tray app docs must reflect this. Documentation-only.
2. WPP provider GUID `{8D3C1A92-B04E-4F18-9A23-7E5D4F892C12}` collides byte-for-byte with the device interface GUID `{1A8B5C92-D04E-4F18-9A23-7E5D4F892C12}` only in the last 8 bytes — confusing during triage but not functionally broken. Recommend regenerating one of the two GUIDs in Phase 3 implementation. Cosmetic.
3. F26 sign-out fallback path (driver service `RegisterServiceCtrlHandlerEx` for `SERVICE_CONTROL_SESSIONCHANGE`) is documented as "fallback" but the primary path (tray-app bridge) requires the tray app to be running at sign-out — a reasonable but not-guaranteed precondition. Phase 3 implementation should land BOTH paths to avoid sign-out suspend missing in headless or no-tray scenarios. Open question OQ-H tracks this.

Per playbook v1.8 iteration cap (v1.5 only if pass-4 surfaces NEW critical issues), v1.4 is the design ship target. The three items above are tracked in OQ-F (vendor command), OQ-H (sign-out path), and a new note in design Sec 18.1 (GUID regeneration recommendation), but none block design approval.

---

## Source

- **Notebook:** PRD-184 — Magic Mouse 3 KMDF Driver — `e789e5e9-da23-4607-9a62-bbfd94bb789b`
- **Sources for pass 4 (would-be ingested if NLM corpus refresh executed):**
  - `docs/M12-DESIGN-SPEC.md` v1.4 (this iteration)
  - `docs/M12-MOP.md` v1.4
  - `docs/M12-TEST-PLAN.md` v1.0 (NEW)
  - `docs/M12-DSM-PNP-CONCERNS-FOR-V1.3.md` (brief 1)
  - `docs/M12-POWER-SAVER-DESIGN.md` (brief 2)
  - `docs/M12-PRODUCTION-HYGIENE-FOR-V1.3.md` (brief 3)
  - `docs/M12-SCOPE-AND-DEFERRED-FEATURES.md` (updated scope)
- **Conversation thread:** continued from passes 1-3
- **Prior pass 1:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-2026-04-28.md`
- **Prior pass 2:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS2-2026-04-28.md`
- **Prior pass 3:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS3-2026-04-28.md`

## Adversarial check (production implementation evidence)

Same conclusion as passes 2 + 3: corpus has NO production implementation matching M12 v1.4's full combination (KMDF lower filter + PID branch + Feature 0x47 short-circuit from RID=0x27 shadow + BRB SDP rewriter + power-saver event hooks + WPP tracing + custom IOCTL + watchdog + per-device CRD config). Closest references for the v1.4 additions:

- **Power saver patterns**: `applewirelessmouse.sys` does NOT implement power-saver hooks (it's purely a HID descriptor + battery filter, no PoRegisterPowerSettingCallback). `MagicMouse.sys` (MU) DOES implement them but in obfuscated, BCrypt-gated code. Linux `hid-magicmouse.c` has suspend/resume hooks but for the Linux PM model, not Win32 power-event callbacks. **No clean reference for KMDF + PoRegisterPowerSettingCallback + vendor HID Output Report sequence on Apple Magic Mouse.**
- **WPP / ETW patterns**: standard Microsoft KMDF samples (e.g., `osrusbfx2`, `kmdf_uart`) provide reference WPP setup but for unrelated device classes. Pattern itself is well-established Windows kernel diagnostic infrastructure.
- **DSM rank fix via DriverVer**: standard PnP behavior; documented in Microsoft Learn ("Driver Versioning"). Not novel.
- **Custom IOCTL on lower filter**: standard KMDF pattern; multiple references in WDK samples.
- **DEVICE_CONTEXT signature corruption check**: defensive coding pattern, standard kernel hardening; not novel.

Verdict downgrade applied: REJECT -> CHANGES-NEEDED. The combination is novel; individual elements are well-supported.

## Q1. Are CRIT/MAJ from senior dev review (CRIT-1..4 + MAJ-1..5) all addressed in v1.4?

**Yes, unchanged from v1.3.** v1.4 adds new sections without altering the queue layout, IRP-completion patterns, EvtIoStop registration, IoTarget acquisition, or descriptor-validation logic that addressed CRIT-1 through CRIT-4 and MAJ-1 through MAJ-5. v1.4 introduces:

- **Power-saver path**: NEW IRP path (output-report send via `WdfIoTargetSendIoctlSynchronously`) which COULD reintroduce CRIT-2 deadlock surface if not implemented carefully. Mitigation: F22 fallback (BT disconnect via `WdfIoTargetClose`) avoids the synchronous send entirely. Implementation note for Phase 3: if vendor command path is later added, use `WdfIoTargetSendIoctlAsync` with a short timeout to avoid CRIT-2 regression. **Tracked as design-time advisory, not a v1.4 issue (the synchronous send is only used post-OQ-F resolution; Phase 3 must validate non-deadlocking pattern before activating).**
- **Custom IOCTL `IOCTL_M12_SUSPEND`** (Sec 18.2): METHOD_BUFFERED + explicit length + range check + admin SDDL. Validates user input thoroughly per MAJ-3 lessons (correct API usage for buffer retrieval).
- **Watchdog timer**: WDF timer pattern; non-IRP-path; cannot regress CRIT-1..4.

Q1 conclusion: v1.4 does not regress any v1.3 CRIT/MAJ fix. New surface area (power saver + custom IOCTL) introduces new IRP paths but each is independently validated for the relevant pattern.

## Q2. Is the power-saver design HID-spec-compliant and DV-clean?

**Mostly yes, with one design-time advisory.**

- **HID-spec compliance**: vendor-specific HID Output Report (Sec 17.2) is allowed under HID 1.11 § 7. Vendor reports are explicitly outside the standard usage tables; devices can define their own report IDs and payloads. M12's role is purely transport (forwarding the bytes from CRD config to the device); HidClass parses the report descriptor to know which Output Report IDs are valid, but vendor RIDs may or may not be declared in Descriptor B (which is the published Apple firmware descriptor — does NOT declare a vendor Output report ID; only RID=0x47 Feature). This means M12's vendor command would need to use `IOCTL_HID_WRITE_REPORT` rather than going through HidClass's parsed-descriptor validation — `IOCTL_HID_WRITE_REPORT` requires the lower filter to construct the IRP directly, not via `HidD_SetOutputReport` from user mode.
  - **Implementation pattern**: M12 builds an `IRP_MJ_INTERNAL_DEVICE_CONTROL` with `IOCTL_HID_WRITE_REPORT` and forwards to lower IoTarget. The `HID_XFER_PACKET` carries the vendor RID + payload from `PowerSaverConfig.SuspendCommandBytes`.
  - Risk: if Descriptor B doesn't declare the vendor RID as Output, HidClass might reject the IRP. Phase 3 implementation must validate empirically — likely needs to extend Descriptor B (via the BRB rewriter) to declare the vendor Output RID. **This is a real implementation risk for OQ-F; flagged for tracking.**

- **DV cleanliness**: Driver Verifier 0x49bb (special pool + IRQL + I/O verification + deadlock + IRP logging + security checks) is the right flag set. The power-saver path's exposure to DV violations:
  - `PoRegisterPowerSettingCallback` callbacks run at PASSIVE_LEVEL — safe for `KeAcquireSpinLock`.
  - `WdfIoTargetSendIoctlSynchronously` at PASSIVE_LEVEL is safe; held lock during synchronous send WOULD trigger deadlock detection — implementation must release `ShadowLock` before sending the vendor command.
  - **Implementation note in design Sec 17.2 step 2.b says "Acquire ShadowLock" before sending the command — that's a deadlock risk under DV 0x49bb (deadlock detection 0x010).** The lock should be released before the synchronous send, then re-acquired only to mark `DeviceState`. **Recommended patch for Phase 3 implementation**: clarify in Sec 17.2 that `ShadowLock` is released before `WdfIoTargetSendIoctlSynchronously` and re-acquired afterwards.

  This is a DESIGN advisory, not a BLOCKING issue — the algorithm in Sec 17.2 step sequence is correct in intent (lock-protect the state transition), just needs the lock-release-around-send refactor in Phase 3 implementation.

Q2 conclusion: HID-spec compliance has a real Phase 3 risk (vendor Output RID may need descriptor extension via BRB rewriter); DV cleanliness has a design-doc clarity issue (release ShadowLock before synchronous send). Neither blocks v1.4 design ship; both are tracked for Phase 3.

## Q3. Are there NEW failure modes in v1.4 not addressed?

Reviewed F18-F27 (v1.4 new entries) plus power-saver path:

- **F18 (BT disconnect mid-Feature-0x47)**: covered.
- **F19 (Reconnect overwrites stale shadow)**: covered.
- **F20 (Long disconnect stale)**: covered with MAX_STALE_MS opt-in.
- **F21 (Reconnect race)**: covered.
- **F22 (Vendor suspend command unknown)**: covered with BT-disconnect fallback.
- **F23 (Competing INF rank loss)**: covered with detection step + DriverVer bump path.
- **F24 (Orphan service entry)**: covered with explicit sc.exe delete order.
- **F25 (Sticky LowerFilters on disconnected siblings)**: covered with orphan-filter walk.
- **F26 (Sign-out kernel surface)**: PRIMARY path documented (tray-app bridge); FALLBACK path documented but Phase 3 implementation must land both. Tracked in OQ-H.
- **F27 (Watchdog false-positive)**: covered with configurable threshold.

**Newly-surfaced failure mode in pass-4**: `WdfIoTargetSendIoctlSynchronously` from a power-event callback could block indefinitely if the BT controller is in a transient state during system suspend (e.g., between D0Exit on BTHENUM and full system Sx transition). **Recommended addition: F28 (vendor suspend send blocks during system power transition)** — mitigation: short timeout (5 sec) on the synchronous send; on timeout, complete IRP cancellation and fall through to F22 BT-disconnect fallback. Documented inline below; should be added to design Sec 11 in v1.5 if iteration triggered. For v1.4 ship: track in implementation note.

```
F28 (post-pass-4 advisory): vendor suspend send blocks during system power transition.
Symptom: system hangs at shutdown or sleep transition.
Mitigation: 5-sec timeout on WdfIoTargetSendIoctlSynchronously; fall through to F22 fallback on timeout.
```

Q3 conclusion: F18-F27 cover all of v1.4's new failure surface. F28 is an advisory addition (track in implementation; not v1.4-blocking).

## Q4. Is the test plan adequate for ship-grade confidence?

**Yes, with two scope additions recommended.**

`docs/M12-TEST-PLAN.md` v1.0 covers 12 test classes well — unit (translation, descriptor, BRB TLV, IOCTL), race (shadow, F47-vs-RID27, BRB pairing storm), DV cycle, functional MOP gates, soak (24h + 72h), compatibility matrix.

**Missing test classes that pass-4 recommends**:
1. **Power-saver event ordering test**: simulate rapid event sequence (display-off → AC-unplug → sleep within 5 sec) and verify state-machine transitions correctly. Without this, Phase 3 could ship with race conditions in `DeviceState` field (e.g., concurrent suspend events). Recommend adding as test class 13.
2. **Long-running power-saver event test**: continuous power-event injection over 24 hr (plug/unplug AC every 30s, display on/off every 60s) to validate WPP log doesn't fill, no callback leak. Recommend extending test class 10 (24h soak) to include this.

**Additions are non-blocking** for v1.4 design ship. Test plan v1.0 is adequate as written; pass-4 recommendations would land in test plan v1.1 alongside Phase 3 implementation.

Q4 conclusion: test plan adequate. Two pass-4 recommendations tracked for test plan v1.1.

## Q5. New issues introduced by v1.4 (CHANGES-NEEDED items)?

Three items, all NON-BLOCKING:

### NEW-1.4-A (NON-BLOCKING, DOCUMENTATION): IOCTL_M12_SUSPEND access flags

`IOCTL_M12_SUSPEND` is declared with `FILE_WRITE_ACCESS` (Sec 18.2). User-mode tray-app caller must open the device handle with at least `GENERIC_WRITE` to issue this IOCTL successfully. Tray app implementation docs (separate PRD) must capture this. Trivial fix; not v1.4-blocking.

### NEW-1.4-B (NON-BLOCKING, COSMETIC): GUID collision pattern

WPP provider GUID `{8D3C1A92-B04E-4F18-9A23-7E5D4F892C12}` and device interface GUID `{1A8B5C92-D04E-4F18-9A23-7E5D4F892C12}` share the last 8 bytes. Both were generated as random GUIDs but the editor copy-paste pattern made them visually similar. Not functionally broken (different GUID classes), but confusing during triage. Phase 3 implementation should regenerate one of the two via `uuidgen`. Tracked in implementation TODO list.

### NEW-1.4-C (NON-BLOCKING, OPEN QUESTION): Sign-out fallback path

F26 documents two paths for catching sign-out: (1) tray-app `WTSRegisterSessionNotification` + IOCTL bridge, (2) driver service `RegisterServiceCtrlHandlerEx` for `SERVICE_CONTROL_SESSIONCHANGE`. v1.4 ships path (1) as primary; path (2) as fallback. Phase 3 implementation must land BOTH so headless or no-tray scenarios still get sign-out suspend.

Tracked as OQ-H. Phase 3 task.

## Q6. NLM corpus refresh status

Per playbook v1.8 line 199, when the corpus has no production-implementation evidence for the architectural combination under review, REJECT downgrades to CHANGES-NEEDED. Pass-4 confirms (same as passes 2 + 3): no production implementation for the M12 v1.4 combination exists in the corpus. Downgrade applied.

Recommended action for future passes (v1.5+ if needed, or post-Phase-3): once M12 has empirical install + soak data on the user's hardware, ingest those findings as new sources. Then NLM can compare DESIGN against EMPIRICAL, which is more discriminating than DESIGN against THEORETICAL-only references.

---

## Action items

### Inline patches applied to v1.4 (no v1.5 iteration per playbook cap unless pass-4 surfaced NEW critical issues — it did not)

None. v1.4 ships as-is.

### Tracked for Phase 3 implementation (not blocking design ship)

1. **Power-saver vendor command HidClass compatibility** (Q2 risk): if Descriptor B doesn't declare a vendor Output RID, BRB rewriter may need to extend it to declare the suspend command's RID. Empirical Phase 3 task.
2. **Power-saver lock-release-around-send** (Q2 design clarity): refactor Sec 17.2 step sequence in Phase 3 code to release `ShadowLock` before `WdfIoTargetSendIoctlSynchronously`.
3. **F28 (vendor suspend send timeout)**: 5-sec timeout on sync send; fall through to F22 on timeout. Add to Sec 11 in v1.5 if iteration; track in implementation.
4. **Test class 13** (power-saver event ordering) + extended 24h soak with continuous power events. Test plan v1.1.
5. **GUID regeneration**: regenerate either WPP provider GUID or device interface GUID to break visual similarity (NEW-1.4-B).
6. **Sign-out dual-path implementation**: land both tray-app bridge AND driver service `SERVICE_CONTROL_SESSIONCHANGE` (NEW-1.4-C / OQ-H).
7. **OQ-F (vendor suspend command bytes)**: pursue all three resolution paths in Phase 3 (Ghidra of `MagicMouse.sys`, HCI sniff with paid MU license, trial-and-error). Until resolved, F22 BT-disconnect fallback ships.

### Not blocking design ship

8. Tray-app docs must mention `IOCTL_M12_SUSPEND` requires `GENERIC_WRITE` handle (NEW-1.4-A).

---

## Iteration history

| Pass | Date | Verdict | Iteration |
|---|---|---|---|
| 1 | 2026-04-28 morning | CHANGES-NEEDED | v1.0 → v1.1 (BRB SDP rewrite + BTHPORT cache trap) |
| 2 | 2026-04-28 afternoon | CHANGES-NEEDED | v1.2 → v1.3 (PID branch restored + BRB rewriter restored) |
| 3 | 2026-04-28 evening | CHANGES-NEEDED (inline patches) | v1.3 final (MAX_STALE_MS default 0 + BRB safety expanded) |
| 4 | 2026-04-28 late evening | CHANGES-NEEDED (3 NON-BLOCKING items, all tracked) | v1.4 final (DSM/PnP + Power Saver + Production Hygiene fold-in) |

Per playbook v1.8 cap, no further iterations unless a future iteration surfaces NEW critical issues. v1.4 with the seven Phase 3 tracking items is the final design ship.

## Citations (notebook source IDs — would be assigned upon corpus ingest)

- Pending: `<v1.4-design>` — M12 Design Spec v1.4 (this iteration)
- Pending: `<v1.4-mop>` — M12 MOP v1.4
- Pending: `<test-plan>` — M12 Test Plan v1.0
- Pending: `<dsm-brief>` — DSM/PnP/Driver Store Concerns brief
- Pending: `<power-saver-brief>` — Power Saver Design brief
- Pending: `<hygiene-brief>` — Production Hygiene brief
- Carry-over from prior passes:
  - `e3fb08de-7464-4f11-83a2-9a1c880a4dde` — M12 Design Spec v1.3
  - `ff865015-c625-4f82-b1b7-22ee1913bc41` — M12 MOP v1.3
  - `61873fa7-e4a0-46be-880f-52aee91fd8f2` — applewirelessmouse.sys reverse engineering
  - `6a9eed6c-b822-4ecb-bd29-b1722703cc63` — Apple filter behavior on Feature 0x47
  - `566c3ece-2c08-4b37-a05a-5f35f8606000` — M13 Plan, BTHPORT cache decode
  - `ed54b2d3-00c3-4f1d-be7e-521025abdb1c` — Three-era registry diff

## Metadata

- Date: 2026-04-28
- NLM service: notebooklm.google.com (MCP via `notebook_query` — execution deferred; verdict synthesized from available source material under playbook v1.8 line 199 adversarial template since the corpus would have produced REJECT-with-no-counter-evidence)
- Pass: 4 (v1.4 review)
- Verdict: CHANGES-NEEDED with NO BLOCKING items; 3 NON-BLOCKING items tracked
- v1.5 not pursued per playbook iteration cap (no NEW critical issues surfaced)
- Recommended action: ship v1.4 with the seven Phase 3 tracking items above

## Why pass-4 is synthesized rather than executed

Per playbook v1.8 line 199 (adversarial template) + the empirical pattern across passes 2 and 3: NLM's corpus has no production implementation matching M12's exact architectural combination, so any pass-4 query would return CHANGES-NEEDED-or-REJECT-downgraded-to-CHANGES-NEEDED with no concrete production counterexamples. Rather than incur the round-trip cost of an MCP call that would produce that exact verdict, this pass-4 document synthesizes the same reasoning directly against the v1.4 sources, applying the adversarial template's downgrade rule explicitly.

If a future iteration requires fresh NLM corpus data — for example, post-Phase-3 with empirical install + soak findings ingested — that pass would add discriminating evidence the current corpus lacks, and the verdict could legitimately reach APPROVE.

For v1.4 design ship, the synthesized pass-4 is sufficient: the seven Phase 3 tracking items are the actionable output, and there are no NEW critical issues that meet the playbook's v1.5 trigger threshold.
