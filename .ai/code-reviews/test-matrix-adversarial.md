# Adversarial Review: M13 Baseline & Cache Test Plan

**Review date:** 2026-04-27
**Reviewer:** Adversarial review agent (Claude Sonnet 4.6)
**Subject:** `.ai/test-plans/m13-baseline-and-cache-test.md` v1.0
**Playbook ref:** `.ai/playbooks/autonomous-agent-team.md` AP-1 through AP-11

---

## 1. Test Matrix Axes — What Is Missing

The current matrix is a 2×2: (mouse model: v1/v3) × (driver state: AppleFilter/NoFilter), with a fixed test sequence at each cell. It misses several axes that can produce state-dependent results or mask failures.

### 1.1 USB-C charging cable connected during test

**Problem:** Step 3 of Phase 1 explicitly calls out the orphan `LowerFilters=MagicMouse` binding on the USB MI_01 device and removes it because it would Code-39 if the mouse is plugged via USB-C. But the test matrix never includes a cell where the USB-C cable *is* connected. This is not paranoia — the Magic Mouse charges via USB-C, users plug it in, and the HID enumeration changes completely when it does: Bluetooth and USB paths compete for the same logical device. The orphan filter is removed, but nothing confirms its removal holds after a re-pair cycle or a Windows Update.

**Recommendation:** Add two cells: T-V3-AF-USB (v3 + AppleFilter + USB-C connected) and T-V3-NF-USB (v3 + NoFilter + USB-C connected). Confirm device enumerates via Bluetooth path even when USB cable present. Confirm Code-39 does NOT reappear. These are 15-minute cells, not full re-runs.

### 1.2 Sleep/wake cycle (not just reboot)

**Problem:** The matrix includes "reboot → test" but not "sleep → wake → test." These are categorically different. Sleep/wake uses S3 or Modern Standby (S0ix), which does NOT re-run PnP AddDevice for most BT devices — it relies on resume. The BTHPORT cache may behave differently post-wake vs. post-boot: the descriptor might be re-read from RAM rather than registry on wake, meaning a registry patch applied before sleep could present the *old* descriptor to HidBth on resume. The plan acknowledges "Sleep/wake?" under Open Questions but defers it. It should not be deferred — this is the most common user scenario (nobody reboots to use their mouse).

**Recommendation:** Add a sleep/wake sub-step to each Phase-2 test cell, after the reboot sub-step. Specifically: sleep via `Start-Sleep -Seconds 30 && shutdown /h` (hibernate) or `rundll32 powrprof.dll,SetSuspendState 0,1,0` then wake. Run the "test" step immediately on resume. Add to halt conditions: mouse not reconnecting within 60s of wake = stop, capture.

### 1.3 Windows Update arriving mid-test

**Problem:** The plan acknowledges this risk under Open Questions but has no mitigation step. A Windows Update that touches `bthport.sys`, `HidBth.sys`, or `applewirelessmouse.sys` will invalidate all Phase-2 data collected before and after the update without any marker in the ETW trace. The test session is estimated at ~4 hours — long enough for Automatic Updates to trigger on a non-managed machine.

**Recommendation:** Before Phase 1 begins, pause Windows Update for 7 days via `UsoClient.exe PauseUpdate` or Group Policy (`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\NoAutoUpdate`). Log the Windows build number and driver version of every affected `.sys` at Phase 1 start. This is a 2-minute pre-flight step, not a full matrix axis.

### 1.4 Mouse battery level: low vs. high

**Problem:** The battery percentage is both a *test input* (AC-06: does the battery read succeed?) and a *test variable* (does a very low battery level affect HID enumeration or driver behavior?). Apple's `applewirelessmouse.sys` may handle low-battery state reports differently. More concretely: a mouse at 5% may have radio instability, creating false-negative scroll failures that look like driver issues. The plan has no check on battery level before starting the matrix.

**Recommendation:** Pre-flight check: `mm-accept-test.sh` battery read should confirm battery >20% before running the matrix. If <20%, charge to >50% before testing. Add to Phase-1 success criteria. This is not a full axis — it is a pre-condition check.

### 1.5 Multiple Bluetooth devices contending

