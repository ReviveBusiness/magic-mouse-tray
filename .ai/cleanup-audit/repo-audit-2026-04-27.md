# Repo Audit — magic-mouse-tray — 2026-04-27

## Executive Summary

**Audit scope:** 83 items reviewed across driver source, scripts, `.ai/` outputs, root markdown, and C:\Temp artifacts.
**Candidate-for-cleanup:** 28 items flagged.
**Obvious-deletes (low risk, high confidence):** 7 items — all C:\Temp scratch files and the `.ai/learning/sessions/` session timestamp.
**Investigate-first items:** 6 items — scripts whose role vs. the new mm-dev.ps1 flow is ambiguous.

**Top 3 most-impactful cleanups by disk reclaimed:**

1. **`MagicMouseTray/bin/` and `MagicMouseTray/obj/`** — already gitignored but present on disk; `bin/` is 734 MB, `obj/` is 29 MB. `dotnet clean` or manual removal recovers 763 MB. No risk — fully reproducible from source.
2. **C:\Temp build artifacts** — `MagicMouseTray-test.exe` (185 MB, April 21), `bttrace.etl` (8 MB), `bttrace.cab` (3.5 MB). These are scratch files from the pre-KMDF investigation era. Removing recovers ~197 MB.
3. **`.ai/rev-eng/08f33d7e3ece/disasm.txt`** — 592 KB disassembly of `applewirelessmouse.sys`. The findings have been incorporated into Driver.h and InputHandler.c; the raw disasm is only useful if re-analysis is needed. Archive rather than delete (findings.md is the value; disasm.txt is regenerable from the binary).

---

## Section 1 — Driver Source Dead-Code Review

### 1.1 `#define` Caller Counts

All `#define` constants in `Driver.h` and `InputHandler.c` were checked for reference sites in the entire `driver/` tree (excluding the definition line itself).

#### Driver.h — fully active defines

| Constant | Callers | Verdict |
|----------|---------|---------|
| `IOCTL_INTERNAL_BTH_SUBMIT_BRB` | 6 | KEEP |
| `BRB_L2CA_OPEN_CHANNEL` | 6 | KEEP |
| `BRB_L2CA_OPEN_CHANNEL_RESPONSE` | 2 | KEEP |
| `BRB_L2CA_CLOSE_CHANNEL` | 4 | KEEP |
| `BRB_L2CA_ACL_TRANSFER` | 14 | KEEP |
| `MM_BRB_TYPE_OFFSET` | 1 | KEEP |
| `MM_BRB_OPEN_CHANNEL_HANDLE_OFFSET` | 1 | KEEP |
| `MM_BRB_CLOSE_CHANNEL_HANDLE_OFFSET` | 1 | KEEP |
| `MM_BRB_ACL_CHANNEL_HANDLE_OFFSET` | 1 | KEEP |
| `MM_BRB_ACL_TRANSFER_FLAGS_OFFSET` | 1 | KEEP |
| `MM_BRB_ACL_BUFFER_SIZE_OFFSET` | 2 | KEEP |
| `MM_BRB_ACL_BUFFER_OFFSET` | 1 | KEEP |
| `MM_BRB_ACL_BUFFER_MDL_OFFSET` | 1 | KEEP |
| `MM_ACL_TRANSFER_IN` | 1 | KEEP |

#### Driver.h — unused report-ID / length defines (0 callers)

| Constant | Callers | Why suspect | Recommended action | Risk if deleted |
|----------|---------|-------------|-------------------|-----------------|
| `MM_REPORT_ID_TOUCH` (0x12) | 0 | Report translation path removed in favour of SDP descriptor injection; `0x12` no longer needs a named constant | ARCHIVE (remove from header, document in comment) | Low — value is documented in comments and in KMDF-PLAN.md |
| `MM_REPORT_ID_MOUSE` (0x01) | 0 | TLC1 report ID is now encoded in `g_HidDescriptor[]` directly, not referenced in C code | ARCHIVE | Low — descriptor byte serves the same purpose |
| `MM_REPORT_ID_CONSUMER` (0x02) | 0 | Same as above; TLC2 report ID in descriptor | ARCHIVE | Low |
| `MM_REPORT_ID_BATTERY` (0x90) | 0 | Battery report pass-through handled implicitly; no code path references this | ARCHIVE | Low |
| `MM_MOUSE_REPORT_LEN` (5) | 0 | Sized for the old in-place Report 0x12→0x01 rewrite; that path is gone | ARCHIVE | Low |
| `MM_CONSUMER_REPORT_LEN` (2) | 0 | Same — sized for old translation path | ARCHIVE | Low |
| `MM_TOUCH_REPORT_MIN_LEN` (14) | 0 | Minimum length guard for old touch-frame parser, which was removed | ARCHIVE | Low |

