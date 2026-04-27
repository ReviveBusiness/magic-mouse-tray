# Autonomous Agent Development Team — Playbook

**Status:** v1.0 (2026-04-27, distilled from PRD-184 magic-mouse-tray work)
**Scope:** how to run a multi-agent autonomous workflow that produces correct results the first time, instead of the iterative-discovery cycles we hit overnight.

This is intended to be lifted out of `magic-mouse-tray/.ai/playbooks/` into a global location (e.g. `~/.claude/playbooks/` or `RILEY/.ai/playbooks/`) once it stabilises across one more autonomous session.

---

## The five rules

If you remember nothing else, remember these. Each one corresponds to a real failure that cost hours overnight.

1. **Reference implementation FIRST.** Before designing from first principles, find a working production tool that solves the same problem. Reverse-engineer it. If you can't find one, document why, and only then start architectural design. (Anti-pattern: PRD-184 spent 6+ hours architecting from peer-review verdicts; MagicUtilities had a working reference all along.)

2. **Empirical evidence beats peer-review verdicts.** A "REJECT" from any reviewer (NotebookLM, model peer, human) that doesn't account for production counterexamples is incomplete, not authoritative. Always ask the reviewer "what working implementation refutes this conclusion?". If they don't have one, gather one before accepting the verdict.

3. **Commit each logical change immediately.** Not "after the feature works." Not "at end of day." Per-step. The first 5 hours of overnight work had ZERO commits to driver code; when something broke there was no rollback point and the user had to ask "why are you not tracking anything?". This is non-negotiable.

4. **Worktree branchpoint = current main HEAD, always.** Spawned agents whose worktree branched from older commits inherited stale state and produced code with wrong constants. Verify branchpoint matches expected baseline before agent starts work; re-base or recreate if it doesn't.

5. **Lint and snapshot before every mutation.** Lint catches things we already learned the hard way (em-dashes in PowerShell, hardcoded offsets, hook violations). Snapshots provide rollback. Both are 10× cheaper than discovering the problem after install.

---

## When to use autonomous agents

Multi-step technical work where:
- The user wants minimal interaction during execution
- The work is long enough (>30 min) that a single linear session would burn cache and tokens
- Phases are independent enough to parallelize
- Each phase has clear success criteria

Don't use autonomous agents for:
- Single-file edits a primary session can do in 5 min
- Decisions requiring sustained user dialogue
- Anything where rollback is impossible (force-pushes, prod deployments, third-party API mutations)

---

## Pre-flight checklist (BEFORE any agent spawn)

### A. State capture
- [ ] Snapshot current state (filesystem, registry, process list, logs) into a timestamped tarball
- [ ] Note current git HEAD on every relevant repo
- [ ] Document any in-flight uncommitted changes

### B. Reference search
- [ ] Identify production implementations that solve the same problem
- [ ] If found: ensure their binaries/source are accessible for analysis
- [ ] If not found: document the search and move to first-principles with that caveat in the brief

### C. Tooling readiness
- [ ] Build harness is headless (no UAC, no manual clicks)
- [ ] Rollback path tested
- [ ] Lint passes on baseline
- [ ] Pre-existing tests pass on baseline

### D. NotebookLM corpus refresh
- [ ] Latest empirical findings ingested as NLM source
- [ ] Active PRD/briefing docs in the corpus
- [ ] Reference implementation analysis (rev-eng output) in the corpus
- [ ] If skipping: document the failure mode this introduces

### E. Cost budget
- [ ] Estimate tokens per agent × number of agents
- [ ] Tier match: Opus for architecture, Sonnet for implementation, Haiku for mechanical
- [ ] User-visible total before proceeding

---

## Agent design

### Scope per agent (the 30-minute test)
A single agent should be able to complete its work in <30 minutes at sonnet tier. If you can't fit the work in that window, the scope is too large — split it.

### Inviolable constraints in every brief
- "Do NOT install/deploy anything. Build only."
- "Do NOT push to origin."
- "Do NOT modify files outside <scope path>."
- "Commit via `python3 scripts/git.py commit --branch <branch> --message "..."` (direct `git commit` is hook-blocked)."
- "Use `install -d` not `mkdir -p` (mkdir is hook-blocked)."

### Known gotchas (always mention to the agent)
- PowerShell + UTF-8 BOM unicode: em-dashes, en-dashes, arrows, ellipses cause parse failures. Use ASCII.
- StrictMode v2: wrap `Where-Object | .Count` in `@()`.
- Hook policies: BCP-REL-309 (no `git commit`), RULE-023 (no `mkdir`), various rm-rf restrictions.
- Worktree branchpoint may be stale: if your worktree's `git log main..HEAD` shows tons of "deletions", you're branched from an older main.

