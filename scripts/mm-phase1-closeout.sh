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

echo "[phase1-closeout] OK Phase 1 close-out complete."
echo "  reg-diff report: $diff_out"
echo "  next: review $diff_out, then proceed to Phase 2 gate."