**Problem:** The test machine almost certainly has other BT devices paired (headphones, keyboard, phone, second mouse). BT piconet congestion affects connection event timing, which affects HID input latency, which affects whether "scroll smooth?" reads as yes or no from a human tester. During the "2-finger scroll for ≥3 seconds" step, a concurrent BT audio stream (e.g., headphones playing music) could cause enough congestion to produce intermittent scroll drops that look like driver failures.

**Recommendation:** Pre-flight: confirm no other BT audio devices are actively streaming during Phase 2. This is an environmental control, not a matrix axis. Add to Phase-1 pre-flight checklist.

### 1.6 Fresh pair vs. heavily-used pairing (pairing bond age)

**Problem:** The BTHPORT descriptor cache is written when the SDP exchange happens at pairing time. A fresh pair (new entry in `BTHPORT\Parameters\Devices\<mac>`) vs. a cache entry that has been in the registry for weeks may differ if a firmware update occurred on the mouse between pairings. The v3 MAC is known (`d0c050cc8c4d`) but its pairing age is not documented. The v1 MAC is unknown ("TBD; user provides"), which means its cache entry age is completely unknown.

**Recommendation:** Phase 3 step 3 should record the `LastSeen` or creation timestamp of the v1 registry key alongside the descriptor decode. Note whether v1 has ever been paired on this machine before. If v1 is a fresh pair, the descriptor cache will reflect current firmware — potentially different from what v3 (an older pairing) shows.

### 1.7 Firmware version of the Magic Mouse itself

**Problem:** The plan defers firmware version differences: "run the same test suite on a system with a different mouse firmware (deferred — out of M13 scope; flag if observed)." But within M13, the v1 and v3 may have *different firmware versions* on the same physical versions of the mouse. The plan has no step to read or record mouse firmware revision from the SDP record or BT device properties during Phase 3. If v3 results differ from v1, there is no way to determine whether the difference is firmware-driven or architecture-driven.

**Recommendation:** During Phase 3, record `bluetoothdevice.FirmwareRevision` from `Windows.Devices.Bluetooth` API or extract from the SDP record (attribute 0x0009, Profile Descriptor List, or version fields). Log it alongside the decoded descriptor. Takes 5 minutes to add to `mm-bthport-read.ps1`.

---

## 2. "Test" Step Definition — What It Misses

The test step (pointer corner-to-corner, 2-finger scroll, AC-Pan swipe, L/R click, tray screenshot) is correct for a smoke test but inadequate as a behavioral baseline. Specific gaps:

### 2.1 Inertial scroll ("fling" gesture)

The Magic Mouse's defining UX characteristic is momentum-based scrolling: you flick and it coasts. This behavior is synthesized in `applewirelessmouse.sys` via software inertia (the driver sends continued wheel events after the finger lifts). If the patch path in Phase 4 routes scroll through a different stack (e.g., userland HID gesture daemon), inertial behavior may disappear or become jerky. The current test only checks "scroll smooth?" qualitatively. It does not check for inertia continuation after finger lift.

**Recommendation:** Add to "test" step: perform a fast 2-finger flick, lift fingers, verify scroll continues for >0.5s. Record human yes/no. This is 5 seconds per test step.

### 2.2 Two-finger right-click

Standard Mac trackpad behavior: 2-finger tap = right-click. The Magic Mouse does NOT do this by default, but `applewirelessmouse.sys` may synthesize it differently than a generic HID stack. Not testing this means we could ship a path where 2-finger tap produces unexpected input.

**Recommendation:** Add: 2-finger tap with right-click recording. Low cost, catches one regression category.

### 2.3 Dwell click / no-click scroll

Not applicable for the Magic Mouse specifically (it is a clicker, not a Force Touch device). Can skip.

### 2.4 Quantitative vs. human-yes/no measurement

**This is the most important gap in the test step definition.** The plan defines "test" as:
- "verifies pointer responsiveness" — human checks, no metric
- "verifies wheel events" — human checks, no metric  
- "Quick subjective notes from human (scroll smooth? click registers? gesture continuous?)"

