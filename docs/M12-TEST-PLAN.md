# M12 Test Plan

**Status:** v1.1 — DRAFT (paired with design spec v1.6)
**Date:** 2026-04-28
**Linked design:** `docs/M12-DESIGN-SPEC.md` v1.6
**Linked MOP:** `docs/M12-MOP.md` v1.6
**Source brief:** `docs/M12-PRODUCTION-HYGIENE-FOR-V1.3.md` item 6; v1.6 additions: self-tuning offset detection (MOP VG-14)

## BLUF

Per-test-class scope, tooling, gating threshold, and frequency for M12 driver validation. Each row is a discrete test class invoked via the corresponding script or harness. Functional gates VG-0..VG-8 are documented in the MOP; this file covers the test-pyramid layers that feed into the MOP gates.

## Test classes

| # | Test class | Scope | Tool | Gating threshold | Frequency |
|---|---|---|---|---|---|
| 1 | Unit (battery translation) | `TranslateBatteryRaw(raw)` for raw in [0..255] | User-mode C harness `tests/unit/test_battery.c`; fixture: known input bytes -> expected output percentage per `(raw-1)*100/64` formula clamped to [0..100] | 100% (66 input values exhaustive) | Every commit (CI) |
| 2 | Unit (descriptor parse) | 116-byte Descriptor B verbatim from `applewirelessmouse.sys` offset 0xa850 | User-mode `hidparser.exe` (EWDK) against the static `g_HidDescriptor[]` blob in M12 source | Clean parse, caps Input=47 / Feature=2 / LinkColl=2 | Every commit (pre-msbuild) |
| 3 | Unit (SDP TLV parser) | `RewriteSdpHidDescriptorList()` recursive parser per Sec 3b' (a)-(g) | User-mode harness `tests/unit/test_brb_rewriter.c` with synthetic SDP TLV blobs (fast-path, rewrite-path, malformed bounds, length-form upgrade required, no-RID-0x47-found) | All abandon conditions correctly detected; rewritten output validates via hidparser; no out-of-bounds writes | Every commit (CI) |
| 4 | Unit (IOCTL input validation) | `HandleSuspendIoctl` rejects all malformed input (Sec 18.2) | User-mode harness driving simulated IOCTL with: zero-len, oversized, wrong-StructureSize, out-of-range Mode, non-zero Reserved | All malformed inputs return STATUS_INVALID_PARAMETER; no kernel state mutation | Every commit (CI) |
| 5 | Race (shadow buffer) | Concurrent reads + writes on per-DEVICE_CONTEXT shadow | Driver-loaded test mode (DBG-only `IOCTL_M12_TEST_RACE`); 8 threads x 100k ops on synthetic shadow under `KSPIN_LOCK` | No torn reads; no deadlock; no lock contention >50ms p99 | Pre-merge gate |
| 6 | Race (Feature 0x47 vs RID=0x27 update) | IOCTL during simulated input report storm | Stress harness: 1ms-spaced Feature 0x47 reads + simulated input every 10ms for 60 sec | Zero data corruption; reads always return current-or-prior shadow snapshot; no deadlock | Pre-merge gate |
| 7 | Race (BRB rewriter under pairing storm) | BRB completion routine reentrancy during repeated pair/unpair | Driver Verifier 0x49bb special pool + scripted 100 pair/unpair cycles | Zero special-pool violations; zero BSOD | Pre-merge + post-feature |
| 8 | DV cycle | Install + functional tests + uninstall under Driver Verifier 0x49bb | `verifier /flags 0x49bb /driver MagicMouseDriver.sys`; 100 install/test/uninstall cycles via automated harness | 0 violations across all cycles | Pre-release gate |
| 9 | Functional (MOP VG-0..VG-8) | End-to-end install + bind + battery readout + scroll + power saver + soak | MOP procedures (operator + scripted) | Each VG passes per MOP gate definition | Pre-release gate (full MOP run) |
| 10 | Soak (24h) | All paths over time on real hardware | Cron-driven Feature 0x47 reads + 3 sleep/wake cycles + AC plug/unplug + sign-in/out cycles | Sustained `OK battery` reads (>= 12 in 24h); zero BSOD; zero `err=` log entries | Pre-release gate |
| 11 | Soak (72h) | Battery drift accuracy | Capture battery percentage every 30 min for 72h with mouse in normal use | Reported % drops monotonically (modulo charge events) over the window; no >5% jumps without corresponding charge event | Pre-release gate |
| 12 | Compatibility matrix | Build + smoke-test on each supported OS | EWDK build + `pnputil /add-driver` + VG-0 + VG-1 + VG-2 on each OS in matrix (Sec 21) | Pass all three gates per OS | Per-release |
| 13 | Self-tuning offset detection (MOP VG-14) | LEARNING mode from fresh install to offset detection; CRD config written correctly | (a) Hardware path: install on machine with no prior BatteryByteOffset, use mouse normally for 5 min, verify WPP log shows "self-tuning detected offset N" and CRD key written. (b) Synthetic path: inject 100 synthetic RID=0x27 frames via `IOCTL_M12_TEST_INJECT` (DBG-build) with known byte N carrying values in [1..65]; assert detected offset == N. | Synthetic: detected offset matches injected byte in all test vectors. Hardware: WPP log entry present; CRD key written; Feature 0x47 returns plausible %. | Pre-release gate |