### Required brief sections
```markdown
# Mission
[1 paragraph]

# Required reading (in this order)
1. Source-of-truth doc 1
2. ...

# Constraints (inviolable)
- ...

# Step-by-step work plan
1. ...

# Early-exit conditions
- If X happens, stop and report.

# Reporting format
End with a <200 word summary of:
- Final commit hashes
- Build/test status
- What user runs to validate
- Surprises or open questions
```

---

## Tier selection

| Task type | Tier | Reason |
|---|---|---|
| Meta-design, peer-review of complex changes, playbook authoring | Opus | Sustained deep reasoning |
| Implementation, multi-file refactor, building tests/lint, rev-eng | Sonnet | Solid coding + judgement |
| Mechanical: rename, find-replace, format conversion, port-with-no-redesign | Haiku | Fastest + cheapest |

Anti-pattern: running Opus on score=1/10 mechanical work for hours. The session-optimizer warning is real ($224/M waste at one point overnight).

---

## Parallelism patterns

### Truly independent → parallel
- Mutating agents on disjoint file paths
- Audit agents producing separate reports
- Lint/test builders that don't touch each other's scope

### Coordinate via reports, not files
- Audit agents write to `.ai/cleanup-audit/<name>-<date>.md` and commit
- Mutating agents commit to their own worktree branch
- Primary session reviews reports + branches before merging anything

### Naming convention
- Agent name: descriptive (`mm-input-rewrite`, not just hash)
- Worktree branch: `worktree-agent-<id>` (auto-generated, fine)
- Report filename: `<scope>-<YYYY-MM-DD>.md`

### Concurrency limits
3-4 agents at once is the sweet spot. More creates coordination overhead larger than parallel speedup.

---

## Empirical-evidence collection (ranked by leverage)

Roughly in order of value-per-hour to gather:

1. **Reference implementation reverse-engineering.** If a working production tool exists, its binary tells you the architecture in <1 hour vs days of designing from scratch.

2. **Live capture of the actual data flow.** For driver work this means BRB traffic during pairing. For API work it means request/response bodies. Replaces speculation with ground truth.

3. **Static analysis output.** Strings, imports, sections, value caps. Cheap to gather, valuable for understanding what's possible.

4. **State diffs across mutations.** Snapshot before, snapshot after, diff. Every mutation should produce one of these.

5. **Failed attempts catalogued.** When something doesn't work, capture what you tried and why it failed. Becomes test fixtures + anti-pattern catalogue.

---

## Logging & telemetry baseline

Every autonomous workflow project should have:

| Channel | What | Where |
|---|---|---|
| Per-session log | Every command, output, state change | Repo session log file |
| Per-mutation snapshot | Pre/post state diff | `.ai/snapshots/<ts>/` |
| Per-build telemetry | Phase timing, exit codes, errors | `.ai/telemetry/builds.jsonl` |
| Per-agent execution | Duration, tokens, exit reason | `.ai/telemetry/agents.jsonl` |
| Decision log | Why we did what we did | PRD work-log entries |
| Failed-approach catalogue | What didn't work and why | `.ai/learning/anti-patterns.md` |
| Empirical findings | Reverse-eng output, probes | `.ai/rev-eng/<sha>/` |
| Cleanup audits | What's stale, what to remove | `.ai/cleanup-audit/<date>.md` |

---

## NotebookLM corpus management

Tonight's biggest single failure was a stale NotebookLM corpus producing a "REJECT" verdict that contradicted production reality. The fix:

### Continuous ingestion
Every empirical finding becomes an NLM source. Specifically:
- New `findings.md` from rev-eng → ingest immediately
- Architecture decision in PRD work log → ingest as text source
- Reverse-engineered binary's strings + imports → ingest

### Adversarial query template
When asking NLM for a peer-review verdict, the prompt should always include:

> "Before answering, list the production implementations in your sources that demonstrate this approach working OR not working. If your sources don't include such evidence, say so explicitly and downgrade your verdict from REJECT to CHANGES-NEEDED."

This forces the corpus's gaps to become explicit instead of silently producing wrong-confidence verdicts.

### Refresh gate
Before invoking `/peer-review` on architecture work, run a corpus-refresh step:
1. Find the latest commits in the project repo
2. Identify any new docs/findings since the last NLM ingestion
3. Ingest as sources
4. THEN run the peer-review query

---

## Anti-pattern catalogue (concrete failures from PRD-184)

### AP-1: First-principles design when a reference exists
**Symptom:** Hours of architectural debate against peer-review verdicts.
**Concrete instance:** Spent overnight session designing a custom upper-filter approach because NLM said the lower-filter wouldn't work. MagicUtilities ships a lower-filter solution.
**Fix:** Step 1 of every workflow is "find production references". Defer architecture work until references are exhausted.

