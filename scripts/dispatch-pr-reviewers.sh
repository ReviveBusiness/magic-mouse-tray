#!/usr/bin/env bash
# scripts/dispatch-pr-reviewers.sh
# M12 PR Review Dispatcher — sequential reviewer chain per TOOL-3 design.
#
# DISPATCH PROTOCOL: This script documents the review sequence and collects
# verdicts. Actual agent spawning happens in the primary Claude session via
# the Agent tool. Each reviewer runs, posts its verdict as a PR comment, and
# the next reviewer is launched only after the previous one completes (or
# halts on CRITICAL finding).
#
# Usage:
#   dispatch-pr-reviewers.sh --pr <PR-URL-or-number> [--repo <owner/repo>]
#   dispatch-pr-reviewers.sh --branch <branch-name> [--repo <owner/repo>]
#   dispatch-pr-reviewers.sh --dry-run --pr <PR-URL>   # print plan only
#
# Inputs:
#   --pr <PR-URL>     Full GitHub PR URL or bare PR number
#   --branch <name>   Branch name (auto-resolves to open PR if one exists)
#   --repo <o/r>      Override owner/repo (auto-detected from git remote)
#   --dry-run         Print dispatch plan; do not spawn or post anything
#   --templates-dir   Override path to agent-templates/ (default: .ai/agent-templates)
#   --output-dir      Where to write aggregate report (default: .ai/peer-reviews)
#
# Outputs:
#   pr-review-aggregate.md   — merged verdict from all reviewers
#   per-reviewer log entries in --output-dir/<PR-number>/<reviewer>-verdict.md
#
# Exit codes:
#   0 = all reviewers ran; no REJECT/CRITICAL halts
#   1 = chain halted by CRITICAL finding, reviewer error, or env failure
#
# Reviewer sequence (from TOOL-3 README, halt-on-critical per design):
#   1. senior-driver-dev-review.md
#   2. hid-protocol-review.md
#   3. security-review.md
#   4. style-review.md
#   5. code-quality-review.md
#
# Each reviewer verdict is posted as a PR comment before proceeding.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || echo "$(dirname "$0")/..")"
GITHUB_PY="/home/lesley/projects/RILEY/scripts/github.py"
GIT_PY="/home/lesley/projects/RILEY/scripts/git.py"

# ---- defaults ----
PR_URL=""
PR_NUMBER=""
BRANCH=""
REPO=""
DRY_RUN=false
TEMPLATES_DIR="$REPO_ROOT/.ai/agent-templates"
OUTPUT_DIR="$REPO_ROOT/.ai/peer-reviews"

# ---- argument parsing ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr)
            PR_URL="$2"; shift 2 ;;
        --branch)
            BRANCH="$2"; shift 2 ;;
        --repo)
            REPO="$2"; shift 2 ;;
        --dry-run)
            DRY_RUN=true; shift ;;
        --templates-dir)
            TEMPLATES_DIR="$2"; shift 2 ;;
        --output-dir)
            OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# //' | sed 's/^#//'
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1 ;;
    esac
done

# ---- environment checks ----
if [[ ! -f "$GITHUB_PY" ]]; then
    echo "ERROR: github.py not found at $GITHUB_PY" >&2
    exit 1
fi

if [[ ! -d "$TEMPLATES_DIR" ]]; then
    echo "ERROR: agent-templates directory not found at $TEMPLATES_DIR" >&2
    echo "  TOOL-3 must have run and merged its branch first." >&2
    exit 1
fi

# ---- timestamp ----
TIMESTAMP=$(python3 -c "
import datetime, zoneinfo
tz = zoneinfo.ZoneInfo('America/Edmonton')
print(datetime.datetime.now(tz).strftime('%Y-%m-%d %H:%M %Z'))
" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")

# ---- resolve repo from git remote ----
if [[ -z "$REPO" ]]; then
    REMOTE_URL=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)
    if [[ -n "$REMOTE_URL" ]]; then
        # Handle ssh: git@github.com:owner/repo.git and https: https://github.com/owner/repo.git
        REPO=$(echo "$REMOTE_URL" | sed -E 's|.*github\.com[:/]||' | sed 's|\.git$||')
    fi
fi

if [[ -z "$REPO" ]]; then
    echo "ERROR: Cannot determine owner/repo. Pass --repo <owner/repo> explicitly." >&2
    exit 1
fi

