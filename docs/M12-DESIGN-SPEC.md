# M12 Design Specification

**Status:** v1.6 — DRAFT pending user approval (v1.5 + three final additions folded in)
**License:** MIT (Copyright (c) 2026 Lesley Murfin / Revive Business Solutions)
**Date:** 2026-04-28
**Linked PRD:** PRD-184 v1.31
**Linked PSN:** PSN-0001 v1.9
**Linked NLM pass-1:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-2026-04-28.md`
**Linked NLM pass-2:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS2-2026-04-28.md`
**Linked NLM pass-3:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS3-2026-04-28.md`
**Linked NLM pass-4:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS4-2026-04-28.md`
**Approval gate:** PR ai/m12-design-prd-mop must be approved by user before any code is written.

## Revision history

- **v1.6 (2026-04-28, final additions iteration):** Three final additions folded in. (a) Section 6c: Self-tuning battery offset detection -- on first install (BatteryByteOffset unset or 0xFF), driver enters LEARNING mode, captures up to 100 RID=0x27 frames over 5 minutes, identifies the byte position whose values cluster in [1..65] with low variance, writes result to CRD config, exits LEARNING mode. Removes manual DebugLevel=4 step for typical case. CRD additions: BatteryByteOffset REG_DWORD (0xFFFFFFFF = auto-learn), LearningModeFramesRequired (default 100), LearningModeMaxDurationSec (default 300). LEARNING_STATE struct added to DEVICE_CONTEXT. ~50 LOC additional. Decision D-S12-52. (b) docs/PRIVACY-POLICY.md: M12 collects nothing; all logging local-only; no network; no telemetry. Table of log channels (WPP/ETW + DebugLevel=4 + self-tuning state), all user-controlled or in-memory only. How to disable. Companion tray app noted as separate PRD. MIT license noted. Linked from README and KNOWN-ISSUES. Decision D-S12-53. (c) KNOWN-ISSUES.md: AV/EDR flag entry added -- kernel filter driver flagged by Defender/CrowdStrike/SentinelOne; workaround: whitelist M12.sys + INF in Defender/EDR; verify signature; corporate IT path. Safety rationale (open-source, MIT, no network, no persistence beyond service registry, test-signed). Decision D-S12-54. NLM pass-6 SKIPPED per playbook v1.8 cap (no architectural changes -- documentation additions only).
- **v1.5 (2026-04-28, supplement fold-in iteration):** Two supplement briefs folded in that v1.4 did not have access to. (a) `M12-V14-SUPPLEMENT-USER-DECISIONS.md` — auto-reinit on wake (Section 5 addition: `EvtDeviceD0Entry` resets shadow staleness flag + optionally re-issues GET_REPORT for RID=0x27 if mouse responsive; IN v1 scope); battery polling fallback (Section 6 addition: if `last_rid27_timestamp > 60s`, issue explicit BTHID GET_REPORT for RID=0x27 before completing Feature 0x47 query; IN v1 scope); PREfast static analyzer GATING for ship (Section 20); Static Driver Verifier GATING for ship (Section 20); power-saver aggressive defaults SuspendOnDisplayOff=1 + SuspendOnACUnplug=1 (Section 17 defaults table updated); click handling explicitly v2 milestone (Section 16); watchdog 30s/120s confirmed documented. MIT license added to metadata. (b) `M12-V14-UPSTREAM-ISSUES-LESSONS.md` — `.gitattributes` CRLF enforcement for driver source tree (Section 20 addition; driver/.gitattributes content in docs/M12-PHASE-3-PREP.md); KNOWN-ISSUES.md with 6 entries created (docs/KNOWN-ISSUES.md); INSTALL.md testsigning section noted (MOP Section 3a already covers this). NLM pass-5 SKIPPED — per playbook v1.8 cap, v1.5 is the final design ship; corpus-gap REJECT-downgrade will not change with another pass. v1.5 changelog table below.
- **v1.4 (2026-04-28, brief fold-in iteration):** Three briefs folded in that v1.3 did not have access to. (a) `M12-DSM-PNP-CONCERNS-FOR-V1.3.md` — declares INF `DriverVer = 01/01/2027, 1.0.0.0` to win PnP rank against `applewirelessmouse` (04/21/2026, 6.2.0.0) and Magic Utilities (11/05/2024, 3.1.5.3); adds service entry hygiene (`sc.exe delete MagicMouseM12` on uninstall + stale-service detection at install); BTHPORT cache invalidation alternatives (registry delete vs unpair-repair); orphan LowerFilter walk reference; coexistence rank table. (b) `M12-POWER-SAVER-DESIGN.md` — power saver / suspend modes IN v1 scope per user direction 2026-04-28; PoRegisterCallback for display state, AC/DC, sleep, sign-out; vendor suspend command marked as OPEN QUESTION with three resolution paths; passive wake on click; manual suspend custom IOCTL `IOCTL_M12_SUSPEND` METHOD_BUFFERED admin-SDDL; CRD `PowerSaver\` config subkey schema; defaults SuspendOnSignOut=1, SuspendOnSleep=1, SuspendOnShutdown=1, others=0. (c) `M12-PRODUCTION-HYGIENE-FOR-V1.3.md` — WPP/ETW provider declared (levels ERROR/WARNING/INFO/VERBOSE; flags PNP/IO/SHADOW_BUFFER/POWER/IOCTL); per-DEVICE_CONTEXT shadow buffer + spinlock confirmed (multi-mouse safe); F15-F18 disconnect/reconnect failure modes added; Driver Verifier flags expanded to `0x49bb`; IOCTL input validation contract (METHOD_BUFFERED + range checks + admin SDDL); test plan in new `docs/M12-TEST-PLAN.md`; build system = msbuild + EWDK 25H2 (decision documented); compatibility matrix Win11 22H2-25H2 x64 (Win10 + ARM64 deferred); coexistence story; pool tag `'M12 '` + structure signature `'M12-'`; watchdog (30s tick, 120s stall threshold); logging policy DebugLevel 0-4 (default 0; 4 only for empirical-offset workflow). New sections 15-25 added; sections 4 + 11 + 12 + 16 patched. v1.4 changelog table below. NLM pass-4 verdict at `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS4-2026-04-28.md`.
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

### v1.4 changelog (brief-finding -> section)

| Brief finding | Section addressed | Resolution |
|---|---|---|
| DSM Issue 1: PnP rank tie-breaker (Apple INF DriverVer 04/21/2026 wins by date) | Sec 4a, Sec 4g (new), Sec 22 | M12 INF declares `DriverVer = 01/01/2027, 1.0.0.0`. Outranks both `applewirelessmouse` (04/21/2026) and Magic Utilities (11/05/2024) without destructive INF deletion. INSTALL-1 MOP gate verifies LowerFilters post-install via `reg query`. |
| DSM Issue 2: pnputil /remove-device + /scan-devices does not bypass rank | Sec 22, MOP Sec 7 | Rank fix above eliminates the issue at install. Uninstall MOP explicitly deletes M12 INF from DriverStore via `pnputil /delete-driver oem<NN>.inf /uninstall /force` BEFORE re-pairing. |
| DSM Issue 3: Apple INF deletion was destructive (Session 12 incident) | Sec 22, MOP | Rank fix removes need for destructive `/delete-driver /force` on competitor INFs. AP-24 backup-verify gate retained. |
| DSM Issue 4: BTHPORT cached descriptor persists across rebind | Sec 3b' (already in v1.3), MOP Sec 7c-pre Path A | v1.3 already addressed via `IOCTL_INTERNAL_BTH_SUBMIT_BRB` rewriter; v1.4 documents registry-based cache flush alternative `reg delete HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<BD-addr>` (faster than UI unpair) in MOP. |
| DSM Issue 5: Orphan service entries persist after uninstall | Sec 15.2 (new), MOP Sec 7a + Sec 8b | Service name = `MagicMouseM12`. Pre-install: `sc.exe query MagicMouseM12`; if exists with STOPPED state and missing binary, `sc.exe delete` before proceeding. Rollback: explicit `sc.exe delete MagicMouseM12` after pnputil delete-driver. |
| DSM Issue 6: DriverStore staged packages don't auto-clean | Sec 15.4, MOP Sec 7a + Sec 8b | Pre-install: enumerate staged M12 packages via `pnputil /enum-drivers \| findstr MagicMouseM12`; delete pre-existing M12 INF before staging. Rollback: explicit `pnputil /delete-driver` of M12's published name. |
| DSM Issue 7: Sticky LowerFilters on disconnected devices | Sec 15.5, MOP Sec 7d post-install | Registry-walk script `mm-orphan-filter-walk.ps1` (referenced in MOP) lists all `LowerFilters` MULTI_SZ values under v1/v3 BTHENUM device tree; flags any not matching `MagicMouseM12`. |
| Power Saver: power-event registration | Sec 17.1 (new) | `PoRegisterCallback` for `GUID_CONSOLE_DISPLAY_STATE`, `GUID_ACDC_POWER_SOURCE`, `GUID_SYSTEM_AWAYMODE`. KMDF `EvtDeviceD0Entry` / `EvtDeviceD0Exit` for D-state. Sign-out via tray-app SessionChange + IOCTL bridge (kernel can't directly subscribe to user-session events). |
| Power Saver: vendor suspend command bytes | Sec 17.2 (new), Sec 17.6 OQ-F | OPEN QUESTION. Three resolution paths: Ghidra of `MagicMouse.sys` HID Output Report patterns; HCI sniff during MU manual-suspend; trial-and-error candidate command bytes. Fallback: BT disconnect via `WdfIoTargetClose` (less battery-efficient but functional). |
| Power Saver: wake handling | Sec 17.3 (new) | Passive — user clicks mouse, BTHPORT re-establishes connection, RID=0x27 frames resume. `EvtDeviceD0Entry` resets shadow timestamp on wake. |
| Power Saver: manual suspend custom IOCTL | Sec 18 (new) | `IOCTL_M12_SUSPEND` (METHOD_BUFFERED) on M12 device interface GUID. SDDL admin-only. CLI tool `mm-suspend.exe` for v1; tray menu item for v2. |
| Power Saver: CRD config subkey | Sec 17.4 (new) | `HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Devices\<HardwareKey>\PowerSaver\` with Enabled, SuspendOnDisplayOff, SuspendOnACUnplug, SuspendOnSignOut, SuspendOnSleep, SuspendOnShutdown, SuspendCommandBytes (REG_BINARY). Defaults SuspendOnSignOut=1, SuspendOnSleep=1, SuspendOnShutdown=1, others=0. |
| Production Hygiene 1: WPP/ETW tracing | Sec 19 (new) | WPP provider GUID declared in `Driver.h`. Trace levels ERROR/WARNING/INFO/VERBOSE; flags PNP/IO/SHADOW_BUFFER/POWER/IOCTL. `WPP_INIT_TRACING` in DriverEntry. TMF generated at build, distributed alongside .sys. All DbgPrint migrated to DoTraceMessage. |
| Production Hygiene 2: Multi-mouse per-device-context | Sec 9b/10a (already per-DEVICE_CONTEXT in v1.3), Sec 19.2 (clarification) | DEVICE_CONTEXT already per-instance in v1.3; v1.4 explicitly confirms: shadow buffer per-DEVICE_CONTEXT (not global), spinlock per-device, battery configuration loaded per-device from CRD config (PID-keyed). Multiple devices = independent contexts. VG-7 expanded to verify simultaneous v1+v3 read-out. |
| Production Hygiene 3: Disconnect / reconnect resilience | Sec 11 F15-F18 (new entries) | F15: BT disconnect mid-Feature-0x47-query → completes from cache (not failure). F16: Reconnect → first RID=0x27 frame overwrites shadow. F17: Long disconnect (>5 min) → shadow marked stale via timestamp; Feature 0x47 returns last cached value, stale flag in WPP log. F18: Reconnect race → if Feature 0x47 query arrives BEFORE first post-reconnect RID=0x27, return last-cached value. |
| Production Hygiene 4: Driver Verifier 0x49bb | Sec 13 (new), MOP VG-8 | DV target: `verifier /flags 0x49bb /driver MagicMouseDriver.sys`. Decoded: 0x9bb base + 0x10000 security checks + 0x40000 IRP logging. Target: 0 violations across 1000 IOCTL cycles + 100 pair/unpair cycles. |
| Production Hygiene 5: IOCTL input validation | Sec 18 (new) | All custom IOCTLs METHOD_BUFFERED. Each handler validates `InputBufferLength == sizeof(struct)`, `OutputBufferLength >= response_size`, range-checks user-controllable fields, returns `STATUS_INVALID_PARAMETER` on any failure (no kernel state change). SDDL on device interface = admin-only. |
| Production Hygiene 6: Test plan | New file `docs/M12-TEST-PLAN.md` | 8 test classes documented: unit (translation), unit (descriptor parse), race (shadow buffer), race (Feature 0x47 vs RID=0x27 update), DV cycle, functional (VG-0..VG-8), 24h soak, 72h soak. |
| Production Hygiene 7: Build system msbuild + EWDK | Sec 20 (new) | Decision: msbuild + EWDK 25H2 (not cmake). EWDK already mounted at `F:\` on dev machine; KMDF templates out-of-box. Build script `scripts/build-m12.ps1` invokes msbuild with EWDK env vars. Output: `build/Win11Release/x64/`. Artifacts: `MagicMouseDriver.sys` + `.cat` + `.inf` + `.tmf` (WPP). |
| Production Hygiene 8: Compatibility matrix | Sec 21 (new) | Supported: Win11 22H2/23H2/24H2/25H2 x64. Deferred: Win11 ARM64 (v2), Win10 21H2+ (v2; KMDF 1.15 still supported but not tested). Out of scope: Windows Server. KMDF version pinned 1.15. |
| Production Hygiene 9: Coexistence story | Sec 22 (new) | Coexistence table: vs `applewirelessmouse` (DriverVer 04/21/2026, M12 wins by rank), vs Magic Utilities (DriverVer 11/05/2024, M12 wins), vs MagicMouseFix forks (variable; MOP detection step flags any with DriverVer >= M12's). Pre-install detection step in MOP lists candidate INFs and warns user. |
| Production Hygiene 10: Crash dump / debug helpers | Sec 23 (new) | Pool tag `'M12 '` (4 ASCII; v1.3). DEVICE_CONTEXT signature field `0x4D31322D` ('M12-' LE) at offset 0 — corruption detection at every spinlock acquire. Each major function logs entry/exit at WPP VERBOSE. !analyze-friendly DbgPrint format for kernel-mode error paths. |
| Production Hygiene 11: Watchdog | Sec 24 (new) | WDF timer started in `EvtDevicePrepareHardware`; fires every 30 sec. Checks `Shadow.Timestamp` — if no input in 120s while D0 active and BT connected, log WARNING (mouse may be in stuck state). Configurable in CRD: `WatchdogIntervalSec`, `StallThresholdSec`. |
| Production Hygiene 12: Logging policy | Sec 25 (new) | DebugLevel REG_DWORD 0-4 (default 0). 0=Errors only; 1=+Warnings; 2=+Info (PnP, IOCTL success, suspend/wake); 3=+Verbose (every Feature 0x47 read, shadow updates); 4=+Hex dumps (full 46-byte RID=0x27 payloads — required for empirical BATTERY_OFFSET resolution). DebugLevel 4 set ONLY during VG-4 empirical-offset validation; reset to 0 in production. |

### v1.5 changelog (supplement finding -> section)

| Supplement finding | Section addressed | Resolution |
|---|---|---|
| User decision: Auto-reinit on wake IN v1 | Sec 5 (new subsection) | `EvtDeviceD0Entry` resets shadow buffer staleness flag; optionally re-issues GET_REPORT for RID=0x27 if mouse responsive. ~50 LOC. |
| User decision: Battery polling fallback (shadow cold >60s) IN v1 | Sec 6 (new subsection) | If `now() - last_rid27_timestamp > 60s`, issue explicit BTHID GET_REPORT for RID=0x27 to warm the cache before completing Feature 0x47. ~80 LOC. |
| User decision: PREfast gating for ship | Sec 20 | msbuild always runs PREfast analysis; 0 warnings = gate. |
| User decision: SDV gating for ship | Sec 20 | Run SDV before sign; 0 violations = gate. |
| User decision: Power-saver aggressive defaults | Sec 17 defaults table | SuspendOnDisplayOff=1, SuspendOnACUnplug=1 (both changed from 0). All 5 events now default 1. |
| User decision: MIT license | Metadata | License = MIT added to header. |
| User decision: Click handling = v2 milestone | Sec 16 | Changed from "out of scope" to "M12 v2 milestone". |
| Upstream lessons: .gitattributes CRLF enforcement | Sec 20 + docs/M12-PHASE-3-PREP.md | driver/.gitattributes enforces CRLF on .inf/.sys/.cat/.h/.c — prevents line-ending-induced signature failures (upstream issue #1). |
| Upstream lessons: KNOWN-ISSUES.md 6 entries | docs/KNOWN-ISSUES.md (NEW) | Sensitivity, scroll-inversion, ARM64, smart-zoom, MU residue, signing. |
| Upstream lessons: INSTALL.md testsigning prominence | MOP Sec 3a (already present) | MOP Section 3a already leads with testsigning check; INSTALL.md will mirror at Phase 3. |

### v1.4 design ship rationale (NLM pass-4)

NLM pass-4 verdict: see `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS4-2026-04-28.md`. Per playbook v1.8 iteration cap (v1.5 max if pass-4 surfaces NEW critical issues), v1.4 is the design ship target. Open questions tracked as future work; none blocking.

### v1.5 design ship rationale (NLM pass-5 SKIPPED)

NLM pass-5 is skipped per playbook v1.8 cap. The v1.4 pass-4 verdict already applied the adversarial-downgrade template that converts corpus-gap REJECTs to CHANGES-NEEDED. Running pass-5 against a supplement that contains only scope confirmation, defaults changes, and documentation additions will not produce new architectural findings. v1.5 ships as the final design approval target.

### v1.6 changelog (final additions -> section)

| Addition | Section addressed | Resolution |
|---|---|---|
| Self-tuning battery offset detection (~50 LOC) | Sec 6c (new) | LEARNING mode state machine in DEVICE_CONTEXT; captures up to 100 RID=0x27 frames; identifies candidate byte by value-range [1..65] + low variance; writes to CRD BatteryByteOffset; exits LEARNING. Three new CRD REG_DWORD keys. Removes manual DebugLevel=4 step for typical install. D-S12-52. |
| Privacy policy document | docs/PRIVACY-POLICY.md (new) | M12 collects nothing; all logging local-only; no network; no telemetry. Table: WPP/ETW (opt-in capture), DebugLevel=4 hex dumps (OFF by default), self-tuning state (in-memory only, written once to CRD config). How to disable all logging. D-S12-53. |
| AV/EDR known-issue entry | docs/KNOWN-ISSUES.md (appended) | Kernel filter flagged by Defender/CrowdStrike/SentinelOne; whitelist path; signature verify; corporate IT path; safety rationale (open-source, MIT, no network, test-signed). D-S12-54. |

### v1.6 design ship rationale (NLM pass-6 SKIPPED)

NLM pass-6 is skipped per playbook v1.8 cap. v1.6 additions are documentation-only (one new code section ~50 LOC, one new doc file, one appended entry) -- no new architectural surfaces, no IRP paths, no kernel-mode mutation. Corpus-gap REJECT-downgrade is permanent at this point per playbook v1.8.

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

### 4a. INF [Version] block — DriverVer to win PnP rank (v1.4)

```
[Version]
Signature   = "$Windows NT$"
Class       = HIDClass
ClassGuid   = {745A17A0-74D3-11D0-B6FE-00A0C90F57DA}
Provider    = %ProviderName%
DriverVer   = 01/01/2027,1.0.0.0
CatalogFile = MagicMouseDriver.cat
PnpLockdown = 1
```

`DriverVer = 01/01/2027, 1.0.0.0` is intentional: it outranks every known competing INF on date-precedence — Apple `applewirelessmouse` (`04/21/2026, 6.2.0.0`) and Magic Utilities `MagicMouse` (`11/05/2024, 3.1.5.3`) — without requiring destructive `pnputil /delete-driver /force` against the competitor (the workaround that hit the user during Session 12). M12 wins on first PnP scan; INSTALL-1 MOP gate verifies post-install LowerFilters via `reg query` to confirm rebinding actually happened.

If a future MagicMouseFix fork ships with `DriverVer >= 01/01/2027`, M12 loses the rank tie. Coexistence table (Sec 22) and MOP pre-install detection step (Sec 7a) flag this case and warn the operator. Bump M12's DriverVer (e.g., `01/01/2028, 1.1.0.0`) on each release to stay ahead.

### 4b. Hardware ID matching

The INF must enumerate all three Apple BT HID PIDs that this user owns:

```
[Standard.NTamd64]
%MM_v1_DeviceDesc% = Install_Mouse, BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&030D
%MM_TrackpadClass_DeviceDesc% = Install_Mouse, BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0310
%MM_v3_DeviceDesc% = Install_Mouse, BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0323
```

PID 0x0310 is included to bind any Magic Mouse advertising as the "trackpad-class" hardware ID even though the user owns the standard v1 (0x030D); this matches the applewirelessmouse INF behaviour and forecloses the over-match issue.

### 4c. Service registration and filter binding

```
[Install_Mouse]
CopyFiles = DriverFiles

