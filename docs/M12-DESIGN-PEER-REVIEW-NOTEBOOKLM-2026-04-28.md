# M12 Design Spec + MOP — NotebookLM Peer Review (2026-04-28)

## BLUF

NotebookLM verdict: **CHANGES-NEEDED**. Design and MOP are mostly sound but contain two material architectural errors that will cause first-attempt failure on already-paired devices: (1) the descriptor delivery path in Design Spec Section 3b uses `IOCTL_HID_GET_REPORT_DESCRIPTOR` which is absorbed by HidBth before reaching a lower filter; the correct hook is `IOCTL_INTERNAL_BTH_SUBMIT_BRB` with SDP TLV pattern-matching in the completion routine. (2) MOP Section 7c's Disable+Enable rebind does NOT trigger a fresh Bluetooth SDP exchange, so HidBth re-uses the cached descriptor from BTHPORT registry — M12's mutation is bypassed. Mitigation: add BTHPORT cache wipe step OR an unpair/repair step in MOP. Success criteria (VG-1..VG-4) approved as-written.

Adversarial gate result: **zero production implementations** in the corpus demonstrate the exact architectural combination M12 proposes (pure-kernel KMDF lower filter + descriptor mutation + in-IRP scroll/battery translation, no userland). Apple's `applewirelessmouse.sys` does descriptor mutation but not in-IRP translation. Magic Utilities `MagicMouse.sys` does descriptor mutation + in-IRP translation but is userland-gated and acts as the function driver replacement on v3, not a lower filter. Linux `hid-magicmouse.c` does pure-kernel in-IRP translation but is not Windows KMDF. The verdict is downgraded from REJECT to CHANGES-NEEDED on this basis.

---

## Source

- **Notebook:** PRD-184 — Magic Mouse 3 KMDF Driver — `e789e5e9-da23-4607-9a62-bbfd94bb789b`
- **Sources added this review:**
  - `1bf7c9dd-0f74-4ceb-806b-fce8d253e1db` — "M12 Design Spec 2026-04-28" (37 KB)
  - `c4817b45-c01b-4ddd-9094-1a1d97f218ab` — "M12 MOP 2026-04-28" (19 KB)
- **Conversation thread:** `8dfc914c-2b40-4ccf-bdb1-f6d582a08a25`

## Adversarial check (production implementation evidence)

NLM enumerated the production-reference set in the corpus and concluded NONE match the M12 architecture exactly:

| Reference | Descriptor mutation? | In-IRP translation? | Pure kernel? | Filter or function? |
|-----------|---------------------|---------------------|--------------|---------------------|
| Apple `applewirelessmouse.sys` | yes (Mode B) | NO (passes Feature 0x47 through, returns err=87) | yes | lower filter |
| Magic Utilities `MagicMouse.sys` | yes (Mode A) | yes | NO (userland-gated via `MagicUtilitiesService.exe`) | function driver replacement on v3 |
| Linux `hid-magicmouse.c` | yes (`magicmouse_report_fixup`) | yes | yes | not Windows KMDF |
| M12 (proposed) | yes (Mode A) | yes | yes | lower filter |

Verdict downgrade applied: REJECT -> CHANGES-NEEDED, conditional on resolving the two architectural errors.

## Q1. Architecture sound?

**No — descriptor delivery path is wrong.**

Design Spec Section 3b and Section 5 specify M12 intercepts `IOCTL_HID_GET_REPORT_DESCRIPTOR` and returns the static Mode A descriptor. NLM's prior corrected analysis of `applewirelessmouse.sys` (already in the notebook corpus) established that this IOCTL is absorbed by HidBth before reaching lower filters on the BTHENUM stack. The correct hook is `IOCTL_INTERNAL_BTH_SUBMIT_BRB`: M12 must intercept BRB completion, scan ACL transfer buffer for the SDP HIDDescriptorList byte pattern (`35 LL` SEQUENCE -> `09 02 06` Attribute ID 0x0206 -> `35 LL` SEQUENCE -> `35 LL` per-entry SEQUENCE -> `08 22` UNSIGNED int 0x22 -> `25 NN` length-prefixed descriptor bytes), and replace the descriptor in place with `g_HidDescriptor[]`, adjusting SDP TLV length bytes accordingly.

