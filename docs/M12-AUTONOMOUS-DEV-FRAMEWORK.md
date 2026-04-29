---
created: 2026-04-28
modified: 2026-04-29
version: 2.0.0
---
# M12 Autonomous Development Framework

## BLUF

How M12 v1 gets implemented while you sleep, in 12-16 hours of agent runtime (reviewer chain accounts for 5 reviewers x 7 PRs at sonnet ~5-15 min each, sequential per template chain), producing code that passes expert review with no AI tells. Multi-tier review chain, automated quality gates, reference-implementation-first pattern. You wake up to PRs ready for human review or merge.

## What "expert-quality, no AI tells" means

AI-written kernel code has visible patterns experts spot in seconds:

| AI tell | Why experts notice | Our defense |
|---|---|---|
| Over-commenting (every line) | Real driver code is sparse | Comment-density linter — match Microsoft sample density |
| Defensive null checks where DV proves invariant | Wastes cycles, looks paranoid | Trust kernel invariants; `NT_ASSERT` for debug-only checks |
| Generic names (`helper`, `data`, `buffer`) | Real code uses domain terms | Style guide: must use HID/WDF idioms (`reqContext`, `devCtx`) |
| Mixed casing styles | Sample drivers are uniform | One style, enforced by clang-format with WDF preset |
| Helper functions for trivial ops | Inlines when obvious | DRY threshold: extract only if 3+ callers |
| TODO/FIXME left in | Pros remove them or open issues | Linter blocks PR with TODO |
| "Just in case" error paths | Exact + minimal | Each error path must reference a real failure mode |
| `Result/Status` return + ref-out param | C# pattern in C | NTSTATUS + standard WDF return idioms only |
| AI-flavored function names (`PerformBatteryRead`) | Uses verb-noun + WDF prefix | `M12EvtIoDeviceControl`, `M12ReadBatteryFromShadow` |

**Multi-pass adversarial reviewer's job: reject anything that smells AI.**

## Reference implementations (every function has a match)

For each M12 function, the implementer agent MUST cite a reference function it's modeled on:

| M12 function | Reference (sample / open-source) |
|---|---|
| `DriverEntry` | Microsoft `Windows-driver-samples/hid/firefly/sys/firefly.c::DriverEntry` |
| `EvtDriverDeviceAdd` | Same sample, same function |
| Lower-filter installation | Microsoft `kbfiltr` / `moufiltr` |
| BRB completion routine for descriptor | Microsoft `bthhid` sample (if available) or applewirelessmouse RE |
| HID descriptor byte layout | Captured `applewirelessmouse.sys` offset 0xa850 (verbatim 116 bytes for col01) + new col02 vendor TLC |
| Power callback | Microsoft `power/poclass` / KMDF samples |
| WPP tracing | Microsoft KMDF WPP guide |
| Self-signed cert + trust install | MagicMouseFix model (verified empirically on dev machine) |

Code that has no matching reference = either (a) novel logic that needs explicit design rationale comment, OR (b) rejected.

## Quality gate sequence (every commit)

```
[Code agent commit]
    ↓
[PREfast static analysis]   — 0 warnings or PR blocked
    ↓
[Build with EWDK]            — must succeed clean (admin queue)
    ↓
[Static Driver Verifier]    — 0 violations or PR blocked
    ↓
[Self-review by author agent] — checks against style guide checklist
    ↓
[Senior driver dev review]  — adversarial pass, looks for kernel bugs + AI tells
    ↓
[HID protocol review]       — descriptor + IRP semantics
    ↓
[Security review]           — buffer validation, IOCTL contracts, SDDL
    ↓
[Code quality / style review] — idioms, DRY, naming
    ↓
[NLM peer review pass]      — corpus-level cross-check
    ↓
[Human (you) PR review]     — final gate
    ↓
[Merge to main]
```

Any gate fails → revert + iterate. Maximum 3 iterations per gate before primary session intervenes.

## Phase 3 agent assignments (parallelizable)

