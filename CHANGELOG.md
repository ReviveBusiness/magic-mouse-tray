# Changelog

All notable changes to Magic Mouse Battery Tray are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased] — M12 KMDF Driver (Phase 3 pending PRD approval)

### Planned additions
- `driver/MagicMouseM12.sys` — pure-kernel BTHENUM LowerFilter providing
  scroll + battery simultaneously on Magic Mouse v1 (PID 0x030D) and
  v3/2024 USB-C (PID 0x0323).
- `driver/MagicMouseM12.inf` — INF binding both PIDs with SPSVCINST_ASSOCSERVICE,
  DriverVer future-dated to win PnP rank over applewirelessmouse.
- `scripts/install-m12.ps1` — admin install: pnputil /add-driver + verify
  COL01+COL02 Status=OK.
- `scripts/uninstall-m12.ps1` — clean removal without orphaned registry keys.
- `scripts/install-m12-trust.ps1` — adds self-signed cert CN=M12-Driver to
  LocalMachine\Root + LocalMachine\TrustedPublisher (admin, one-time).
- Self-signed cert model: no test-signing boot flag required for personal use.

### Architecture decided
- M12 sits as BTHENUM LowerFilter intercepting IOCTL_INTERNAL_BTH_SUBMIT_BRB.
  Rewrites SDP HIDDescriptorList TLV on PSM 1 (SDP control channel) during
  initial pairing exchange. Does NOT operate at HID class layer. (D-S12-70)
- Battery layout confirmed final: RID=0x90 / 3-byte / UP=0xFF00/U=0x0014 /
  buf[2] direct. (H-014 RESOLVED)

---

## [0.9.0] — Session 12+13 toolchain + doc consolidation (2026-04-29)

### Added
- `scripts/mm-task-runner.ps1` — headless EWDK task queue dispatcher. Routes
  BUILD / SIGN / DV-CHECK / PREFAST / SDV / SNAPSHOT / WPPDECODE requests via
  C:\mm-dev-queue\. Includes CRIT-1 fix (SetupBuildEnv.cmd, not LaunchBuildEnv)
  and CRIT-2 fix (/tr /td sha256 RFC3161 timestamp on SIGN route).
- `scripts/run-prefast.ps1` — PREfast static analysis wrapper, PR-ready JSON
  output, EWDK env via SetupBuildEnv.cmd.
- `scripts/run-sdv.ps1` — Static Driver Verifier wrapper, SDV.log + dvl.xml
  fallback parsing, JSONL gate results.
- `scripts/run-quality-gates.ps1` — aggregate PREfast + SDV gate runner with
  SkipSdv mode.
- `scripts/check-style.sh` — style linter: comment density, TODO/FIXME,
  generic names, mixed casing, defensive null, helper-function threshold,
  pool tag, clang-format. CRIT-3 fix: mktemp + JSONL temp file replaces
  heredoc injection.
- `scripts/dispatch-pr-reviewers.sh` — sequential reviewer chain orchestrator
  using .ai/agent-templates/ templates, GitHub PR comment posting.
- `driver-test/HelloWorld.c|inf|vcxproj|sln` — minimal KMDF EWDK build-test
  scaffold for end-to-end toolchain validation before Phase 3.
- `driver/.clang-format` — WDF-preset clang-format config.
- `docs/M12-PHASE-3-PREP.md` — Phase 3 dispatch reference: task queue
  protocol, BUILD/SIGN/DV-CHECK route examples, agent brief template.
- `docs/M12-TOOL-REVIEW-2026-04-29.md` — senior driver dev adversarial review
  of TOOL-1/2/4 (verdict: CHANGES-NEEDED, 3 CRITs + 4 MAJs fixed in this
  release).
- `CHANGELOG.md` (this file).
- `NOTICE` — third-party attribution.
- `PSN-0001-hid-battery-driver.yaml` bumped to v2.0. Added H-014 RESOLVED,
  AP-25, AP-26, decisions D-S12-08 through D-S12-12, Session 12+13 timeline.
- `docs/M12-AUTONOMOUS-DEV-FRAMEWORK.md` bumped to v2.0. Plan-review CRIT
  items resolved: Wave 1 = DRIVER-1 alone, reviewer budget 12-16h, pre-flight
  HelloWorld gate, user spot-check of reviewer templates, BRB architecture
  locked.

