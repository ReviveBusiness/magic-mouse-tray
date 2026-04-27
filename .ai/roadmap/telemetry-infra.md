# Telemetry & Infrastructure Roadmap — magic-mouse-tray (PRD-184)

**Generated 2026-04-27.**
**Scope:** project-specific gaps surfaced during the overnight autonomous session. The generic playbook lives at `.ai/playbooks/autonomous-agent-team.md`.

## Where we are right now

Headless development harness is complete and validated:
- `mm-dev.sh` orchestrates state/build/sign/install/verify/rollback/capture/debug
- Scheduled task `MM-Dev-Cycle` runs as user/Highest with patched ACL — no UAC for any phase
- Empirical-evidence pipeline (`mm-rev-eng.sh`) extracts signatures + disasm context from binaries
- State-flip tool (`mm-state-flip.ps1`) toggles AppleFilter ↔ NoFilter in 5 seconds
- Snapshot script (`mm-snapshot-state.sh`) captures full pre-mutation state
- Acceptance test (`mm-accept-test.sh`) validates 8 checks post-install
- Lint (`mm-lint.sh`) catches 7 known failure modes (em-dashes, hardcoded offsets, hook violations, StrictMode hazards)
- Unit tests (`scripts/mm-test.sh`) — 58 assertions on pure-logic functions, all pass

What's still in the way of "get the next change right the first time":

## Highest-leverage gaps (prioritised)

### 1. Live BRB capture during fresh BT pairing — ground truth for SDP layout
**Why it matters:** Our SDP scanner (`ScanForSdpHidDescriptor`) was designed from the Bluetooth Core Spec text, not from a captured live exchange. The byte pattern is plausible but not yet empirically verified against the actual Magic Mouse 2024 SDP response. If a future device (or this device under different circumstances) emits a different pattern variant, our scanner silently fails.

**What's needed:**
- A logging-only filter mode that dumps every `BRB_L2CA_ACL_TRANSFER` to debug log with header + first 256 bytes of payload
- Procedure: install logging filter → unpair Magic Mouse → re-pair while capturing → save the buffer that triggered HidBth's descriptor cache write
- Output as a fixture file in `tests/fixtures/sdp-response-real.bin`
- Unit test that runs the actual scanner against the real fixture and confirms detection

**Effort:** ~2 hours. Adds one phase to `mm-dev.sh` (`capture-sdp`), one new fixture, one new test.

### 2. Post-install acceptance test runs as part of `Verify` phase
**Why it matters:** Our `Verify` step today checks LowerFilters + COL01 Started. But the acceptance test (`mm-accept-test.sh`) checks 8 things including descriptor-injection-fired and battery-readable. Two separate paths for the same intent. If `Verify` says PASS and `mm-accept-test` says FAIL we have an inconsistency.

**What's needed:**
- Replace `mm-dev.ps1`'s `Verify-Install` with a call to `mm-accept-test.sh` (or PowerShell equivalent)
- Update `Full` phase: `state → build → sign → install → mm-accept-test → state`

**Effort:** ~30 min refactor.

### 3. NotebookLM corpus continuous refresh
**Why it matters:** The single most expensive failure overnight was a "REJECT" verdict from NLM that didn't account for MagicUtilities (already documented in our PRD!). The corpus was stale because we don't auto-refresh.

**What's needed:**
- New script `scripts/mm-nlm-refresh.sh` that:
  - Diffs commits since last refresh marker
  - Identifies new doc files in `.ai/`, `Personal/prd/`, `MORNING-BRIEFING-*.md`, `findings.md`
  - Ingests each as a text source via `mcp__notebooklm-mcp__source_add`
  - Updates the refresh marker
- Pre-flight gate in any `peer-review` invocation calls this script
- Adversarial query template that asks "what production implementations refute this?"

**Effort:** ~2 hours. Adds one script, modifies `/peer-review` skill to call it.

### 4. Worktree branchpoint validation before agent spawn
**Why it matters:** Both rewrite agents tonight branched from `5001ab3`, missing 4+ hours of my work on main. Their commits used wrong BRB offsets. We caught it during merge but only because I read the diff carefully.

**What's needed:**
- Pre-spawn check (in the wrapper that uses `Agent` tool with `isolation: "worktree"`):
  - Read the agent runtime's worktree creation log
  - Compare branchpoint SHA to current main HEAD SHA
  - Refuse to launch if branchpoint < HEAD - N commits (configurable threshold)
