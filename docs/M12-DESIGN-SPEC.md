# M12 Design Specification

**Status:** v1.3 — DRAFT pending user approval (NLM pass-2 blocking issues resolved)
**Date:** 2026-04-28
**Linked PRD:** PRD-184 v1.27
**Linked PSN:** PSN-0001 v1.9
**Linked NLM pass-1:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-2026-04-28.md`
**Linked NLM pass-2:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS2-2026-04-28.md`
**Approval gate:** PR ai/m12-design-prd-mop must be approved by user before any code is written.

## Revision history

- **v1.3 (2026-04-28, post-NLM-pass-3 patches inline):** Pass-3 ran against v1.3 and surfaced two CHANGES-NEEDED items, both documentation-quality fixes (not architectural). Patched in place: (a) `MAX_STALE_MS` default changed from 10000 to **0 (disabled)** — 10-sec default would force NOT_READY whenever mouse is asleep (~2 min idle), severe UX regression. Operator can opt-in to non-zero. (b) BRB TLV parser safety requirements expanded in Section 3b' to mandatory subsections a-g: MDL bounds, TLV walk bounds with abandon-on-failure, no-expansion-beyond-BufferLen, no-length-form-upgrade, recursive-parser, Driver Verifier special-pool catch. Pass-3 verdict at `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS3-2026-04-28.md`. Per playbook iteration cap, no v1.4 — v1.3 with these inline patches is the final design ship.
- **v1.3 (2026-04-28, original):** Resolved two blocking issues from NLM pass-2: (1) **PID branch restored for Feature 0x47** (Section 7d). v1 (PID 0x030D / 0x0310) Feature 0x47 IRPs pass-through to native firmware unchanged; only v3 (PID 0x0323) gets the shadow-buffer short-circuit. v1's working Feature 0x47 baseline preserved by definition. (2) **BRB-level descriptor mutation restored as fallback** (Section 3b'). When VG-0 detects the cached SDP descriptor is the device's native multi-TLC Descriptor A (no Feature 0x47 declared) — the fresh-pair scenario where no `applewirelessmouse` previously mutated the cache — M12's BRB completion routine intercepts `IOCTL_INTERNAL_BTH_SUBMIT_BRB` and rewrites the SDP HIDDescriptorList TLV to inject the unified Descriptor B (the v1.1 logic, retained as a fresh-pair fallback). Fast-path: when the cache already has Descriptor B (post-applewirelessmouse, the common case), no rewriting occurs and the v1.2 simplification still applies. New advisory: tunable `MAX_STALE_MS` registry default 10000 — if shadow timestamp older, return STATUS_DEVICE_NOT_READY (forces fresh data or explicit N/A in tray).
- **v1.2 (2026-04-28):** Major architectural correction following five parallel reviews (senior driver dev + HID protocol validation + Ghidra extended + applewirelessmouse Ghidra + RID=0x27 empirical). Re-baselined on `applewirelessmouse.sys` rather than MU `MagicMouse.sys`: M12 = applewirelessmouse baseline (Descriptor B = 116 bytes verbatim, RID=0x02 native scroll pass-through, RID=0x27 vendor blob input declared but raw) PLUS one delta — IRP completion intercept on `IOCTL_HID_GET_FEATURE` for ReportID 0x47, served from a shadow buffer of the most recent RID=0x27 input. No Mode A scroll synthesis. No Resolution Multiplier features. No active-poll path. Estimated < 100 LOC of M12-specific code beyond the applewirelessmouse skeleton. Senior driver dev review CRIT-1..CRIT-4 + MAJ-1..MAJ-5 + MIN-1..MIN-5 addressed inline. RID=0x27 battery byte offset implemented as registry-tunable `BATTERY_OFFSET` constant with debug log of cached payload bytes for empirical post-install confirmation. Translation formula `(raw - 1) * 100 / 64` clamped at boundaries.
- **v1.1 (2026-04-28):** Patched after NLM peer review pass-1 CHANGES-NEEDED. Section 3b descriptor delivery rewritten to use `IOCTL_INTERNAL_BTH_SUBMIT_BRB` + SDP TLV interception (lower filter cannot intercept `IOCTL_HID_GET_REPORT_DESCRIPTOR` — that IOCTL is absorbed by HidBth). Section 11 added F13 (BTHPORT SDP cache trap on already-paired devices) and F14 (sequential queue blocking on stalled GET_REPORT 0x90).
- **v1.0 (2026-04-28):** Initial design package.

### v1.2 changelog (review-finding -> section)