[Install_Mouse.HW]
AddReg = AddReg_LowerFilter

[AddReg_LowerFilter]
HKR,,"LowerFilters",0x00010008,"MagicMouseM12"   ; FLG_ADDREG_TYPE_MULTI_SZ|FLG_ADDREG_APPEND
                                                  ; service key name = MagicMouseM12 (no namespace
                                                  ; conflict with applewirelessmouse or MagicMouse)
                                                  ; binary on disk is MagicMouseDriver.sys

[Install_Mouse.Services]
AddService = MagicMouseM12, 0x00000002, ServiceInstall

[ServiceInstall]
DisplayName   = %ServiceDesc%
ServiceType   = 1                ; SERVICE_KERNEL_DRIVER
StartType     = 3                ; SERVICE_DEMAND_START
ErrorControl  = 1                ; SERVICE_ERROR_NORMAL
ServiceBinary = %12%\MagicMouseDriver.sys
```

**Service name decision (v1.4):** `MagicMouseM12` (not `M12` — too short, would collide if a future driver author also picks 3-letter short-forms). Avoids namespace conflict with Apple's `applewirelessmouse` and Magic Utilities' `MagicMouse`. Pool tag stays `'M12 '` (4 ASCII chars, distinct from service name). Throughout this document, Section 4 onwards uses `MagicMouseM12` as the canonical service name; older v1.0-v1.3 references to bare `M12` should be read as `MagicMouseM12` post-v1.4.

Note (per Senior MIN-5 + DSM Issue 1 mitigation): with `DriverVer = 01/01/2027`, M12 outranks both `applewirelessmouse` and Magic Utilities at PnP rank evaluation, so explicit pre-install removal of `applewirelessmouse` is no longer strictly required. However, if `applewirelessmouse` is on the LowerFilters chain at install time, both filters end up on the stack and behaviour is undefined. MOP step INSTALL-1 still enforces removal as a defensive measure (preferable to relying on rank alone for the steady state).

### 4d. Class

```
Class       = HIDClass
ClassGuid   = {745A17A0-74D3-11D0-B6FE-00A0C90F57DA}
```

The filter sits on the HID-class GUID stack (per AP-16 lesson: filter binding lives on `{00001124-...}` LowerFilters of the HID-class device, not the BT-service GUID).

### 4e. Include / Needs

```
Include = input.inf, hidbth.inf
Needs   = HID_Inst.NT, HID_Inst.NT.Services
```

Same as applewirelessmouse and MU. Ensures HidClass is registered as the function driver of record; M12 sits below it as a lower filter without taking ownership.

### 4f. PnpLockdown

`PnpLockdown=1`. Standard. Already declared in [Version] block (Sec 4a).

### 4g. Strings

`Provider`, `DeviceDesc`, `ServiceDesc` are M12-specific. No reuse of Apple or Magic Utilities trademarks. Provider string: `Magic Mouse Tray (M12 Filter)`.

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

### 5c. Auto-reinit on wake (v1.5 — IN v1 scope per user decision D-S12-41)

M12 registers `EvtDeviceD0Entry` as part of the KMDF power state machine. On every D0 entry (system resume, Bluetooth reconnect after sleep):

1. Reset shadow buffer staleness flag: `KSPIN_LOCK` acquired; `Shadow.Valid = FALSE`; spinlock released. This ensures the next Feature 0x47 query returns `STATUS_DEVICE_NOT_READY` (or the FirstBootPolicy value) until fresh RID=0x27 data arrives — avoids serving pre-sleep stale data as if it were current.
2. If mouse appears responsive (BTHPORT connection state indicates link-up), optionally issue one explicit GET_REPORT for RID=0x27 to prime the shadow buffer. This is a best-effort fire-and-forget: if the GET_REPORT fails (mouse still waking up), shadow stays invalid and the next organic RID=0x27 frame from user input populates it naturally.

```c
EVT_WDF_DEVICE_D0_ENTRY EvtDeviceD0Entry;