**Note:** These 7 defines are vestigial artifacts from the `TranslateReport12` / `TranslateTouch` path that was removed when the SDP descriptor-injection approach was adopted (commit `c935acc`). Keeping them in the header creates misleading "live" constants.

#### InputHandler.c — local SDP scanner defines (all active, 1+ callers each)

All 9 SDP scanner `#define`s (`SDP_DE_UINT16`, `SDP_DE_SEQUENCE_1B`, etc.) have at least one caller inside `ScanForSdpHidDescriptor()`. **All KEEP.**

### 1.2 Static Functions — Caller Counts

| Function | Location | Callers (excluding own definition) | Verdict |
|----------|----------|-----------------------------------|---------|
| `BrbReadHandle` (FORCEINLINE) | InputHandler.c:48 | 4 | KEEP |
| `BrbReadUlong` (FORCEINLINE) | InputHandler.c:56 | 3 | KEEP |
| `BrbReadPtr` (FORCEINLINE) | InputHandler.c:64 | 3 | KEEP |
| `StoreChannelHandle` | InputHandler.c:76 | 2 | KEEP |
| `ClearChannelHandle` | InputHandler.c:91 | 2 | KEEP |
| `ScanForSdpHidDescriptor` | InputHandler.c:149 | 2 | KEEP |
| `PatchSdpHidDescriptor` | InputHandler.c:196 | 2 | KEEP |

All static functions are in use. No dead static functions in the current codebase.

### 1.3 TODO / FIXME / XXX / PENDING Comments

| File | Line | Text | Recommended action |
|------|------|------|-------------------|
| `driver/InputHandler.c` | 29 | `TODO: verify vs bthddi.h` (BRB_L2CA_OPEN/CLOSE ChannelHandle offset +0x20) | INVESTIGATE — offset value is not confirmed by static analysis; risk of wrong offset if this code path is ever exercised |
| `driver/InputHandler.c` | 31 | `TODO: verify` (ACL_TRANSFER.TransferFlags at +0x28) | INVESTIGATE — Driver.h has this at +0x80; the comment table and Driver.h disagree |
| `driver/InputHandler.c` | 32 | `TODO: verify` (ACL_TRANSFER.BufferSize at +0x2C) | INVESTIGATE — Driver.h has +0x84; conflict needs resolution |
| `driver/InputHandler.c` | 33 | `TODO: verify` (ACL_TRANSFER.Buffer at +0x30) | INVESTIGATE — Driver.h has +0x88 |
| `driver/InputHandler.c` | 34 | `TODO: verify` (ACL_TRANSFER.BufferMDL at +0x38) | INVESTIGATE — Driver.h has +0x90 |
| `driver/HidDescriptor.c` | 128 | `PENDING REVISION` (HidDescriptor_Handle() intercepts IOCTL that never reaches lower filter) | See §1.4 below |

**Critical note on TODO offsets:** The comment block in `InputHandler.c` lines 27–34 documents an **old** offset table that conflicts with the `#define` values in `Driver.h`. The `Driver.h` values (+0x80, +0x84, +0x88, +0x90) are marked "confirmed via static analysis of applewirelessmouse.sys." The comment table values (+0x28, +0x2C, +0x30, +0x38) appear to be the unverified pre-port estimates. The comment block is stale. Recommend updating the comment to match Driver.h confirmed offsets, or deleting the stale table.

### 1.4 Vestigial / Deprecated Functions

**`HidDescriptor_Handle()`** — `driver/HidDescriptor.c` lines 122–148