## Test ordering

For a release candidate:

1. **Pre-commit (developer machine)**: tests 1, 2, 4. Block on failure.
2. **CI (every push)**: tests 1, 2, 3, 4. Block on failure.
3. **Pre-merge**: tests 5, 6, 7. Block on failure.
4. **Pre-release**: tests 8, 9, 10, 11, 12, 13 in that order. All must pass for release.

## Tooling

| Tool | Source | Purpose |
|---|---|---|
| User-mode C harness | `tests/unit/` | Unit tests 1, 3, 4 |
| Driver-loaded test mode | DBG-build only; `IOCTL_M12_TEST_*` codes | Race tests 5, 6 |
| Driver Verifier | Built-in Windows | Tests 7, 8 |
| Automated install harness | `scripts/test-cycle.ps1` | Test 8 (100x install/test/uninstall) |
| Frame injection harness | DBG-build `IOCTL_M12_TEST_INJECT` | Test 13 (synthetic self-tuning) |
| MOP procedure | `docs/M12-MOP.md` | Test 9 |
| Cron soak harness | `scripts/soak-24h.ps1`, `scripts/soak-72h.ps1` | Tests 10, 11 |
| Per-OS VM matrix | Hyper-V or VMware images of Win11 22H2/23H2/24H2/25H2 | Test 12 |

## Coverage targets

| Module | Coverage target | Measurement |
|---|---|---|
| `Battery.c` (TranslateBatteryRaw) | 100% line + branch | Test 1 exhaustive input |
| `BrbDescriptor.c` (TLV parser) | 100% branch (incl. all abandon conditions per Sec 3b' (a)-(g)) | Test 3 |
| `IoctlHandlers.c` (Feature 0x47 short-circuit) | 100% line | Tests 6, 9 (VG-2) |
| `IoctlHandlers.c` (custom IOCTL surface) | 100% line | Test 4 |
| `Power.c` | 70% line (vendor command path may be untestable until OQ-F resolved) | Tests 9 (VG-5), 10 |
| `Watchdog.c` | 80% line | Test 10 |

## Exit criteria

A release ships when:

- All test classes 1-9 pass.
- Test class 10 (24h soak) passes.
- Test class 12 (compatibility matrix) passes for all SUPPORTED rows in Sec 21.
- Test class 13 (self-tuning offset) passes: synthetic path detects correct offset in all vectors; hardware path WPP log entry present + CRD key written.
- DV soak (test class 8) reports 0 violations.
- No `STATUS_*` failures in tray debug.log during soak (other than transient at sleep/wake boundaries).

## Out of scope

- Localization / internationalization tests (Sec 16.5).
- HLK test compliance (v2 release engineering).
- WHQL submission tests (v2).
- Performance benchmarking (no perf SLA for v1).
- Long-tail compatibility beyond Sec 21 matrix.

## References

- `docs/M12-PRODUCTION-HYGIENE-FOR-V1.3.md` item 6 (test plan source brief)
- `docs/M12-DESIGN-SPEC.md` Sec 6c (self-tuning algorithm) + Sec 13 (DV flags) + Sec 18 (IOCTL contract) + Sec 19 (WPP)
- `docs/M12-MOP.md` Sec 9 (validation gates VG-0..VG-14)