NTSTATUS EvtDeviceD0Entry(WDFDEVICE Device, WDF_POWER_DEVICE_STATE PreviousState) {
    PDEVICE_CONTEXT dctx = DeviceGetContext(Device);
    KIRQL oldIrql;

    // Reset shadow buffer staleness flag
    KeAcquireSpinLock(&dctx->ShadowLock, &oldIrql);
    dctx->Shadow.Valid = FALSE;
    KeReleaseSpinLock(&dctx->ShadowLock, oldIrql);

    DoTraceMessage(TRACE_POWER, "EvtDeviceD0Entry: shadow invalidated, PreviousState=%d", PreviousState);

    // Optionally prime shadow by issuing GET_REPORT for RID=0x27
    // Best-effort: failure is silent; organic RID=0x27 from user input populates it
    M12_TryPrimeShadowBuffer(Device);

    return STATUS_SUCCESS;
}
```

The `M12_TryPrimeShadowBuffer` helper issues an async `BTHID_GET_REPORT` on the IoTarget with a short timeout (200ms). If it returns within the timeout, the completion routine populates the shadow buffer. If it times out or fails, shadow remains invalid until the next user-generated RID=0x27 frame. Estimated ~50 LOC for `EvtDeviceD0Entry` + `M12_TryPrimeShadowBuffer`.

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

### 6b. Battery polling fallback for cold shadow buffer (v1.5 — IN v1 scope per user decision D-S12-42)

If `now() - last_rid27_timestamp > 60s` when a Feature 0x47 query arrives, the shadow buffer is considered cold. Rather than immediately returning `STATUS_DEVICE_NOT_READY` (which the tray treats as N/A), M12 first issues an explicit BTHID GET_REPORT for RID=0x27 to wake the mouse and prime the shadow buffer.

Rationale:
- Mitigates first-boot race: on cold start the mouse hasn't sent any RID=0x27 frames yet; polling immediately returns N/A without this fallback.
- Mitigates extended-disconnect scenario: mouse was off for hours; shadow is stale; first tray poll should produce a real value without waiting for user input.
- 60s threshold chosen to avoid triggering on normal idle (mouse emits 0x27 ~10/sec during use; a 60s gap means it has genuinely gone inactive or was just powered on).

```c
// In HandleGetFeature47 (v3 path, after PID branch check):
LONGLONG now_ms = KeQueryTimeIncrement();  // simplified; actual uses KeQuerySystemTime
LONGLONG age_ms = (now_ms - dctx->Shadow.Timestamp.QuadPart) / 10000;