There is no quantitative measurement. For a test that is supposed to produce a yes/no answer to Q7 ("can we deliver scroll+battery without a kernel driver?"), the scroll quality evidence is entirely subjective. If the answer is "scroll works but feels slightly different," the plan produces ambiguous output (see Section 8).

**Recommendation:** At minimum, capture WM_MOUSEWHEEL / WM_MOUSEHWHEEL event counts and deltas via a simple PowerShell listener or the existing ETW HID channel during the scroll gesture. A 3-second scroll should produce a predictable number of events; compare across cells. This quantifies "smooth" vs. "stuttery" vs. "absent" objectively. The `mm-hid-probe.ps1` could be extended to do live event capture during a timed window.

### 2.5 Acceptance test mismatch with test matrix context

**AC-01 checks for `MagicMouseDriver` in LowerFilters.** In T-V3-AF and T-V1-AF cells, the driver state is `AppleFilter` (meaning `applewirelessmouse` in LowerFilters, not `MagicMouseDriver`). This means AC-01 will FAIL in every AppleFilter cell by design. The plan says the accept test produces "8 checks" but does not note that AC-01 is structurally inapplicable in 2 of the 4 matrix cells. The JSON output will show 7/8 PASS as the best possible result for AppleFilter cells — which could be misread as a failure without this context documented.

**Recommendation:** The test orchestrator should document per-cell which checks are "expected PASS," "expected FAIL (driver state)," and "unexpected FAIL (bug)." The distinction matters for interpreting Phase-2 results. Consider adding a `--mode applefilter|nofilter|mmd` parameter to `mm-accept-test.ps1` that adjusts expected AC-01 pass/fail accordingly.

---

## 3. Capture Completeness

### 3.1 ETW providers — likely incomplete

The plan specifies "ETW Bluetooth + HidClass + Kernel-PnP providers via `wpr.exe`" without naming the providers. This is a significant gap. The relevant ETW providers for this work are:

| Provider | GUID | Why needed |
|---|---|---|
| `Microsoft-Windows-Bluetooth-MTPEnum` | `{B74F3E73-1B24-4D38-9E6E-B5E38B4F3D8B}` | PnP enumeration via BTHENUM |
| `Microsoft-Windows-Bluetooth-BluetoothDevice` | `{E2B7B9A0-4DC1-4B6B-965E-23B23BF7F9F6}` | HCI events, connection lifecycle |
| `Microsoft-Windows-Bluetooth-Policy` | `{A6A67D20-C849-434F-934E-F92E31F64A29}` | Policy decisions affecting enum |
| `Microsoft-Windows-BTHPORT` | (kernel ETW provider) | BTHPORT internal ops, descriptor cache reads |
| `Microsoft-Windows-Kernel-PnP` | `{9C205A39-1250-487D-ABD7-E831C6290539}` | AddDevice, RemoveDevice, filter binding |
| `Microsoft-Windows-UserModePowerService` | not needed for BT; exclude |
| HidClass kernel trace | available via WMI/kernel logger | per-TLC input report flow |

The wpr.exe built-in "Bluetooth" profile captures MTPEnum and BluetoothDevice but typically misses BTHPORT internal events and HidClass. The plan's ETW section assumes wpr.exe will capture the right providers without specifying which profile or manifest. If the wrong providers are active, the ETL file will be large but missing the key events that explain why COL02 does or does not appear after a descriptor patch.

**Recommendation:** `mm-test-matrix.sh` should use explicit `wpr.exe -start <provider-list>` or equivalent `tracelog.exe`/`xperf` invocations with named providers, not just "Bluetooth + HidClass + Kernel-PnP." Add a validation step that verifies the ETL file contains at least one event from each expected provider before the cell is considered captured.

### 3.2 DebugView log rollover

DebugView accumulates kernel debug output in `C:\mm3-debug.log`. Over a 4-hour session with 4 cells each doing reboot+repair, this log will grow substantially and may not be trivially searchable per-cell. There is no log rotation or per-cell marker injected into the debug stream.

**Recommendation:** At the start of each test cell, have the orchestrator inject a sentinel via `DbgPrint`-equivalent (`OutputDebugString` from a user-mode process writes to the kernel debug stream): `[mm-test-matrix] === CELL T-V3-AF START ===`. This creates clear boundaries in the DebugView log without requiring a separate tool.