| Agent | Tier | Scope | LOC est. | Reference | Reviewers |
|---|---|---|---|---|---|
| **DRIVER-1: KMDF skeleton** | sonnet | INF + driver scaffold (DriverEntry, EvtDriverDeviceAdd, EvtDeviceD0Entry, EvtDeviceD0Exit, EvtIoStop, ServiceBinary), pool tag, struct sigs, WPP init | ~80 | Microsoft `firefly` | Senior dev, Style |
| **DRIVER-2: Descriptor mutation** | sonnet | BRB completion routine intercepting SDP descriptor; rewrites to add col02 vendor battery TLC (UP:0xFF00 U:0x0014 RID=0x90 3-byte) while preserving col01 (mouse + Wheel/Pan/ResMult) | ~50 | applewirelessmouse RE + descriptor bytes from offset 0xa850 | Senior dev, HID protocol, Security |
| **DRIVER-3: Power saver** | sonnet | PoRegisterPowerSettingCallback for display/AC/sleep; manual suspend custom IOCTL with admin-only SDDL; CRD PowerSaver config; vendor suspend command (TBD — may use BT disconnect fallback) | ~120 | KMDF power samples | Senior dev, Security |
| **DRIVER-4: Self-trust + signing harness** | sonnet | Self-signed cert generation script; signtool wrapping; install-m12-trust.ps1 user trust install; .pfx kept offline | ~80 (PowerShell) | MagicMouseFix model | Security |
| **DRIVER-5: Build + install scripts** | haiku | scripts/build-m12.ps1 (admin-queue dispatched); scripts/install-m12.ps1; scripts/uninstall-m12.ps1; .gitattributes for CRLF | ~100 (PowerShell) | EWDK conventions | Style |
| **DOC-1: User-facing docs** | sonnet | README, INSTALL, UNINSTALL, CONFIGURATION, TROUBLESHOOTING, EMPIRICAL-VALIDATION, KNOWN-ISSUES (already drafted), MOP, PRIVACY-POLICY (already drafted), CHANGELOG, NOTICE | ~documentation | Microsoft sample doc structure | Doc-quality reviewer |
| **TEST-1: Unit tests** | sonnet | User-mode harness for descriptor parse + battery extract; race tests for shadow buffer (none in v1.7 — passthrough only); IOCTL validation tests | ~150 | Microsoft test patterns | Senior dev |

**Wave layout (per plan-review CRIT-1 — parallel Wave 1 is unsafe):**

- **Wave 1**: DRIVER-1 alone (INF + KMDF skeleton). Must land and build clean before Wave 2.
- **Wave 2**: DRIVER-2 + DRIVER-3 + DRIVER-4 + DRIVER-5 in parallel (descriptor mutation + power saver + signing harness + build/install scripts) — gated on Wave 1 merge.
- **Wave 3**: DOC-1 + TEST-1 in parallel — gated on Wave 1+2 complete.

**Pre-flight gate (required before Wave 1 dispatches):** BUILD route must successfully compile the HelloWorld KMDF test target (driver-test/HelloWorld.sln) end-to-end via the EWDK task queue before any agent writes M12 driver code. This confirms EWDK mount is active, SetupBuildEnv.cmd path is correct, and msbuild runs to completion. Reference: TOOL-1 deploy + TOOL-2 EWDK validation.

**Total agent runtime estimate**: 12-16 hours (5 reviewers x 7 PRs at sonnet ~5-15 min each, sequential per reviewer template chain; implementation agents ~30 min each).

## Reviewer chain (per PR)

After implementer commits, BEFORE merge to ai/m12-* branch:

| Reviewer | Tier | What they check | Pass criteria |
|---|---|---|---|
| **Self-review** | implementer agent | Style guide checklist (see below); WPP trace coverage; pool tag usage; pre/post conditions documented | Author signs off |
| **Senior kernel driver dev** | sonnet (gemini t2 fallback for adversarial) | KMDF idioms; IRP races; lock semantics; DV-clean; EvtIoStop; cancellation patterns; pool overflow risk; UAF | 0 critical, ≤3 minor |
| **HID protocol expert** | sonnet | Descriptor byte correctness; IRP semantics; IOCTL completion patterns; HID 1.11 compliance | Confirmed against captured 116-byte descriptor + HID spec |
| **Security reviewer** | sonnet | IOCTL input validation; SDDL on device interface; user-controllable buffer bounds; privilege escalation surface; cert-trust install script (admin-only, verified thumbprint) | 0 critical |
| **Code quality / style reviewer** | sonnet | Naming idioms; comment density; DRY threshold; AI tells; matches MS sample style | All AI-tells absent |
| **NLM peer review** | NLM corpus | Architectural soundness vs corpus | CHANGES-NEEDED max (REJECT-downgrade per playbook) |
| **You (human)** | gold | Final go-or-no | Merge or comments |

