# M12 Test Plan

**Status:** v1.2 — DRAFT (paired with design spec v1.7, empirical layout correction)
**Date:** 2026-04-28
**Linked design:** `docs/M12-DESIGN-SPEC.md` v1.7
**Linked MOP:** `docs/M12-MOP.md` v1.7
**Source brief:** `docs/M12-PRODUCTION-HYGIENE-FOR-V1.3.md` item 6; v1.7 correction: self-tuning offset detection (test class 13) DELETED; replaced with col02 descriptor verification

## BLUF

Per-test-class scope, tooling, gating threshold, and frequency for M12 driver validation. Each row is a discrete test class invoked via the corresponding script or harness. Functional gates VG-0..VG-8 are documented in the MOP; this file covers the test-pyramid layers that feed into the MOP gates. v1.2 reflects the empirical correction: shadow buffer and self-tuning test classes removed; col02 descriptor verification added.

## Test classes

| # | Test class | Scope | Tool | Gating threshold | Frequency |
|---|---|---|---|---|---|
| 1 | Unit (battery translation) | REMOVED in v1.7 -- `TranslateBatteryRaw()` function deleted; battery is buf[2] direct percent from col02 RID=0x90; no translation formula | N/A | N/A | N/A |
| 2 | Unit (descriptor parse) | Reference descriptor (col01 Mouse TLC + col02 Vendor battery TLC UP:0xFF00 U:0x0014 RID=0x90 InLen=3) | User-mode `hidparser.exe` (EWDK) against the static `g_HidDescriptor[]` blob in M12 source | Clean parse; col01 UsagePage=0x0001 Usage=0x0002; col02 UsagePage=0xFF00 Usage=0x0014 RID=0x90 InLen=3; LinkColl=2 | Every commit (pre-msbuild) |
| 3 | Unit (SDP TLV parser) | `RewriteSdpHidDescriptorList()` recursive parser per Sec 3b' (a)-(g) | User-mode harness `tests/unit/test_brb_rewriter.c` with synthetic SDP TLV blobs (fast-path, rewrite-path, malformed bounds, length-form upgrade required, no col02-found) | All abandon conditions correctly detected; rewritten output validates via hidparser showing col01+col02; no out-of-bounds writes | Every commit (CI) |
| 4 | Unit (IOCTL input validation) | `HandleSuspendIoctl` rejects all malformed input (Sec 18.2) | User-mode harness driving simulated IOCTL with: zero-len, oversized, wrong-StructureSize, out-of-range Mode, non-zero Reserved | All malformed inputs return STATUS_INVALID_PARAMETER; no kernel state mutation | Every commit (CI) |
| 5 | Race (shadow buffer) | REMOVED in v1.7 -- shadow buffer eliminated; no concurrent read/write race possible | N/A | N/A | N/A |
| 6 | Race (Feature 0x47 vs RID=0x27 update) | REMOVED in v1.7 -- Feature 0x47 IRP interception and RID=0x27 shadow tap both removed | N/A | N/A | N/A |
| 7 | Race (BRB rewriter under pairing storm) | BRB completion routine reentrancy during repeated pair/unpair | Driver Verifier 0x49bb special pool + scripted 100 pair/unpair cycles | Zero special-pool violations; zero BSOD | Pre-merge + post-feature |
| 8 | DV cycle | Install + functional tests + uninstall under Driver Verifier 0x49bb | `verifier /flags 0x49bb /driver MagicMouseDriver.sys`; 100 install/test/uninstall cycles via automated harness | 0 violations across all cycles | Pre-release gate |
| 9 | Functional (MOP VG-0..VG-14) | End-to-end install + bind + col02 descriptor verification + battery readout + scroll + power saver + soak | MOP procedures (operator + scripted) | Each VG passes per MOP gate definition | Pre-release gate (full MOP run) |
| 10 | Soak (24h) | All paths over time on real hardware | Cron-driven col02 RID=0x90 reads + 3 sleep/wake cycles + AC plug/unplug + sign-in/out cycles | Sustained `OK battery=N% (split)` reads (>= 12 in 24h); zero BSOD; zero `err=` log entries | Pre-release gate |
| 11 | Soak (72h) | Battery drift accuracy | Capture battery percentage every 30 min for 72h with mouse in normal use | Reported % drops monotonically (modulo charge events) over the window; no >5% jumps without corresponding charge event | Pre-release gate |
| 12 | Compatibility matrix | Build + smoke-test on each supported OS | EWDK build + `pnputil /add-driver` + VG-0 + VG-1 + VG-2 on each OS in matrix (Sec 21) | Pass all three gates per OS | Per-release |
| 13 | col02 descriptor verification (MOP VG-14) | REPLACES self-tuning in v1.2. Validates col02 (UP:0xFF00 U:0x0014 RID=0x90 InLen=3) is visible after install. Two paths: (a) HidP_GetCaps probe confirming col02 TLC layout. (b) HidD_GetInputReport(0x90) on col02 returns buf[2] as valid percent in [1..99]. | (a) `mm-hid-descriptor-dump.ps1` output verification. (b) Tray debug.log shows `OK ... battery=N% (split)`. | col02 visible with correct caps; HidD_GetInputReport(0x90) returns valid percent; no OPEN_FAILED or err= for col02. | Pre-release gate |

