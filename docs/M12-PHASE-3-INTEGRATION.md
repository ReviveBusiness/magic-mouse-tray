# M12 Phase 3 Tool Integration

## BLUF

How Phase 3 implementation agents invoke the style linter and PR reviewer dispatcher.
Read this before spawning any DRIVER-N or DOC-1 agent.

---

## Tools delivered by TOOL-4

| Script | Purpose | Exit |
|---|---|---|
| `scripts/check-style.sh` | AI-tell linter; 8 checks; REJECT blocks commit | 0=pass / 1=fail |
| `scripts/dispatch-pr-reviewers.sh` | Sequential reviewer dispatch; posts verdicts as PR comments | 0=all passed / 1=chain halted |
| `driver/.clang-format` | WDF-style clang-format preset; used by check #8 | n/a |

---

## How Phase 3 agents use check-style.sh

### Before every commit

Every implementation agent (DRIVER-1 through DRIVER-5, DOC-1, TEST-1) runs the
style linter as a pre-commit gate. No exceptions.

```bash
cd /path/to/worktree
bash scripts/check-style.sh --staged
```

If exit code is 1, the agent MUST fix all REJECT-severity violations before committing.
FLAG and WARN violations are recorded but do not block commit.

### Against a specific set of files

```bash
bash scripts/check-style.sh --files driver/Driver.c driver/HidDescriptor.c
```

### Against a branch diff (for PR-level gate)

```bash
bash scripts/check-style.sh --branch main
```

### Outputs

Both output files are written to the repo root:

- `style-results.json` -- machine-readable violation list
- `style-report.md` -- human-readable; paste into PR body or comment

### Check summary (all 8)

| # | Check | Severity | What it catches |
|---|---|---|---|
| 1 | Comment density | REJECT | >25% comment-to-code ratio (over-commented AI output) |
| 2 | TODO/FIXME/HACK/XXX | REJECT | Markers left in submitted code |
| 3 | Generic identifier names | FLAG | helper, util, data, buffer, temp, tmp, dummy, placeholder, var |
| 4 | Mixed casing styles | REJECT | snake_case + camelCase in same file |
| 5 | Over-defensive null checks | WARN | if (X == NULL) after _In_ annotation (DV proves non-null) |
| 6 | Helper function <3 callers | FLAG | DRY threshold: extract only if 3+ call sites |
| 7 | Pool tag | REJECT | ExAllocatePoolWithTag/WdfMemoryCreate not using 'M12 ' tag |
| 8 | clang-format compliance | REJECT | Formatting deviates from driver/.clang-format WDF preset |

### Fixing clang-format violations (check #8)

```bash
clang-format --style=file:driver/.clang-format -i driver/Driver.c
```

Run after every edit that touches whitespace or brace layout. Commit the
formatted result; do not hand-format around the tool.

---

## How Phase 3 agents use dispatch-pr-reviewers.sh

### After implementer commits to PR branch

Once an implementation agent has committed its code and pushed a PR, the primary
session runs the reviewer dispatcher:

```bash
bash scripts/dispatch-pr-reviewers.sh --pr <PR-URL-or-number>
```

Auto-detects `owner/repo` from git remote. Override with `--repo` if needed.

### Reviewer chain (always sequential)

```
senior-driver-dev-review.md   -> halt on REJECT
hid-protocol-review.md        -> halt on REJECT
security-review.md            -> halt on REJECT
style-review.md               -> halt on FAIL
code-quality-review.md        -> halt on REJECT
```

Each reviewer is spawned via the Agent tool in the primary Claude session,
with the template content and PR diff as inputs. The agent posts its verdict
as a PR comment and writes a local file to `.ai/peer-reviews/pr-<N>/`.

The dispatcher re-reads those verdict files and assembles a single aggregate
report at `.ai/peer-reviews/pr-<N>/pr-review-aggregate.md`, then posts it
as a final PR comment.

### Dry-run to preview dispatch plan

```bash
bash scripts/dispatch-pr-reviewers.sh --pr 42 --dry-run
```

Prints the reviewer sequence and spawn commands without touching the PR.

### Template locations

Templates are in `.ai/agent-templates/` (created by TOOL-3 on branch
`ai/m12-tool-3-reviewer-templates`). The dispatcher validates all five
templates exist before starting the chain.

| File | Reviewer |
|---|---|
| `senior-driver-dev-review.md` | Adversarial senior Windows kernel dev |
| `hid-protocol-review.md` | HID 1.11 / Bluetooth HIDP expert |
| `security-review.md` | Kernel security, IOCTL surface, signing chain |
| `style-review.md` | Code style and AI-tells filter |
| `code-quality-review.md` | DRY, modularity, reference traceability, tests |

### Halt-on-critical protocol

If any reviewer returns REJECT or FAIL:

1. Dispatcher prints the halt reason and exits 1.
2. Implementing agent reads the blocking reviewer's verdict file.
3. Agent fixes the cited violations.
4. Agent commits the fix (with a new commit -- no amend).
5. Dispatcher re-runs from the top of the chain (max 3 iterations per reviewer
   before primary session intervenes).

---

## Per-phase quality gate sequence (Phase 3)

Full sequence per M12-AUTONOMOUS-DEV-FRAMEWORK.md:

```
[Implementer commits]
        |
        v
[check-style.sh --staged]               <- TOOL-4 (REJECT = fix first)
        |
        v
[PREfast static analysis]               <- TOOL-2 gate
        |
        v
[Build with EWDK]                       <- TOOL-1 gate
        |
        v
[Static Driver Verifier]                <- TOOL-2 gate
        |
        v
[dispatch-pr-reviewers.sh]              <- TOOL-4 (5 reviewers sequential)
        |
        v
[NLM peer review (/peer-review skill)]  <- corpus cross-check
        |
        v
[Human PR review]                       <- final gate
        |
        v
[Merge to main]
```

check-style.sh runs BEFORE PREfast/build because it is fast (seconds vs minutes)
and catches obvious issues without burning build time.

---

## Agent brief addendum (include in every DRIVER-N brief)

Add this block to every Phase 3 agent brief under "Inviolable constraints":

```
- Run `bash scripts/check-style.sh --staged` before every commit.
  If exit code 1: fix all REJECT violations first. Do not commit over a failing gate.
- Pool tag for all allocations: 'M12 ' (four chars: M, 1, 2, space).
  Any other tag = REJECT from linter and from reviewer.
- Run `clang-format --style=file:driver/.clang-format -i <file>` after every edit.
- Do not leave TODO/FIXME/HACK/XXX in submitted code. Open a GitHub issue instead.
- No helper functions unless they have 3+ callers. Document rationale if kept.
- No mixed casing in a single file. WDF convention: camelCase locals, PascalCase types,
  M12Prefix for driver-defined functions.
```

---

## Activity Log

| Date | Update |
|---|---|
| 2026-04-28 | TOOL-4 complete: check-style.sh (8 checks), dispatch-pr-reviewers.sh (5-reviewer chain), driver/.clang-format (WDF preset), this integration doc |