Apple's `applewirelessmouse.sys` reverse engineering (notebook source `61873fa7`) confirmed BRB Type-field reads at offset +0x16 in two function entry points — M12 must do the same.

## Q2. Failure modes complete?

**Two missing failure modes.**

- **F13 — BTHPORT SDP cache trap.** Already-paired devices: HidBth does NOT re-fetch the SDP descriptor from the device on AddDevice; it reads the cached copy from `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<mac>\CachedServices\00010000` (REG_BINARY). M12's BRB-level descriptor injection only fires during a fresh SDP exchange (i.e., a fresh pair). On install over an already-paired device, the cache short-circuits the BRB path and M12's mutation is silently bypassed. Two mitigations: (a) MOP step that wipes the BTHPORT cache value before forcing PnP rebind; (b) MOP step that asks operator to unpair + re-pair both mice from BT settings.
- **F14 — Sequential queue blocking on stalled GET_REPORT 0x90.** Design Spec Section 8 puts `IOCTL_HID_GET_FEATURE` on a sequential queue. If `HandleGetFeature47_ActivePoll` issues a downstream `IOCTL_HID_GET_INPUT_REPORT` for ReportID 0x90 and the v3 firmware drops the packet, the 500ms timeout serializes all subsequent IOCTLs on that queue (including system power/capability queries from PnP). Mitigation: move active-poll to a separate parallel queue dedicated to long-running synchronous downstream IRPs, OR shorten the timeout to 200ms and back-off cache TTL on consecutive timeouts.

## Q3. MOP runnable?

**No — Section 7c step "Force re-bind" is insufficient on already-paired devices.**

`pnputil /disable-device` + `/enable-device` rebuilds the driver stack but does NOT trigger a fresh SDP exchange. HidBth reads from the BTHPORT cache and serves the original (Apple Mode B) descriptor regardless of which lower filter is now bound. The MOP must include either:

- An explicit unpair + re-pair step before validation (visible to user; one-time cost per mouse), OR
- A scripted BTHPORT cache wipe — `Remove-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<mac>\CachedServices' -Name '00010000'` followed by Disable+Enable. (Empirical investigation of cache-wipe-then-rebind is needed before this is committed; falls back to unpair/re-pair if it fails.)

Also recommended: add a pre-validation diagnostic step that reads HIDP_CAPS on the bound device and confirms `Input=8 / Feature=2 / 5 link collections` (Mode A) BEFORE attempting VG-1. If the caps still match Mode B (47-byte input), the mutation isn't applied — halt before tray restart.

## Q4. Success criteria right?

**Yes.** VG-1 v1 regression baseline + VG-2 v3 target outcome + VG-3 scroll on both + VG-4 24-hour soak are aligned with PRD-184's goals and adequately distinguish v1 pass-through correctness from v3 translation correctness (addressing the v3-specific test gap from the prior NLM peer review). Quantitative scroll metric (>= 30 WM_MOUSEWHEEL events per 3-second 2-finger gesture) is the right operational threshold.

## Q5. Most likely first-attempt failure?

**Mode A descriptor never reaches HidClass on already-paired devices, leading to "translation produces 8-byte upstream packets but HidClass parses with Mode B 47-byte expectation" -> HID parsing errors, dropped events, complete VG-3 failure.**