if (!dctx->Shadow.Valid || age_ms > 60000) {
    // Shadow cold -- issue GET_REPORT for RID=0x27 synchronously (short timeout)
    NTSTATUS primeStatus = M12_PrimeShadowBufferSync(Device, 500 /* ms timeout */);
    if (!NT_SUCCESS(primeStatus)) {
        // Mouse unresponsive -- return NOT_READY; tray retries on next poll interval
        WdfRequestComplete(req, STATUS_DEVICE_NOT_READY);
        return STATUS_DEVICE_NOT_READY;
    }
    // Shadow now valid; fall through to translation
}
```

The `M12_PrimeShadowBufferSync` helper is a synchronous variant with a 500ms timeout. It serialises with the shadow spinlock identically to the normal OnReadComplete completion routine. Estimated ~80 LOC for this path.

`COLD_SHADOW_THRESHOLD_MS` is registry-tunable at `HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Parameters\ColdShadowThresholdMs` (REG_DWORD, default 60000 = 60s).

### 6c. Self-tuning battery offset detection (v1.6 -- IN v1 scope per user decision D-S12-52)

On `EvtDriverDeviceAdd`, M12 reads `BatteryByteOffset` from CRD config:
- If unset (key absent), OR set to magic sentinel value `0xFFFFFFFF`: enter LEARNING mode.
- If set to valid value in [0..45]: enter NORMAL mode (skip learning).

This removes the manual DebugLevel=4 step for the typical case: user installs, M12 self-detects the offset, battery just works. Manual override always available via registry.

#### LEARNING_STATE struct (added to DEVICE_CONTEXT):

```c
typedef struct _LEARNING_STATE {
    BOOLEAN  LearningActive;
    UINT32   FramesCaptured;
    UINT8    ByteUniqueValues[46][66]; // bitmap: byte_position -> set of values seen
    UINT8    ByteUniqueCount[46];      // count of unique values per byte position
    LARGE_INTEGER FirstCaptureTime;    // KeQuerySystemTime at first frame
} LEARNING_STATE;
```

#### Learning mode algorithm:

1. `LearningActive = TRUE` at `EvtDriverDeviceAdd` when BatteryByteOffset is absent or 0xFFFFFFFF.
2. On every RID=0x27 input report received (in the OnReadComplete tap path):
   - For each byte position `b` in [0..45]:
     - Set `ByteUniqueValues[b][payload[b]] = 1`.
     - Recount `ByteUniqueCount[b]` from bitmap popcount.
   - Increment `FramesCaptured`.
3. After `LearningModeFramesRequired` captured frames OR `LearningModeMaxDurationSec` elapsed:
   - Find candidate bytes meeting ALL of:
     - All values seen so far fall in [1..65] (matches Logical Min/Max declared for battery).
     - Low variance: `ByteUniqueCount[b] <= 5`.
     - Position not in the 0x47-area false-positive range (skip bytes that show constant 0x47).
   - If exactly one candidate: write `BatteryByteOffset` to CRD config; exit LEARNING mode; log via WPP INFO.
   - If multiple candidates: write best candidate (lowest `ByteUniqueCount`, most plausible position) + flag ambiguous via WPP WARNING; exit LEARNING mode.
   - If zero candidates: fall back to `BATTERY_OFFSET = 0` (first byte); log WPP WARNING; note user can verify via DebugLevel=4 manual workflow.
4. Exit LEARNING mode; future Feature 0x47 reads use the detected or default offset.

#### CRD config additions:

```
HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Devices\<HardwareKey>\
    BatteryByteOffset      REG_DWORD  (absent or 0xFFFFFFFF = auto-learn; [0..45] = fixed)
    LearningModeFramesRequired  REG_DWORD  (default 100; how many frames before deciding)
    LearningModeMaxDurationSec  REG_DWORD  (default 300; cap learning time in seconds)
```

`BATTERY_OFFSET` (the existing per-Parameters tunable) continues to function as an explicit override that bypasses learning entirely. Reading order: if `BatteryByteOffset` in CRD is a valid [0..45] value, use it; else use learning (or `BATTERY_OFFSET` parameter if set as a legacy override).

Estimated ~50 LOC for the LEARNING_STATE management path. The bitmap approach (46 * 66 bytes = ~3 KB per device, stack-allocated in DEVICE_CONTEXT) avoids dynamic allocation in the hot path.

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

// Power.c (v1.4)
EVT_WDF_DEVICE_D0_ENTRY                EvtDeviceD0Entry;
EVT_WDF_DEVICE_D0_EXIT                 EvtDeviceD0Exit;
PO_SETTING_CALLBACK_ROUTINE            OnDisplayStateChange;
PO_SETTING_CALLBACK_ROUTINE            OnAcDcChange;
PO_SETTING_CALLBACK_ROUTINE            OnAwayModeChange;
NTSTATUS SendVendorSuspendCommand(_In_ PDEVICE_CONTEXT Ctx);
NTSTATUS SendBtDisconnectFallback(_In_ PDEVICE_CONTEXT Ctx);   // F22

// Ioctl.c (v1.4 — custom IOCTL surface, Sec 18)
NTSTATUS HandleSuspendIoctl(_In_ WDFREQUEST Req, _In_ PDEVICE_CONTEXT Ctx);

// Watchdog.c (v1.4)
EVT_WDF_TIMER  EvtWatchdogTimer;

// Tracing.c (v1.4 — WPP support, Sec 19)
// (No exported functions; WPP_INIT_TRACING / WPP_CLEANUP are macros in DriverEntry / EvtDriverContextCleanup)
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
    ULONG          Signature;           // == M12_DEVICE_CONTEXT_SIG ('M12-' LE = 0x4D31322D); v1.4 corruption detection (Sec 23.2)

    WDFDEVICE      Device;
    WDFIOTARGET    IoTarget;            // == WdfDeviceGetIoTarget(Device); set in EvtDeviceAdd
    WDFQUEUE       IoctlQueue;          // sequential
    WDFQUEUE       ReadQueue;           // parallel

    USHORT         Vid;
    USHORT         Pid;                 // 0x030D / 0x0310 / 0x0323
    UNICODE_STRING InstanceId;          // v1.4 — for WPP per-device correlation (Sec 19.5)

    // Battery shadow (the only mutable state). Per-DEVICE_CONTEXT, NOT global, so multi-mouse safe (Sec 19.2).
    KSPIN_LOCK     ShadowLock;
    SHADOW_BUFFER  Shadow;

    // Tunables (read once from registry at AddDevice; defaults if absent)
    ULONG          BatteryOffset;       // default 1
    ULONG          FirstBootPolicy;     // 0=NOT_READY (default), 1=return 0%
    ULONG          MaxStaleMs;          // default 0 = no staleness check (v1.3 final per NLM pass-3 — 10s default UX-regressed when mouse asleep)
    ULONG          DebugLevel;          // v1.4 — 0..4, see Sec 25
    ULONG          WatchdogIntervalSec; // v1.4 — default 30; 0 = disabled (Sec 24)
    ULONG          StallThresholdSec;   // v1.4 — default 120 (Sec 24)

    // BRB rewriter telemetry (v1.3)
    BOOLEAN        DescriptorBRewritten;  // set TRUE after first successful BRB SDP rewrite
                                          // VG-0 reads this to distinguish fresh-pair from stale-cache

    // Power saver (v1.4 — Sec 17)
    ULONG          DeviceState;          // M12_DEVICE_STATE_ACTIVE / SUSPENDED
    PO_SETTING_REGISTRATION DisplayCallback;
    PO_SETTING_REGISTRATION AcDcCallback;
    PO_SETTING_REGISTRATION AwayModeCallback;
    POWER_SAVER_CONFIG      PowerSaverConfig;  // loaded from CRD subkey at AddDevice

    // Watchdog (v1.4 — Sec 24)
    WDFTIMER       WatchdogTimer;
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;
WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEVICE_CONTEXT, GetDeviceContext)

#define M12_DEVICE_CONTEXT_SIG          0x4D31322D  // 'M12-' little-endian
#define M12_DEVICE_STATE_ACTIVE         0
#define M12_DEVICE_STATE_SUSPENDED      1
```

