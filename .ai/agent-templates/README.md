# M12 Reviewer Agent Templates

Phase 3 dispatches five reviewer agents against every M12 driver PR. This directory
contains the prompt templates. Standardized templates produce consistent enforcement
across all PRs regardless of which model instance runs the review.

---

## Template index

| File | Reviewer role | Verdict type | Auto-reject on |
|---|---|---|---|
| `senior-driver-dev-review.md` | Adversarial senior Windows kernel dev | APPROVE / CHANGES-NEEDED / REJECT | Any CRIT-N finding |
| `hid-protocol-review.md` | HID 1.11 / Bluetooth HIDP / Linux cross-check | APPROVE / CHANGES-NEEDED / REJECT | Any CRIT-N finding |
| `security-review.md` | Kernel security, IOCTL surface, signing chain | APPROVE / CHANGES-NEEDED / REJECT | Any CRIT-N finding |
| `style-review.md` | Code style + AI-tells filter | PASS / FAIL | Any AI-tell finding |
| `code-quality-review.md` | DRY, modularity, reference traceability, tests | APPROVE / CHANGES-NEEDED / REJECT | Structural cohesion break |

---

## Review chain per PR

Each PR runs reviewers in this sequence. A reviewer that blocks (REJECT or FAIL)
halts the chain. The implementing agent fixes and re-submits from the top.

```
[Implementer commits to PR branch]
        |
        v
[senior-driver-dev-review]  -- CRIT-level bugs, UAF, deadlock, DV violations
        | APPROVE/CHANGES-NEEDED
        v
[hid-protocol-review]       -- Descriptor bytes, report ID semantics, IOCTL contracts
        | APPROVE/CHANGES-NEEDED
        v
[security-review]           -- Buffer validation, SDDL, cert chain, PFX storage
        | APPROVE/CHANGES-NEEDED
        v
[style-review]              -- Comment density, naming, AI-tells, clang-format
        | PASS
        v
[code-quality-review]       -- DRY, cohesion, reference citations, test coverage
        | APPROVE
        v
[NLM peer review]           -- Corpus-level cross-check (/peer-review skill)
        | APPROVE or CHANGES-NEEDED (REJECT downgraded per AP-2 if no production refutation)
        v
[Human (you) PR review]     -- Final gate
        |
        v
[Merge to main]
```

Maximum 3 iterations per reviewer before primary session intervenes.

---

## Dispatch instructions

### Single reviewer

```bash
python3 /home/lesley/projects/RILEY/scripts/agent.py spawn \
  --tier sonnet \
  --template .ai/agent-templates/<template-file> \
  --pr-url <PR-URL>
```

### All reviewers in sequence (orchestrated)

```bash
for template in \
  senior-driver-dev-review.md \
  hid-protocol-review.md \
  security-review.md \
  style-review.md \
  code-quality-review.md; do
  python3 /home/lesley/projects/RILEY/scripts/agent.py spawn \
    --tier sonnet \
    --template ".ai/agent-templates/${template}" \
    --pr-url "<PR-URL>"
done
```

Note: run sequentially, not in parallel. Each reviewer's output informs context
for the next. Parallel dispatch is appropriate only for truly independent reviewers
(e.g., security + HID on disjoint code paths -- uncommon).

### With riley delegate (T2 fallback for adversarial pass)

```bash
riley delegate --model t2 \
  --prompt-file .ai/agent-templates/senior-driver-dev-review.md \
  --attachment <path/to/pr-diff.patch>
```

Gemini T2 fallback is recommended for the senior driver dev review when an adversarial
second opinion is needed. Append the T2 verdict to the PR comment body.

---

## Adding new templates

1. Copy the structure from an existing template (Role / Required reading / Checklist /
   Verdict format / Anti-patterns / Dispatch).
2. Add an entry to this README's index table.
3. Commit both files together.
4. Update docs/M12-AUTONOMOUS-DEV-FRAMEWORK.md reviewer chain table if the new
   reviewer is part of the standard chain.

---

## Template versioning

Templates are pinned to branch `ai/m12-tool-3-reviewer-templates` until Phase 3
begins. When Phase 3 starts, templates are merged to the Phase 3 working branch and
locked. Post-merge changes require a new branch + PR.