Operator should watch in the first 30 minutes after install:
1. HIDP_GetCaps reading on v1 BTHENUM HID PDO via `Get-PnpDevice` + DEVPKEY queries -> confirm Input=8, Feature=2, LinkColl=5 (Mode A) before tray restart. If shows Input=47 / FeatLen=2 / LinkColl=2, the mutation isn't applied — halt.
2. M12 service state RUNNING via `sc.exe query MagicMouseDriver`.
3. Tray debug.log: presence of `OPEN_FAILED err=N` or `FEATURE_BLOCKED` indicates first-pass mutation didn't land — invoke MOP rollback Section 8 + investigate cache state.

---

## Action items (must address before user PRD approval)

1. **Design Spec Section 3b:** rewrite descriptor delivery to use `IOCTL_INTERNAL_BTH_SUBMIT_BRB` with SDP TLV pattern-matching in the BRB completion routine. Reference notebook source `61873fa7` for BRB handler entry pattern (offset +0x16). Add a note that this is the same architecture Apple's `applewirelessmouse.sys` uses (validated via static analysis of the binary on this user's system).
2. **Design Spec Section 11:** add F13 (BTHPORT cache trap) and F14 (sequential queue blocking on stalled 0x90 poll) to the failure modes table with mitigations.
3. **MOP Section 7c:** add a sub-step "7c-pre" that EITHER wipes BTHPORT `CachedServices\00010000` (preferred, scripted) OR triggers an operator-driven unpair + re-pair sequence (fallback). Document both, mark unpair/re-pair as the safe default until the cache-wipe path is validated empirically.
4. **MOP add Section 9.0 / VG-0:** pre-validation diagnostic — confirm HIDP_GetCaps shows Mode A (Input=8 / Feature=2 / LinkColl=5) on both v1 and v3 before tray restart and VG-1.
5. **Design Spec Section 8:** add note that active-poll path may move to a parallel long-running queue if VG-4 soak surfaces queue-blocking symptoms.

These changes are SCOPED for the same PR. None require new code — all are documentation updates to the design spec and MOP markdown files.

## Citations (notebook source IDs)

- `1bf7c9dd-0f74-4ceb-806b-fce8d253e1db` — M12 Design Spec 2026-04-28 (under review)
- `c4817b45-c01b-4ddd-9094-1a1d97f218ab` — M12 MOP 2026-04-28 (under review)
- `61873fa7-e4a0-46be-880f-52aee91fd8f2` — applewirelessmouse.sys reverse engineering, BRB handler pattern, cached-descriptor trap
- `566c3ece-2c08-4b37-a05a-5f35f8606000` — M13 Plan, BTHPORT cache decode (CachedServices\00010000)
- `ed54b2d3-00c3-4f1d-be7e-521025abdb1c` — Three-era registry diff, BTHPORT cache location confirmed
- `bbd3dc75-9f6d-44b9-8c16-af3b3117fc5d` — M12 empirical capture inventory (MU 3.1.5.3, 11 BCrypt imports, license gate)
- `8ff5daf6-7dd6-47bc-ad9e-f83b3620baae` — Session 12 corrected plan (M12 via MU RE reference)
- `d4d270d7-f6e3-4f54-a36f-4f4ca811bb81` — Three-driver architecture comparison
- `88ca7a3d-49a4-4367-8cd3-8d5985da51c0` — Linux hid-magicmouse.c (GPL-2 reference)
- `6a9eed6c-b822-4ecb-bd29-b1722703cc63` — Apple filter behavior on Feature 0x47 (descriptor declares cap, device returns err=87, no active trap)

## Metadata

- Date: 2026-04-28
- NLM service: notebooklm.google.com (MCP via `notebook_query`)
- Verdict: CHANGES-NEEDED (downgraded from REJECT per adversarial gate — no production implementation exactly matches M12 architecture)
- Prior peer review: `docs/M12-PEER-REVIEW-NOTEBOOKLM-2026-04-28.md` (review of M12-MAGIC-UTILITIES-REFERENCE-PLAN, recommended v3-specific tests — addressed in this design's MOP VG-2/VG-3)