```c
// PowerSaver config loaded from CRD subkey (Sec 17.4)
typedef struct _POWER_SAVER_CONFIG {
    ULONG  Enabled;                      // master toggle
    ULONG  SuspendOnDisplayOff;
    ULONG  SuspendOnACUnplug;
    ULONG  SuspendOnSignOut;
    ULONG  SuspendOnSleep;
    ULONG  SuspendOnShutdown;
    UCHAR  SuspendCommandBytes[16];      // vendor-specific HID Output Report payload; empty = F22 fallback
    ULONG  SuspendCommandLen;
} POWER_SAVER_CONFIG, *PPOWER_SAVER_CONFIG;
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
| F18 (v1.4) | BT disconnect mid-Feature-0x47 query | IRP arrives at M12 while target offline | M12 completes from cached shadow buffer (not a failure). EvtIoStop already wired (CRIT-3 fix); for the in-flight Feature 0x47 IRP, M12 has not yet forwarded it (short-circuit), so no target dependency. WPP log records "F18-DISCONNECT-DURING-QUERY". |
| F19 (v1.4) | BT reconnect — first RID=0x27 after stale shadow | Shadow has data from prior session | First post-reconnect `OnReadComplete` fires, overwrites payload + bumps timestamp. Shadow becomes fresh. Operator workflow: tray polls within 60s of mouse activity, sees fresh value. Failure mode benign. |
| F20 (v1.4) | Long disconnect (>5 min) — shadow buffer marked stale | Feature 0x47 returns last cached value | If `MAX_STALE_MS != 0` and `(now - Shadow.Timestamp) > MAX_STALE_MS`, return STATUS_DEVICE_NOT_READY. WPP `STALE_SHADOW_RETURN` event emitted. v1.3 default `MAX_STALE_MS=0` (disabled) per NLM pass-3; operator opts in to non-zero only with empirical justification. |
| F21 (v1.4) | Reconnect race — Feature 0x47 query arrives BEFORE first post-reconnect RID=0x27 | Risk of returning stale value | Acceptable per HID 1.11 §7 ("data may be stale"). Return last-cached value. WPP log records "F21-RECONNECT-RACE-STALE-SERVED". If MAX_STALE_MS configured, staleness check (F20) catches very old values. Tray's adaptive polling re-queries within seconds; user sees corrected value on next poll. |
| F22 (v1.4) | Vendor suspend command bytes unknown | Power-saver activates but mouse doesn't enter low-power state | Fallback: M12 issues `WdfIoTargetClose` on the lower target (forces BT disconnect). Less battery-efficient than vendor suspend but functional. CRD config `SuspendCommandBytes` empty -> use BT-disconnect fallback. Once OQ-F resolved, populate `SuspendCommandBytes` via registry. |
| F23 (v1.4) | Competing INF (e.g., MagicMouseFix fork) ships DriverVer >= 01/01/2027 | M12 loses PnP rank tie | MOP pre-install detection (Sec 7a, brief Issue 9) lists candidate INFs; flags any with DriverVer >= M12's. Operator warned + can choose: bump M12 DriverVer next release, or accept competing driver. No silent failure. |
| F24 (v1.4) | Orphan service entry persists after uninstall | `MagicMouseM12` service in HKLM with STOPPED + missing binary | MOP rollback Sec 8b explicit `sc.exe delete MagicMouseM12` after `pnputil /delete-driver`. Pre-install Sec 7a detects + cleans stale entries. WPP log records nothing (service not loaded); detection is registry-side. |
| F25 (v1.4) | Sticky `LowerFilters` reference on disconnected sibling devices | Apple keyboard's BTHENUM still references `applewirelessmouse` after M12 install | MOP post-install `mm-orphan-filter-walk.ps1` (Sec 7d) walks the BTHENUM tree, flags orphan references. Cleanup script removes `applewirelessmouse` from sibling Device Parameters keys. Non-fatal; cosmetic registry hygiene. |
| F26 (v1.4) | Sign-out event does not reach kernel filter | Power-saver's "SuspendOnSignOut=1" never fires | Kernel KMDF filter cannot directly subscribe to user-session events. Resolution: tray app subscribes to `WTS_SESSION_LOGOFF` via `WTSRegisterSessionNotification`, then sends `IOCTL_M12_SUSPEND` to M12. If tray not running at sign-out, fallback: SCM session-end signal via `RegisterServiceCtrlHandlerEx` (driver service receives `SERVICE_CONTROL_SESSIONCHANGE`). |
| F27 (v1.4) | Watchdog false-positive on long idle | WARNING log spam when mouse legitimately idle for >120s | Watchdog only fires WARNING (not ERROR). Configurable `StallThresholdSec` in CRD (default 120). Operator can raise to 600+ if false-positives observed. Watchdog never triggers IRP cancellation or recovery — purely diagnostic. |

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

- **OQ-F (v1.4 — power-saver vendor suspend command):** what bytes does Magic Utilities send to put the Magic Mouse into low-power state? Three resolution paths:
  1. Ghidra of `MagicMouse.sys` (look for `HidD_SetOutputReport` or `IOCTL_HID_WRITE_REPORT` patterns post-power-event-callback; likely in obfuscated region).
  2. HCI sniff during MU manual-suspend test (requires paid MU license, reproducible).
  3. Trial-and-error candidate command bytes (0x40, 0x80, etc. on common output report IDs); observe BT controller log for state change.

  If irretrievable: ship M12 v1 power-saver as `WdfIoTargetClose` BT-disconnect fallback (F22). Less battery-efficient but functional. Phase 3 task.

- **OQ-G (v1.4 — Modern Standby detection):** query via `GUID_SYSTEM_AWAYMODE` callback or `GetSystemPowerStatus` polling? Determines whether wake-computer-on-click works. Phase 3 empirical task; out of scope for design ship.

- **OQ-H (v1.4 — sign-out kernel surface):** F26 documents two candidate paths (tray-app bridge via WTSRegisterSessionNotification + IOCTL, or driver service `RegisterServiceCtrlHandlerEx` on `SERVICE_CONTROL_SESSIONCHANGE`). KMDF lower filter has limited direct surface for user-session events. Phase 3 implementation chooses based on reliability + simplicity.

- **OQ-I (v1.4 — DEVICE_CONTEXT signature corruption check IRQL):** structure signature `0x4D31322D` ('M12-' LE) is checked at every spinlock acquire. At DISPATCH_LEVEL inside `OnReadComplete`, the check is a single 4-byte read — cheap. Confirm KMDF allows reading from device context at DISPATCH_LEVEL (it does, per docs); flag for implementation review.

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

---

## 14. (reserved)

(Section number reserved to maintain stable numbering for v1.0-v1.3 cross-references.)

---

## 15. Windows DSM / PnP / Driver Store Compliance (v1.4)

Folded in from `docs/M12-DSM-PNP-CONCERNS-FOR-V1.3.md`. Covers the seven concrete failure modes observed during Session 12 install/uninstall cycles.

### 15.1 INF DriverVer rank

Already declared in Section 4a. Repeated here for cross-reference: `DriverVer = 01/01/2027, 1.0.0.0`. Bumps with each release. Rationale: must exceed all competing applewirelessmouse / MagicMouse / MagicMouseFix INFs to win PnP rank tie without destructive workaround.

### 15.2 Service entry hygiene

- INF declares service name `MagicMouseM12` (Sec 4c).
- **Pre-install detection** (MOP Sec 7a): `sc.exe query MagicMouseM12`; if exists with `STATE = STOPPED, EXIT_CODE = 31` (driver binary missing) -> stale orphan entry from prior install. `sc.exe delete MagicMouseM12` before proceeding.
- **Uninstall sequence** (MOP Sec 8b): explicit `sc.exe delete MagicMouseM12` AFTER `pnputil /delete-driver oem<NN>.inf /uninstall /force`. Order matters: deleting the service before the INF can leave the INF referencing a non-existent service.

### 15.3 BTHPORT cache invalidation

Two paths documented in MOP Sec 7c-pre:

- **Path A (preferred — scripted)**: `reg delete HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<BD-addr>\CachedServices /v 00010000 /f`. Faster than full BT stack reset, less invasive than UI unpair flow. Requires AP-24 backup-verify gate (export the CachedServices subtree to `.reg` first).
- **Path B (fallback — operator-driven)**: remove + re-pair the device via Bluetooth Settings UI. Forces fresh SDP exchange + descriptor reload through M12's filter.

v1.3 BRB rewriter (Sec 3b') eliminates the need for cache invalidation in fresh-pair scenarios — M12 rewrites the SDP TLV during the SDP exchange. Cache invalidation only required when M12 is installed AFTER the device was paired (no SDP exchange happens, so M12's BRB rewriter never fires).

### 15.4 DriverStore staged-package cleanup

- **Pre-install** (MOP Sec 7a): `pnputil /enum-drivers | findstr MagicMouseM12`. Delete any pre-existing M12 INF via `pnputil /delete-driver oem<NN>.inf /uninstall /force` to avoid duplicate-staging. (DriverStore is reference-counted by binding, but staged packages without active bindings still persist for re-use — explicit cleanup required.)
- **Rollback** (MOP Sec 8b): explicit `pnputil /delete-driver` of M12's published name to leave DriverStore clean.

### 15.5 Orphan LowerFilter walk

Post-install registry-walk script `scripts/mm-orphan-filter-walk.ps1`:

```powershell
# Lists all LowerFilters MULTI_SZ values under v1/v3 BTHENUM device tree;
# flags any that don't match the expected service name (MagicMouseM12).
$BthRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\BTHENUM"
Get-ChildItem -Path $BthRoot -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.PSIsContainer } |
    ForEach-Object {
        $params = "$($_.PSPath)\Device Parameters"
        if (Test-Path $params) {
            $lf = (Get-ItemProperty -Path $params -ErrorAction SilentlyContinue).LowerFilters
            if ($lf -and ($lf -notcontains "MagicMouseM12") -and ($lf -contains "applewirelessmouse")) {
                Write-Warning "Orphan applewirelessmouse reference: $($_.PSChildName)"
            }
        }
    }
```

Run after install (MOP Sec 7d post-install) and after rollback (Sec 8e). Removes stale `applewirelessmouse` references on Device Parameters keys when child binding has changed (DSM Issue 7 — sticky LowerFilters on disconnected devices).

---

## 16. Scope and Non-Goals (v1.4 — folded from `M12-SCOPE-AND-DEFERRED-FEATURES.md`)

### 16.1 Goals (M12 v1)

- Battery percentage readable for v3 Magic Mouse via standard Feature 0x47 path.
- v1 Magic Mouse continues working unchanged (regression baseline).
- DSM/PnP/Driver Store hygiene (Sec 15).
- Per-PID configuration via registry (K8s-CRD-style at `HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Devices\<HardwareKey>\`).
- Power saver / suspend modes — IN v1 scope per user direction 2026-04-28 (Sec 17).
- WPP/ETW tracing for diagnostics (Sec 19).

### 16.2 Non-goals (M12 v1)

- Click handling / gesture interpretation — Apple driver suffices for standard 1-finger clicks. Left/right/middle finger position detection and per-mode click configuration is **M12 v2 milestone** (not "never") — deferred pending v1 ship and v2 planning. A separate `docs/M12-V2-CLICK-HANDLING-PLAN.md` will be created when v2 planning starts.
- Smooth-scroll auto-reinit on wake — Apple driver does smooth scroll synthesis; M12 doesn't override.
- Device rename / factory reset — UX layer responsibility.
- Bluetooth pairing diagnostics — operational documentation, not code.
- Tray UX — covered in separate PRD.
- High-resolution scroll (Mode A 5-link-collection / Resolution Multiplier features) — see Section 5a.
- Multi-finger gestures.
- Force-feedback, click-pressure, per-finger touch data.
- USB-C wired path for v3.
- Replacing `MagicKeyboard.sys` for the AWK keyboard.
- Magic Trackpad support (PIDs 0x030E, 0x0314).

### 16.3 Deferred to M12 v2 (future)

| Feature | LOC est. | Trigger to add |
|---|---|---|
| Keepalive ping every 2 sec (Win10 2004 freeze workaround) | ~30 | If users report freeze symptoms |
| Click handling (finger position, per-mode config) | ~500-1000 | v1 ships; v2 planning starts; see docs/M12-V2-CLICK-HANDLING-PLAN.md (TBD) |
| Win11 ARM64 support | ~50 (mostly build-system) | User requests + ARM64 hardware acquired |
| Win10 21H2+ support | ~100 | User requests + KMDF 1.15 fallback validated |

### 16.4 Future tray-app PRD scope

| Feature | Why tray, not driver |
|---|---|
| K8s-CRD config UI (registry editor) | UX |
| Battery low toast notification (<20%) | UX |
| Per-device dashboard | UX |
| Driver health check (M12 bound? descriptor mode? RID=0x27 received recently?) | UX + diagnostic |
| Manual "restart driver" / "force reinit" buttons | UX wrapper around CLI |
| Diagnostic export (MOP-validation report) | UX |
| Sign-out detection bridge to driver (`WTSRegisterSessionNotification` -> `IOCTL_M12_SUSPEND`) | F26 mitigation |

### 16.5 NEVER in scope (or new PRD)

- WMI provider for battery exposure
- Performance counters
- Localization (INF + device strings)
- Static-analysis-clean (PREfast / SDV) — aspirational; not gating
- WHQL submission — test-sign for v1; WHQL is v2 release engineering
- HLK test compliance — v2

---

## 17. Power Saver / Suspend Modes (v1.4 — folded from `M12-POWER-SAVER-DESIGN.md`)

Per user direction 2026-04-28, power saver / suspend modes are IN v1 scope. Matches Magic Utilities' "Battery saver" feature surface.

### 17.1 Power-event registration

In `EvtDriverDeviceAdd`:

```c
// D-state callbacks (KMDF native)
WDF_PNPPOWER_EVENT_CALLBACKS pnpCallbacks;
WDF_PNPPOWER_EVENT_CALLBACKS_INIT(&pnpCallbacks);
pnpCallbacks.EvtDeviceD0Entry              = EvtDeviceD0Entry;        // wake from low-power
pnpCallbacks.EvtDeviceD0Exit               = EvtDeviceD0Exit;          // entering low-power
pnpCallbacks.EvtDeviceSelfManagedIoSuspend = EvtDeviceSelfManagedIoSuspend;  // CRIT-3 fix from v1.2
pnpCallbacks.EvtDeviceSelfManagedIoRestart = EvtDeviceSelfManagedIoRestart;
WdfDeviceInitSetPnpPowerEventCallbacks(DeviceInit, &pnpCallbacks);

