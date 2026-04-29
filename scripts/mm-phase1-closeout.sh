#!/usr/bin/env bash
# mm-phase1-closeout.sh - Run all Phase 1 post-cleanup verification steps in
# one shot. Replaces the manual sequence of mm-reg-export.sh + mm-reg-diff.sh
# + mm-snapshot-state.sh. This is the MOP gate after the admin-PS cleanup
# orchestrator returns control to WSL.
#
# Usage:
#   ./scripts/mm-phase1-closeout.sh [phase-tag]
#
#   phase-tag    label appended to artifacts (default "m13-phase0")
#
# Exit 0 on success. Non-zero if any step fails — does NOT suppress; you want
# loud failure here because this is the audit gate.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

phase_tag="${1:-m13-phase0}"
out_dir="$REPO_ROOT/.ai/test-runs/$phase_tag"
mkdir -p "$out_dir"

ts=$(date '+%Y-%m-%d-%H%M%S')

echo "[phase1-closeout] === Step 1/3 — post-cleanup registry export ==="
./scripts/mm-reg-export.sh post-cleanup
echo ""

echo "[phase1-closeout] === Step 2/3 — reg-diff verification (MOP gate) ==="
diff_out="$out_dir/reg-diff-$ts.md"
./scripts/mm-reg-diff.sh --auto pre-cleanup post-cleanup "$diff_out"
echo "  -> $diff_out"
echo ""

echo "[phase1-closeout] === Step 3/3 — state snapshot ==="
./scripts/mm-snapshot-state.sh
echo ""

echo "[phase1-closeout] OK Block 1 (verification artefacts) complete."
echo "  reg-diff report: $diff_out"
echo ""
echo "================================================================"
echo "  PER-PHASE CLOSE-OUT GATE — non-skippable, see"
echo "  .ai/playbooks/autonomous-agent-team.md \"Per-phase close-out gate\""
echo "================================================================"
echo ""
echo "  [done] Block 1 — Verification artefacts (this script)"
echo "  [todo] Block 2 — Continuity files:"
echo "         - PSN-0001-hid-battery-driver.yaml: bump last_updated,"
echo "           sessions_logged, append Session History row, update"
echo "           Hypotheses + Decisions tables, refresh Next Session Brief"
echo "         - .ai/test-plans/m13-baseline-and-cache-test.md: version"
echo "           bump if step list / success criteria / halt conditions"
echo "           changed; append changelog"
echo "         - .ai/playbooks/autonomous-agent-team.md: capture any new"
echo "           AP-NN for novel failure modes; bump version"
echo "  [todo] Block 3 — GitHub issues (PSN linked_issues: #2 #3 #4):"
echo "         - cross-reference each open issue with phase findings"
echo "         - close resolved · comment status on still-open"
echo "         - file new issues for any new risks/bugs surfaced"
echo "  [todo] Block 4 — /prd update-progress against PRD-184"
echo "  [todo] Block 5 — atomic commit covering Blocks 1-4"
echo ""
echo "  Skipping ANY block above means the next session pays a 30+ min"
echo "  context-recovery tax. The blocks are cheap NOW (~10 min) and"
echo "  enormous later. See PSN-0001 Session History for the empirical"
echo "  pattern that motivated this gate."
echo "================================================================"
