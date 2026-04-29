# Activity Log — magic-mouse-tray

Format: `| Date | Update |`

| Date | Update |
|------|--------|
| 2026-04-17 | Session 1: Initial feasibility. HID 0x90 confirmed returning battery %. PIDs documented. M1-M7 complete. v1.0.0 released to GitHub. |
| 2026-04-21 | Session 2: Peer review via NotebookLM + Gemini. Issues #2, #3, #4 filed (blocking). H-001 rejected. M8 complete. |
| 2026-04-22 | Session 3: H-002 confirmed (worst-state-wins DriverHealthChecker). PR merged. Reboot test confirms COL02 stripped every boot with filter active. |
| 2026-04-24 | Session 4: H-003 opened. PSN-0001 created. |
| 2026-04-26 | Session 5: H-003 rejected (/restart-device strips COL02). H-004 rejected. startup-repair.ps1 fixed. KMDF driver confirmed as only path for scroll+battery. |
| 2026-04-27 | Session 6: Full AppleWirelessMouse.inf reviewed. Error 1077 root cause confirmed. INF design confirmed. Pre-build validation complete. |
| 2026-04-27 | Session 7: M13 Phase 0+1. Three orphan artefacts removed. Two cleanup-script bugs fixed. Reg-diff MOP gate added. Per-phase 5-block close-out gate added to playbook. |
| 2026-04-27 | Session 8: M13 Phase 2 Cell 1. Post-reboot: battery OK, scroll broken. Wheel not in COL01 descriptor -- not a filter binding issue. Cell 1 report committed. |
| 2026-04-27 | Session 9: M13 Phase 3 BTHPORT cache decode. Q1=YES Q2=NO. Phase 4A confirmed viable. Multi-agent forensic analysis. AC-01 bug fixed. |
| 2026-04-27 | Session 10: Phase 4-Omega (Disable+Enable BTHENUM). State A restored reliably. 65-min persistence confirmed. State-machine characterization complete. Phase 4-Omega alone insufficient for PRD-184. |
| 2026-04-28 | Session 11: Phase E empirical findings. Two-state HidBth descriptor cache model confirmed. ~588 probe attempts, 0 hits in Descriptor B. Filter binding NOT the axis. AP-18/19/20/21 added. |
| 2026-04-28 | Session 12 (early): D-S12-01..04 approved. M12 clean-room KMDF filter confirmed as production target. Path 5b reframed to reference-only. AP-22/23 added. |
| 2026-04-28 | Session 12 (continued): H-013 CONFIRMED FAIL (kernel-only MU test). M12 architecture finalized (D-016): pure kernel, no userland split. MU captures at D:\Backups\MagicUtilities-Capture-2026-04-28-1937\. Incident: Apple INF deleted without backup. Recovery successful. AP-24 added. PSN v1.9. |
| 2026-04-28 | Design spec (M12-DESIGN-SPEC.md) v1.8 finalized. Signing strategy folded in (self-signed cert + install-m12-trust.ps1 model). PR #14 opened. |
| 2026-04-28 | Toolchain agents (TOOL-1/2/4) delivered: mm-task-runner.ps1, run-prefast.ps1, run-sdv.ps1, run-quality-gates.ps1, check-style.sh, dispatch-pr-reviewers.sh, HelloWorld build-test scaffold. PR #15 bundle. |
| 2026-04-29 | Session 12+13 doc consolidation: PSN-0001 v1.9 -> v2.0 (H-014 RESOLVED, AP-25/26, D-S12-08..12, Session 12+13 timeline). M12-AUTONOMOUS-DEV-FRAMEWORK.md v1.x -> v2.0 (plan-review CRIT-1..4 + MAJ-8 resolved). CHANGELOG.md created. NOTICE created. README updated (M12 status, quick install placeholder, key docs table). Tool review CRIT-1/2/3 + MAJ-1..4 fixes applied to mm-task-runner.ps1 and check-style.sh. PRD-184 v1.34 (D-S12-62..71). Memory updated (battery layout + cert pattern). |