// System power events (Win32 callbacks routed to kernel)
PoRegisterPowerSettingCallback(NULL, &GUID_CONSOLE_DISPLAY_STATE,    OnDisplayStateChange,    dctx, &dctx->DisplayCallback);
PoRegisterPowerSettingCallback(NULL, &GUID_ACDC_POWER_SOURCE,        OnAcDcChange,            dctx, &dctx->AcDcCallback);
PoRegisterPowerSettingCallback(NULL, &GUID_SYSTEM_AWAYMODE,          OnAwayModeChange,        dctx, &dctx->AwayModeCallback);
```

`PoRegisterPowerSettingCallback` is the kernel-mode equivalent of `RegisterPowerSettingNotification`. Each callback receives a `POWERBROADCAST_SETTING` payload; M12 inspects `Data` to determine the new state.

Sleep / hibernate / shutdown are picked up via the standard KMDF `EvtDeviceD0Exit` (system-wide power transition cascades to D-state changes on every device).

Sign-out is NOT directly observable by the kernel filter (F26). Resolution: tray app uses `WTSRegisterSessionNotification` (Win32 user-mode) and bridges to M12 via `IOCTL_M12_SUSPEND` (Sec 18). If tray is not running at sign-out time, fallback: register the M12 service via `RegisterServiceCtrlHandlerEx` to catch `SERVICE_CONTROL_SESSIONCHANGE` events.

### 17.2 Suspend command sequence

When a configured event fires:

1. Acquire CRD config from `DEVICE_CONTEXT->PowerSaverConfig`.
2. If config flag for THIS event is enabled (e.g., `SuspendOnSleep == 1`):
   a. Acquire `ShadowLock`.
   b. Send vendor-specific HID Output Report to mouse via `WdfIoTargetSendIoctlSynchronously(IOCTL_HID_WRITE_REPORT, ...)`. Report ID and command bytes are loaded from `PowerSaverConfig.SuspendCommandBytes` (REG_BINARY).
      - **OPEN QUESTION (OQ-F)**: vendor command bytes are unknown. Three resolution paths in OQ-F. Until resolved: empty `SuspendCommandBytes` triggers F22 fallback (BT disconnect via `WdfIoTargetClose`).
   c. Mark `dctx->DeviceState = M12_DEVICE_STATE_SUSPENDED`.
   d. Release `ShadowLock`.
3. Subsequent Feature 0x47 reads return last cached value with stale flag in WPP log (no shadow update during suspend; mouse not emitting RID=0x27).

### 17.3 Wake handling

Wake is passive — user clicks mouse, BT controller sees activity, BTHPORT re-establishes connection, HidBth resumes I/O, RID=0x27 reports start arriving.

In `EvtDeviceD0Entry` (driver wake):

```c
NTSTATUS EvtDeviceD0Entry(WDFDEVICE device, WDF_POWER_DEVICE_STATE prev) {
    PDEVICE_CONTEXT dctx = GetDeviceContext(device);
    KIRQL irql;
    KeAcquireSpinLock(&dctx->ShadowLock, &irql);
    dctx->DeviceState = M12_DEVICE_STATE_ACTIVE;
    // Don't invalidate Shadow.Valid here — last cached value still serves Feature 0x47
    // until first post-wake RID=0x27 arrives. Reset timestamp to "now" so MAX_STALE_MS
    // doesn't immediately fire on a stale cache.
    KeQuerySystemTime(&dctx->Shadow.Timestamp);
    KeReleaseSpinLock(&dctx->ShadowLock, irql);

    DoTraceMessage(TRACE_POWER, "Device D0 entry from %d", prev);
    return WdfIoTargetStart(dctx->IoTarget);
}
```

### 17.4 CRD config schema

Power-saver config lives at:

```
HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Devices\<HardwareKey>\PowerSaver\
    Enabled                  REG_DWORD   (master toggle, default 1)
    SuspendOnDisplayOff      REG_DWORD   (default 1)  -- v1.5: changed from 0 (aggressive defaults per D-S12-45)
    SuspendOnACUnplug        REG_DWORD   (default 1)  -- v1.5: changed from 0 (aggressive defaults per D-S12-45)
    SuspendOnSignOut         REG_DWORD   (default 1)
    SuspendOnSleep           REG_DWORD   (default 1)
    SuspendOnShutdown        REG_DWORD   (default 1)
    SuspendCommandBytes      REG_BINARY  (vendor command payload -- empirically determined; empty = F22 fallback)
```

`<HardwareKey>` is the BTHENUM PID-keyed subkey (e.g., `VID_004C&PID_0323`). Per-device configuration so v1 and v3 can have independent power-saver settings.

Defaults reflect aggressive battery-saving stance per user decision D-S12-45 (2026-04-28): all 5 events default to 1. User can dial back via registry if too aggressive in practice (e.g., set SuspendOnDisplayOff=0 for desktop users).

### 17.5 Manual suspend interface

For v1 (no tray app yet): a small user-mode CLI tool `mm-suspend.exe` that opens the M12 device interface and sends `IOCTL_M12_SUSPEND`. See Sec 18 for IOCTL contract.

For v2 / tray app: tray menu item invokes the same IOCTL.

The custom IOCTL is registered in M12's INF as part of the device interface GUID — chosen to NOT collide with MU's `{7D55502A-...}`. M12 device interface GUID: `{1A8B5C92-D04E-4F18-9A23-7E5D4F892C12}` (random; uniqueness verified via `uuidgen`).

### 17.6 OQ-F resolution priority

See Section 12 OQ-F for full details. Priority order:

1. **Trial-and-error** (lowest cost) — test candidate command bytes during VG-5; observe HCI sniff or BT controller log for state change.
2. **HCI sniff during MU manual-suspend** — requires re-installing MU trial OR finding a paid MU license; reproducible test if achievable.
3. **Ghidra of `MagicMouse.sys`** — likely in obfuscated region; expensive to RE.

Until resolved: F22 fallback (BT disconnect) ships in v1. Power saver works (mouse goes idle within ~2 minutes when BT disconnects); just less battery-efficient than vendor suspend.

---

## 18. Custom IOCTL surface (v1.4)

M12 exposes a single custom IOCTL for manual suspend (and future feature hooks). All custom IOCTLs follow the validation contract below.

### 18.1 Device interface

Registered in `EvtDriverDeviceAdd` via `WdfDeviceCreateDeviceInterface`:

```c
DEFINE_GUID(GUID_DEVINTERFACE_M12,
    0x1a8b5c92, 0xd04e, 0x4f18, 0x9a, 0x23, 0x7e, 0x5d, 0x4f, 0x89, 0x2c, 0x12);
// {1A8B5C92-D04E-4F18-9A23-7E5D4F892C12}

WdfDeviceCreateDeviceInterface(device, &GUID_DEVINTERFACE_M12, NULL);
```

INF declares interface SDDL admin-only:

```
[Install_Mouse.HW]
AddReg = AddReg_DeviceInterface

[AddReg_DeviceInterface]
HKR,,DeviceInterfaceGUIDs,0x10000,"{1A8B5C92-D04E-4F18-9A23-7E5D4F892C12}"
HKR,,Security,0x10001,"D:P(A;;GA;;;BA)(A;;GR;;;WD)"   ; admin full access; users read only
```

### 18.2 IOCTL_M12_SUSPEND

```c
// Custom IOCTL definition (see WdfRequestRetrieveInputBuffer for METHOD_BUFFERED)
#define IOCTL_M12_SUSPEND \
    CTL_CODE(FILE_DEVICE_UNKNOWN, 0x801, METHOD_BUFFERED, FILE_WRITE_ACCESS)