## Test ordering

For a release candidate:

1. **Pre-commit (developer machine)**: tests 2, 4. Block on failure. (Test 1 removed in v1.2.)
2. **CI (every push)**: tests 2, 3, 4. Block on failure. (Tests 1, 5, 6 removed in v1.2.)
3. **Pre-merge**: test 7. Block on failure. (Tests 5, 6 removed in v1.2.)
4. **Pre-release**: tests 8, 9, 10, 11, 12, 13 in that order. All must pass for release.

## Tooling

| Tool | Source | Purpose |
|---|---|---|
| User-mode C harness | `tests/unit/` | Unit tests 3, 4 (tests 1, 5, 6 removed in v1.2) |
| Driver Verifier | Built-in Windows | Tests 7, 8 |
| Automated install harness | `scripts/test-cycle.ps1` | Test 8 (100x install/test/uninstall) |
| HID descriptor dump | `scripts/mm-hid-descriptor-dump.ps1` | Test 13 (col02 descriptor verification) |
| MOP procedure | `docs/M12-MOP.md` | Test 9 |
| Cron soak harness | `scripts/soak-24h.ps1`, `scripts/soak-72h.ps1` | Tests 10, 11 |
| Per-OS VM matrix | Hyper-V or VMware images of Win11 22H2/23H2/24H2/25H2 | Test 12 |

## Coverage targets

| Module | Coverage target | Measurement |
|---|---|---|
| `Battery.c` (TranslateBatteryRaw) | REMOVED in v1.2 -- no translation function | N/A |
| `BrbDescriptor.c` (TLV parser) | 100% branch (incl. all abandon conditions per Sec 3b' (a)-(g)) | Test 3 |
| `IoctlHandlers.c` (Feature 0x47 short-circuit) | REMOVED in v1.2 -- no Feature 0x47 intercept | N/A |
| `IoctlHandlers.c` (custom IOCTL surface) | 100% line | Test 4 |
| `Power.c` | 70% line (vendor command path may be untestable until OQ-F resolved) | Tests 9 (VG-5), 10 |
| `Watchdog.c` | 80% line | Test 10 |

## Exit criteria

A release ships when:

- Test classes 2, 3, 4 pass (CI gates). (Class 1 removed in v1.2.)
- Test class 7 passes (BRB rewriter race gate).
- Test classes 8, 9 pass (DV cycle + functional MOP).
- Test class 10 (24h soak) passes.
- Test class 12 (compatibility matrix) passes for all SUPPORTED rows in Sec 21.
- Test class 13 (col02 descriptor verification) passes: col02 visible via HidP_GetCaps; HidD_GetInputReport(0x90) returns valid percent; tray shows `OK battery=N% (split)`.
- DV soak (test class 8) reports 0 violations.
- No `OPEN_FAILED` or `err=` failures in tray debug.log during soak (other than transient at sleep/wake boundaries).

## Out of scope

- Localization / internationalization tests (Sec 16.5).
- HLK test compliance (v2 release engineering).
- WHQL submission tests (v2).
- Performance benchmarking (no perf SLA for v1).
- Long-tail compatibility beyond Sec 21 matrix.

## References

- `docs/M12-PRODUCTION-HYGIENE-FOR-V1.3.md` item 6 (test plan source brief)
- `docs/M12-V16-EMPIRICAL-LAYOUT-CORRECTION.md` (v1.7 correction basis; empirical evidence for col02 layout)
- `docs/M12-DESIGN-SPEC.md` Sec 5b (col02 descriptor requirement) + Sec 13 (DV flags) + Sec 18 (IOCTL contract) + Sec 19 (WPP)
- `docs/M12-MOP.md` Sec 9 (validation gates VG-0..VG-14)
- `MagicMouseTray/MouseBatteryReader.cs` (UP_VENDOR_BATTERY=0xFF00, BatteryReportId=0x90, buf[2] pattern)