## Style guide checklist (auto-enforced before each commit)

```
[ ] No comments restating what the code does (only WHY non-obvious)
[ ] No TODO/FIXME — open a tracked issue instead
[ ] No defensive null checks where DV/contract proves the invariant
[ ] No "helper functions" for ops with <3 callers
[ ] No mixed casing styles in same file
[ ] All identifiers use M12 prefix or WDF/KMDF/HID standard prefixes
[ ] All status codes are NTSTATUS values
[ ] All allocations use pool tag 'M12 '
[ ] Each function ≤80 lines (split if longer)
[ ] Each module has 1 lock; lock order documented at top of module
[ ] Every IRP completion path has an audit comment "completed at addr X"
[ ] WPP traces at appropriate level (no debug spew)
[ ] No DbgPrint outside test-only code paths
[ ] clang-format with WDF preset applied
[ ] PREfast 0 warnings on this file
```

## What you wake up to

1. **PR #14 design + MOP** at v1.8 (final, approval-ready)
2. **PR #190 PRD** at v1.33 (D-S12 decisions through ~70)
3. **PR #?? M12 KMDF skeleton** (DRIVER-1) — reviewable, builds clean, DV-clean, NOT YET INSTALLED on your machine
4. **PR #?? Descriptor mutation** (DRIVER-2)
5. **PR #?? Power saver** (DRIVER-3)
6. **PR #?? Signing harness** (DRIVER-4)
7. **PR #?? Build/install scripts** (DRIVER-5)
8. **PR #?? Documentation** (DOC-1)
9. **PR #?? Unit tests** (TEST-1)

Each PR has:
- Clean commit history (no "fix typo", no "wip" — squashed)
- Linked to design spec section it implements
- All reviewer agents' verdicts attached as comments
- Build + DV + PREfast logs attached
- A `## How to test` section in PR body

## Boundaries — what won't happen while you sleep

- **No driver installs on your machine** — Phase 3 PRs are review-only. Install happens only after you merge + manually run install-m12.ps1.
- **No destructive ops on your registry** — backup discipline per AP-24
- **No signing with real EV cert** — self-signed only (your future call on attestation signing)
- **No network calls beyond GitHub PR creation + NLM ingestion**
- **No SMS for non-critical updates** — only one final SMS when full pipeline is review-ready

## Failure modes + handling

| Mode | Detection | Action |
|---|---|---|
| Build fails | EWDK exit code | Implementer agent revises; retry up to 3× |
| PREfast warning | exit code | Same |
| SDV violation | exit code | Same |
| Reviewer rejects 3× | review log | Pause that PR; primary session triages; SMS if blocking |
| Queue stuck | timeout >60 min | Primary intervenes |
| All reviewers approve but tests fail | test log | Pause; SMS |
| Cert generation fails | script exit | Switch to self-signed test cert; defer cert-trust path |

## Telemetry (for your sleep insurance)

Every agent emits to `.ai/telemetry/agents.jsonl`:
- agent_id
- start_time
- end_time
- model_tier
- tokens_used
- exit_status
- iterations_required
- reviewer_verdicts (JSON)

You can grep this on wake to see what happened.

## Net answer to "expert-quality, no AI tells"

It's not magic — it's **process**:
1. Reference-implementation-first (every function modeled on a Microsoft sample)
2. Style guide checklist enforced automatically pre-commit
3. Multi-tier adversarial reviewer chain (5 reviewers per PR) with anti-AI-tell pattern detection
4. Hard quality gates (PREfast 0, SDV 0, DV 0) — no human override
5. NLM peer review with corpus that includes Microsoft sample driver source as reference
6. Tight LOC budget (~30-200 LOC per agent) — small enough that style coheres
7. Final human (you) review on every merge

If any reviewer can articulate "this looks AI-written," that's a rejection reason — implementer revises until the pattern is gone.

## Phase 3 dispatch — when does it start?