- Declared in `driver/HidDescriptor.h` line 9.
- Implemented in `driver/HidDescriptor.c` lines 122–148.
- **Zero call sites** in the main codebase (`driver/Driver.c` does NOT call it; the current `EvtIoInternalDeviceControl` only calls `InputHandler_HandleBrbSubmit()`).
- `driver/Driver.h` line 20 explicitly labels it: *"HidDescriptor_Handle() (IOCTL-based) is vestigial and unused."*
- The function body contains a `PENDING REVISION` comment acknowledging it intercepts an IOCTL that never reaches a lower filter.
- Called in several **worktree branches** (`agent-af251d9374353682d`, `agent-ac18516878133412b`, `agent-ad0e2b435c5b8fd1b`), which represent older development states pre-dating the BRB interception rewrite.

| Item | Path | Why suspect | Recommended action | Risk if deleted |
|------|------|-------------|-------------------|-----------------|
| `HidDescriptor_Handle()` declaration | `driver/HidDescriptor.h:9` | Declared but never called in main branch | ARCHIVE (disable, add `/* VESTIGIAL */` guard or `#if 0`) | Low — confirmed unused; worktree branches still call it but they are stale |
| `HidDescriptor_Handle()` implementation | `driver/HidDescriptor.c:122–148` | Implements IOCTL interception that cannot work for a lower filter | ARCHIVE | Low |

### 1.5 Declaration / Implementation Mismatches

No orphan declarations (declaration in .h with no .c implementation) were found for the main branch driver. All three public functions declared in `Driver.h` (`DriverEntry`, `EvtDeviceAdd`, `EvtIoInternalDeviceControl`) are implemented in `Driver.c`. The `HidDescriptor_Handle` case (§1.4) is declaration+implementation present but unused — not a mismatch.

---

## Section 2 — Scripts Review

### 2.1 Cross-Reference Map (who calls what)

| Script | Called by | Verdict |
|--------|-----------|---------|
| `scripts/mm-dev.sh` | Primary dev loop entry point (manual) | KEEP — active orchestrator |
| `scripts/mm-dev.ps1` | Called by `mm-dev.sh` via `powershell.exe` | KEEP — active build/sign/install/state phases |
| `scripts/mm-accept-test.sh` | Manual post-install; referenced in README indirectly | KEEP — active acceptance harness |
| `scripts/mm-accept-test.ps1` | Called by `mm-accept-test.sh` | KEEP — active |
| `scripts/mm-task-setup.ps1` | Referenced in `mm-dev.sh` help text + `mm-task-setup.ps1` header | KEEP — one-time scheduled-task registration |
| `scripts/mm-task-runner.ps1` | Executed by Windows Scheduled Task `MM-Dev-Cycle`; task registered by `mm-task-setup.ps1` | KEEP — active task runner |
| `scripts/mm-snapshot-state.sh` | Manual (no automated caller found) | KEEP — useful pre-change snapshot tool, but no caller in scripts |
| `scripts/mm-rev-eng.sh` | Manual; referenced in MORNING-BRIEFING archive | KEEP — still useful for binary analysis; rev-eng phase complete but tool is reusable |
| `scripts/mm-rev-eng-context.sh` | Manual; called manually after `mm-rev-eng.sh` | KEEP — companion to above |
| `scripts/mm-extract-pe.py` | Manual; no caller in repo | KEEP — installer-extraction utility; rev-eng complete but low cost to retain |
| `scripts/mm-battery-probe.ps1` | No caller in scripts; referenced in `mm-battery-probe.ps1` itself | INVESTIGATE — may be superseded by `mm-hid-probe.ps1` |
| `scripts/mm-hid-probe.ps1` | Called by `mm-snapshot-state.sh` | KEEP — active |
| `scripts/mm-state-flip.ps1` | Referenced in `KMDF-PLAN.md` restore instructions | KEEP — recovery tool |
| `scripts/capture-hid-descriptor.ps1` | No caller in scripts; mentioned in `docs/mm3-pre-validation-baseline-2026-04-26.md` as a one-time tool | INVESTIGATE — pre-validation era tool; may be superseded |
| `scripts/capture-state.ps1` | Called in some worktrees; no caller in main scripts | INVESTIGATE — unclear if still active |
| `scripts/TouchpadProbe.ps1` | No caller in scripts; mentioned in baseline doc as one-time tool; live copy in C:\Temp | INVESTIGATE — pre-KMDF investigation probe |
| `scripts/test-filter-stack.ps1` | No caller in main scripts; exists in worktrees | INVESTIGATE — may be superseded by `mm-accept-test.ps1` |
| `diagnose-driver.ps1` (root) | Referenced in README.md (scroll fix instructions mention manual steps) | KEEP — diagnostic tool for end users; referenced in docs |
| `sign-and-install.ps1` (root) | Referenced directly in README.md "Run the fix script" instructions | ARCHIVE / SUPERSEDED — see §2.2 |
| `startup-repair.ps1` (root) | Referenced in `sign-and-install.ps1` Step 9; registered as Scheduled Task | ARCHIVE / SUPERSEDED — see §2.2 |