- OR: post-spawn in agent's brief, require them to print `git merge-base main HEAD` in their first response so we can detect stale spawns

**Effort:** Unknown — depends on whether agent runtime exposes branchpoint control. Worth investigating before next overnight run.

### 5. Driver kernel telemetry — counter-based observability
**Why it matters:** When debugging "did the descriptor injection actually fire?", we read DebugView log lines manually. That's slow and error-prone. A counter-based dashboard would tell us instantly.

**What's needed:**
- Driver maintains in-kernel counters (atomic):
  - `brb_acl_transfer_count` (total ACL transfers seen)
  - `sdp_pattern_match_count` (times scanner found pattern)
  - `descriptor_inject_count` (times patcher succeeded)
  - `descriptor_inject_skipped_buffer_too_small_count`
  - `descriptor_inject_skipped_other_count`
- Expose via a custom IOCTL or a registry value the user-mode tray reads
- Tray displays the counters as part of its status

**Effort:** ~4 hours. Driver work + tray work + protocol design.

### 6. Apple driver disassembly cross-reference index
**Why it matters:** `disasm.txt` is 10K lines. Finding which function does X means manual searching. Some greps return false positives (the `0x206` regex caught `0x200`). Line-by-line annotation would speed up future rev-eng.

**What's needed:**
- Annotated copy of `disasm.txt` with function boundaries labelled
- Sub-tool that takes a constant or string and finds the enclosing function by walking back to nearest `push rbp` / function-start pattern
- Save as `.ai/rev-eng/<sha>/annotated-disasm.md`

**Effort:** ~2 hours. The current `mm-rev-eng-context.sh` is the seed for this; needs refinement.

## Medium-leverage gaps

### 7. Build artefact retention
The MSBuild SignTask failure cleans up `.sys` after a "successful" compile. We have to read the build log to know what really happened. Either fix the SignTask `/fd` flag in the vcxproj (right fix) or copy `.sys` to a side directory before SignTask runs (defensive).

### 8. Mouse hardware test fixture
We can't generate gestures from software. But we CAN capture real gesture packets (Report 0x12 with finger data) into binary files, then unit-test the gesture-parsing logic against them. Currently we have no captured packets — every "does this work?" cycle requires the user to physically use the mouse.

### 9. Cross-session memory
Each Claude Code session starts fresh. The user has to re-explain context every time. The `.ai/learning/`, `.ai/peer-reviews/`, and `MEMORY.md` patterns help, but the single hand-off doc (`MORNING-BRIEFING-*.md`) is the primary mechanism. Could be more structured — a templated "session-resume.md" with current state + open questions + next actions.

### 10. Cost telemetry per autonomous workflow
Tonight's session showed cost-overspend warnings repeatedly (Opus running haiku-tier work). We have no aggregate per-session cost tracking. A simple JSONL log of `{"agent_id", "model", "duration_ms", "tokens_in", "tokens_out"}` after each agent completes would let us review cost trends.

## Lower-leverage gaps (defer)

### 11. SignPath / Microsoft WHQL signing pipeline
Currently we use a local test cert. For real distribution we'd need cross-signed packages. Out of scope until the driver is empirically validated.

### 12. CI/GitHub Actions
Automating lint+test on push would catch issues before manual dev cycle. But GitHub Actions on Windows kernel-driver builds is complex (EWDK installation, cert management). Defer until codebase stabilises.

## What we're NOT going to do

- **Build a userland helper that injects scroll via SendInput.** We've confirmed the lower-filter approach works (Apple's driver proves it). The hybrid approach was a fallback for an architecture we mistakenly thought was impossible.
- **Replace HidBth with our own minidriver.** Massively more invasive than the lower filter; not justified by any empirical finding.
- **Target Magic Mouse v1 or Trackpad.** PRD-184 scope is the 2024 model (PID 0x0323). Generalising later if/when we have working baseline.

## Current bottleneck

The single thing blocking progress today: **we don't yet know if the SDP scanner fires correctly during a real fresh BT pair on this hardware.** Item #1 above is the blocker. Until we capture a real SDP exchange and confirm the byte pattern matches, every install attempt is partly speculative.

Once #1 is done, #2 (acceptance test in Verify) closes the loop and we have a tight iterate-build-test cycle for kernel driver work.
