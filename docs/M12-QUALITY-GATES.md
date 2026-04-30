# M12 Quality Gates

## BLUF

Three PowerShell scripts wrap EWDK PREfast and SDV for Phase 3 driver agents.
Run `run-quality-gates.ps1` as the single entry point. Exit 0 = both gates pass
and the PR may proceed to the reviewer chain. Exit 1 = gate failure; PR is
blocked. Exit 2 = pre-flight error (EWDK not mounted or M12.sln not built yet).

---

## Scripts

| Script | Purpose | Typical runtime |
|---|---|---|
| `scripts/run-prefast.ps1` | PREfast static analysis via EWDK msbuild | 1-3 min |
| `scripts/run-sdv.ps1` | Static Driver Verifier via EWDK msbuild /t:sdv | 5-20 min |
| `scripts/run-quality-gates.ps1` | Sequential wrapper; aggregates both; single exit code | PREfast + SDV |

---

## Prerequisites

1. **EWDK ISO mounted at F:\\** -- `F:\BuildEnv\SetupBuildEnv.cmd` must exist.
   If it doesn't, exit code 2 is returned before any build runs.
   To remount: use Windows Disk Management or `Mount-DiskImage`.

2. **M12.sln built at least once** (Phase 3 DRIVER-1 produces this).
   PREfast runs a Build pass; it does not require a prior successful compile,
   but the project file must exist.

3. **Admin-queue context** -- both scripts are designed to be called from the
   `MM-Dev-Cycle` scheduled task (SYSTEM, admin rights). If running interactively,
   open an elevated PowerShell prompt.

4. **WSL path convention** -- pass `SolutionPath` as a Windows UNC path when
   calling from WSL:
   ```
   \\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\driver\M12.sln
   ```

---

## Exit codes

| Code | Meaning | Action |
|---|---|---|
| 0 | Gate(s) passed | PR proceeds to reviewer chain |
| 1 | Gate failed (warnings or violations) | Fix issues; re-run gates |
| 2 | Pre-flight error | Mount EWDK, or wait for Phase 3 to create M12.sln |

---

## Output files

Every run writes to a timestamped directory under `C:\mm-dev-queue\`.

### run-quality-gates.ps1 (aggregate)

```
C:\mm-dev-queue\quality-gates-<timestamp>\
    gate-results.json      <- machine-readable aggregate
    gate-report.md         <- PR-comment-ready summary (both gates)
    quality-gates.log      <- verbose run log
    prefast-report.md      <- copy of PREfast gate report
    sdv-report.md          <- copy of SDV gate report
    prefast\               <- PREfast subdirectory (see below)
    sdv\                   <- SDV subdirectory (see below)
```

### run-prefast.ps1

```
<OutputDir>\
    prefast-results.json   <- structured: warning_count, warnings[], gate_passed
    prefast-report.md      <- PR-comment table: file/line/code/message per warning
    prefast-build.log      <- full msbuild /v:diagnostic output
```

### run-sdv.ps1

```
<OutputDir>\
    sdv-results.json       <- structured: violation_count, violations[], all_rules[]
    sdv-report.md          <- PR-comment table: rule/status/detail per violation
    sdv-build.log          <- full msbuild /t:sdv output
```

---

## JSON schema (machine-readable)

### prefast-results.json

```json
{
  "tool": "prefast",
  "timestamp": "2026-04-28T23:00:00Z",
  "solution": "...",
  "configuration": "Release",
  "platform": "x64",
  "warning_count": 0,
  "build_exit": 0,
  "gate_passed": true,
  "warnings": []
}
```

Each warning entry:
```json
{ "file": "Driver.c", "line": 42, "code": "C6001", "message": "Using uninitialized memory..." }
```

### sdv-results.json

```json
{
  "tool": "sdv",
  "timestamp": "2026-04-28T23:05:00Z",
  "solution": "...",
  "rule_set": "/check:default.sdv",
  "violation_count": 0,
  "rule_count": 47,
  "build_exit": 0,
  "parse_source": "SDV.log",
  "gate_passed": true,
  "violations": [],
  "all_rules": [
    { "rule": "WdfFdoAttachDevice", "status": "PASS" }
  ]
}
```

### gate-results.json

```json
{
  "tool": "quality-gates",
  "timestamp": "...",
  "solution": "...",
  "configuration": "Release/x64",
  "fully_passed": true,
  "prefast_only": false,
  "prefast": { "exit": 0, "passed": true, "duration": 90, "warnings": 0, ... },
  "sdv":     { "exit": 0, "passed": true, "skipped": false, "duration": 720, "violations": 0, ... }
}
```

---

## How Phase 3 agents integrate

### Standard flow (every implementer agent commit)

```
1. Agent writes code + commits to worktree branch.
2. Agent submits BUILD request to admin-queue (via mm-queue-submit.sh).
3. admin-queue runner invokes:
       powershell.exe -File run-quality-gates.ps1 -SolutionPath <M12.sln>
4. Agent polls for result.txt (nonce match).
5. Agent reads gate-results.json to get pass/fail + warning/violation counts.
6. If exit 0: attach gate-report.md to PR body; proceed to reviewer chain.
7. If exit 1: read prefast-results.json / sdv-results.json; fix issues; re-commit;
              repeat up to 3 iterations (per M12-AUTONOMOUS-DEV-FRAMEWORK.md).
8. If exit 2: report EWDK/solution pre-flight failure; pause agent; notify primary session.
```

### Fast pre-commit check (PREfast only)

During rapid iteration, agents may request PREfast-only mode to avoid the 5-20 min SDV wait:

```
powershell.exe -File run-quality-gates.ps1 -SolutionPath <M12.sln> -SkipSdv
```

Exit 0 from SkipSdv mode does NOT unblock merge. Full SDV is still required.
The aggregate `gate-results.json` will have `"prefast_only": true` and
`"fully_passed": false` to make this unambiguous.

### PR body template

Paste the contents of `gate-report.md` into the PR description. Example:

```markdown
## M12 Quality Gates Report

| Gate | Status | Detail | Duration |
|---|---|---|---|
| PREfast | PASS | 0 warnings | 92s |
| SDV     | PASS | 0 violations, 47 rules | 714s |

**Overall: PASS**

Both PREfast and SDV passed. PR may proceed to reviewer chain.
```

---

## DV flags (separate from SDV)

Driver Verifier (DV) with flags `0x49bb` is a runtime soak test, not a static
gate. It runs post-install on the development machine during Phase 3 validation,
not as part of the PR build pipeline.

Reference: M12-PRODUCTION-HYGIENE-FOR-V1.3.md Section 4.

DV soak procedure: VG-8 in the test plan (`docs/M12-TEST-PLAN.md`).

---

## Deferral note (Phase 2.5)

These scripts exist as of the worktree branch `ai/m12-tool-2-prefast-sdv`.
They cannot be executed yet because M12.sln does not exist until Phase 3
DRIVER-1 (KMDF skeleton agent) runs.

**Testing deferred to Phase 3.** The scripts are designed to return exit 2
(pre-flight error) gracefully when called before M12.sln is available, so
Phase 3 agents can call them in a guard-check pattern without special-casing.

First live execution: after DRIVER-1 produces a buildable M12.sln/M12.vcxproj
and the EWDK is mounted at F:\.

---

## Activity Log

| Date | Update |
|---|---|
| 2026-04-28 | Initial scripts written (Phase 2.5); testing deferred to Phase 3 |