### 2.2 Scripts from M9/M10 Legacy Work

#### `sign-and-install.ps1` — **SUPERSEDED**

| Item | Detail |
|------|--------|
| Path | `/home/lesley/projects/Personal/magic-mouse-tray/sign-and-install.ps1` |
| Why suspect | References `driver\AppleWirelessMouse.inf`, `driver\applewirelessmouse.cat`, `driver\AppleWirelessMouse.sys` — none of which exist in the `driver/` directory. The driver/ directory now contains `MagicMouseDriver.*` (KMDF custom driver). This script installs the OLD patched Apple driver, not the new KMDF driver. |
| Recommended action | ARCHIVE — move to `docs/archive/` with a header note marking it superseded by the KMDF driver install flow (`mm-dev.ps1 -Phase Install`). README still references it; README needs updating. |
| Risk if deleted | Medium — README currently directs users to run `.\sign-and-install.ps1`; deleting without updating README breaks the user-facing install story |

#### `startup-repair.ps1` — **LEGACY ACTIVE (applewirelessmouse era)**

| Item | Detail |
|------|--------|
| Path | `/home/lesley/projects/Personal/magic-mouse-tray/startup-repair.ps1` |
| Why suspect | Designed to repair COL02 after `applewirelessmouse` LowerFilter strips it. KMDF-PLAN.md (superseded doc) documents two bugs in this script that were fixed 2026-04-26. The new KMDF driver (`MagicMouseDriver`) injects a descriptor that preserves COL02 natively, making the startup repair loop unnecessary if the new driver is installed. However, the script still correctly handles `applewirelessmouse` environments. |
| Recommended action | ARCHIVE when KMDF driver ships; currently retain as LEGACY ACTIVE for users still on the old Apple driver path. Add a header comment marking it as applicable only to the `applewirelessmouse` era. |
| Risk if archived too early | Medium — users who followed the old README install path (`sign-and-install.ps1`) rely on this for battery persistence across reboots |

#### `diagnose-driver.ps1` — **LEGACY ACTIVE**

| Item | Detail |
|------|--------|
| Path | `/home/lesley/projects/Personal/magic-mouse-tray/diagnose-driver.ps1` |
| Why suspect | Checks `applewirelessmouse.sys` driver state; predates the KMDF driver. Checks LowerFilters at a hardcoded HID class key path (`{745a17a0-74d3-11d0-b6fe-00a0c90f57da}\0005`) rather than querying by device. |
| Recommended action | KEEP as LEGACY ACTIVE for now — end user diagnostic value; however, flag for update once KMDF driver ships (it should check for `MagicMouseDriver` in addition to `applewirelessmouse`). |
| Risk if deleted | Low-medium — diagnostic tool only, not in the install path |

### 2.3 Probe Scripts — One-Time Use, Not Called by Automation

| Script | Last modified | Classification | Recommended action |
|--------|--------------|----------------|--------------------|
| `scripts/capture-hid-descriptor.ps1` | 2026-04-27 (updated) | One-time pre-validation probe (MM3 baseline) | KEEP but DOCUMENT — add header comment marking as "investigation tool, not part of install flow" |
| `scripts/TouchpadProbe.ps1` | 2026-04-27 (updated) | One-time pre-validation probe (confirmed COL02 battery 49%) | KEEP but DOCUMENT — same note |
| `scripts/capture-state.ps1` | 2026-04-27 (updated) | State snapshot helper | INVESTIGATE — may overlap with `mm-snapshot-state.sh` |
| `scripts/test-filter-stack.ps1` | 2026-04-27 (via worktrees) | Stack verification tool | INVESTIGATE — overlap with `mm-accept-test.ps1` AC-01/AC-02 checks |
| `scripts/mm-battery-probe.ps1` | 2026-04-27 | Battery read probe | INVESTIGATE — overlap with `mm-accept-test.ps1` AC-06 |