# ---- resolve PR number from URL or branch ----
resolve_pr() {
    if [[ -n "$PR_URL" ]]; then
        # Extract number from URL like https://github.com/owner/repo/pull/42
        PR_NUMBER=$(echo "$PR_URL" | grep -oP '(?<=/pull/)\d+' || true)
        if [[ -z "$PR_NUMBER" ]]; then
            # Bare number passed as --pr argument
            PR_NUMBER="$PR_URL"
        fi
    elif [[ -n "$BRANCH" ]]; then
        # Find open PR for branch via github.py
        PR_NUMBER=$(python3 "$GITHUB_PY" list-prs --repo "$REPO" 2>/dev/null \
            | python3 -c "
import sys, json
data = json.load(sys.stdin)
branch = '$BRANCH'
for pr in data:
    if pr.get('head', {}).get('ref') == branch and pr.get('state') == 'open':
        print(pr['number'])
        break
" 2>/dev/null || true)
        if [[ -z "$PR_NUMBER" ]]; then
            echo "ERROR: No open PR found for branch '$BRANCH' in $REPO" >&2
            exit 1
        fi
    else
        echo "ERROR: Must supply --pr <url-or-number> or --branch <name>" >&2
        exit 1
    fi

    if [[ -z "$PR_NUMBER" ]]; then
        echo "ERROR: Could not resolve PR number from input '$PR_URL'" >&2
        exit 1
    fi
}

resolve_pr
echo "dispatch-pr-reviewers: repo=$REPO PR=#${PR_NUMBER}"

# ---- reviewer sequence ----
declare -a REVIEWER_ORDER=(
    "senior-driver-dev-review.md"
    "hid-protocol-review.md"
    "security-review.md"
    "style-review.md"
    "code-quality-review.md"
)

# Human-readable labels matching filenames
declare -A REVIEWER_LABEL=(
    ["senior-driver-dev-review.md"]="Senior Driver Dev (adversarial)"
    ["hid-protocol-review.md"]="HID Protocol Expert"
    ["security-review.md"]="Security Reviewer"
    ["style-review.md"]="Style / AI-Tells Filter"
    ["code-quality-review.md"]="Code Quality / DRY"
)

# ---- validate templates exist ----
for tpl in "${REVIEWER_ORDER[@]}"; do
    tpl_path="$TEMPLATES_DIR/$tpl"
    if [[ ! -f "$tpl_path" ]]; then
        echo "ERROR: Template not found: $tpl_path" >&2
        echo "  Verify TOOL-3 branch is merged and templates are in $TEMPLATES_DIR" >&2
        exit 1
    fi
done

# ---- fetch PR diff ----
fetch_pr_diff() {
    local diff_file="$1"
    python3 "$GITHUB_PY" get-pr-diff \
        --repo "$REPO" \
        --pr "$PR_NUMBER" \
        --output "$diff_file" 2>/dev/null || {
        # Fallback: gh cli
        if command -v gh >/dev/null 2>&1; then
            gh pr diff "$PR_NUMBER" --repo "$REPO" > "$diff_file" 2>/dev/null
        else
            echo "ERROR: Cannot fetch PR diff. Ensure github.py or gh CLI is available." >&2
            exit 1
        fi
    }
}

# ---- output directory setup ----
PR_OUTPUT_DIR="$OUTPUT_DIR/pr-${PR_NUMBER}"
install -d "$PR_OUTPUT_DIR"

AGGREGATE_MD="$PR_OUTPUT_DIR/pr-review-aggregate.md"

# ---- dry-run mode ----
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "=== DRY RUN: dispatch plan for PR #${PR_NUMBER} in ${REPO} ==="
    echo ""
    echo "Reviewer chain (sequential; halt on CRITICAL/REJECT):"
    local_idx=0
    for tpl in "${REVIEWER_ORDER[@]}"; do
        local_idx=$((local_idx + 1))
        label="${REVIEWER_LABEL[$tpl]}"
        echo "  ${local_idx}. ${label}"
        echo "     Template: ${TEMPLATES_DIR}/${tpl}"
    done
    echo ""
    echo "Output dir: $PR_OUTPUT_DIR"
    echo "Aggregate:  $AGGREGATE_MD"
    echo ""
    echo "Spawn command (per reviewer):"
    echo "  python3 /home/lesley/projects/RILEY/scripts/agent.py spawn \\"
    echo "    --tier sonnet \\"
    echo "    --template <template-path> \\"
    echo "    --pr-url https://github.com/${REPO}/pull/${PR_NUMBER}"
    echo ""
    echo "(Dry run complete. No agents spawned, no PR comments posted.)"
    exit 0
fi

# ---- fetch diff ----
DIFF_FILE="$PR_OUTPUT_DIR/pr-diff.patch"
echo "dispatch-pr-reviewers: fetching PR diff -> $DIFF_FILE"
fetch_pr_diff "$DIFF_FILE"

if [[ ! -s "$DIFF_FILE" ]]; then
    echo "WARNING: PR diff is empty. Continuing with empty diff context." >&2
fi

# ---- aggregate report header ----
cat > "$AGGREGATE_MD" <<MDEOF
# M12 PR Review Aggregate

**PR:** #${PR_NUMBER} in ${REPO}
**Generated:** ${TIMESTAMP}
**Reviewer chain:** sequential (halt on CRITICAL)

| Reviewer | Verdict | Notes |
|---|---|---|
MDEOF

# ---- run reviewers sequentially ----
CHAIN_HALTED=false
HALT_REASON=""

run_reviewer() {
    local tpl_file="$1"
    local tpl_path="$TEMPLATES_DIR/$tpl_file"
    local label="${REVIEWER_LABEL[$tpl_file]}"
    local verdict_file="$PR_OUTPUT_DIR/${tpl_file%.md}-verdict.md"

    echo ""
    echo "--- Reviewer: ${label} ---"

    # DISPATCH STUB: In a live session, this is where the primary session
    # spawns the reviewer agent via the Agent tool, passing:
    #   - template content from $tpl_path
    #   - PR diff from $DIFF_FILE
    #   - PR URL for posting back verdicts
    # The agent writes its verdict to $verdict_file and posts a PR comment.
    #
    # For scripted/batch use: if a verdict file already exists (posted by
    # a reviewer agent in a parallel window), this script reads it directly.

    if [[ -f "$verdict_file" ]]; then
        echo "  Found existing verdict at $verdict_file"
        VERDICT=$(grep -oP '(?<=\*\*Verdict:\*\* )\w[\w-]+' "$verdict_file" | head -1 || echo "UNKNOWN")
    else
        echo "  No verdict file at $verdict_file"
        echo "  --> Spawn reviewer agent manually:"
        echo "      python3 /home/lesley/projects/RILEY/scripts/agent.py spawn \\"
        echo "        --tier sonnet \\"
        echo "        --template ${tpl_path} \\"
        echo "        --pr-url https://github.com/${REPO}/pull/${PR_NUMBER}"
        echo "      Write verdict to: $verdict_file"
        echo "      Then re-run this script to continue the chain."
        # Append placeholder row to aggregate
        printf "| %s | PENDING | Verdict file not found -- spawn agent first |\n" "$label" >> "$AGGREGATE_MD"
        # Cannot continue chain without verdict
        CHAIN_HALTED=true
        HALT_REASON="Verdict missing for reviewer: ${label}"
        return 1
    fi

    # Parse verdict for halt conditions
    # Style reviewer: PASS / FAIL
    # All others: APPROVE / CHANGES-NEEDED / REJECT
    local is_critical=false
    case "$VERDICT" in
        REJECT|FAIL)
            is_critical=true ;;
        APPROVE|PASS|CHANGES-NEEDED)
            is_critical=false ;;
        *)
            echo "  WARNING: Unrecognised verdict '${VERDICT}' -- treating as CHANGES-NEEDED" >&2
            VERDICT="CHANGES-NEEDED (unrecognised)"
            ;;
    esac

    # Post verdict as PR comment via github.py
    if python3 "$GITHUB_PY" comment-pr \
        --repo "$REPO" \
        --pr "$PR_NUMBER" \
        --body-file "$verdict_file" 2>/dev/null; then
        echo "  Verdict posted as PR comment."
    else
        echo "  WARNING: Failed to post verdict as PR comment. Continuing." >&2
    fi

    # Append to aggregate table
    printf "| %s | %s | See %s |\n" "$label" "$VERDICT" "${verdict_file#$REPO_ROOT/}" >> "$AGGREGATE_MD"

    if [[ "$is_critical" == "true" ]]; then
        echo "  HALT: ${label} returned ${VERDICT}. Chain stopped. Fix before continuing."
        CHAIN_HALTED=true
        HALT_REASON="${label} returned ${VERDICT}"
        return 1
    fi

    echo "  Verdict: ${VERDICT} -- continuing chain."
    return 0
}