typedef struct _M12_SUSPEND_INPUT {
    ULONG  StructureSize;     // == sizeof(M12_SUSPEND_INPUT); validated
    ULONG  Mode;              // 0=immediate, 1=deferred-on-next-idle (reserved); range [0..1]
    UCHAR  Reserved[8];       // zeros; must be zero (validated)
} M12_SUSPEND_INPUT, *PM12_SUSPEND_INPUT;
```

Handler validation contract (mandatory for all custom IOCTLs):

```c
NTSTATUS HandleSuspendIoctl(WDFREQUEST req, PDEVICE_CONTEXT dctx) {
    PM12_SUSPEND_INPUT input;
    size_t len;
    NTSTATUS s = WdfRequestRetrieveInputBuffer(req, sizeof(M12_SUSPEND_INPUT), (PVOID*)&input, &len);
    if (!NT_SUCCESS(s)) {
        WdfRequestComplete(req, STATUS_INVALID_PARAMETER);
        return STATUS_INVALID_PARAMETER;
    }
    // Validate every field
    if (input->StructureSize != sizeof(M12_SUSPEND_INPUT) ||
        input->Mode > 1 ||
        RtlCompareMemory(input->Reserved, "\0\0\0\0\0\0\0\0", 8) != 8) {
        WdfRequestComplete(req, STATUS_INVALID_PARAMETER);
        return STATUS_INVALID_PARAMETER;
    }
    // ... invoke SendVendorSuspendCommand(dctx) per Sec 17.2 ...
    WdfRequestComplete(req, STATUS_SUCCESS);
    return STATUS_SUCCESS;
}
```

### 18.3 Validation requirements (apply to every future custom IOCTL)

- METHOD_BUFFERED only (kernel validates buffer ownership; user-mode pointer dereferences forbidden in METHOD_NEITHER).
- `InputBufferLength == sizeof(<expected struct>)` validated explicitly (don't trust `WdfRequestRetrieveInputBuffer`'s minimum-length check alone).
- `OutputBufferLength >= <response_size>` validated.
- All user-controllable fields range-checked; reserved bytes validated as zero.
- Invalid input -> `STATUS_INVALID_PARAMETER`, no kernel state mutation.
- SDDL on device interface (admin-only, declared in INF).
- WPP log: every IOCTL entry/exit at WPP INFO; failures at WPP WARNING with input fingerprint (length, IOCTL code).

---

## 19. WPP / ETW Tracing (v1.4)

M12 declares its own WPP provider for runtime diagnostics.

### 19.1 Provider declaration

```c
// Driver.h
#define WPP_CONTROL_GUIDS                                           \
    WPP_DEFINE_CONTROL_GUID(                                        \
        M12TraceGuid,                                               \
        (8d3c1a92,b04e,4f18,9a23,7e5d4f892c12),                     \
        WPP_DEFINE_BIT(TRACE_PNP)        /* PnP / AddDevice */      \
        WPP_DEFINE_BIT(TRACE_IO)         /* IRP path */             \
        WPP_DEFINE_BIT(TRACE_SHADOW)     /* shadow buffer */        \
        WPP_DEFINE_BIT(TRACE_POWER)      /* D-state / suspend */    \
        WPP_DEFINE_BIT(TRACE_IOCTL)      /* custom IOCTLs */        \
        WPP_DEFINE_BIT(TRACE_BRB)        /* BRB rewriter */         \
    )
// {8D3C1A92-B04E-4F18-9A23-7E5D4F892C12}
```

`WPP_INIT_TRACING(DriverObject, RegistryPath)` in `DriverEntry`. `WPP_CLEANUP(DriverObject)` in `EvtDriverContextCleanup`.

### 19.2 Trace levels

Standard WPP levels: ERROR (1), WARNING (2), INFO (3), VERBOSE (4). M12 adds DebugLevel registry control (Sec 25) that maps to WPP filter level at runtime.

### 19.3 Migration

All existing `DbgPrint` calls migrated to `DoTraceMessage(<flag>, "fmt", ...)`. Examples:

```c
// Before: DbgPrint("[M12] Shadow.Payload[0..45]: %02x ...\n", buf[0]);
// After:
DoTraceMessage(TRACE_SHADOW, "Shadow.Payload[0..45]: %!HEXDUMP!", WPP_HEX(buf, 46));
```

### 19.4 TMF generation + distribution

`tracewpp.exe` runs as msbuild pre-build step, generates `MagicMouseDriver.tmf`. The TMF + `.sys` ship together. Diagnostic capture command (in MOP):

```pwsh
logman start M12 -p {8D3C1A92-B04E-4F18-9A23-7E5D4F892C12} -o capture.etl -ets
# ... reproduce issue ...
logman stop M12 -ets
tracefmt capture.etl -p <tmf-dir> -o decoded.txt
```

### 19.5 Multi-mouse trace correlation

WPP entries include `Device->Pid` and `Device->InstanceId` so a multi-mouse capture can be filtered per-device. (Per-DEVICE_CONTEXT shadow + spinlock from Sec 9b/10a means each device's events are independent; filtering on `Pid` separates them.)

---

## 20. Build System (v1.4)

**Decision: msbuild + EWDK 25H2** (not cmake).

Rationale:

- EWDK 25H2 is already mounted at `F:\` on the dev machine (or `D:\ewdk25h2` fallback).
- msbuild has KMDF templates out-of-box (`<DriverType>KMDF</DriverType>` in vcxproj).
- cmake-for-WDK is a community workaround with maintenance burden + non-standard tool integration.
- Microsoft's official KMDF samples ship as msbuild-only.

Build invocation:

```pwsh
# scripts/build-m12.ps1
& F:\LaunchBuildEnv.cmd
cd C:\Users\Lesley\projects\Personal\magic-mouse-tray\driver
msbuild MagicMouseDriver.vcxproj `
    /p:Configuration=Release `
    /p:Platform=x64 `
    /p:SignMode=Off `
    /p:WppEnabled=true `
    /verbosity:minimal `
    /m
```

Build artefacts:

| Artefact | Path | Purpose |
|---|---|---|
| `MagicMouseDriver.sys` | `build\Win11Release\x64\` | Kernel binary |
| `MagicMouseDriver.cat` | same | Catalog (post-inf2cat + signtool) |
| `MagicMouseDriver.inf` | same | Install file |
| `MagicMouseDriver.tmf` | same | WPP trace messages format file |

KMDF version pinned in vcxproj to **1.15** (matches `applewirelessmouse.sys` baseline + OS minimum compatibility). Forward-compatible with newer KMDF via standard runtime-loaded WDF binaries.

EWDK provides full toolchain (`msbuild`, `WDK props/targets`, `inf2cat`, `signtool`, `hidparser`, `tracewpp`, WinDbg) without Visual Studio install.

### 20.1 PREfast static analyzer gate (v1.5 — GATING for ship per D-S12-43)

PREfast is NOT aspirational. Every msbuild invocation for a ship candidate MUST run PREfast. Zero warnings is the gate before a test-signed build can be submitted for review.

```pwsh
# Enable PREfast in the build
msbuild MagicMouseDriver.vcxproj `
    /p:Configuration=Release `
    /p:Platform=x64 `
    /p:RunCodeAnalysis=true `
    /p:CodeAnalysisRuleSet=NativeMinimumRules.ruleset `
    /p:WppEnabled=true `
    /verbosity:minimal `
    /m

# Gate: parse output for "warning C6" / "warning C28" lines
# Exit code != 0 if PREfast warnings present (enabled via /p:CodeAnalysisTreatWarningsAsErrors=true)
```

PREfast catches at build time: null pointer dereferences, buffer overruns, IRQL violations, use-after-free patterns. These are the same classes of issues that the senior driver-dev review surfaced as CRIT-1 through CRIT-4 in the design iterations — PREfast would have caught them at zero cost before peer review.

### 20.2 Static Driver Verifier gate (v1.5 — GATING for ship per D-S12-44)

SDV is NOT aspirational. Run SDV against `MagicMouseDriver.sys` before any test-signed build is submitted for signing. Zero violations is the gate.

```pwsh
# Run SDV (from EWDK build environment)
msbuild MagicMouseDriver.vcxproj `
    /t:sdv `
    /p:inputs="/check:default.sdv" `
    /p:Configuration=Release `
    /p:Platform=x64

# Check result: sdv-map.h + sdv-report.xml in driver\ directory
# Gate: sdv-report.xml must contain <DEFECTS count="0" />
```

SDV catches: deadlock conditions, IRP completion races, KMDF rule violations, use of deprecated APIs. The 4 critical bugs from the senior driver-dev peer review (CRIT-1 through CRIT-4) fall directly in SDV's check coverage — SDV on the v1.0 skeleton would have surfaced all of them in <15 minutes.

### 20.3 .gitattributes CRLF enforcement for driver source (v1.5 — per upstream lessons D-S12-49)