After design spec v1.8 approved (PR #14 merged) and PRD v1.34 approved. Phase 3 waits for your explicit "approve PRD" after v1.34 SMS lands.

**Pre-dispatch pre-flight checklist (must complete before agents spawn):**

- [ ] EWDK mounted at D:\ewdk25h2\ and SetupBuildEnv.cmd path confirmed
- [ ] BUILD route HelloWorld test completes successfully (driver-test/HelloWorld.sln builds clean via task queue)
- [ ] mm-task-runner.ps1 deployed to D:\mm3-driver\scripts\ and task registered
- [ ] User spot-checks at least 2 of the 5 reviewer templates end-to-end (per CRIT-4): spawn a test reviewer against a known file, confirm it produces a structured verdict, confirm github.py posts the comment correctly

## M12 driver architecture (MAJ-8 resolved)

M12 sits as a **BTHENUM LowerFilter** intercepting `IOCTL_INTERNAL_BTH_SUBMIT_BRB`. It does NOT operate at the HID class layer. Specifically:

- **What it intercepts**: BRB completions on PSM 1 (SDP control channel) via `BRB_L2CA_ACL_TRANSFER`. It reads the SDP HIDDescriptorList attribute response, rewrites the embedded HID descriptor TLV bytes in place to inject the custom 113-byte descriptor (col01: Mouse + Wheel + Pan + ResMult; col02: vendor TLC UP=0xFF00 U=0x0014 RID=0x90 3-byte).
- **What it does NOT intercept**: `IOCTL_HID_GET_REPORT_DESCRIPTOR` (absorbed by HidBth before reaching any lower filter), HID class IOCTL_HID_* calls.
- **Why BRB level**: HidBth fetches the descriptor via L2CAP SDP traffic on PSM 1 during the initial pairing SDP exchange. By the time PSM 17 (HID control) and PSM 19 (HID interrupt) channels open, SDP is complete and the descriptor is cached in HidBth's kernel pool. The only interception window is the SDP response on PSM 1.
- **Reference**: M12-DESIGN-SPEC.md v1.8 Section 3b + PRD-184 D-S12-70. Confirmed by MU Ghidra analysis (MagicMouse.sys BRB_L2CA_ACL_TRANSFER dispatch). DRIVER-2 agents must cite this spec section.

DRIVER-2 brief must reference this section. Any agent that proposes intercepting at HID class layer instead of BRB layer must be rejected with a pointer here.

## Plan-review verdict CRIT items resolved 2026-04-29

The following CRITs were raised in the /plan-review pass against the Phase 3 framework and are now resolved in this v2.0:

- [x] **CRIT-1 (resolved)**: Wave 1 = DRIVER-1 alone. DRIVER-2 + DRIVER-3 + DRIVER-4 + DRIVER-5 in Wave 2 after Wave 1 lands. DOC-1 + TEST-1 in Wave 3. Rationale: parallel DRIVER-1+2+5 in Wave 1 creates INF version conflicts (DRIVER-1 creates the INF skeleton; DRIVER-2 needs to read and modify it; DRIVER-5 creates build scripts that reference the INF path) and makes debugging harder when a build fails.
- [x] **CRIT-2 (reminder documented)**: BUILD route end-to-end test against HelloWorld must succeed before Wave 1 dispatches. Reference TOOL-1 deploy + EWDK mount as pre-flight. This is enforced in the "Phase 3 pre-dispatch pre-flight checklist" above.
- [x] **CRIT-3 (resolved)**: Reviewer-chain budget corrected from "~6 hours total" to "12-16 hours total". Calculation: 5 reviewers x 7 PRs x ~5-15 min per reviewer at sonnet = 175-525 min = ~3-9 hours for reviews alone; plus ~30 min per implementation agent x 7 agents = ~3.5 hours; total 6-12 hours lower bound, 12-16 hours with iteration and queuing overhead.
- [x] **CRIT-4 (reminder documented)**: Phase 3 pre-flight requires user spot-check of at least 2 of 5 reviewer templates end-to-end before chain dispatches. Templates: senior-driver-dev-review.md, hid-protocol-review.md, security-review.md, code-quality-review.md, nlm-peer-review.md. Must confirm a spawned agent produces a structured verdict and github.py posts it.
- [x] **MAJ-8 (resolved)**: BRB-vs-HID interception decision locked down in "M12 driver architecture" section above. DRIVER-2 direction is unambiguous: BTHENUM LowerFilter intercepting IOCTL_INTERNAL_BTH_SUBMIT_BRB for SDP HIDDescriptorList TLV rewriting, NOT HID class layer.