for tpl in "${REVIEWER_ORDER[@]}"; do
    run_reviewer "$tpl" || break
    if [[ "$CHAIN_HALTED" == "true" ]]; then
        break
    fi
done

# ---- aggregate report footer ----
cat >> "$AGGREGATE_MD" <<MDEOF

---

## Summary

**Chain completed:** $([ "$CHAIN_HALTED" == "true" ] && echo "NO -- halted" || echo "YES -- all reviewers ran")
$([ -n "$HALT_REASON" ] && echo "**Halt reason:** ${HALT_REASON}" || true)

**Next step:**
$(if [[ "$CHAIN_HALTED" == "true" ]]; then
    echo "- Fix issues identified by the blocking reviewer."
    echo "- Re-run: \`scripts/dispatch-pr-reviewers.sh --pr ${PR_NUMBER}\`"
else
    echo "- All automated reviewers passed. Proceed to NLM peer review (/peer-review), then human review."
fi)

---
<!-- Generated by scripts/dispatch-pr-reviewers.sh -->
MDEOF

echo ""
echo "dispatch-pr-reviewers: aggregate report -> $AGGREGATE_MD"

# ---- post aggregate as PR comment ----
if python3 "$GITHUB_PY" comment-pr \
    --repo "$REPO" \
    --pr "$PR_NUMBER" \
    --body-file "$AGGREGATE_MD" 2>/dev/null; then
    echo "dispatch-pr-reviewers: aggregate posted as PR comment."
else
    echo "WARNING: Could not post aggregate as PR comment. File is at $AGGREGATE_MD" >&2
fi

# ---- exit code ----
if [[ "$CHAIN_HALTED" == "true" ]]; then
    echo "dispatch-pr-reviewers: FAIL -- chain halted (${HALT_REASON})." >&2
    exit 1
fi

echo "dispatch-pr-reviewers: PASS -- all 5 reviewers completed without CRITICAL findings."
exit 0