| Review finding | Section addressed | Resolution |
|---|---|---|
| Senior CRIT-1 (parallel queue UAF on read completion) | Sec 3b, Sec 8, Sec 9 | M12 does NOT intercept `IOCTL_HID_READ_REPORT` for translation. RID=0x02 (scroll/buttons) and RID=0x27 (vendor blob) flow native from device; M12 only TAPS RID=0x27 in a completion routine to update shadow buffer (read-only side-effect, no IRP mutation). RID=0x12/0x29 not used. No double-complete surface. |
| Senior CRIT-2 (sync IoTarget send deadlock) | Sec 7 | Active-poll path REMOVED entirely. M12 is shadow-buffer-only. Feature 0x47 always completes inline from cached RID=0x27 payload. |
| Senior CRIT-3 (missing EvtIoStop on BT disconnect) | Sec 8, Sec 9 | EvtIoStop registered on both queues. RID=0x27 tap completion tolerates target-gone via standard cancellation. EvtDeviceSelfManagedIoSuspend calls WdfIoTargetStop. |
| Senior CRIT-4 (NULL IoTarget before EvtDevicePrepareHardware) | Sec 3, Sec 9 | M12 uses `WdfDeviceGetIoTarget(device)` (default lower target, valid post-EvtDeviceAdd) — no separate IoTarget creation. NULL-deref window eliminated. |
| Senior MAJ-1 (HidClass gates on descriptor) | Sec 5 | Descriptor B (116 bytes, applewirelessmouse) is verbatim — DOES declare Feature 0x47 (`05 06 09 20 85 47 15 00 25 64 75 08 95 01 B1 A2`). HidClass forwards GET_FEATURE 0x47. |
| Senior MAJ-2 (scroll_speed div-by-zero) | Sec 6 | N/A — M12 has no scroll synthesis. RID=0x02 native pass-through carries native X/Y/Wheel/Pan from device firmware. The whole scroll-from-touch algorithm is removed in v1.2. |
| Senior MAJ-3 (wrong WDF API for METHOD_NEITHER) | Sec 7 | `WdfRequestRetrieveOutputBuffer` for METHOD_BUFFERED/DIRECT or `WdfRequestGetParameters` -> `Parameters.Others.Arg1` (Type3InputBuffer = `HID_XFER_PACKET *`) for METHOD_NEITHER documented per IOCTL. |
| Senior MAJ-4 (active-poll v3 GET_INPUT_REPORT 0x90 unconfirmed) | Sec 7 | N/A — active-poll removed (CRIT-2 fix). RID=0x90 not used. v3 emits RID=0x27 ~10/sec while in use; cache stays warm. |
| Senior MAJ-5 (no pool tag) | Sec 9 | Pool tag `'M12 '` (= 0x2032314D little-endian, ASCII "M12 ") declared. Distinct from MU's `'MMMM'` and applewirelessmouse's untagged allocations. |
| Senior MAJ-6 (descriptor short-circuit not enforced) | Sec 3b | M12 doesn't bypass `IOCTL_HID_GET_REPORT_DESCRIPTOR` — that IOCTL never reaches lower filters on BTHENUM (absorbed by HidBth, see v1.1). Descriptor delivery is via BRB SDP TLV rewrite. ASSERT-and-fall-through pattern still added in EvtIoInternalDeviceControl default case. |
| Senior MIN-1 (HID_DEVICE_ATTRIBUTES static export) | Sec 9 | Removed — M12 does not override `IOCTL_HID_GET_DEVICE_ATTRIBUTES`. VID/PID flow through native. |
| Senior MIN-2 (16-bit Logical Min/Max byte encoding) | Sec 5 | Descriptor B (116 bytes) is verbatim from `applewirelessmouse.sys` offset 0xa850. Bytes are 8-bit Wheel/Pan (`75 08 95 01`), not 16-bit — MIN-2 concern was about Mode A which is no longer in M12. Verified byte-for-byte against `M12-HID-PROTOCOL-VALIDATION-2026-04-28.md` decode. |
| Senior MIN-3 (TOUCH_STATE_MASK = 0xf0) | Sec 6 | N/A — touch parsing removed. |
| Senior MIN-4 (registry path) | Sec 7 | Registry path `\Registry\Machine\System\CurrentControlSet\Services\M12\Parameters` for `BATTERY_OFFSET` tunable — KMDF convention. |
| Senior MIN-5 (LowerFilters MULTI_SZ append) | Sec 4 | Note: applewirelessmouse must be removed from LowerFilters before M12 install (MOP step). M12's INF appends; coexistence with applewirelessmouse on the same stack is rejected. |
| HID-protocol short-circuit IRP recommendation | Sec 7 | Adopted. Feature 0x47 always completes inline from shadow buffer; never forwarded to device. |
| HID-protocol shadow buffer + first-boot race | Sec 7, Sec 10 | Shadow buffer 47-byte non-paged allocation, KSPIN_LOCK protected, timestamp-tracked. First-boot (no RID=0x27 yet): return `STATUS_DEVICE_NOT_READY` so tray shows N/A until first input arrives, OR return `[0x47, 0x00]` per registry policy (default: `STATUS_DEVICE_NOT_READY`). |
| HID-protocol translation formula | Sec 7 | `(raw - 1) * 100 / 64` for raw in [1..65]; clamped: raw < 1 -> 0%, raw > 65 -> 100%. Hypothesis; needs empirical validation post-install. Implemented as `TranslateBatteryRaw()` standalone function for easy update without recompile if data shows non-linear. |
| Phase 1 ext (BRB filter, not HID class) | Sec 3a, Sec 3b | M12 binds to BTHENUM via lower-filter on HID-class GUID `{00001124-...}`. Descriptor delivery is via BRB completion (BRB type at +0x16, BRB_L2CA_ACL_TRANSFER = 5). Stateless per-BRB allocation (`'M12 '` pool tag). Mirrors MU's stateless pattern minus license logic. |
| Phase 1 ext (no license gate) | Sec 3c | Reaffirmed — no flag, no userland handshake, no license check. Translation unconditional. |
| Phase 1 ext (Descriptor B verbatim, skip A) | Sec 5 | M12 serves Descriptor B verbatim (116 bytes from applewirelessmouse offset 0xa850). Does not implement Descriptor A (Apple's Mode B has 47-byte input but it IS Descriptor B in applewirelessmouse — naming convention clarified in Sec 5). |
| applewirelessmouse baseline (delta = Feature 0x47 intercept) | Sec 1, Sec 3 | M12 = applewirelessmouse + 1 delta. Estimated < 100 LOC of new code on top of the applewirelessmouse skeleton. |
| RID=0x27 empirical (offset BLOCKED) | Sec 7, Sec 12 | `BATTERY_OFFSET` registry-tunable. Default value (best-guess from descriptor analysis): 1 (first payload byte after RID). Debug log emits cached payload hex on every Feature 0x47 query so post-install ETW/HCI sniff can verify which byte tracks battery level. |

### v1.3 changelog (NLM pass-2 blocking issues -> section)

| Pass-2 finding | Section addressed | Resolution |
|---|---|---|
| NEW-1 BLOCKING: same-path-for-v1-and-v3 regresses v1's working native Feature 0x47 | Sec 7d | PID branch restored. v1 (PID 0x030D / 0x0310) Feature 0x47 IRPs pass-through to native firmware unchanged — `ForwardRequest(req, dctx)` without M12 logic. v1's working baseline (PRD-184 M2 production code path) is preserved by definition. Only v3 (PID 0x0323) gets the shadow-buffer short-circuit. v1's RID=0x27 may not even be emitted; M12 doesn't depend on it for v1. |
| NEW-2 BLOCKING: no descriptor mutation breaks fresh-pair scenarios where BTHPORT cache lacks Descriptor B | Sec 3b' | BRB-level descriptor mutation restored as fallback. M12 attaches a completion routine to `IOCTL_INTERNAL_BTH_SUBMIT_BRB` IRPs. In completion, scan ACL transfer buffer for the SDP HIDDescriptorList TLV pattern (`35 LL` -> `09 02 06` -> `35 LL` -> `35 LL` -> `08 22` -> `25 NN` -> descriptor bytes). If the descriptor is the device's native multi-TLC variant (no Feature 0x47 declared), rewrite in place to the unified 116-byte Descriptor B (which DOES declare Feature 0x47). If the descriptor already declares Feature 0x47, leave it alone (fast-path; v1.2 behaviour for the common post-applewirelessmouse case). v1.1 BRB rewriter logic restored from prior design version + `.ai/code-reviews/bthport-patch-safety.md` security-reviewer guidance. |
| NEW-3 NON-BLOCKING: BATTERY_OFFSET=1 hypothesis | Sec 7, Sec 12 | Already addressed in v1.2 via VG-4 + registry tunable. v1.3 explicitly notes: tray ships with NOT_READY default; user must complete VG-4 before relying on percentage. |
| NEW-4 NON-BLOCKING: cold-start N/A indefinite if mouse idle | Sec 7c, Sec 12 | Already accepted in v1.2. v1.3 adds advisory MAX_STALE_MS registry tunable (default 10000 ms / 10 sec): if shadow timestamp older than threshold, return STATUS_DEVICE_NOT_READY rather than serve potentially stale percentage. Forces tray to retry rather than display stale data. |
| Pass-2 advisory: soft active-poll for cold-start | Sec 12 OQ-D | Documented as future work; out of scope for v1.3. |

---

## 1. BLUF

M12 is a pure-kernel KMDF lower filter driver, built clean-room from public references, that binds to Apple Magic Mouse v1 (PIDs 0x030D, 0x0310) and v3 (PID 0x0323) BTHENUM HID devices. M12's architectural baseline is Apple's own `applewirelessmouse.sys` (open-source provenance, 76 KB, no BCrypt, no userland service). The **delta vs applewirelessmouse** is two IRP-path interventions:

1. **For v3 only (PID 0x0323):** when HidClass forwards `IOCTL_HID_GET_FEATURE` for ReportID 0x47, M12 short-circuits and completes inline with `[0x47, percentage]` derived from a shadow buffer of the latest RID=0x27 vendor input report (46-byte raw payload, refreshed on the BT interrupt channel ~10/sec while the mouse is in use). v1 (PIDs 0x030D, 0x0310) Feature 0x47 IRPs pass-through to native firmware unchanged — preserves v1's working PRD-184 M2 baseline.
2. **Fresh-pair fallback (any PID):** if the BTHPORT cached SDP descriptor lacks Feature 0x47 (the device's native multi-TLC Descriptor A — present when no `applewirelessmouse` previously mutated the cache), M12's `IOCTL_INTERNAL_BTH_SUBMIT_BRB` completion routine rewrites the SDP HIDDescriptorList TLV to inject the unified Descriptor B (which declares Feature 0x47). When the cache already serves Descriptor B (the common post-applewirelessmouse case), no rewriting occurs.

Translation formula `(raw - 1) * 100 / 64` for raw in [1..65]; clamped at boundaries. Battery byte offset within the 46-byte payload is registry-tunable (`BATTERY_OFFSET`, default 1) with debug logging to support empirical post-install validation. Shadow staleness threshold `MAX_STALE_MS` registry-tunable (default 10000 ms): older = STATUS_DEVICE_NOT_READY. No Mode A high-resolution scroll synthesis. No Resolution Multiplier feature reports. No active-poll. No userland service, no license gate, no trial expiry. Estimated 100-200 LOC of M12-specific code beyond an applewirelessmouse-equivalent KMDF skeleton (revised up from <100 in v1.2 to account for BRB SDP TLV rewriter); total binary 20-40 KB. Replaces both `applewirelessmouse.sys` (Apple/tealtadpole) and `MagicMouse.sys` (Magic Utilities) on the v1+v3 mouse stacks.

---

## 2. Goals and Non-Goals

### Goals

1. Deliver simultaneous scroll AND battery on Magic Mouse v3 (PID 0x0323) on Windows 11.
2. Maintain regression-free operation on Magic Mouse v1 (PID 0x030D) — both scroll and battery readable in the existing tray's "Feature 0x47" code path.
3. Deterministic at every cold boot, sleep/wake, and BT reconnect — no PnP recycle scripts, no userland watchdog, no startup tasks required.
4. Pure kernel: no userland service, no license enforcement, no trial mechanism.
5. Clean-room implementation under interoperability exemption (DMCA section 1201(f), Canada Copyright Act section 30.61, EU Software Directive 2009/24/EC Article 6). Reference binaries (`applewirelessmouse.sys`, `MagicMouse.sys`) read for facts only; no source code or binary fragment copied. The HID descriptor at applewirelessmouse offset 0xa850 is used verbatim under the Mode B interoperability requirement (it IS the device's empirical published descriptor surface).
6. WHQL-pathable: design uses standard KMDF, standard HID class IOCTLs, standard INF directives. WHQL submission is OUT of scope for M12 itself but the implementation must not preclude it.

### Non-Goals

- Magic Trackpad support (PIDs 0x030E, 0x0314 — different report formats, not on the user's hardware).
- Magic Keyboard support.
- High-resolution scroll (Mode A 5-link-collection / Resolution Multiplier features). Mode B 8-bit Wheel/Pan from native firmware is sufficient for the tray's PRD-184 goals; precision-scroll is a future milestone.
- Multi-finger gestures. Native RID=0x02 already includes Wheel + Pan; M12 does not synthesise gestures from touch.
- Force-feedback, click-pressure, or per-finger touch data.
- USB-C wired path. v3 charges via USB-C but the host-mouse data path is BT-only on this hardware.
- Replacing `MagicKeyboard.sys` for the AWK keyboard.

---

## 3. Architecture

### 3a. Driver position in the HID stack

```
                      +------------------------------+
                      |   Win32 input subsystem      |
                      |   (mouhid, RawInput, etc.)   |
                      +---------------+--------------+
                                      |
                      +---------------v--------------+
                      |       HidClass (FDO)         |
                      +---------------+--------------+
                                      |
                      +---------------v--------------+
                      |   HidBth (function driver)   |
                      +---------------+--------------+
                                      |
                      +---------------v--------------+
                      |    M12 (lower filter)        |   <- this design
                      |    MagicMouseDriver.sys      |
                      +---------------+--------------+
                                      |
                      +---------------v--------------+
                      |   BthEnum / Bluetooth stack  |
                      +------------------------------+
                                      |
                                  Magic Mouse
                                  (v1 PID 0x030D
                                   v1 PID 0x0310 trackpad-class
                                   v3 PID 0x0323)
```

The filter is a lower filter under HidClass and underneath HidBth. `WdfFdoInitSetFilter` marks it as a non-power-policy-owner filter so HidClass remains the function driver of record.

**Filter classification (per Phase 1 A2):** M12 is a BRB filter on the HID-class GUID `{00001124-0000-1000-8000-00805F9B34FB}` LowerFilters chain. It is NOT a HID class filter in the sense of mutating already-parsed HID input streams; HID parsing happens in HidClass (above M12). M12 sits at the BRB boundary — between HidBth (which produces BRBs from L2CAP traffic) and the BT minidriver (which produces BRBs from raw Bluetooth frames). M12 sees BRBs going both directions.

**IoTarget acquisition (CRIT-4 fix):** M12 uses `WdfDeviceGetIoTarget(device)` to obtain the default lower IoTarget. This is valid immediately after `WdfDeviceCreate` returns successfully — no separate `EvtDevicePrepareHardware` step required. The NULL-IoTarget window from v1.1 is eliminated.

### 3b. Data flow

There are exactly THREE distinct data flows in M12. Each gets explicit handling.

**Flow 1 — Native input pass-through (the hot path, NO M12 code in the IRP path):**
1. Device emits RID=0x02 (mouse/scroll, 5 payload bytes) or RID=0x27 (vendor blob, 46 payload bytes) on BT interrupt channel.
2. HidBth packages it; HidClass dispatches `IOCTL_HID_READ_REPORT` down the stack.
3. M12's default-queue dispatcher inspects IOCTL code:
   - For `IOCTL_HID_READ_REPORT`: forward to lower IoTarget WITH a completion routine attached (`OnReadComplete`).
   - The completion routine inspects the buffer's first byte (Report ID) AFTER the IRP completes upstream. For RID=0x27, copy the 46-byte payload + timestamp into the device-context shadow buffer (under spinlock). For all other RIDs, no action. Always allow the IRP to complete upstream unmolested — never modify the buffer, never re-complete, never absorb. This is a passive tap, not a translation.
4. HidClass parses the input report against the (Mode B / Descriptor B) descriptor and dispatches to mouhid / RawInput as native.

This flow exercises NONE of M12's IRP synthesis logic. M12 acts solely as a passive eavesdropper on the input stream. CRIT-1 (double-complete) cannot occur because M12 never completes the read IRP; the IoTarget completes it.

**Flow 2 — Feature 0x47 GET_REPORT (the only synthesised IRP):**
1. Tray app calls `HidD_GetFeature(handle, 0x47, ...)`.
2. HidClass validates ReportID against the parsed descriptor (Descriptor B declares Feature 0x47 — the `85 47 ... B1 A2` block at offsets 87-98 of the 116-byte descriptor — so HidClass forwards). HidClass dispatches `IOCTL_HID_GET_FEATURE` down the stack as `IRP_MJ_INTERNAL_DEVICE_CONTROL`, METHOD_NEITHER.
3. M12's `EvtIoInternalDeviceControl` (sequential queue) inspects:
   - Retrieve `HID_XFER_PACKET *pkt` via `WdfRequestGetParameters(req, &params)` then `pkt = (HID_XFER_PACKET *)params.Parameters.Others.Arg1` (the METHOD_NEITHER path; MAJ-3 fix).
   - Validate `pkt != NULL && pkt->reportBufferLen >= 2 && pkt->reportId == 0x47`.
   - Read shadow buffer under spinlock; if buffer is empty (no RID=0x27 received yet) and policy is "wait for input", complete with `STATUS_DEVICE_NOT_READY`.
   - Else: extract `raw = shadow_buffer[BATTERY_OFFSET]`. Apply `pct = TranslateBatteryRaw(raw)`. Write `pkt->reportBuffer[0] = 0x47; pkt->reportBuffer[1] = pct;`. `WdfRequestSetInformation(req, 2)`. `WdfRequestComplete(req, STATUS_SUCCESS)`.
4. Important: **M12 NEVER forwards the Feature 0x47 IRP to the device.** This is the short-circuit recommendation from HID-protocol validation — eliminates err=87 round-trip, eliminates cancellation race, and avoids the active-poll pattern entirely.

For PIDs 0x030D / 0x0310 (v1): M12 still serves Feature 0x47 from the shadow buffer using the same algorithm. v1's native firmware also backs Feature 0x47 directly, but having M12 short-circuit it ensures behavioural symmetry between v1 and v3 — both deliver the SAME `[0x47, pct]` from the SAME translation path. v1 regression risk reduced because the v1 vendor blob ALSO populates the shadow buffer (RID=0x27 is a v1 report too, declared in the same applewirelessmouse descriptor for both PIDs).

**Flow 3 — All other IRPs (pass-through):**
1. M12's default queue forwards every other IRP type unchanged (no completion routine) via `WdfRequestForwardToIoQueue` -> default forwarding via `WdfRequestSend` to the lower IoTarget.
2. Specifically pass-through (no inspection): all `IOCTL_HID_*` codes other than READ_REPORT and GET_FEATURE; `IOCTL_INTERNAL_BTH_SUBMIT_BRB` (M12 does NOT mutate descriptors at the BRB level — see 3b' below); PnP IRPs handled by the framework default; power IRPs handled by HidClass as policy owner.

**3b'. BRB-level descriptor mutation as fallback (restored in v1.3 per NLM pass-2 NEW-2):**

The empirical reality (per `M12-APPLEWIRELESSMOUSE-FINDINGS` Q3 + Phase E descriptor-state research) is that v3 publishes a multi-TLC NATIVE descriptor (Descriptor A: COL01 Mouse 8-byte + COL02 Vendor 0x90 Input). `applewirelessmouse.sys` MUTATES this at the BRB level into the unified single-TLC 116-byte Descriptor B at offset 0xa850 (which declares Feature 0x47). When `applewirelessmouse` is on the stack, the BTHPORT cache stores Descriptor B. When `applewirelessmouse` is NOT on the stack and the device pairs fresh, the BTHPORT cache stores Descriptor A — and HidClass's preparsed data does not declare Feature 0x47, so `HidD_GetFeature(0x47)` returns ERROR_INVALID_PARAMETER at the HidClass layer before reaching M12.

Therefore M12 v1.3 retains a BRB-level descriptor-mutation fallback. Algorithm:

1. M12's default queue dispatcher catches `IOCTL_INTERNAL_BTH_SUBMIT_BRB` IRPs.
2. Forwards the IRP downstream WITH a completion routine attached.
3. In the completion routine, inspect the BRB type at offset `+0x16` of the BRB structure (per `applewirelessmouse.sys` reverse engineering, signature `IOCTL_INTERNAL_BTH_SUBMIT_BRB (0x00410003)` -> 5 hits, BRB_L2CA_ACL_TRANSFER -> 13 hits).
4. If BRB type is `BRB_L2CA_ACL_TRANSFER` (5) and the ACL buffer (mapped via `MmGetSystemAddressForMdlSafe`) contains an SDP HIDDescriptorList byte pattern, parse the TLV.
5. SDP TLV pattern: `35 LL` (SEQUENCE) -> `09 02 06` (Attribute ID 0x0206 HIDDescriptorList) -> `35 LL` (SEQUENCE) -> `35 LL` (per-entry SEQUENCE) -> `08 22` (UNSIGNED int 0x22 = "report descriptor type") -> `25 NN ...` (length-prefixed descriptor bytes).
6. Inspect the descriptor bytes:
   - **Fast-path**: scan for the `85 47` byte sequence (Report ID 0x47). If found, descriptor already declares Feature 0x47 → leave unmodified, complete the IRP.
   - **Rewrite-path**: if not found (Descriptor A → no Feature 0x47), replace the embedded descriptor with the 116-byte `g_HidDescriptor[]` (the Descriptor B layout from Section 5). Adjust the three SDP length bytes (outer SEQUENCE + inner SEQUENCE + descriptor 25-prefix) accordingly. If `g_HidDescriptor[]` length crosses the 127-byte threshold, encoding shifts from 1-byte to 2-byte length form and all subsequent offsets shift — implementer must use a recursive TLV parser, not a fixed-offset writer (per prior security-reviewer finding `.ai/code-reviews/bthport-patch-safety.md`).
7. Pool tag `'M12 '` (Section 9a) for any temporary buffers.

**TLV parser safety requirements (mandatory, per NLM pass-3 fix and `.ai/code-reviews/bthport-patch-safety.md`):** The implementer MUST follow these rules; deviation = bugcheck risk during BT pairing.

a. **MDL bounds**: every access to the ACL transfer buffer is via `MmGetSystemAddressForMdlSafe` with `LowPagePriority` flag and explicit NULL check. Buffer length is `MmGetMdlByteCount(Mdl)`. NEVER access beyond `[buffer, buffer + length)`.

b. **TLV walk bounds**: every `35 LL` SEQUENCE descent decrements a remaining-bytes counter. If at any TLV boundary the next field would extend beyond the remaining counter, abandon the rewrite (do not modify the buffer) and complete the IRP with the original status. Example pseudocode:

```c
NTSTATUS RewriteSdpHidDescriptorList(PUCHAR Buffer, size_t BufferLen, PBOOLEAN Rewritten) {
    *Rewritten = FALSE;
    if (BufferLen < 8) return STATUS_BUFFER_TOO_SMALL;

    PUCHAR p = Buffer;
    PUCHAR end = Buffer + BufferLen;
    // Walk to the HIDDescriptorList attribute (id 0x0206)
    // ... recursive TLV parser; every read checks `(p + N) <= end` before dereferencing
    // ... if any check fails: log telemetry event 102 (BRB_REWRITE_FAILED) and return original status

    // Locate the embedded descriptor bytes (after 25 NN length-prefix)
    if (p + 2 > end) return STATUS_INVALID_BUFFER_SIZE;
    UCHAR descLen = *(p + 1);   // length byte
    if (descLen > (end - (p + 2))) return STATUS_INVALID_BUFFER_SIZE;

    // Fast-path: scan for 85 47 in [p+2, p+2+descLen)
    if (ScanForReportId47(p + 2, descLen)) {
        return STATUS_SUCCESS;  // already declares 0x47, no rewrite needed
    }

    // Rewrite-path: replace the descLen bytes with g_HidDescriptor[]
    // BEFORE writing, compute the deltas:
    //   deltaDesc  = g_HidDescriptorLen - descLen           (descriptor body delta)
    //   deltaInner = same (inner SEQUENCE wraps descriptor)
    //   deltaOuter = same (outer SEQUENCE wraps inner)
    // If deltaDesc + (current outer SEQUENCE length) > 255, encoding shifts from 1-byte
    // length to 2-byte length form (35 LL -> 36 LLLL). Bail out (return STATUS_NOT_SUPPORTED)
    // if any of the three SEQUENCE length headers would need to upgrade form — v1.3 does
    // NOT support encoding upgrades. Fail-safe: 116-byte g_HidDescriptor stays under
    // every realistic outer-SEQUENCE size for this attribute (typical Apple SDP sends ~120 bytes
    // total HIDDescriptorList; 116 is well within 1-byte length form).

    // Verify the WRITE region fits: required new length = (BufferLen - descLen + g_HidDescriptorLen)
    // and the ACL transfer buffer must accommodate it. If `(end + deltaDesc) > Mdl backing storage`,
    // bail. For SDP responses, HidBth allocates the buffer based on the device's reply, so
    // expansion beyond the provided buffer would corrupt the next allocation. ABANDON if
    // expansion would exceed BufferLen.

    // OK: do the rewrite. memmove first (handle overlap), then update length bytes,
    // then set *Rewritten = TRUE.
    return STATUS_SUCCESS;
}
```

c. **Hard failover**: any unexpected TLV tag, length overflow, or buffer-bounds violation → abandon the rewrite, log telemetry event 102 (BRB_REWRITE_FAILED) with the failure reason, complete the IRP with the original status (do NOT modify the buffer). MOP gate VG-0 will detect the unrewritten descriptor and direct the operator to Section 7c-pre cache wipe.

d. **No expansion beyond BufferLen**: the rewrite cannot grow the SDP attribute beyond the original `BufferLen`. The 116-byte `g_HidDescriptor` is sized to fit within typical Apple SDP HIDDescriptorList allocations (which are ~135-170 bytes per Phase 3 BTHPORT cache decode), but the parser MUST verify before writing.

e. **Length-form upgrade not supported**: SDP TLV length encoding shifts from 1-byte (`35 LL`) to 2-byte (`36 LLLL`) at threshold 256. v1.3 does NOT handle this upgrade. If the rewrite would require it, abandon. The 116-byte `g_HidDescriptor` is well below this threshold for typical inputs.

f. **Recursive parser, not fixed-offset writer**: the SDP TLV is nested SEQUENCE-within-SEQUENCE. Implementer MUST walk the structure recursively. Hardcoding offsets ("the descriptor is always at byte 18") will fail when Apple changes the SDP service record between firmware versions.

g. **Driver Verifier with special pool**: MOP VG-6 enables Driver Verifier flag 0x9bb which includes special pool allocations for the BRB rewriter's temporary buffers. Any out-of-bounds write triggers a bugcheck during pairing — caught immediately, not silently corrupting the next allocation.

This dual-mode design preserves v1.2's simplification benefit (no rewrite cost when the cache is already correct, common post-applewirelessmouse case) while closing the fresh-pair compatibility hole. The TLV-parser safety regime is mandatory; v1.3 implementation must include unit tests for each abandon condition before VG-6 soak.

**F13 (BTHPORT cache trap):** still relevant for FRESH pair scenarios. If a user pairs the mouse for the first time AFTER M12 install and HidBth caches Descriptor A, the BRB completion routine ABOVE rewrites the cache during the SDP exchange. If the user pairs BEFORE M12 install (cache contains Descriptor A from native firmware) and then installs M12, the BRB rewrite never fires because no SDP exchange occurs on already-paired devices — operator must invalidate the BTHPORT cache (MOP Section 7c-pre Path A) to force a fresh SDP, OR unpair + re-pair (Path B). VG-0 caps check detects this state.

The pre-validation gate VG-0 has TWO valid pass conditions in v1.3:
- (i) Cache contains Descriptor B (Input=47, Feature=2, LinkColl=2) — applewirelessmouse-baseline; M12 BRB rewriter takes the fast-path no-op.
- (ii) Cache contains Descriptor A (Input=8 from COL01, plus COL02 vendor TLC, LinkColl=2 across split TLCs) AND M12 BRB rewriter has logged a successful rewrite event — fresh-pair-with-M12 scenario; subsequent SDP cache reads will get B.

VG-0 fail condition: cache contains Descriptor A AND M12 BRB rewriter has NOT logged a rewrite event — already-paired device with a stale Descriptor A cache; trigger Section 7c-pre.

### 3c. Why pure kernel (no userland)

H-013 confirmed empirically (Session 12) that Magic Utilities splits descriptor mutation (kernel) from translation + battery (userland service, license-gated). With trial-expired userland the kernel filter alone produces broken scroll and hidden battery. M12 collapses the split: Feature 0x47 synthesis is a single short-circuit in the kernel, no userland dependency, no license check, no trial expiry. Phase 1 A2 extended analysis re-confirmed: the OS-capability flag at MU offset 0x1405d7400 is NOT a license gate — the actual license logic is in obfuscated code reachable only via IOCTLs from MU's userland service. M12 omits this entirely; translation runs unconditionally.

---

## 4. INF Design

### 4a. Hardware ID matching

The INF must enumerate all three Apple BT HID PIDs that this user owns:

```
[Standard.NTamd64]
%MM_v1_DeviceDesc% = Install_Mouse, BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&030D
%MM_TrackpadClass_DeviceDesc% = Install_Mouse, BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0310
%MM_v3_DeviceDesc% = Install_Mouse, BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0323
```

PID 0x0310 is included to bind any Magic Mouse advertising as the "trackpad-class" hardware ID even though the user owns the standard v1 (0x030D); this matches the applewirelessmouse INF behaviour and forecloses the over-match issue.

### 4b. Service registration and filter binding

```
[Install_Mouse]
CopyFiles = DriverFiles

[Install_Mouse.HW]
AddReg = AddReg_LowerFilter

[AddReg_LowerFilter]
HKR,,"LowerFilters",0x00010008,"M12"   ; FLG_ADDREG_TYPE_MULTI_SZ|FLG_ADDREG_APPEND
                                        ; service key name short-form 'M12'
                                        ; binary on disk is MagicMouseDriver.sys

[Install_Mouse.Services]
AddService = M12, 0x00000002, ServiceInstall

[ServiceInstall]
DisplayName   = %ServiceDesc%
ServiceType   = 1                ; SERVICE_KERNEL_DRIVER
StartType     = 3                ; SERVICE_DEMAND_START
ErrorControl  = 1                ; SERVICE_ERROR_NORMAL
ServiceBinary = %12%\MagicMouseDriver.sys
```

Note (per Senior MIN-5): `applewirelessmouse` must be removed from LowerFilters BEFORE M12 install. M12's INF appends; if applewirelessmouse is still bound, BOTH filters end up on the stack and behaviour is undefined. MOP step INSTALL-1 enforces removal.

### 4c. Class

```
Class       = HIDClass
ClassGuid   = {745A17A0-74D3-11D0-B6FE-00A0C90F57DA}
```

The filter sits on the HID-class GUID stack (per AP-16 lesson: filter binding lives on `{00001124-...}` LowerFilters of the HID-class device, not the BT-service GUID).

### 4d. Include / Needs

```
Include = input.inf, hidbth.inf
Needs   = HID_Inst.NT, HID_Inst.NT.Services
```

Same as applewirelessmouse and MU. Ensures HidClass is registered as the function driver of record; M12 sits below it as a lower filter without taking ownership.

### 4e. PnpLockdown

`PnpLockdown=1`. Standard.

### 4f. Strings

`Provider`, `DeviceDesc`, `ServiceDesc` are M12-specific. No reuse of Apple or Magic Utilities trademarks.

---

## 5. HID descriptor: Descriptor B verbatim (no mutation)

M12 does NOT mutate the descriptor delivered to HidClass. The applewirelessmouse-published (Apple-firmware-native) 116-byte HID descriptor — which HidBth fetches via SDP and HidClass parses — remains unchanged.

The descriptor bytes are documented here for completeness, byte-for-byte from `applewirelessmouse.sys` offset 0xa850, cross-validated against the empirical Windows HID caps capture and the HID-protocol validation review.

```
05 01 09 02 A1 01    UsagePage(GenericDesktop), Usage(Mouse), Collection(Application)

  85 02              ReportID(0x02) — Input mouse/scroll
  -- 2-button mouse --
  05 09 19 01 29 02  UsagePage(Button), UsageMin(1), UsageMax(2)
  15 00 25 01        Logical Min(0), Max(1)
  95 02 75 01 81 02  Count(2), Size(1), Input(Data,Variable,Absolute)
  95 01 75 05 81 03  Count(1), Size(5), Input(Constant) — 5-bit padding
  -- vendor const bit --
  06 02 FF 09 20     UsagePage(Vendor 0xFF02), Usage(0x20)
  95 01 75 01 81 03  Count(1), Size(1), Input(Constant) — 1-bit Apple vendor
  -- X/Y axes --
  05 01 09 01 A1 00  UsagePage(GenericDesktop), Usage(Pointer), Collection(Physical)
  15 81 25 7F        Logical Min(-127), Max(127)
  09 30 09 31        Usage(X), Usage(Y)
  75 08 95 02 81 06  Size(8), Count(2), Input(Data,Variable,Relative)
  -- AC Pan (horizontal scroll, 8-bit) --
  05 0C 0A 38 02     UsagePage(Consumer), Usage(AC Pan = 0x0238)
  75 08 95 01 81 06  Size(8), Count(1), Input(Data,Variable,Relative)
  -- Wheel (vertical scroll, 8-bit) --
  05 01 09 38        UsagePage(GenericDesktop), Usage(Wheel = 0x38)
  75 08 95 01 81 06  Size(8), Count(1), Input(Data,Variable,Relative)
  C0                 End Collection (Physical/Pointer)

  -- Feature 0x47: synthesised battery percentage --
  05 06 09 20        UsagePage(0x06 Generic Device), Usage(0x20 Battery Strength)
  85 47              ReportID(0x47)
  15 00 25 64        Logical Min(0), Max(100)
  75 08 95 01 B1 A2  Size(8), Count(1), Feature(Data,Variable,Absolute,NoPreferred,NoNull)

  -- RID=0x27: vendor blob input pass-through (46 bytes) --
  05 06 09 01        UsagePage(0x06 Generic Device), Usage(0x01 BatteryStrength alt)
  85 27              ReportID(0x27)
  15 01 25 41        Logical Min(1), Max(65)
  75 08 95 2E        Size(8), Count(46)
  81 06              Input(Data,Variable,Relative)

C0                   End Collection (Application)
```

Total: 116 bytes. RID=0x02 on-wire = 6 bytes (1 RID + 5 payload). RID=0x27 on-wire = 47 bytes. RID=0x47 on-wire = 2 bytes Feature.

### 5a. Why this descriptor (and not Mode A)

- **Native scroll works as-is.** RID=0x02 declared with 8-bit X/Y/Pan/Wheel. HidClass parses it natively into a standard mouse input stream. No M12 code in the scroll path.
- **Feature 0x47 IS declared.** This is the senior dev MAJ-1 concern: HidClass gates IOCTL_HID_GET_FEATURE on descriptor declarations. Descriptor B declares 0x47 explicitly, so HidClass forwards the IRP and M12 can intercept.
- **RID=0x27 vendor blob is declared as Input.** This is what surfaces the 46-byte vendor payload to the HID input stream so M12 can tap it via `IOCTL_HID_READ_REPORT` completion. Without this RID in the descriptor, the device would still send the 0x27 frame but HidClass might filter or drop it.
- **No Resolution Multiplier features.** M12 does not implement Mode A high-resolution scroll. This is a deliberate tradeoff vs MU: simpler, smaller, no scroll synthesis, but standard scroll precision instead of 120-units-per-detent.

### 5b. Descriptor validation gate

Pre-install: hidparser.exe (EWDK) parses the 116-byte literal and confirms:
- TLC: UsagePage=0x0001 Usage=0x0002 (Mouse)
- Report lengths: Input=47 (max, RID=0x27), Output=0, Feature=2
- Counts: LinkColl=2 (App + Physical), InpBC=1 (Button 1-2), InpVC=4 (X, Y, Pan, Wheel) + 1 (RID=0x27 vendor strength), FeatVC=1 (battery)

Mismatch = halt before signtool.

---

## 6. Translation algorithm: NONE for input flows

M12 does NOT translate RID=0x02 (mouse/scroll) or RID=0x12/0x29 (touch — not used). All native input flows pass through unmodified. The only translation in M12 is the 1-byte battery byte:

```c
UCHAR TranslateBatteryRaw(UCHAR raw) {
    // Hypothesised formula per HID-protocol-validation review.
    // Descriptor declares RID=0x27 Logical Min=1, Max=65.
    // Empirical confirmation needed post-install.
    if (raw < 1)  return 0;
    if (raw > 65) return 100;
    return (UCHAR)(((ULONG)raw - 1) * 100 / 64);
}
```

Examples: raw=1 -> 0%; raw=33 -> 50%; raw=65 -> 100%.

This is intentionally a small standalone function so that if empirical capture shows non-linearity (lookup table needed), only this function changes — no structural rewrite.

The byte offset within the 46-byte payload is not yet known empirically (RID=0x27 empirical review BLOCKED). M12 reads `shadow_buffer[BATTERY_OFFSET]` where `BATTERY_OFFSET` is read from registry at `EvtDeviceAdd` time:

```
HKLM\SYSTEM\CurrentControlSet\Services\M12\Parameters
    BATTERY_OFFSET (REG_DWORD, default = 1)
```

Default of 1 = first byte of the 46-byte payload (i.e., shadow_buffer[1] if RID byte is at offset 0). Operator can update via `reg add` and `pnputil /disable-device + /enable-device` cycle without recompile.

---

## 7. Battery synthesis: short-circuit Feature 0x47 from shadow buffer

### 7a. Shadow buffer (the only state)

```c
typedef struct _SHADOW_BUFFER {
    UCHAR        Payload[46];    // RID=0x27 vendor data (excluding RID byte)
    LARGE_INTEGER Timestamp;     // KeQuerySystemTime when last updated
    BOOLEAN      Valid;          // TRUE once first RID=0x27 received
} SHADOW_BUFFER, *PSHADOW_BUFFER;
```

Allocated in DEVICE_CONTEXT, initialised zero in EvtDeviceAdd, accessed under `KSPIN_LOCK` (`ShadowLock`). 46 bytes (not the full 47) because the RID byte (0x27) is identical for every frame and not stored.

### 7b. Tap from RID=0x27 input (Flow 1, completion routine)

```c
// Registered as completion routine for IOCTL_HID_READ_REPORT IRPs forwarded to IoTarget.
EVT_WDF_REQUEST_COMPLETION_ROUTINE OnReadComplete;

VOID OnReadComplete(WDFREQUEST Request, WDFIOTARGET Target,
                    PWDF_REQUEST_COMPLETION_PARAMS Params, WDFCONTEXT Ctx) {
    PDEVICE_CONTEXT dctx = (PDEVICE_CONTEXT)Ctx;
    NTSTATUS s = Params->IoStatus.Status;
    if (!NT_SUCCESS(s)) return;  // upstream sees failure unchanged

    // METHOD_NEITHER for IOCTL_HID_READ_REPORT — buffer in HID_XFER_PACKET.
    HID_XFER_PACKET *pkt = (HID_XFER_PACKET *)Params->Parameters.Others.Arg1;
    if (pkt == NULL || pkt->reportBuffer == NULL) return;

    // Buffer layout: [0]=RID, [1..N]=payload.
    if (pkt->reportBuffer[0] != 0x27) return;
    if (pkt->reportBufferLen < 47) return;  // need RID + 46 payload bytes

    KIRQL irql;
    KeAcquireSpinLock(&dctx->ShadowLock, &irql);
    RtlCopyMemory(dctx->Shadow.Payload, &pkt->reportBuffer[1], 46);
    KeQuerySystemTime(&dctx->Shadow.Timestamp);
    dctx->Shadow.Valid = TRUE;
    KeReleaseSpinLock(&dctx->ShadowLock, irql);

    // No mutation of upstream IRP. IoTarget already completed it.
}
```

Notes:
- Completion routine never modifies the IRP buffer that flows upstream. The framework handles upstream completion. M12 only reads.
- Verification: senior CRIT-1 (UAF / double-complete) does not apply — M12 doesn't complete here.
- F13 (BT disconnect mid-IRP): if Status indicates failure or Cancel, we early-out and let the framework's upstream completion proceed. EvtIoStop handles in-flight IRPs (Sec 8).

### 7c. Feature 0x47 short-circuit (Flow 2)

```c
NTSTATUS HandleGetFeature47(WDFREQUEST req, PDEVICE_CONTEXT dctx) {
    WDF_REQUEST_PARAMETERS params;
    WDF_REQUEST_PARAMETERS_INIT(&params);
    WdfRequestGetParameters(req, &params);

    // METHOD_NEITHER: HID_XFER_PACKET in Type3InputBuffer (Arg1).
    HID_XFER_PACKET *pkt = (HID_XFER_PACKET *)params.Parameters.Others.Arg1;
    if (pkt == NULL || pkt->reportBuffer == NULL || pkt->reportBufferLen < 2) {
        WdfRequestComplete(req, STATUS_INVALID_PARAMETER);
        return STATUS_INVALID_PARAMETER;
    }
    if (pkt->reportId != 0x47) {
        // Wrong RID — forward downstream (defensive; HidClass should never send other RIDs here).
        return ForwardRequest(req, dctx);
    }

    UCHAR raw;
    BOOLEAN valid;
    LARGE_INTEGER ts;
    KIRQL irql;
    KeAcquireSpinLock(&dctx->ShadowLock, &irql);
    valid = dctx->Shadow.Valid;
    raw = dctx->Shadow.Payload[dctx->BatteryOffset];
    ts = dctx->Shadow.Timestamp;
    KeReleaseSpinLock(&dctx->ShadowLock, irql);

    // Debug log: cached payload first 46 bytes hex (every Feature 0x47 query)
    // for empirical post-install offset/formula validation.
    LogShadowBuffer(dctx);

    if (!valid) {
        // First-boot, no RID=0x27 received yet.
        // Default policy: STATUS_DEVICE_NOT_READY -> tray shows N/A.
        // Registry-tunable: FirstBootPolicy=0 (NOT_READY) | 1 (return [0x47, 0x00])
        if (dctx->FirstBootPolicy == 1) {
            pkt->reportBuffer[0] = 0x47;
            pkt->reportBuffer[1] = 0;
            WdfRequestSetInformation(req, 2);
            WdfRequestComplete(req, STATUS_SUCCESS);
            return STATUS_SUCCESS;
        }
        WdfRequestComplete(req, STATUS_DEVICE_NOT_READY);
        return STATUS_DEVICE_NOT_READY;
    }

    UCHAR pct = TranslateBatteryRaw(raw);
    pkt->reportBuffer[0] = 0x47;
    pkt->reportBuffer[1] = pct;
    WdfRequestSetInformation(req, 2);
    WdfRequestComplete(req, STATUS_SUCCESS);
    return STATUS_SUCCESS;
}
```

Notes:
- Inline complete. NEVER forward to IoTarget. CRIT-2 (sync-send deadlock) does not apply.
- METHOD_NEITHER buffer retrieval per MAJ-3.
- Shadow buffer staleness check: optional. Default policy is "always serve cache regardless of age" because (a) v3 emits RID=0x27 ~10/sec when in use; cache stays warm, and (b) when mouse is idle for >30s the user probably isn't watching the tray either. A future tunable `MAX_STALE_MS` could return STATUS_DEVICE_NOT_READY if `now - ts > MAX_STALE_MS`; out of scope for v1.2 default.

### 7d. PID branch for Feature 0x47 (restored in v1.3 per NLM pass-2 NEW-1)

v1 and v3 use DIFFERENT paths. v1 firmware natively backs Feature 0x47 — that's the working PRD-184 M2 baseline (existing tray code reads v1 battery via `HidD_GetFeature(0x47)` against native firmware, returns the actual battery percentage). Routing v1 through M12's shadow-buffer short-circuit risks regression because (a) v1 may not emit RID=0x27 frames at all in normal operation (v1 firmware has a working 0x47, no need to push 0x27), and (b) even if v1 emits 0x27, the byte layout may differ from v3.

```c
NTSTATUS HandleGetFeature47(WDFREQUEST req, PDEVICE_CONTEXT dctx) {
    WDF_REQUEST_PARAMETERS params;
    WDF_REQUEST_PARAMETERS_INIT(&params);
    WdfRequestGetParameters(req, &params);

    HID_XFER_PACKET *pkt = (HID_XFER_PACKET *)params.Parameters.Others.Arg1;
    if (pkt == NULL || pkt->reportBuffer == NULL || pkt->reportBufferLen < 2) {
        WdfRequestComplete(req, STATUS_INVALID_PARAMETER);
        return STATUS_INVALID_PARAMETER;
    }
    if (pkt->reportId != 0x47) {
        return ForwardRequest(req, dctx);
    }

    // PID branch — v1.3
    if (dctx->Pid == 0x030D || dctx->Pid == 0x0310) {
        // v1 firmware natively backs Feature 0x47 — pass-through.
        // Preserves PRD-184 M2 working baseline.
        return ForwardRequest(req, dctx);
    }

    if (dctx->Pid != 0x0323) {
        // Defensive — INF should not have matched any other PID.
        WdfRequestComplete(req, STATUS_DEVICE_CONFIGURATION_ERROR);
        return STATUS_DEVICE_CONFIGURATION_ERROR;
    }

    // v3 short-circuit (rest of HandleGetFeature47 from Section 7c)
    // ... shadow buffer read + STATUS_DEVICE_NOT_READY check (with MAX_STALE_MS) +
    //     TranslateBatteryRaw + WdfRequestComplete(req, STATUS_SUCCESS) ...
}
```

The shadow buffer is STILL populated for both v1 and v3 by the OnReadComplete tap (Section 7b) — that's a passive read-only side-effect with no IRP cost — but only v3's Feature 0x47 reads from it. v1 ignores the shadow entirely and lets the native firmware path serve the IRP. If empirical evidence later shows v1's RID=0x27 layout matches v3's and short-circuiting v1 has a benefit (e.g., unified behaviour during sleep/wake), the v1 path can be flipped to short-circuit by changing the PID branch — no other structural change.

### 7e. Shadow staleness threshold (v1.3, default REVISED per NLM pass-3)

`MAX_STALE_MS` registry tunable at `\Registry\Machine\System\CurrentControlSet\Services\M12\Parameters\MAX_STALE_MS` (REG_DWORD, **default 0 = disabled**). v3 short-circuit checks:

```c
if (dctx->MaxStaleMs != 0) {
    LONGLONG age_ms = (now.QuadPart - ts.QuadPart) / 10000;
    if (age_ms > dctx->MaxStaleMs) {
        WdfRequestComplete(req, STATUS_DEVICE_NOT_READY);
        return STATUS_DEVICE_NOT_READY;
    }
}
```

**Default DISABLED rationale (NLM pass-3 fix):** v3 mouse goes to sleep after ~2 minutes of inactivity (BT disconnect, no further RID=0x27 frames pushed). Tray polls every 2 hours when battery > 50%. A 10-sec staleness threshold would cause the tray to see NOT_READY almost every poll because the mouse hasn't sent fresh data. The user would see "N/A" instead of the last known battery percentage — significantly worse UX than serving slightly-stale-but-accurate-as-of-last-input data.

The mouse only stops sending RID=0x27 because it is asleep; battery percentage cannot have changed materially in that window. The cached value remains authoritative.

**Operator can opt-in to staleness check** by setting `MAX_STALE_MS` to a non-zero value (recommended: 7200000 = 2 hours, matching tray's max poll interval). Reserved for cases where empirical data shows the cache becoming corrupted across long sleep windows.

**Pairs with OQ-D (advisory):** if VG-7 soak reveals persistent N/A windows >5min on v3 cold-start (no input has happened since boot/wake to populate shadow), consider implementing the soft async active-poll. Without an active wake, the passive shadow buffer cannot resolve its own emptiness on cold-start. v1.3 ships without active-poll; cold-start N/A is accepted until first user input.

---

## 8. WDF queue layout

| Queue | Dispatch | What it handles |
|-------|----------|-----------------|
| Default queue | parallel | All IRPs by default; forwards to specialised queues by IOCTL major function code |
| Sequential IOCTL queue | sequential | `IOCTL_HID_GET_FEATURE` ONLY — Feature 0x47 short-circuit |
| Parallel input queue | parallel | `IOCTL_HID_READ_REPORT` — input report stream (forward + tap on completion) |

`WdfIoQueueCreate` is called twice. Forwarding from default queue to specialised queues uses `WdfDeviceConfigureRequestDispatching` keyed on `IRP_MJ_INTERNAL_DEVICE_CONTROL` major code.

### 8a. EvtIoStop registered on both specialised queues (CRIT-3 fix)

```c
VOID EvtIoStop_Sequential(WDFQUEUE q, WDFREQUEST req, ULONG flags) {
    UNREFERENCED_PARAMETER(q);
    UNREFERENCED_PARAMETER(flags);
    // Feature 0x47 handler is short and PASSIVE_LEVEL — drains quickly.
    // Acknowledge without requeue.
    WdfRequestStopAcknowledge(req, FALSE);
}

VOID EvtIoStop_Parallel(WDFQUEUE q, WDFREQUEST req, ULONG flags) {
    UNREFERENCED_PARAMETER(q);
    UNREFERENCED_PARAMETER(flags);
    // Read IRPs were forwarded with completion routine; framework cancels
    // the IoTarget request on stop. Acknowledge.
    WdfRequestStopAcknowledge(req, FALSE);
}
```

### 8b. EvtDeviceSelfManagedIoSuspend (CRIT-3)

```c
NTSTATUS EvtDeviceSelfManagedIoSuspend(WDFDEVICE device) {
    PDEVICE_CONTEXT dctx = GetDeviceContext(device);
    WdfIoTargetStop(dctx->IoTarget, WdfIoTargetCancelSentIo);
    // Mark shadow as invalid so post-resume the next RID=0x27 frame populates fresh data.
    KIRQL irql;
    KeAcquireSpinLock(&dctx->ShadowLock, &irql);
    dctx->Shadow.Valid = FALSE;
    KeReleaseSpinLock(&dctx->ShadowLock, irql);
    return STATUS_SUCCESS;
}

NTSTATUS EvtDeviceSelfManagedIoRestart(WDFDEVICE device) {
    PDEVICE_CONTEXT dctx = GetDeviceContext(device);
    return WdfIoTargetStart(dctx->IoTarget);
}
```

---

## 9. Function signatures

```c
// Driver.c
NTSTATUS DriverEntry(_In_ PDRIVER_OBJECT DriverObject, _In_ PUNICODE_STRING RegistryPath);
EVT_WDF_DRIVER_DEVICE_ADD EvtDriverDeviceAdd;
EVT_WDF_OBJECT_CONTEXT_CLEANUP EvtDriverContextCleanup;

// EvtDeviceAdd.c
NTSTATUS EvtDeviceAdd(_In_ WDFDRIVER Driver, _Inout_ PWDFDEVICE_INIT DeviceInit);
NTSTATUS QueryHardwareIdAndStorePid(_In_ WDFDEVICE Device, _Out_ PDEVICE_CONTEXT Ctx);
NTSTATUS ReadRegistryTunables(_In_ WDFDEVICE Device, _Out_ PDEVICE_CONTEXT Ctx);
NTSTATUS CreateQueues(_In_ WDFDEVICE Device);
EVT_WDF_DEVICE_SELF_MANAGED_IO_SUSPEND  EvtDeviceSelfManagedIoSuspend;
EVT_WDF_DEVICE_SELF_MANAGED_IO_RESTART  EvtDeviceSelfManagedIoRestart;

// IoctlHandlers.c
EVT_WDF_IO_QUEUE_IO_INTERNAL_DEVICE_CONTROL EvtIoInternalDeviceControl_Sequential;
EVT_WDF_IO_QUEUE_IO_INTERNAL_DEVICE_CONTROL EvtIoInternalDeviceControl_Parallel;
EVT_WDF_IO_QUEUE_IO_STOP                    EvtIoStop_Sequential;
EVT_WDF_IO_QUEUE_IO_STOP                    EvtIoStop_Parallel;
NTSTATUS HandleGetFeature47(_In_ WDFREQUEST Req, _In_ PDEVICE_CONTEXT Ctx);
NTSTATUS ForwardRequest(_In_ WDFREQUEST Req, _In_ PDEVICE_CONTEXT Ctx);
EVT_WDF_REQUEST_COMPLETION_ROUTINE OnReadComplete;

// Battery.c
UCHAR TranslateBatteryRaw(_In_ UCHAR Raw);
VOID  LogShadowBuffer(_In_ PDEVICE_CONTEXT Ctx);

// BrbDescriptor.c (v1.3 — fresh-pair fallback)
EVT_WDF_REQUEST_COMPLETION_ROUTINE OnBrbSubmitComplete;
NTSTATUS RewriteSdpHidDescriptorList(
    _Inout_updates_bytes_(BufferLen) PUCHAR Buffer,
    _In_ size_t BufferLen,
    _Out_ PBOOLEAN Rewritten);
BOOLEAN ScanForReportId47(_In_reads_bytes_(Len) PUCHAR Bytes, _In_ size_t Len);
```

### 9a. Pool tag (MAJ-5 fix)

```c
// Driver.h
#define M12_POOL_TAG 'M12 '   /* ASCII "M12 ", little-endian = 0x2032314D */
```

All M12 manual `ExAllocatePool2` calls use `M12_POOL_TAG`. WinDbg post-install: `!poolused 4 'M12 '` enumerates allocations.

### 9b. NX pool

All non-paged allocations use `POOL_FLAG_NON_PAGED` (not `POOL_FLAG_NON_PAGED_EXECUTE`) per Driver Verifier compatibility for KMDF 1.33 (and forward-compatible to 1.15 via `ExAllocatePool2` shim). Senior review's "NonPagedPoolNx" recommendation captured.

---

## 10. Data structures

### 10a. DEVICE_CONTEXT

```c
typedef struct _DEVICE_CONTEXT {
    WDFDEVICE      Device;
    WDFIOTARGET    IoTarget;            // == WdfDeviceGetIoTarget(Device); set in EvtDeviceAdd
    WDFQUEUE       IoctlQueue;          // sequential
    WDFQUEUE       ReadQueue;           // parallel

    USHORT         Vid;
    USHORT         Pid;                 // 0x030D / 0x0310 / 0x0323

    // Battery shadow (the only mutable state)
    KSPIN_LOCK     ShadowLock;
    SHADOW_BUFFER  Shadow;

    // Tunables (read once from registry at AddDevice; defaults if absent)
    ULONG          BatteryOffset;       // default 1
    ULONG          FirstBootPolicy;     // 0=NOT_READY (default), 1=return 0%
    ULONG          MaxStaleMs;          // default 0 = no staleness check (v1.3 final per NLM pass-3 — 10s default UX-regressed when mouse asleep)

    // BRB rewriter telemetry (v1.3)
    BOOLEAN        DescriptorBRewritten;  // set TRUE after first successful BRB SDP rewrite
                                          // VG-0 reads this to distinguish fresh-pair from stale-cache
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;
WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, GetDeviceContext)
```

### 10b. SHADOW_BUFFER

```c
typedef struct _SHADOW_BUFFER {
    UCHAR         Payload[46];
    LARGE_INTEGER Timestamp;
    BOOLEAN       Valid;
} SHADOW_BUFFER, *PSHADOW_BUFFER;
```

No REQUEST_CONTEXT needed in v1.2 — M12 does not stash per-IRP state.

---

## 11. Failure modes

| # | Failure | Symptom | Mitigation |
|---|---------|---------|------------|
| F1 | RID=0x27 byte offset wrong | Battery reads return wrong percentage | `BATTERY_OFFSET` registry-tunable (Sec 7); LogShadowBuffer logs cached bytes on every Feature 0x47 query — operator runs ETW/HCI sniff at known battery levels, computes offset, updates registry, re-binds. No code change. |
| F2 | First-boot Feature 0x47 before any RID=0x27 received | `STATUS_DEVICE_NOT_READY`, tray N/A briefly | Default policy returns NOT_READY; tray retries on next adaptive interval. Registry-tunable `FirstBootPolicy=1` forces `[0x47, 0x00]` if tray cannot tolerate retries. |
| F3 | v1 regression: M12 modifies v1's working Feature 0x47 | v1 tray shows N/A or wrong % after install | Same path for v1 and v3 (Sec 7d); v1 vendor blob populates shadow same as v3. Registry tunable allows v1-specific BATTERY_OFFSET if needed. Validation gate VG-1 (MOP) — v1 must produce `OK battery=N% (Feature 0x47)` BEFORE v3 testing. v1 regression halts rollout. |
| F4 | RID=0x27 not declared in cached SDP descriptor | Shadow buffer never populates | applewirelessmouse-published descriptor declares RID=0x27 (verified, Sec 5). If an old/non-matching firmware variant doesn't, M12 logs and falls back to FirstBootPolicy=1. |
| F5 | Shadow read while completion routine writes (race) | Torn 46-byte read | KSPIN_LOCK on every read/write. Standard. |
| F6 | Memory pressure: HID_XFER_PACKET buffer NULL | IOCTL fails | Defensive NULL/length check; complete with STATUS_INVALID_PARAMETER. HidClass retries or surfaces upstream. |
| F7 | Descriptor parse fails post-install | HidClass FDO doesn't bind | Pre-install: `hidparser.exe` validates the 116-byte descriptor pre-signtool. M12 doesn't actually serve the descriptor — applewirelessmouse-style cached SDP does — but the validation confirms the bytes M12's code reasons about match the device's published descriptor. |
| F8 | Driver sees PID outside {0x030D, 0x0310, 0x0323} | Spurious DEVICE_CONTEXT | INF won't match. Defensive PID check at EvtDeviceAdd; return STATUS_DEVICE_CONFIGURATION_ERROR if INF was over-ridden manually. |
| F9 | Concurrent Feature 0x47 callers | Double-complete? Lost update? | Sequential IOCTL queue serialises. Spinlock is read-only side. No risk. |
| F10 | DSM property-write triggers re-enumeration mid-session | EvtDeviceRemove + Add cycle; shadow lost | Acceptable — shadow re-warms within 100ms once first RID=0x27 arrives. Brief NOT_READY visible. |
| F11 | PnP rank: M12 INF outranked by Apple's `applewirelessmouse` or MU's `magicmouse.inf` | Old driver wins | MOP step INSTALL-1: `pnputil /enum-drivers` enumeration BEFORE install; if competing INFs present, MOP halts and asks user; AP-24 backup-verify gate before any `/delete-driver`. |
| F12 | WDF version skew: KMDF 1.33 vs older target | Driver fails to load, error 31 | KMDF version pinned in vcxproj to 1.15 (matches MU + applewirelessmouse + OS minimum). |
| F13 | BTHPORT SDP cache trap (less critical in v1.2) | M12 expects descriptor X but cache serves descriptor Y | v1.2 doesn't mutate descriptor; whatever HidBth has cached IS what HidClass parses. VG-0 verifies caps Input=47/Feature=2/LinkColl=2. If caps mismatch (e.g., a competing filter previously injected something else): unpair + re-pair. |
| F14 | Sequential queue stalls on long-running IRP | UI stutter | v1.2 Feature 0x47 handler is inline and fast (single spinlock + memcpy + arithmetic). No downstream send. F14 risk eliminated. |
| F15 | EvtIoStop not called (CRIT-3) | BSOD on BT disconnect | EvtIoStop registered on both queues + EvtDeviceSelfManagedIoSuspend (Sec 8). Driver Verifier gates this. |
| F16 | Registry BATTERY_OFFSET set to 46 (out of bounds) | Reads past payload[45] | Validate at registry-read time: clamp to [0..45]; default if out-of-range. |
| F17 | Cached SDP descriptor doesn't include RID=0x27 (very old applewirelessmouse pre-firmware) | Shadow buffer never receives 0x27 frames | LogShadowBuffer always logs "Shadow.Valid=FALSE" -> operator notices in debug.log; MOP VG-0 fails caps check. Mitigation: re-pair via Path B with fresh SDP. |

---

## 12. Open questions

OQ-A through OQ-E from v1.1 are simplified or removed in v1.2:

- **OQ-1 (v1.1) v3 input 0x12 padding bytes:** REMOVED — M12 doesn't parse 0x12.
- **OQ-2 (v1.1) cache hit ratio for active-poll:** REMOVED — no active-poll.
- **OQ-3 (v1.1) tray expects 1-byte vs 2-byte Feature 0x47 response:** RESOLVED — tray reads `buf[1]` for pct in unified path (descriptor declares 1-byte field; on-wire 2-byte report). Confirmed in HID-protocol-validation review.
- **OQ-4 (v1.1) PID 0x0310 binding:** UNCHANGED — log on first AddDevice for visibility.
- **OQ-5 (v1.1) Resolution Multiplier features:** REMOVED — not in v1.2 descriptor.

New open questions in v1.2:

- **OQ-A:** Battery byte offset within RID=0x27 46-byte payload. Phase 1 RID=0x27 empirical capture was BLOCKED (ETW didn't preserve payloads). Default `BATTERY_OFFSET=1` (first byte after RID); confirm post-install via debug.log diff at known battery levels (target: spec a 100%-vs-20% diff session as a Phase 3 validation step in PRD).
- **OQ-B:** Translation formula linearity. Hypothesis `(raw - 1) * 100 / 64`. If post-install logs show non-linear distribution (e.g., raw clusters at discrete values like 1, 13, 25, 37, 49, 65), replace `TranslateBatteryRaw` with a lookup table. No structural change required.
- **OQ-C:** Shadow staleness. v1.3 introduces `MAX_STALE_MS` registry tunable (default 10000 ms). If 24-hr soak (VG-7) shows users seeing N/A frequently when mouse is briefly idle, raise threshold or set to 0 (no check) at `Parameters` subkey.
- **OQ-D:** Soft active-poll for cold-start (advisory, future work). If VG-7 reveals persistent N/A windows >5min on v3 cold-start, consider an async (non-blocking) downstream `IOCTL_HID_GET_INPUT_REPORT` for ReportID 0x90 issued from EvtDeviceAdd to wake the firmware. Must be careful not to re-introduce CRIT-2 deadlock — async pattern with held request reference + short timeout. Out of scope for v1.3.
- **OQ-E:** v1 short-circuit re-evaluation. v1.3 ships v1 as pass-through. If post-install soak shows v1 also benefits from short-circuit (e.g., during BT reconnect when v1 firmware stalls on Feature 0x47), the PID branch in Section 7d can be flipped to short-circuit v1 too. Empirical decision; out of scope for design.

---

## 13. References

### Primary references (clean-room, public)

- Microsoft Learn — KMDF Filter Drivers, HID Architecture.
- USB-IF HID 1.11 spec (descriptor encoding).
- Linux kernel `drivers/hid/hid-magicmouse.c` (GPL-2) — algorithm reference for v3 0x12 input format. NOT used in M12 v1.2 (no scroll synthesis); retained for record.

### Captured artefacts (this project)

- `D:\Backups\AppleWirelessMouse-RECOVERY\applewirelessmouse.sys` — primary M12 architectural baseline.
  - Descriptor B at offset 0xa850 (116 bytes) — verbatim spec source.
  - 37 imports, 0 BCrypt — confirms pure-kernel-only viability.
  - See `M12-APPLEWIRELESSMOUSE-FINDINGS.md` (`ai-m12-ghidra-applewirelessmouse` worktree).
- `D:\Backups\MagicUtilities-Capture-2026-04-28-1937\` — MU 3.1.5.2 reverse-engineering reference (BCrypt obfuscation, license gate, BRB filter pattern, Descriptor B at 0x1405af110). Used for understanding MU's complexity and confirming what M12 OMITS.
  - See `M12-GHIDRA-FINDINGS-EXTENDED.md` (`ai-m12-ghidra-magicmouse-extended` worktree).
- `.ai/test-runs/2026-04-27-154930-T-V3-AF/hid-descriptor-full-v3-col01.txt` — empirical Mode B HID caps (control comparison).
- `M12-HID-PROTOCOL-VALIDATION-2026-04-28.md` (`ai-m12-hid-protocol-validation` worktree) — descriptor item-by-item parse, RID semantics confirmation.
- `M12-RID27-EMPIRICAL-2026-04-28.md` (`ai-m12-rid27-empirical` worktree) — battery byte offset BLOCKED, registry-tunable approach recommended.
- `M12-SENIOR-DRIVER-REVIEW-2026-04-28.md` (`ai-m12-senior-driver-review` worktree) — 4 critical, 5 major, 5 minor issues, all addressed in v1.2.

### Decision documents

- `Personal/prd/184-magic-mouse-windows-tray-battery-monitor.md` v1.27.
- `magic-mouse-tray/PSN-0001-hid-battery-driver.yaml` v1.9.
- `magic-mouse-tray/.ai/playbooks/autonomous-agent-team.md` v1.8.
- `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-2026-04-28.md` (NLM pass-1).
- `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS2-2026-04-28.md` (NLM pass-2).

### Legal basis (interoperability exemptions)

- USA: `17 U.S.C. section 1201(f)` (DMCA interoperability exemption).
- Canada: `R.S.C. 1985, c. C-42, s. 30.61` (Copyright Act interoperability exemption).
- EU: Software Directive 2009/24/EC Article 6 (decompilation for interoperability).

Interoperability target: Apple Magic Mouse hardware. M12 is independently authored. Captured artefacts are read for facts (API patterns, report formats, descriptor bytes); no expression is copied. The 116-byte HID descriptor is the device's published descriptor surface (firmware-emitted); M12 does not modify it but reads it for structural reference.