### 3.3 Procmon filter scope

The plan filters Procmon to `BTHPORT.SYS`, `HidBth.sys`, `applewirelessmouse.sys`. This misses:
- `HidClass.sys` — the Windows HID class driver that arbitrates between COL01 and COL02 PDOs
- `bthusb.sys` — the BT radio stack below BTHPORT (relevant if USB-C cable is ever inserted)
- Registry access by `svchost.exe` hosting the BT service stack — relevant for cache read events

**Recommendation:** Extend the Procmon filter to include `HidClass.sys` and process name `svchost.exe` with path filter `BTHPORT\Parameters\Devices`.

### 3.4 No BRB (Bluetooth Request Block) capture

The plan mentions BRB traffic as the highest-leverage empirical evidence source in the playbook (Playbook section "Empirical-evidence collection"). Phase 2 has no BRB capture step. BRB captures during pairing would directly show what the SDP exchange produces and whether the descriptor in the BRB matches the registry cache. This was the approach that originally revealed the MU architecture (commit context references BRB handler).

**This is not a "nice to have" — it is a direct gap between what the playbook says is highest-value and what the plan captures.** The plan's ETW channel closest to BRB traffic is BTHPORT, but BRB traffic is only available at the kernel trace level, not ETW.

**Recommendation:** Add BRB capture via WPP tracing (`tracelog.exe -start bthport -f bthport.etl -p {36DA592D-E43B-4D1E-9B93-D4C8F33D90D0}`) during Phase 2 pair/repair steps. The orchestrator already opens ETW at the start of each cell; add BRB session alongside.

---

## 4. Decision Branches in Phase 4 — Exhaustiveness Analysis

### 4.1 Are 4A / 4B / 4C mutually exclusive?

Not entirely. 4A and 4B share a precondition: the cached descriptor *has* COL02. They diverge on whether `applewirelessmouse` strips it. 4B and 4C share the remediation (patch the cache). The branches are internally consistent but the entry conditions overlap:

- 4A: descriptor has COL02 → Apple strips it → try stack substitution
- 4B: descriptor missing COL02 but has scroll → patch cache to add COL02
- 4C: descriptor missing both → keep filter, patch cache

**Gap:** the plan does not define what "has COL02" means precisely. Does it mean any vendor-page collection (UP=0xFF00), or specifically UP=0xFF00 U=0x0014 with the correct byte length? What if the descriptor has a COL02-like collection with wrong usage? This ambiguity in the Phase 3 → Phase 4 handoff means the branch selection could be contested in execution.

**Recommendation:** Phase 3 should produce a structured decision record with these specific boolean fields:
- `col02_present_in_cache`: true/false (UP=0xFF00 U=0x0014 present in decoded descriptor)
- `scroll_usages_present_in_cache`: true/false (Wheel and/or AC-Pan declared)
- Branch is then deterministic from these two booleans.

### 4.2 Missing Branch 4D

**4D: Cached descriptor has COL02 AND Apple does NOT strip it (Apple passes it through)**

