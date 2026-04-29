# M12 Peer Review — NotebookLM — 2026-04-28

## BLUF

NotebookLM confirms the corrected M12 plan is architecturally sound and legally defensible with one material flag: **the v1-as-regression-control strategy has a critical blind spot** — v1 testing exercises zero lines of the v3-specific 0x90 translation and 0x12 scroll parsing code, so a separate v3-specific test suite is required.

---

## Source Added

- **Notebook used**: PRD-184 — Magic Mouse 3 KMDF Driver (Scroll + Battery Coexistence)
  `https://notebooklm.google.com/notebook/e789e5e9-da23-4607-9a62-bbfd94bb789b`
- **Source already present**: `8ff5daf6-7dd6-47bc-ad9e-f83b3620baae` — "PRD-184 Session 12 corrected plan — M12 via MU reverse-engineering reference (2026-04-28)"
  (Source was added in a prior session; no duplicate add was needed.)

---

## Q1 — Legal: Is reverse-engineering MagicMouse.sys defensible under DMCA §1201(f) / Canadian Copyright §30.61 / EU Software Directive Art. 6?

**NLM Response (summarised from full answer):**

Yes — all three statutory frameworks provide interoperability exemptions that cover this use case, subject to common conditions:

- **DMCA §1201(f)**: Requires a lawfully obtained copy (MU trial qualifies), sole purpose must be interoperability, and interoperability information must not be readily available. Case law (*Lexmark v. Static Control Components*) supports RE for interop. Protection is lost only if literal binary code is copied into the new driver.
- **Canadian §30.61**: Same conditions. Extracted information may only be used for interoperability — not to create a functionally identical clone using literal copied code.
- **EU Art. 6** (*SAS Institute v. World Programming Ltd*): Strongest protection; contractual terms (EULA) cannot override this right. Risk only arises if object code is literally copied.
- **Clean-room approach**: The plan's use of dumpbin/strings/Ghidra to extract un-copyrightable API facts (report sizes, offsets, polling mechanics) — then writing an original KMDF driver — is the gold standard. Copyright protects expression, not functional logic.
- **Caveat**: A true two-party clean-room (one team RE, separate team writes) provides maximum protection. Single-person RE-then-write is still highly defensible under the interop exemptions but slightly less insulated.

**Interpretation**: Green-light on legal. Proceed with the reverse-engineering capture; do not copy literal code from MagicMouse.sys into M12.

---

## Q2 — Architectural premise: Does v3 firmware genuinely not back Feature 0x47, and must translation occur in host code?

**NLM Response (summarised):**

Premise confirmed — strongly and exhaustively. Five independent lines of evidence:

1. **err=87 on direct 0x47 request**: When applewirelessmouse.sys injects a Feature 0x47 capability into Descriptor B, direct `HidD_GetFeature(0x47)` calls to the device return `ERROR_INVALID_PARAMETER`. The device hardware rejects it.
2. **Native v3 battery path**: v3 stores battery in `UP=FF00` vendor outer collection → Input 0x90 → `[0x90, flags, pct]`, 3 bytes. Host must intercept 0x47 requests, dispatch 0x90, and translate.
3. **588-attempt exhaustive enumeration returned 0 hits**: All HID report IDs, WMI battery classes, IOCTL codes, and PnP DEVPKEYs probed while in Descriptor B — no alternative battery path exists.
4. **No unsolicited push**: 10,728 ETW events / 5,342 HID Interrupt packets on connection 0x032 — the device never pushes battery data; polling is mandatory.
5. **Linux corroboration**: `hid-magicmouse.c` uses `hid_hw_request(hdev, report, HID_REQ_GET_REPORT)` — poll-based, not push-based. Architecture convergently confirmed.

**Interpretation**: Premise is 100% correct. No hidden v3 firmware query mechanism exists. The 0x47→0x90 translation must live in host driver code.

---

## Q3 — KMDF patterns: Are there known filter driver patterns for HID GET_REPORT redirection we should use?

**NLM Response (summarised):**

Three established patterns apply, all sourced from the existing driver skeleton and Microsoft Learn docs:

1. **KMDF Lower Filter Initialization**: `WdfFdoInitSetFilter()` during `EvtDriverDeviceAdd` — correctly prevents exclusive I/O ownership. Already implemented in `driver/Driver.c`.
2. **Forward-With-Completion pattern**: For 0x47→0x90 translation: intercept via `WdfIoQueueDispatchParallel` / `EvtIoInternalDeviceControl`, forward down the stack via `WdfRequestSend`, translate in completion routine (`InputHandler_OnReadComplete`). Unrelated IOCTLs use `SEND_AND_FORGET` passthrough.
3. **BRB Interception pattern (critical)**: The descriptor is NOT delivered via `IOCTL_HID_GET_REPORT_DESCRIPTOR`. HidBth fetches it via L2CAP SDP (BRB_L2CA_ACL_TRANSFER, PSM 1) during pairing. The correct hook is `IOCTL_INTERNAL_BTH_SUBMIT_BRB`. In the completion routine, scan ACL buffer for SDP attribute 0x0206 (HIDDescriptorList) TLV pattern and replace in-place with `g_HidDescriptor[]`. This is what applewirelessmouse.sys does (confirmed from binary signatures).

WDK references: "Creating Device Objects in a Filter Driver" (Microsoft Learn); `mac-precision-touchpad` (roblabla) for WDF skeleton; Linux `hid-magicmouse.c` for report parsing.

**Interpretation**: All three patterns are already present in the driver skeleton in various states of completion. BRB interception is the most complex and highest-risk piece — must be complete before the descriptor injection works on already-paired devices.

---

## Q4 — Filter binding order: What's the failure mode if M12 loads after applewirelessmouse.sys has mutated the descriptor?

**NLM Response (summarised):**

Load ordering is a critical concern — and it's the primary reason M12 must **replace** (not coexist with) applewirelessmouse.sys.

The failure mode if both drivers are loaded is a **silent descriptor overwrite**:

- IRP completion routines execute bottom-up. M12 (lower filter) runs its completion routine first and injects the custom descriptor preserving COL02.
- applewirelessmouse.sys (function driver) runs its completion routine second, pattern-matches the SDP TLV, and overwrites M12's descriptor with its own Descriptor B (which strips `USAGE_VENDOR_FF00` — the battery collection).
- Net result: M12's descriptor is neutralised before HidClass ever sees it. Battery remains broken.

**Upper-filter alternative**: Upper filters cannot intercept `IOCTL_INTERNAL_BTH_SUBMIT_BRB` because these internal IOCTLs travel downward from HidBth — they never pass through a driver sitting above the originator.

**Conclusion**: Coexistence at BRB level is architecturally impossible. M12 must be the sole driver on the BTHENUM stack for the v3 mouse; applewirelessmouse.sys must be uninstalled (Step 5 of the plan).

**Interpretation**: M12 plan's Step 5 (uninstall MU) is mandatory, not optional. Do not attempt to layer M12 on top of MU.

---

## Q5 — Published Apple HID translation driver examples besides Magic Utilities?

**NLM Response (summarised):**

Two open-source references are documented in the notebook; no others exist in the sources:

1. **Linux `hid-magicmouse.c`** (kernel.org) — Primary source. Extract:
   - Report 0x12 (`MOUSE2_REPORT_ID`): 14-byte header + 8-byte touch blocks. Per-touch: ID = `(tdata[6]<<2|tdata[5]>>6)&0xf`, 12-bit signed X/Y.
   - Scroll synthesis (`magicmouse_emit_touch`): `TOUCH_STATE_START (0x30)` resets accumulator; `TOUCH_STATE_DRAG (0x40)` computes `step_y / ((64-speed)*accel)` → `REL_WHEEL`.
   - Battery poll: `magicmouse_fetch_battery` → `hid_hw_request(..., HID_REQ_GET_REPORT)` on a timer.
   - Descriptor fixup: `magicmouse_report_fixup` for dynamic in-place descriptor byte replacement.
   - **Note**: PID 0x0323 is not in the Linux device table (released after driver); format assumed same as MAGICMOUSE2_USBC — verify on first test run.

2. **`mac-precision-touchpad`** (roblabla/GitHub) — WDF skeleton reference only. Does NOT support PID 0x0323.

No other published open-source Apple HID translation drivers identified in the sources.

**Interpretation**: Linux `hid-magicmouse.c` is the only substantive reference for protocol parsing. The PID 0x0323 format assumption must be empirically verified on first driver run against live hardware.

---

## Q6 — Regression strategy: Is v1-as-known-good-control sound for catching v3 translation issues?

**NLM Response (summarised):**

**No — the v1 regression control is fundamentally unsound for validating v3-specific logic.** It has two critical blind spots:

1. **Battery translation gap**: M12 uses a transparent passthrough for v1 (v1 natively backs 0x47 — no interception needed). Testing battery on v1 exercises zero lines of the `IOCTL_HID_GET_FEATURE` interception, `IOCTL_HID_GET_INPUT_REPORT` dispatch, and `[0x90, flags, pct]` → `[0x47, pct]` buffer translation code.

2. **Scroll parsing gap**: v1 sends `MOUSE_REPORT_ID (0x29)` with a 6-byte header; v3 sends `MOUSE2_REPORT_ID (0x12)` with a 14-byte header. Byte offset math, array indexing, and tracking ID extraction are completely different. A passing v1 scroll test proves nothing about v3 0x12 parsing.

v1 testing is only valid for **Tier 3 Integration tests** (driver loads, stack doesn't crash, native data passes through). It is a complete blind spot for Tier 1 and Tier 4 E2E tests.

**Interpretation**: **Material flag.** The test plan must add v3-specific tests: direct 0x90 poll after driver install, and v3 scroll delta verification. v1 as a "does not break" smoke test is fine; v1 as a proxy for v3 translation correctness is not acceptable.

---

## Q7 — Tray API approach: Synthesize Feature 0x47 in kernel vs. modify tray to read 0x90 directly?

**NLM Response (summarised):**

Two viable paths — NLM identifies both, with clear tradeoffs:

**Approach A — Synthesize 0x47 in M12 kernel driver (plan's current position)**:
- Intercept `IOCTL_HID_GET_FEATURE` for 0x47, dispatch internal `IOCTL_HID_GET_INPUT_REPORT` for 0x90, repack in completion routine.
- Pro: Unified API — tray is hardware-agnostic, identical call for v1 and v3.
- Pro: Aligned with Apple's own approach (binary signatures confirm Apple synthesizes a unified 0x47 for v3 in applewirelessmouse.sys).
- Con: High kernel complexity — completion routines, memory buffer manipulation, I/O forwards under kernel constraints.

**Approach B — Passthrough 0x90, modify tray to read it directly**:
- M12 preserves COL02 in the descriptor; tray calls `HidD_GetInputReport(handle_col02, 0x90)`.
- Pro: Dramatically simpler kernel driver — eliminates all battery-specific completion routines.
- Pro: Empirically proven — `MouseBatteryReader.cs` already uses this path (96 consecutive successful reads confirmed on 2026-04-27). The tray may already have the 0x90 logic implemented.
- Con: Hardware-specific branching in userland (PID-based dispatch in tray code).

**Recommendation**: Approach B is lower-risk for M12 implementation (simpler kernel, empirically proven path). Approach A is architecturally cleaner long-term. Given the dev is in personal-use/test-signed mode, Approach B is the pragmatic choice for first-pass validation — upgrade to A later if productising.

**Interpretation**: The sources suggest `MouseBatteryReader.cs` already handles 0x90 reads. The tray may need minimal changes. Approach B de-risks the kernel driver significantly for M12.

---

## Net Assessment

**Green-light to proceed with MU capture and M12 implementation**, with three action items:

1. **Legal**: Proceed with RE under interop exemption. Do not copy literal binary code from `MagicMouse.sys` into M12.
2. **Test plan gap (material)**: Add v3-specific tests — 0x90 direct poll and v3 scroll delta verification. v1 regression control is insufficient as a proxy for v3 translation correctness.
3. **Battery API decision**: Consider Approach B (passthrough 0x90, tray reads directly) over Approach A (kernel-synthesized 0x47) for M12 first-pass — lower kernel risk, already empirically proven. Document the decision before implementing.

No architectural blockers identified. The BRB-interception pattern, clean-room approach, and MU-uninstall-before-M12-install sequencing are all confirmed correct.

---

## Metadata

- **Date**: 2026-04-28
- **Notebook**: PRD-184 — Magic Mouse 3 KMDF Driver (Scroll + Battery Coexistence)
- **Notebook URL**: `https://notebooklm.google.com/notebook/e789e5e9-da23-4607-9a62-bbfd94bb789b`
- **Source used for peer review**: `8ff5daf6-7dd6-47bc-ad9e-f83b3620baae` (already present from prior session)
- **Conversation thread ID**: `8dfc914c-2b40-4ccf-bdb1-f6d582a08a25`
- **Supporting sources cited**: `61873fa7`, `566c3ece`, `ccd5f53a`, `f3fd5f07`, `e9b6e804`, `88ca7a3d`, `06c74b30`, `ed54b2d3`