### Fixed
- CRIT-1: mm-task-runner.ps1 BUILD route replaced LaunchBuildEnv.cmd (cmd /k,
  hangs) with SetupBuildEnv.cmd (returns after env setup).
- CRIT-2: mm-task-runner.ps1 SIGN route replaced deprecated /t timestamp flag
  with /tr /td sha256 (RFC 3161, required for Windows 11 Secure Boot).
- CRIT-3: check-style.sh add_violation() heredoc injection fixed. Violations
  now written as JSONL to a mktemp file; no shell-expansion into Python source.
- MAJ-1: run-quality-gates.ps1 dead $allPassed variable with incorrect operator
  precedence removed.
- MAJ-2: check-style.sh WdfMemoryCreate pool-tag regex corrected (3rd arg, not
  4th -- PoolTag is after Attributes+PoolType).
- MAJ-3: run-sdv.ps1 parse_source='none' now forces gate FAIL instead of
  silently passing when no SDV report artifacts found.
- MAJ-4: check-style.sh startup now checks grep PCRE availability and exits 2
  with clear error if -P is not supported.

---

## [0.8.0] — Session 12 M12 architecture + reference capture (2026-04-28)

### Changed
- M12 architecture finalized as pure-kernel BTHENUM LowerFilter, ~300-500 LOC,
  no userland split. Decision D-016. (H-013 CONFIRMED FAIL proved userland-
  gated MU design is unnecessary.)
- Path 5b (preserve Magic Utilities INF) reframed from last-resort production
  path to reverse-engineering reference only. D-S12-01.
- v1 Magic Mouse (PID 0x030D) adopted as regression control. D-S12-02.

### Added
- `docs/INCIDENT-2026-04-28-APPLE-INF-DELETION.md` — incident doc for
  destructive pnputil command without prior backup. AP-24 added to PSN+playbook.
- `docs/APPLE-DRIVER-RECOVERY-PROCEDURE.md` — step-by-step Apple INF recovery.
- `docs/M12-MAGIC-UTILITIES-REFERENCE-PLAN.md` — RE reference capture plan,
  DMCA 1201(f) / Canada 30.61 / EU Art 6 legal basis.
- MU install-state capture: D:\Backups\MagicUtilities-Capture-2026-04-28-1937\
  (41 files, 78.6 MB).
- Permanent Apple driver recovery backup:
  D:\Backups\AppleWirelessMouse-RECOVERY\.

---

## [0.7.0] — Session 11 Phase E empirical findings (2026-04-28)

### Changed
- v3 battery problem confirmed as HidBth kernel-pool descriptor cache state
  (A vs B), NOT filter binding. Filter bound in both states.
- ~588 probe attempts across 6 channels confirm: battery unreadable in
  Descriptor B from any user-mode path.
- "Apple driver traps Feature 0x47" framing REJECTED (AP-19). err=87 = device
  doesn't back the phantom 0x47 ReportID. No trap.
- "Filter inert / unbound on v3" framing REJECTED (AP-18). Wrong registry path.

### Added
- `docs/PHASE-E-FINDINGS.md`, `docs/DESCRIPTOR-A-vs-B-DIFF.md`,
  `docs/v3-BATTERY-EMPIRICAL-PROOF-AND-PATHS.md`,
  `docs/REGISTRY-DIFF-AND-PNP-EVIDENCE.md`.
- NotebookLM 150-source research synthesis (notebook bd78726f-...).
- PSN-0001 v1.6 + playbook v1.7: AP-18, AP-19, AP-20, AP-21.

---

## [0.6.0] — M13 Phases 0-4 investigation (2026-04-27)

### Added
- M13 milestone: empirical baseline + BTHPORT cache investigation.
- Phase 0 pre-flight: Windows Update paused 7d, driver fingerprints captured.
- Phase 1 cleanup: three orphan PnP/registry artefacts removed.
- Phase 2 Cell 1 (T-V3-AF): scroll broken post-reboot confirmed.
- Phase 3 BTHPORT cache decode: Q1=YES, Q2=NO (no Wheel in cache).
- Phase 4-Omega: Disable+Enable BTHENUM restores State A reliably (65-min
  persistence confirmed).
- `scripts/mm-reg-diff.sh`, `scripts/mm-phase01-run.ps1`,
  `scripts/mm-phase1-cleanup.ps1`, `scripts/mm-accept-test.ps1`.