### AP-2: Stale review corpus
**Symptom:** Peer reviewer produces high-confidence wrong verdicts.
**Concrete instance:** NLM peer-review tonight said lower-filter was "REJECT" because the corpus didn't include MU runtime analysis (which was already in our PRD).
**Fix:** Refresh corpus before every review query. Accept verdicts only if reviewer has confirmed access to production counterexamples.

### AP-3: Worktree branched from old main
**Symptom:** Agent's commits use stale constants/structures.
**Concrete instance:** Both rewrite agents tonight branched from `5001ab3`, missing my offset corrections in `6b10b49`. Their code had wrong BRB offsets — would BSOD on install.
**Fix:** Verify worktree branchpoint = current main HEAD. If not, recreate the worktree before agent starts.

### AP-4: Manual em-dash discovery cycle
**Symptom:** Same trivial bug rediscovered in N files.
**Concrete instance:** Every PowerShell script written overnight had em-dashes; PowerShell parsed wrong; I fixed each one after discovering the failure at runtime.
**Fix:** Lint pre-commit. Document the gotcha in agent briefs. Both.

### AP-5: Opus running haiku-tier work
**Symptom:** Cost-optimization warnings in every prompt.
**Concrete instance:** Hours of mechanical edit-build-run cycles done at Opus tier. Session optimization showed ~$1276/M waste at peak.
**Fix:** Tier match before spawning. Opus for design only. Sonnet for implementation. Haiku for mechanical.

### AP-6: Multi-step changes without commits
**Symptom:** No rollback when something breaks.
**Concrete instance:** First 5 hours of overnight work had zero driver commits. User had to ask "why are you not tracking anything?".
**Fix:** Per-step commits. "Working tree clean" is the normal state between changes.

### AP-7: Trusting agent self-reports without verification
**Symptom:** Agent says "build succeeded" but binary doesn't exist on disk.
**Concrete instance:** Rewrite agent reported successful compile. The build log confirmed it produced `.sys`, but the SignTask post-build cleanup deleted it. We didn't check.
**Fix:** Verify artefacts independently after agent reports done. Trust the disk state, not the summary.

### AP-8: Hook-policy discovery in production
**Symptom:** Scripts that work on dev fail on the user's machine because of hook restrictions.
**Concrete instance:** `mm-dev.sh` had `mkdir -p` calls that the hook would block at runtime. Lint caught it before user hit it.
**Fix:** Encode every known hook policy in lint. Document in agent briefs.

### AP-9: Reading agent worktree status by `git diff main..HEAD`
**Symptom:** Diff shows huge deletions and you panic, thinking the agent destroyed your work.
**Concrete instance:** When the agent's branchpoint is older than current main, `git diff main..HEAD` shows my recent commits as "deletions" relative to the agent's branch. I almost re-implemented work that was already committed.
**Fix:** Use `git log <branchpoint>..HEAD` to see only the agent's actual changes. Or `git show <commit>` per-commit.

### AP-10: Missing post-condition validation
**Symptom:** Driver installs without error but doesn't actually work.
**Concrete instance:** Earlier in the project, `pnputil /add-driver` succeeded but the LowerFilters binding wasn't taking effect because PnP didn't call AddDevice. We discovered this empirically over multiple debug cycles.
**Fix:** Acceptance test that probes the post-state with concrete checks (LowerFilters present, COL01/COL02 enumerated, battery readable). Don't trust install exit codes alone.

---

## Templates (see `templates/` for full versions)

- `templates/agent-brief.md` — fill-in-the-blanks for agent prompts
- `templates/audit-report.md` — for read-only agents producing markdown reports
- `templates/morning-brief.md` — session handoff doc for waking up to autonomous work
- `templates/preflight-checklist.md` — pre-spawn checklist
- `templates/postmortem.md` — after a workflow completes (or fails)

---

## When this playbook is wrong

This is v1.0 distilled from one project. It will be wrong in places. When you find a wrong rule:

1. Don't silently work around it.
2. File a finding in `.ai/learning/playbook-corrections.md` with the concrete failure and the proposed correction.
3. Bump the playbook version. Date the change.

Real anti-patterns are anti-patterns because they're EASY to fall into. The playbook helps only if it gets honest updates.

---

## Open questions for v1.1

Things v1.0 doesn't answer well yet:
- How to validate worktree branchpoint pre-spawn programmatically
- How to enforce NLM corpus refresh as a workflow gate
- How to capture cross-session learnings into automated checks
- How to budget cost across an autonomous workflow with feedback to user
- How to design rollback paths for changes whose effect is detected only days later
- How to choose between agent isolation (worktree) vs SendMessage continuation