This would mean the current AppleFilter mode *should* work for battery, but something else in the stack (HidClass, a device policy, or the tray app's read path) is blocking it. The plan's Phase 2 "Expected battery: ✗ (per overnight finding)" for T-V3-AF assumes this is impossible, but it is a real hypothesis that Phase 3 evidence might surface. If Phase 3 shows COL02 in cache AND Apple doesn't strip it (verifiable by HID probe showing COL02 enumerated in AppleFilter mode), then the bug is upstream in the tray app or the HidD_GetInputReport call, not in the driver architecture at all.

**Recommendation:** Add Branch 4D: "If Phase 3 shows COL02 in cache AND Phase 2 T-V3-AF shows COL02 enumerated: investigate tray-app read path, not driver stack." This would be the easiest path to a fix and the plan should not structurally exclude it.

### 4.3 Rollback path in Branch 4A

Branch 4A tests removing `applewirelessmouse` and substituting userland scroll synthesis. The plan does not specify the rollback for this step. Removing `applewirelessmouse` as the function driver requires a PnP reinstall; the rollback is not simply "restore registry export" — it requires `pnputil /install-driver applewirelessmouse.inf` or equivalent. This is not trivially reversible in the same way Phase 1 is.

**Recommendation:** Branch 4A must specify the exact commands to restore `applewirelessmouse` as function driver before attempting the substitution. The snapshot step exists but the restore procedure is undocumented.

---

## 5. Halt Conditions — Gaps

### 5.1 "Completely unresponsive" excludes partial failure

Phase 2 halt condition: "v3 mouse becomes completely unresponsive." This misses:
- Pointer moves but scroll stops: a partial failure that the test might run through without halting, producing ambiguous baseline data
- Mouse reconnects intermittently: a stochastic failure that individual test steps pass but the session is unreliable
- Mouse pointer stutters or shows high latency: could be radio interference, low battery, or driver issue — indistinguishable without quantitative capture (see Section 2.4)

**Recommendation:** Extend halt conditions to: "Mouse exhibits any of: pointer stutter >3 events in 10s, scroll events stop for >5s during active gesture, connection drops and does not recover within 30s. In any of these cases: stop, capture, do not proceed to next cell."

### 5.2 "Phase-2 elapsed time exceeds 2h 30min — measured how, by whom?"

The plan says the orchestrator manages timing, but it does not specify whether the 2h 30min clock is wall-clock time from Phase-2 start, or cumulative test-cell time, or something else. The phase structure includes reboot steps — reboots typically take 2-5 minutes, but on a slow machine could take 10+. The timer is ambiguous.

**Recommendation:** The orchestrator should record `$phase2StartTime = Get-Date` at Phase 2 entry and check `(Get-Date) - $phase2StartTime > [TimeSpan]::FromMinutes(150)` at the start of each cell. This is deterministic and unambiguous. Also: define what "stop, reassess scope" means — which cells are dropped first? Recommended: drop T-V1-NF (the "?" cell) and T-V1-AF to preserve v3 data integrity.

### 5.3 No halt condition for corrupt ETW capture

If the ETW session fails to start (permission issue, another session already running, disk full), the plan has no halt condition. The cell would proceed and produce test data with no trace. The ETW capture is the primary forensic artefact for Phase 3 and 4 analysis.

**Recommendation:** After `wpr.exe start`, verify the session is active via `wpr.exe -status`. If not active, HALT — do not proceed with the test cell.

---

## 6. Reproducibility Gaps

### 6.1 Variables not controlled between runs

If M13 is re-run a week later:

| Variable | Controlled? | Risk |
|---|---|---|
| Windows build number | Not locked | Windows Update could change `HidBth.sys` version |
| `applewirelessmouse.sys` version | Not recorded | The inf might be updated by Apple Software Update |
| BTHPORT driver version | Not recorded | Same as above |
| Mouse firmware version | Not recorded | OTA update possible |
| Host machine's other BT pairings | Not controlled | New devices could have been paired, changing piconet state |
| Time-of-day RF interference | Not controlled | 2.4GHz congestion varies by environment and time |
| Mouse battery level at start | Not controlled | See Section 1.4 |

The plan records post-cleanup registry exports and `mm-snapshot-state` tarballs, which will capture the Windows driver versions. But Phase 3 has no step to record the mouse firmware revision or the state of other BT pairings.

**Recommendation:** Pre-flight record:
- `Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\bthport" ` → ImagePath + version
- `Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\HidBth"` → same
- Windows build: `(Get-WmiObject Win32_OperatingSystem).BuildNumber`
- List all paired BT devices: `Get-PnpDevice -Class Bluetooth`

This is a 10-line addition to `mm-snapshot-state.sh`.

### 6.2 Implicit assumption: same MAC address between runs

The v3 MAC `d0c050cc8c4d` is hardcoded in Phase 3. If the user unpairs and re-pairs the mouse on a fresh Windows installation (or if the mouse MAC changes — rare but possible after factory reset), the registry path changes. This is low risk for the current M13 session but would break any automation that hardcodes the MAC.

---

## 7. Anti-Pattern Triggers (AP-1 through AP-11)

### AP-1: First-principles design when a reference exists

**Plan section:** Phase 4 Branch 4A, "Try removing `applewirelessmouse` and using `usbccgp`-equivalent generic HID stack... or just HidBth direct."

**Trigger: PARTIAL.** The plan correctly references `applewirelessmouse.sys` as the function driver and the MU finding. However, Branch 4A proposes a "userland gesture-to-wheel daemon" as a scroll synthesis replacement without checking whether this has been done by existing tools. `MagicUtilities` itself likely has a userland component that does exactly this. Before building a userland daemon, the plan should enumerate whether MU's userland component can be studied or the approach validated against it. The plan defers firmware-version differences but does not ask: "does MU's userland gesture synthesis have a reference implementation we can study?"

**Severity:** Low for Phase 3 (read-only); Medium for Phase 4A execution.

### AP-2: Stale review corpus

**Plan section:** Pre-execution gate item 4: "NLM corpus refreshed (registry-diff report + this M13 plan ingested as sources)."

**Trigger: PARTIAL.** The gate exists and is correct. However, it specifies only two new sources: the registry-diff report and the M13 plan itself. It does not include:
- The overnight session's empirical findings (the three facts in the "Why M13" section)
- The MU footprint analysis from the Apr 3 backup (referenced in Phase 3 comparison step)
- The `5ff866a` SDP-scanner filter commit's design notes

If the peer-review query in gate item 5 draws on a corpus missing these, it will produce the same stale-verdict problem the playbook was written to prevent.

**Recommendation:** Expand gate item 4 to enumerate all new sources since last ingestion. The M13 pre-exec phase should check NLM corpus source list and diff against `.ai/telemetry/events/peer-reviews.jsonl` last timestamp.

**Severity:** High. This is the most costly failure mode (overnight session burned 6+ hours on it).

### AP-3: Worktree branched from old main

**Plan section:** Not mentioned.

**Trigger: NOT TRIGGERED** (M13 is a human-executed test plan, not an agent worktree spawn). However, if Phase 4B builds `mm-bthport-patch.ps1` using an autonomous agent, this AP applies and is not addressed. The brief for that agent would need to specify branchpoint verification.

**Severity:** N/A for human execution; High if Phase 4 scripts are agent-built.

### AP-4: Manual em-dash discovery cycle

**Plan section:** Not mentioned for Phase 4 scripts.

**Trigger: LATENT.** The plan instructs building `mm-bthport-read.ps1` and `mm-bthport-patch.ps1` in Phase 3 and 4B respectively. If these are written by an agent, they will encounter the em-dash/en-dash issue. The playbook documents this explicitly but the test plan's Phase 3/4 build steps do not include a lint gate before first execution.

**Recommendation:** After building each new `.ps1`, run `mm-lint.sh` against it before first execution. The lint script exists in `scripts/mm-lint.sh`. This should be a mandatory step in the Phase 3 and 4 build sequences.

**Severity:** Medium (predictable runtime failure without lint).

### AP-5: Opus running haiku-tier work

**Plan section:** Pre-execution gates reference "three specialist reviewer agents."

**Trigger: POTENTIAL.** If the three reviewer agents are spawned at Opus tier for mechanical review tasks (reading registry keys, validating script structure), that is tier mismatch. The plan does not specify the tier for reviewer agents.

**Recommendation:** Reviewer agents producing read-only reports → Sonnet. The only Opus-warranted work in M13 would be the Phase 4 architectural decision (which branch to take and why), not the empirical capture.

**Severity:** Low-Medium (cost, not correctness).

### AP-6: Multi-step changes without commits

**Plan section:** Phase 1 steps, Phase 4 build steps.

**Trigger: PARTIAL.** Phase 1 has 9 steps and commits only at the end via `mm-snapshot-state.sh`. If step 5 or 6 breaks the system and the pre-cleanup export is not captured, there is no intermediate rollback point. Phase 4B builds `mm-bthport-patch.ps1` and then immediately runs it — no commit between "script written" and "script executed against live registry."

**Recommendation:** Phase 1: commit the pre-cleanup export to the repo immediately after step 1 (before any cleanup mutations). Phase 4B: commit the patch script before first execution, so the script is recoverable even if the execution corrupts state.

**Severity:** Medium.

### AP-7: Trusting agent self-reports without verification

**Plan section:** Phase 2 per-cell capture, pre-execution gate item 2 ("Three specialist reviewer agents complete").

**Trigger: YES.** Two instances:

1. The test orchestrator (`mm-test-matrix.sh`) is not yet written. When it is written (likely by an agent), the plan relies on it to auto-start all capture channels. If the orchestrator reports "capture started" but the ETW session silently failed (see Section 5.3), the cell data is uncaptured and the session proceeds. The plan has no independent verification of capture artefact existence.

2. Gate item 2 requires three reviewer agents to "complete" — but completion is verified by the gate check only if the commit exists. An agent that writes a malformed or empty report and commits it passes the gate without delivering value.

**Recommendation:** After each test cell closes, the orchestrator should verify artefact existence: assert `.etl` file size > 0, `.PML` file exists and is non-empty, `mm-accept-test-<ts>.json` exists. Fail the cell if artefacts are missing — do not continue to the next cell.

**Severity:** High. This is the same failure mode as the overnight session where the build reported success but the binary was deleted post-build.

### AP-10: Missing post-condition validation after Phase 1 steps

**Plan section:** Phase 1, steps 2-6, halt condition.

**Trigger: YES.** The plan specifies "each verified before next" for Phase 1 but only defines success criteria at the *end* of Phase 1 (scroll works, LowerFilters correct, no MU residue). The companion script `mm-phase1-cleanup.ps1` is described as "halts on any verify failure" but this script does not yet exist — it is listed as something to be built before execution. The test plan's Phase-1 post-condition validation is delegated to a not-yet-written script without specifying what "verify failure" means for each individual step.

For example, step 2 removes the dead `MagicMouseDriver` service key. What verifies it is gone? `sc query MagicMouseDriver` should return error 1060. Step 3 removes `LowerFilters=MagicMouse` from USB MI_01. What verifies it is gone? A `reg query` on the specific path. None of these per-step checks are documented; they are left to whoever writes `mm-phase1-cleanup.ps1`.

**Recommendation:** Define per-step post-condition commands inline in the test plan, not delegated entirely to an unwritten script. This ensures that if the script is written incorrectly, the human executor has a reference to check against.

**Severity:** High. AP-10 was the original failure that led to silent driver installs that didn't take effect. Phase 1 is the cleanup foundation — if it fails silently, every subsequent phase is baseline-corrupted.

### AP-11: No registry backup before driver experimentation

**Plan section:** Phase 1 step 1, Phase 4 branch 4B step 1.

**Trigger: NOT TRIGGERED — but the backup location is fragile.** Phase 1 step 1 explicitly exports to `D:\Users\Lesley\Documents\Backups\<ts>-pre-cleanup.reg`. Phase 4B step 1 says "Snapshot current state + reg export." However:

1. The `D:\` drive is assumed to exist. If the machine uses only `C:\`, this path silently fails (PowerShell's `reg.exe export` to a non-existent drive will error, and if the script doesn't check exit code, it proceeds without backup).

2. Phase 4B step 1 says "reg export" but does not specify the exact path or command, unlike Phase 1's explicit path. In execution, if someone runs Phase 4 without re-reading Phase 1's backup convention, the backup may end up in an undocumented location.

**Recommendation:** Define a single canonical backup variable `$MM_BACKUP_DIR` at session start (defaulting to `C:\Users\Lesley\Documents\Backups` with D:\ check), used by both Phase 1 and Phase 4. Document this variable in both phases explicitly.

**Severity:** Medium (backup exists if the drive exists, but the assumption should be explicit).

---

## 8. Ambiguous Results — The Core Risk

**This is the plan's most significant structural weakness.** The test is designed to produce a clean yes/no on Q7 ("can we deliver scroll+battery without a kernel driver?"). But the test plan has no decision criteria for the "intermittent" outcome, which is the most likely real-world result.

### Scenarios that produce ambiguous output:

1. **Scroll works 95% of the time after the patch.** The "test" step is a 3-second human observation. A 5% drop rate will not be caught. The plan would record PASS. The shipped solution would exhibit random scroll drops in production.

2. **Battery reads correctly in the AppleFilter cell, sometimes.** AC-06 attempts `HidD_GetInputReport` three times with 50ms sleep. If the battery report is only available during specific BT connection events (e.g., immediately after pairing), the three-attempt window may miss it, returning FAIL when the hardware can actually deliver it.

3. **Scroll works for v3 firmware but not all firmware versions.** The plan captures one firmware version (whatever is installed on test day). It cannot detect firmware-dependent behavior without a second device with different firmware.

4. **Phase 4B patch works, then breaks after sleep.** See Section 1.2. The patch modifies the registry cache. On a sleep/wake cycle, if BTHPORT re-reads the cache from a different source or validates against a checksum, the patched descriptor may be rejected silently on resume.

### What to do about it:

The plan needs a defined procedure for "intermittent" results:

> "If any test cell produces a result that varies between run attempts (scroll present on first test, absent on second within the same cell), record the cell as INTERMITTENT. Do not proceed to Phase 4. Capture 3 additional identical iterations of that cell. If >50% pass, classify as DEGRADED (proceed with caution, document). If <50% pass, classify as FAIL."

Without this, the plan conflates "works during 3-second observation" with "works reliably enough to ship."

---

## VERDICT: CHANGES-NEEDED

The plan is structurally sound — the phase structure, the decision tree, and the capture protocol are all above average for driver experimentation plans. The fundamental hypothesis (patch the BTHPORT cache rather than building a kernel driver) is well-motivated and the Phase 3 → Phase 4 decision logic is pre-written rather than improvised.

However, the following items must be addressed before execution:

### Required before Phase 1:

1. **Sleep/wake axis:** Add a sleep/wake sub-step to Phase 2 test cells. Without it, the most common failure mode is not tested.

2. **Quantitative scroll measurement:** Replace "human checks scroll" with WM_MOUSEWHEEL event count capture. Without this, Q7 has no objective evidence.

3. **ETW provider list:** Specify named ETW providers in `mm-test-matrix.sh` and add post-start ETL verification.

4. **AC-01 expected-state documentation:** Document that AC-01 is a structural FAIL in AppleFilter cells, or add `--mode` parameter to accept test.

5. **Intermittent result procedure:** Define what happens when a test cell produces variable results.

6. **AP-10 per-step checks:** Inline post-condition commands for each Phase 1 step.

7. **NLM corpus gate expansion:** Gate item 4 must enumerate all new sources since last ingestion.

### Recommended (defer at documented risk):

- USB-C cable test cells (15 min)
- Windows Update pause pre-flight (2 min, should just do it)
- Branch 4D (Apple passes COL02 through, tray-app is the bug)
- BRB capture addition to Phase 2
- Mouse firmware version recording in Phase 3
- `$MM_BACKUP_DIR` canonical variable

---

## Summary

**Report path:** `/home/lesley/projects/Personal/magic-mouse-tray/.ai/code-reviews/test-matrix-adversarial.md`

**Verdict:** CHANGES-NEEDED

**Top 3 missing axes:**

1. Sleep/wake cycle — the most common user scenario and the most likely way a registry-patch approach fails silently (patch survives reboot, fails to survive S3/S0ix resume).
2. Quantitative scroll measurement — the entire Q7 answer depends on "scroll works," but the test definition is human-subjective with no event count or latency metric. An intermittent 5% drop rate passes the test and ships broken.
3. USB-C cable connected — Phase 1 explicitly removes the Code-39 hazard but never confirms its absence holds after re-pair or driver update. One USB-C plug-in post-test could re-trigger it.

**Top 3 anti-pattern risks:**

1. AP-7 (trusting agent self-reports) — the test orchestrator is unwritten and will self-report capture success. No artefact-existence verification gate after each cell means silent capture failures proceed undetected.
2. AP-2 (stale corpus) — the NLM refresh gate lists only 2 sources but the overnight session produced at least 5 new empirical findings. A peer-review query against a corpus missing MU footprint analysis will reproduce the same false-REJECT that burned the overnight session.
3. AP-10 (missing post-condition validation) — Phase 1 per-step verification is delegated entirely to `mm-phase1-cleanup.ps1` which does not yet exist. If the script is written with incomplete checks, Phase 2 starts from a baseline that was not actually cleaned, invalidating all Phase 2 cells.