- Per-phase 5-block close-out gate added to playbook v1.2.
- AP-12 through AP-17 added to playbook.

---

## [0.5.0] — M12 KMDF pre-validation + design (2026-04-27)

### Added
- EWDK 25H2 confirmed at D:\ewdk25h2\ (Build 26100.6584, 18.6 GB).
- Lower-filter architecture (not full function driver): WdfFdoInitSetFilter(),
  intercepts IOCTL_INTERNAL_BTH_SUBMIT_BRB. Decision D-S12-08.
- `driver/Driver.c`, `driver/HidDescriptor.c`, `driver/InputHandler.c` — BRB-
  level InputHandler.c rewrite (commit 53f00b7).
- `docs/M12-DESIGN-SPEC.md` v1.8 (PR #14, pending approval).
- `docs/M12-MOP.md` — install + uninstall MOP.
- Signing strategy: self-signed cert CN=M12-Driver + install-m12-trust.ps1
  (MagicMouseFix model, empirically validated).

### Changed
- Driver architecture revised from full function driver to BTHENUM LowerFilter.

---

## [0.4.0] — M10 startup repair + M11 battery saver design (2026-04-26)

### Added
- `startup-repair.ps1` — scheduled task checking/repairing COL02 at boot.
  PR #8 merged (7a3d3f1).
- M11 milestone defined: battery saver auto-suspend on display-off, AC unplug,
  sign-out, sleep, shutdown.

### Fixed
- Options A/B/C for COL02 restoration documented. COL02 stripped on every
  reboot when filter active — Option C (startup task) mandatory.

---

## [0.3.0] — M9 safe script + signing (2026-04-22)

### Fixed
- Issue #2: hardcoded paths in sign-and-install.ps1 replaced with
  $PSScriptRoot-relative. PR #6 (9b8b152).
- Issue #3: pnputil /delete-driver oem53.inf replaced with dynamic INF slot
  enumeration. PR #6.
- Issue #4: DriverHealthChecker.GetStatus() worst-state-wins priority logic.
  PR fix/issue-4-driver-priority-v2 (cb49ece).
- MouseBatteryReader: zero-access handle + HidP_GetCaps pre-check + 3x50ms
  retry. PR #7 (eebd3cc).

---

## [0.2.0] — M8 future-PID detection + SmartScreen docs (2026-04-21)

### Added
- `DriverHealthChecker.cs` rewritten with DriverStatus enum (Ok / NotInstalled
  / NotBound / UnknownAppleMouse). Full BTHENUM enumeration replaces single
  registry key check.
- Three-way tray menu for driver warnings.
- SmartScreen section in README: Unblock checkbox + Unblock-File workaround.
- PR #1 merged. Adversarial peer review via NotebookLM + Gemini — 3 blocking
  bugs filed as Issues #2, #3, #4.

---

## [0.1.0] — v1.0.0 initial release (2026-04-20)

### Added
- `MagicMouseTray.exe` — single .exe (178 MB, self-contained .NET 8) showing
  Apple Magic Mouse battery % in Windows tray.
- HID Input Report 0x90 battery reading via P/Invoke on COL02 collection.
- Adaptive polling: 2h / 30m / 10m / 5m tiers.
- Low-battery toast at configurable threshold (10/15/20/25%).
- Cascading alerts + persistent 1% CriticalAlert window.
- Driver health detection: warns if applewirelessmouse not installed/bound.
- Start with Windows toggle (HKCU Run key).
- MIT LICENSE, CONTRIBUTING.md (DCO), SPDX headers.
- GitHub Release v1.0.0: `ReviveBusiness/magic-mouse-tray`.
- README, diagnostics guide, SmartScreen workaround.

---

[Unreleased]: https://github.com/ReviveBusiness/magic-mouse-tray/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/ReviveBusiness/magic-mouse-tray/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/ReviveBusiness/magic-mouse-tray/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/ReviveBusiness/magic-mouse-tray/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/ReviveBusiness/magic-mouse-tray/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/ReviveBusiness/magic-mouse-tray/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/ReviveBusiness/magic-mouse-tray/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/ReviveBusiness/magic-mouse-tray/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ReviveBusiness/magic-mouse-tray/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ReviveBusiness/magic-mouse-tray/releases/tag/v0.1.0