---

## Section 3 — `.ai/` Output Review

### 3.1 Subdirectory Summary

| Subdirectory | Size | Last modified | Purpose |
|-------------|------|---------------|---------|
| `.ai/rev-eng/` | 1.1 MB | 2026-04-27 11:25 | Binary analysis of `applewirelessmouse.sys` |
| `.ai/archive/` | 24 KB | 2026-04-27 12:11 | Session briefing documents |
| `.ai/telemetry/` | 68 KB | 2026-04-27 12:11 | git-ops and github-ops JSONL logs |
| `.ai/learning/` | 12 KB | 2026-04-27 05:25 | Session start timestamp only |
| `.ai/snapshots/` | — | (does not exist) | Would be written by `mm-snapshot-state.sh` |
| `.ai/cleanup-audit/` | (this file) | 2026-04-27 | Audit outputs |

### 3.2 Rev-Eng Output Dirs

| SHA prefix | Binary | Source binary exists? | Status |
|-----------|--------|----------------------|--------|
| `08f33d7e3ece` | `applewirelessmouse.sys` (78,424 bytes, from `C:\Windows\System32\drivers\`) | Yes — live OS file | KEEP |

The `08f33d7e3ece/` directory corresponds to `applewirelessmouse.sys` as confirmed by the PDB path in `findings.md`:
```
D:\BWA\B69DF622-5A99-0\AppleWirelessMouseWin-7635\srcroot\x64\Release\AppleWirelessMouse.pdb
```
The source binary lives in the Windows driver store (`C:\Windows\System32\drivers\`), not in the repo. It has not been replaced or deleted.

#### Rev-eng file findings

| File | Size | Recommended action |
|------|------|--------------------|
| `.ai/rev-eng/08f33d7e3ece/findings.md` | 4 KB | KEEP — value document, summarises all confirmed architecture decisions |
| `.ai/rev-eng/08f33d7e3ece/disasm.txt` | 592 KB | ARCHIVE — large; findings incorporated into driver; regenerable from binary. Consider adding to `.gitignore` for rev-eng dirs. |
| `.ai/rev-eng/08f33d7e3ece/imports.txt` | 40 KB | ARCHIVE — raw objdump output; key imports captured in findings.md |
| `.ai/rev-eng/08f33d7e3ece/strings.txt` | 8 KB | KEEP — small; occasionally useful for cross-reference |
| `.ai/rev-eng/08f33d7e3ece/sections.txt` | 4 KB | KEEP — PE section layout reference |
| `.ai/rev-eng/08f33d7e3ece/imports-clean.txt` | 4 KB | KEEP — filtered import list |
| `.ai/rev-eng/08f33d7e3ece/contexts/` | 384 KB total | ARCHIVE — 6 disassembly context dumps; value was in deriving confirmed offsets (now in Driver.h). Regenerable via `mm-rev-eng-context.sh`. |

### 3.3 Snapshots

`.ai/snapshots/` does not exist. `mm-snapshot-state.sh` will create it on first run. No action needed.

### 3.4 Other `.ai/` Items

| Item | Recommended action | Risk |
|------|-------------------|------|
| `.ai/archive/MORNING-BRIEFING-2026-04-27.md` | KEEP — session record | None |
| `.ai/archive/PARALLEL-SESSION-BRIEF.md` | KEEP — session record | None |
| `.ai/telemetry/git-ops.jsonl` (44 KB) | KEEP — operational telemetry | None |
| `.ai/telemetry/github-ops.jsonl` (1.3 KB) | KEEP | None |
| `.ai/telemetry/events/peer-reviews.jsonl` | KEEP | None |
| `.ai/telemetry/events/session-lifecycle.jsonl` | KEEP | None |
| `.ai/learning/sessions/.current-session-start` | INVESTIGATE — contains only a timestamp (`2026-04-27 05:25:26`); no other session state | Low-risk DELETE — it's a single-line timestamp file with no cross-references |

---

## Section 4 — Repo Root Files

### 4.1 Markdown Files at Root

| File | Size | Classification | Basis |
|------|------|---------------|-------|
| `README.md` | 5.7 KB | **ACTIVE** | User-facing install guide; referenced from GitHub releases |
| `TEST-PLAN.md` | 21 KB | **ACTIVE** | Acceptance criteria; referenced by `mm-accept-test.sh` checks |
| `KMDF-PLAN.md` | 9.2 KB | **ARCHIVE** | Frontmatter explicitly states `status: superseded`; superseded by PRD-184 M12. Still useful as a root-cause and session record. |
| `CONTRIBUTING.md` | 849 bytes | **ACTIVE** | Standard contributor guide |
| `LICENSE` | 1.1 KB | **ACTIVE** | MIT license |
| `PSN-0001-hid-battery-driver.yaml` | 5.4 KB | **ACTIVE** | Problem Session Note; `status: active`, linked to PRD-184 and Issues #2-4 |

**KMDF-PLAN.md note:** The file is correctly self-labelled superseded but kept at repo root with the same visual weight as CONTRIBUTING.md and README.md. Consider moving to `docs/archive/` to signal clearly to new contributors that it is not the canonical plan.

### 4.2 Stale Lock Files, Swap Files, Build Artifacts

| Item | Path | Finding | Recommended action |
|------|------|---------|-------------------|
| Vim swap files | (none found) | None present | N/A |
| `.git/riley-session-id` | `.git/riley-session-id` | RILEY session tracking file; 29 bytes | KEEP — operational, not a stale artifact |
| `.git/riley-session-lock` | `.git/riley-session-lock` | 123-byte lock file | KEEP |
| `MagicMouseTray/bin/` | (gitignored) | 734 MB of compiled .NET output; gitignored and not committed | Run `dotnet clean` to free disk; no action in git |
| `MagicMouseTray/obj/` | (gitignored) | 29 MB of intermediate build files; gitignored | Same — `dotnet clean` clears it |
| `MagicMouseTray/obj/*.nuget.*` | (gitignored) | NuGet restore cache; 5 files tracked by git check-ignore | Confirm gitignore coverage; appears correctly excluded |

**Confirmed:** `git ls-files MagicMouseTray/obj/ MagicMouseTray/bin/` returns zero results — these directories are not tracked. The gitignore `bin/` and `obj/` patterns match correctly.

---

## Section 5 — Worktree Branches

### 5.1 Enumeration

```
worktree-agent-ac18516878133412b   → commit 5001ab3  (locked)
worktree-agent-ad0e2b435c5b8fd1b   → commit f76ccfc  (locked)
worktree-agent-ae54d3dc6baa2b378   → commit a36f3ef  (locked)
worktree-agent-af251d9374353682d   → commit 5001ab3  (locked)
```

### 5.2 What Has NOT Been Ported to Main

Comparing branch tips to main (`e6bb601`):

| Branch | Unique commits not in main | Subject |
|--------|---------------------------|---------|
| `worktree-agent-ad0e2b435c5b8fd1b` | `a36f3ef` — `feat(Driver): wire IOCTL_INTERNAL_BTH_SUBMIT_BRB` | Wire BRB handler in Driver.c (this was a mid-session state; the same work was re-done and merged to main via subsequent commits) |
| `worktree-agent-ad0e2b435c5b8fd1b` | `fda72d8` — `chore(Driver.h): add IOCTL_INTERNAL_BTH_SUBMIT_BRB constant` | Same — subsumed by main |
| `worktree-agent-ad0e2b435c5b8fd1b` | `90c8863` — `feat(InputHandler): SDP HIDDescriptorList scanner + BRB ACL interception` | Same — subsumed by main's `5ff866a` |
| `worktree-agent-ac18516878133412b` / `worktree-agent-af251d9374353682d` | `f76ccfc` — `fix(mm-accept-test): @() array wrap` | mm-accept-test StrictMode fix — NOT in main |
| `worktree-agent-ac18516878133412b` / `worktree-agent-af251d9374353682d` | `851e5cd` — `fix(mm-accept-test): strip em-dashes` | PowerShell BOM fix — NOT in main |
| `worktree-agent-ac18516878133412b` / `worktree-agent-af251d9374353682d` | `6ab4104` — `feat(scripts): mm-accept-test — 8-check acceptance test` | Earlier version of mm-accept-test, superseded by `24e79be` in main |

**Action required:** `f76ccfc` (StrictMode `.Count` safety) and `851e5cd` (em-dash strip) from `worktree-agent-ac18516878133412b` / `worktree-agent-af251d9374353682d` are bugfixes that appear NOT to have been cherry-picked to main. Verify whether `scripts/mm-accept-test.ps1` on main has these fixes, then either cherry-pick or confirm they're subsumed.

**Do not delete worktree branches** — they are currently locked (agent processes running lint/test work).

---

## Section 6 — C:\Temp Leftovers

`/mnt/c/Temp/` is accessible from WSL. Full listing of magic-mouse-tray related files:

| File | Size | Modified | Classification | Recommended action |
|------|------|----------|---------------|--------------------|
| `MagicMouseTray.exe` | 185,983,971 bytes (178 MB) | 2026-04-27 06:51 | **Current production build** — the live exe in use | KEEP — do not delete; this is the running binary |
| `MagicMouseTray-test.exe` | 185,979,875 bytes (178 MB) | 2026-04-21 22:28 | **Old test build** — pre-KMDF era, April 21 | DELETE — 6 days old, superseded by current build; identical size with minor diff suggests different iteration |
| `MagicMouseFix.cer` | 772 bytes | 2026-04-21 15:50 | Self-signed cert from `sign-and-install.ps1` run | INVESTIGATE — required if user re-runs `sign-and-install.ps1`; otherwise orphan |
| `TouchpadProbe.ps1` | 9,720 bytes | 2026-04-26 23:46 | Copy of `scripts/TouchpadProbe.ps1` for Windows-side run | DELETE — duplicate; source is in repo |
| `TouchpadProbe_reports.txt` | 40 bytes | 2026-04-26 23:47 | Output from TouchpadProbe run | DELETE — 40-byte scratch output |
| `bttrace.etl` | 8,388,608 bytes (8 MB) | 2026-04-26 23:20 | Bluetooth ETW trace from investigation | ARCHIVE — investigation artifact; delete after confirming findings are captured |
| `bttrace.cab` | 3,511,149 bytes (3.4 MB) | 2026-04-26 23:22 | Compressed BT trace | ARCHIVE — same as above |
| `capture-hid-descriptor.ps1` | 5,811 bytes | 2026-04-26 23:39 | Copy of repo script | DELETE — duplicate of `scripts/capture-hid-descriptor.ps1` |
| `capture-state.ps1` | 7,742 bytes | 2026-04-27 02:44 | Copy of repo script | DELETE — duplicate |
| `debug-hid-descriptor.ps1` | 4,760 bytes | 2026-04-26 23:28 | One-off debug script NOT in repo | INVESTIGATE — check if any findings should be captured before deletion |
| `register-task.ps1` | 1,581 bytes | 2026-04-22 18:32 | One-off task registration script | DELETE — superseded by `mm-task-setup.ps1` |
| `startup-repair-fixed.ps1` | 8,323 bytes | 2026-04-27 00:50 | Fixed version of `startup-repair.ps1` developed in Temp | INVESTIGATE — check if it matches current repo `startup-repair.ps1`; if merged, delete |
| `after-mu-services.csv`, `after-mu.csv` | 758 / 2,338 bytes | 2026-04-21 23:35 | MagicUtilities before/after service comparison | ARCHIVE — investigation data |
| `before-mu-services.csv`, `before-mu.csv` | 569 / 1,864 bytes | 2026-04-21 23:31 | Same | ARCHIVE |
| `state-post-reboot-1.json` | 2,783 bytes | 2026-04-27 02:40 | Post-reboot state snapshot | ARCHIVE — investigation data |
| `state-pre-reboot-1.json` | 2,782 bytes | 2026-04-27 01:09 | Pre-reboot state snapshot | ARCHIVE — investigation data |
| `test-filter-stack.ps1` | 8,291 bytes | 2026-04-26 22:28 | Copy of repo script (older version) | DELETE — duplicate |
| `mm-tray-new/` (dir) | 4 KB dir entry | 2026-04-27 06:50 | Build output staging dir | INVESTIGATE — may contain binaries |
| `mu-extract/` (dir) | 4 KB dir entry | 2026-04-21 23:26 | MagicUtilities installer extraction | DELETE after verifying no unrecovered findings |
| `chrome-debug-profile/` (dir) | 4 KB dir entry | 2026-04-21 09:55 | Chrome debug session | DELETE — unrelated to driver work |

---

## Summary Table — All Findings

| # | Item | Action | Risk |
|---|------|--------|------|
| 1 | `driver/Driver.h` — 7 unused report-ID/length defines | ARCHIVE (remove from header) | Low |
| 2 | `driver/HidDescriptor.h` — `HidDescriptor_Handle` declaration | ARCHIVE | Low |
| 3 | `driver/HidDescriptor.c` — `HidDescriptor_Handle` implementation | ARCHIVE | Low |
| 4 | `driver/InputHandler.c:27-34` — stale offset comment table | UPDATE comment to match Driver.h confirmed values | Low |
| 5 | `driver/HidDescriptor.c:128` — PENDING REVISION comment | UPDATE after decision on `HidDescriptor_Handle` fate | Low |
| 6 | `sign-and-install.ps1` — references non-existent Apple driver files | ARCHIVE | Medium (README link) |
| 7 | `startup-repair.ps1` — applewirelessmouse era script | KEEP as LEGACY ACTIVE; add supersession header | Medium |
| 8 | `KMDF-PLAN.md` — superseded plan at repo root | MOVE to `docs/archive/` | Low |
| 9 | `scripts/TouchpadProbe.ps1` | DOCUMENT as investigation-only | Low |
| 10 | `scripts/capture-hid-descriptor.ps1` | DOCUMENT as investigation-only | Low |
| 11 | `scripts/capture-state.ps1` | INVESTIGATE overlap with `mm-snapshot-state.sh` | Low |
| 12 | `scripts/test-filter-stack.ps1` | INVESTIGATE overlap with `mm-accept-test.ps1` | Low |
| 13 | `scripts/mm-battery-probe.ps1` | INVESTIGATE overlap with `mm-accept-test.ps1` AC-06 | Low |
| 14 | `.ai/learning/sessions/.current-session-start` | DELETE (timestamp file only) | Low |
| 15 | `.ai/rev-eng/08f33d7e3ece/disasm.txt` (592 KB) | ARCHIVE (add to rev-eng .gitignore) | Low — regenerable |
| 16 | `.ai/rev-eng/08f33d7e3ece/imports.txt` (40 KB) | ARCHIVE | Low — regenerable |
| 17 | `.ai/rev-eng/08f33d7e3ece/contexts/` (384 KB) | ARCHIVE | Low — regenerable |
| 18 | `MagicMouseTray/bin/` (734 MB) | `dotnet clean` — not in git | Low |
| 19 | `MagicMouseTray/obj/` (29 MB) | `dotnet clean` — not in git | Low |
| 20 | `worktree-agent-ac18516878133412b/af251d` — `f76ccfc` / `851e5cd` fixes | CHERRY-PICK to main if not already applied | Medium |
| 21 | `C:\Temp\MagicMouseTray-test.exe` (178 MB) | DELETE | Low |
| 22 | `C:\Temp\TouchpadProbe.ps1` | DELETE (duplicate) | Low |
| 23 | `C:\Temp\TouchpadProbe_reports.txt` | DELETE | Low |
| 24 | `C:\Temp\capture-hid-descriptor.ps1` | DELETE (duplicate) | Low |
| 25 | `C:\Temp\capture-state.ps1` | DELETE (duplicate) | Low |
| 26 | `C:\Temp\register-task.ps1` | DELETE (superseded) | Low |
| 27 | `C:\Temp\test-filter-stack.ps1` | DELETE (duplicate, older) | Low |
| 28 | `C:\Temp\startup-repair-fixed.ps1` | INVESTIGATE — check vs repo; delete if merged | Low-Medium |
| 29 | `C:\Temp\debug-hid-descriptor.ps1` | INVESTIGATE — not in repo | Medium |
| 30 | `C:\Temp\bttrace.etl` + `bttrace.cab` (11.5 MB combined) | ARCHIVE or DELETE | Low |
| 31 | `C:\Temp\mu-extract/` | DELETE after verifying findings captured | Low |
| 32 | `C:\Temp\chrome-debug-profile/` | DELETE | Low |

---

*Audit generated 2026-04-27. Read-only. No files were modified during this audit.*