Driver source files MUST use CRLF line endings. The most-commented upstream issue (MagicMouse2DriversWin10x64 #1) was caused by git auto-converting .inf CRLF to LF, breaking signing verification. M12 prevents this via `driver/.gitattributes`.

Content of `driver/.gitattributes` (to be created as the FIRST file committed to driver/ directory in Phase 3):

```
# Driver source files MUST use CRLF on Windows (signing depends on byte-exact content)
*.inf  text eol=crlf
*.cat  binary
*.sys  binary
*.tmf  text eol=crlf
*.h    text eol=crlf
*.c    text eol=crlf
*.rc   text eol=crlf

# Build/sign artifacts -- never modify
build/** binary
*.cer  binary
*.pfx  binary

# Documentation -- let git auto-detect (Markdown is platform-agnostic)
*.md   text
```

MOP pre-build gate: run `git ls-files --eol -- driver/` and confirm `.inf` files show `crlf` not `lf`. Failure = block build until line endings fixed.

---

## 21. Compatibility Matrix (v1.4)

| OS | Arch | Status | Notes |
|---|---|---|---|
| Windows 11 22H2 | x64 | SUPPORTED | Test target; KMDF 1.15 baseline |
| Windows 11 23H2 | x64 | SUPPORTED | Test target |
| Windows 11 24H2 | x64 | SUPPORTED | Test target |
| Windows 11 25H2 | x64 | SUPPORTED (current) | Primary dev OS |
| Windows 11 ARM64 | ARM64 | DEFERRED to v2 | Build system supports ARM64 via msbuild `/p:Platform=ARM64`; no test hardware |
| Windows 10 21H2+ | x64 | DEFERRED to v2 | KMDF 1.15 supported but not tested on Win10 |
| Windows Server | x64 | OUT OF SCOPE | Different driver ecosystem; not a personal-use target |

KMDF version: **1.15** (matches `applewirelessmouse.sys` + `MagicMouse.sys` reference; broadly compatible).

INF declares `[Manufacturer]` section as `%ProviderName% = Standard, NTamd64.10.0...22000` (Win11 22H2 minimum). v2 adds `NTamd64.10.0...19041` (Win10 21H2) and `NTarm64.10.0...22000` (Win11 ARM64) decorators.

---

## 22. Coexistence (v1.4)

| Coexistence target | M12 wins via | Failure mode | Mitigation |
|---|---|---|---|
| Apple `applewirelessmouse` (DriverVer 04/21/2026, 6.2.0.0) | M12 DriverVer 01/01/2027, 1.0.0.0 (date wins) | n/a — M12 always wins | MOP INSTALL-1 verifies LowerFilters post-install |
| Magic Utilities `MagicMouse` (DriverVer 11/05/2024, 3.1.5.3) | DriverVer rank | n/a — MU older | MOP pre-install enumeration flags any MU INF; warn user |
| MagicMouseFix variants (community forks; DriverVer varies) | DriverVer rank if M12 newer | If community fork has DriverVer >= 01/01/2027, M12 loses tie | MOP pre-install detection step; user warned + bump M12 DriverVer next release |
| Microsoft default `HidBth` (no LowerFilter) | INF declares hardware ID match; M12 binds as filter | n/a — base case | None needed |
| Two M12 INFs in DriverStore (e.g., post-failed-uninstall) | None — duplicate-staging risk | PnP picks one arbitrarily | MOP pre-install enumerates + cleans (Sec 15.4) |

### 22.1 MOP detection step

Pre-install (MOP Sec 7a-pre):

```pwsh
# List all candidate INFs for the v3 hardware ID
pnputil /enum-drivers | Select-String -Context 5,5 -Pattern "BTHENUM.*PID&0323" | Tee-Object $BackupRoot\candidate-infs.txt

# Extract DriverVer for each candidate; flag any >= M12's DriverVer
$m12Date = [DateTime]"01/01/2027"
foreach ($inf in <enumerated INFs>) {
    $verLine = pnputil /enum-drivers /class HIDClass | Select-String "$inf" -Context 0,5 | Select-String "DriverVer"
    $candidateDate = ParseDriverVerDate($verLine)
    if ($candidateDate -ge $m12Date) {
        Write-Warning "$inf has DriverVer $candidateDate >= M12's $m12Date — M12 may lose rank tie"
    }
}
```

Operator chooses: bump M12 DriverVer + rebuild, or accept competing driver, or remove competing driver via `pnputil /delete-driver oem<NN>.inf /uninstall /force` (after AP-24 backup-verify).

### 22.2 Rank-loss runtime detection

Even with rank fix, INSTALL-1 MOP gate runs `reg query` post-install to confirm M12 is actually bound:

```pwsh
$v3Inst = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&0323*" -Status OK).InstanceId
reg query "HKLM\SYSTEM\CurrentControlSet\Enum\$v3Inst\Device Parameters" /v LowerFilters
# Expected: REG_MULTI_SZ containing "MagicMouseM12"
```

If LowerFilters does NOT contain `MagicMouseM12` post-install, M12 lost the rank tie. Halt; investigate (Sec 22.1 detection step missed something).

---

## 23. Crash dump / debug helpers (v1.4)

### 23.1 Pool tag

Already declared in Sec 9a: `'M12 '` (4 ASCII bytes 0x4D 0x31 0x32 0x20, little-endian = 0x2032314D). WinDbg post-install: `!poolused 4 'M12 '` enumerates allocations.

### 23.2 DEVICE_CONTEXT signature field

```c
typedef struct _DEVICE_CONTEXT {
    ULONG          Signature;        // == M12_DEVICE_CONTEXT_SIG; corruption detection
    // ... rest of fields from Sec 10a + power-saver fields ...
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;

#define M12_DEVICE_CONTEXT_SIG 0x4D31322D   // 'M12-' little-endian
```

Set in `EvtDeviceAdd` after context allocation:

```c
dctx->Signature = M12_DEVICE_CONTEXT_SIG;
```

Validated at every spinlock acquire in `OnReadComplete` and `HandleGetFeature47`:

```c
if (dctx->Signature != M12_DEVICE_CONTEXT_SIG) {
    DoTraceMessage(TRACE_IO, "DEVICE_CONTEXT corruption detected: sig=%08x", dctx->Signature);
    KeBugCheckEx(0xC4, dctx->Signature, M12_DEVICE_CONTEXT_SIG, 0, 0);
}
```

OQ-I (Sec 12) flags the DISPATCH_LEVEL safety question for the implementer.

### 23.3 !analyze-friendly DbgPrint format

Kernel-mode error paths use the `!analyze`-friendly format:

```
[M12] <function>:<line>: <error code> - <description>
```

Example: `[M12] HandleGetFeature47:142: STATUS_INVALID_PARAMETER - pkt->reportBufferLen=1 < 2`

### 23.4 WPP entry/exit tracing

Each major function logs entry + exit at WPP VERBOSE:

```c
NTSTATUS HandleGetFeature47(...) {
    DoTraceMessage(TRACE_IO, "ENTRY HandleGetFeature47 pid=0x%04x", dctx->Pid);
    NTSTATUS s = STATUS_SUCCESS;
    // ...
    DoTraceMessage(TRACE_IO, "EXIT  HandleGetFeature47 status=0x%08x", s);
    return s;
}
```

Compiled-out at non-VERBOSE levels (zero-cost in production builds with DebugLevel < 3).

---

## 24. Watchdog (v1.4)

### 24.1 Purpose

Diagnostic-only watchdog detects "mouse stuck silent" condition: device is connected (D0) and BT is up, but no RID=0x27 frames have arrived for >120s. Does NOT trigger recovery — purely informational.

### 24.2 Implementation

```c
// In EvtDevicePrepareHardware
WDF_TIMER_CONFIG timerCfg;
WDF_TIMER_CONFIG_INIT_PERIODIC(&timerCfg, EvtWatchdogTimer, dctx->WatchdogIntervalSec * 1000);
WdfTimerCreate(&timerCfg, &attrs, &dctx->WatchdogTimer);
WdfTimerStart(dctx->WatchdogTimer, WDF_REL_TIMEOUT_IN_SEC(dctx->WatchdogIntervalSec));
```

```c
// EvtWatchdogTimer — runs every WatchdogIntervalSec (default 30)
VOID EvtWatchdogTimer(WDFTIMER timer) {
    PDEVICE_CONTEXT dctx = GetDeviceContext(WdfTimerGetParentObject(timer));
    if (dctx->DeviceState != M12_DEVICE_STATE_ACTIVE) return;  // skip if suspended

    LARGE_INTEGER now;
    KeQuerySystemTime(&now);
    LONGLONG age_sec = (now.QuadPart - dctx->Shadow.Timestamp.QuadPart) / 10000000;
    if (age_sec > dctx->StallThresholdSec) {
        DoTraceMessage(TRACE_IO, "WATCHDOG_STALL pid=0x%04x age=%lld sec",
                       dctx->Pid, age_sec);
    }
}
```

### 24.3 CRD config

```
HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Devices\<HardwareKey>\
    WatchdogIntervalSec    REG_DWORD   (default 30)
    StallThresholdSec      REG_DWORD   (default 120)
```

Operator can disable by setting `WatchdogIntervalSec=0` (timer not started in EvtDevicePrepareHardware).

---

## 25. Logging Policy (v1.4)

### 25.1 DebugLevel registry value

```
HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Parameters
    DebugLevel    REG_DWORD   (default 0)
```

| DebugLevel | What's logged | WPP filter |
|---|---|---|
| 0 | Errors only (driver init failure, IOCTL invalid, BSOD-class issues) | ERROR (1) |
| 1 | + Warnings (BT disconnect, stale shadow buffer, DV-flagged conditions) | WARNING (2) |
| 2 | + Info (PnP events, IOCTL success, suspend/wake events) | INFO (3) |
| 3 | + Verbose (every Feature 0x47 read, shadow buffer updates) | VERBOSE (4) |
| 4 | + Hex dumps (full 46-byte RID=0x27 payloads on each Feature 0x47 read — required for empirical BATTERY_OFFSET resolution) | VERBOSE + custom hex flag |

### 25.2 Default + workflow

- **Production default**: `DebugLevel = 0` (errors only).
- **Empirical BATTERY_OFFSET workflow** (MOP VG-4): set `DebugLevel = 4` for the duration of the offset-confirmation capture. Reset to 0 (or 2 for normal operation visibility) after.
- **Triage mode**: `DebugLevel = 2` recommended for incident investigation. PnP events + IOCTL outcomes give enough signal to root-cause most issues without flooding the log.

### 25.3 Log volume

| DebugLevel | Approx volume per hour (active mouse, 24-hr soak) |
|---|---|
| 0 | <1 KB (idle errors only) |
| 1 | <10 KB |
| 2 | ~100 KB |
| 3 | ~5 MB (every Feature 0x47 read = 1 line) |
| 4 | ~20 MB (hex dump every Feature 0x47 read) |

`DebugLevel = 4` should NEVER be left on in production — disk fill risk.

### 25.4 Read-once semantics

DebugLevel is read in `EvtDeviceAdd` and stored in `DEVICE_CONTEXT`. Changing the registry value requires PnP cycle (`pnputil /disable-device + /enable-device`) for the new value to take effect. Documented in MOP VG-4 workflow.
