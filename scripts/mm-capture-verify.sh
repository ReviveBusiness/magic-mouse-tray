#!/usr/bin/env bash
# mm-capture-verify.sh - Verify all expected capture files exist for a test step.
#
# Called after a test cell step completes to confirm all required artefacts
# were written before the orchestrator advances to the next step.
# Halts the orchestrator (exit 1) if any required file is missing or undersized.
#
# USAGE:
#   ./scripts/mm-capture-verify.sh <step-dir>
#   ./scripts/mm-capture-verify.sh --quiet <step-dir>
#
# ARGUMENTS:
#   step-dir   Path to a test step directory, e.g.
#              .ai/test-runs/2026-04-27-120000-T-V3-AF/test-1-initial/
#
# FLAGS:
#   --quiet    Suppress per-file output; print only final PASS/FAIL verdict.
#              Intended for use when called from mm-test-matrix.sh.
#
# EXIT CODES:
#   0  All required files present and meet minimum-size thresholds.
#   1  One or more checks failed. Orchestrator must NOT advance.
#   2  Usage error (bad arguments).
#
# REQUIRED-FILE RULES:
#   hid-probe.txt        >= 1024 bytes  (non-empty; < 1 KB means probe silently failed)
#   accept-test.json     >= 500 bytes   (contains 8 AC check entries)
#   accept-test.log      >= 500 bytes   (transcript of the PS1 run)
#   snapshot/            directory with >= 3 files inside
#   tray-debug-tail.log  >= 0 bytes     (empty OK if tray had not polled yet)
#   kernel-debug-tail.log >= 0 bytes    (empty OK if DebugView had no output)
#   observations.txt     >= 100 bytes   (must contain user notes; header-only = halt)

set -uo pipefail

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
QUIET=0
STEP_DIR=""

for arg in "$@"; do
    case "$arg" in
        --quiet) QUIET=1 ;;
        -*)      echo "[mm-capture-verify] ERROR: unknown flag '$arg'" >&2; exit 2 ;;
        *)
            if [[ -n "$STEP_DIR" ]]; then
                echo "[mm-capture-verify] ERROR: unexpected extra argument '$arg'" >&2
                exit 2
            fi
            STEP_DIR="$arg"
            ;;
    esac
done

if [[ -z "$STEP_DIR" ]]; then
    cat <<EOF
mm-capture-verify.sh - verify M13 per-step capture completeness

Usage: $0 [--quiet] <step-dir>

  step-dir   Path to a test step directory, e.g.:
             .ai/test-runs/2026-04-27-120000-T-V3-AF/test-1-initial/

  --quiet    Suppress per-file lines; print only final verdict.

Exit 0 = all checks pass. Exit 1 = one or more failures (halt orchestrator).
EOF
    exit 2
fi

# Normalize: strip trailing slash
STEP_DIR="${STEP_DIR%/}"

if [[ ! -d "$STEP_DIR" ]]; then
    echo "[mm-capture-verify] ERROR: step directory does not exist: $STEP_DIR" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0

log_pass() {
    local label="$1"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
    if [[ "$QUIET" -eq 0 ]]; then
        printf '[mm-capture-verify] PASS  %s\n' "$label"
    fi
}

log_fail() {
    local label="$1"
    local reason="$2"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    # Always print failures regardless of --quiet
    printf '[mm-capture-verify] FAIL  %s  (%s)\n' "$label" "$reason" >&2
}

# ---------------------------------------------------------------------------
# Check: regular file with minimum byte threshold
# check_file <relative-name> <min-bytes> <label>
# ---------------------------------------------------------------------------
check_file() {
    local rel="$1"
    local min_bytes="$2"
    local label="$3"
    local path="$STEP_DIR/$rel"

    if [[ ! -f "$path" ]]; then
        log_fail "$label" "file missing: $path"
        return
    fi

    local size
    size=$(stat -c '%s' "$path" 2>/dev/null || echo 0)

    if [[ "$size" -lt "$min_bytes" ]]; then
        log_fail "$label" "size ${size}B < required ${min_bytes}B ($path)"
        return
    fi

    log_pass "$label"
}

# ---------------------------------------------------------------------------
# Check: snapshot directory with minimum file count
# check_snapshot_dir <min-file-count>
# ---------------------------------------------------------------------------
check_snapshot_dir() {
    local min_count="$1"
    local snap_dir="$STEP_DIR/snapshot"

    if [[ ! -d "$snap_dir" ]]; then
        log_fail "snapshot/" "directory missing: $snap_dir"
        return
    fi

    local count
    # count regular files at any depth inside snapshot/
    count=$(find "$snap_dir" -maxdepth 3 -type f 2>/dev/null | wc -l)

    if [[ "$count" -lt "$min_count" ]]; then
        log_fail "snapshot/" "only ${count} files inside (need >= ${min_count})"
        return
    fi

    log_pass "snapshot/ (${count} files)"
}

# ---------------------------------------------------------------------------
# Check: observations.txt — must be >= 100 bytes AND contain content beyond
# the auto-generated header (header ends after the blank line following "Cell:").
# A file that is all-header with no user-entered lines is treated as a failure.
# ---------------------------------------------------------------------------
check_observations() {
    local path="$STEP_DIR/observations.txt"

    if [[ ! -f "$path" ]]; then
        log_fail "observations.txt" "file missing: $path"
        return
    fi

    local size
    size=$(stat -c '%s' "$path" 2>/dev/null || echo 0)

    if [[ "$size" -lt 100 ]]; then
        log_fail "observations.txt" "size ${size}B < required 100B (empty or header-only)"
        return
    fi

    # The auto-generated header ends after the blank line that follows "Cell: ..."
    # Any non-empty line appearing after that header counts as user content.
    # Header pattern: lines matching "=== Manual test", "Step:", "When:", "Cell:", or blank lines.
    local header_end_seen=0
    local user_lines=0
    while IFS= read -r line; do
        if [[ "$header_end_seen" -eq 0 ]]; then
            # Detect end of header: blank line after the Cell: line
            if [[ -z "$line" ]]; then
                header_end_seen=1
            fi
            continue
        fi
        # Post-header: any non-blank line is user content
        if [[ -n "$line" ]]; then
            user_lines=$(( user_lines + 1 ))
        fi
    done < "$path"

    if [[ "$user_lines" -eq 0 ]]; then
        log_fail "observations.txt" "contains only auto-generated header; no user notes found"
        return
    fi

    log_pass "observations.txt (${size}B, ${user_lines} user line(s))"
}

# ---------------------------------------------------------------------------
# Run all checks
# ---------------------------------------------------------------------------
if [[ "$QUIET" -eq 0 ]]; then
    printf '[mm-capture-verify] Verifying step dir: %s\n' "$STEP_DIR"
fi

check_file "hid-probe.txt"          1024  "hid-probe.txt (>= 1 KB)"
check_file "accept-test.json"        500  "accept-test.json (>= 500 B)"
check_file "accept-test.log"         500  "accept-test.log (>= 500 B)"
check_snapshot_dir                     3
check_file "tray-debug-tail.log"       0  "tray-debug-tail.log (>= 0 B)"
check_file "kernel-debug-tail.log"     0  "kernel-debug-tail.log (>= 0 B)"
check_observations

# ---------------------------------------------------------------------------
# Final verdict
# ---------------------------------------------------------------------------
TOTAL=$(( PASS_COUNT + FAIL_COUNT ))
if [[ "$QUIET" -eq 0 ]]; then
    printf '\n'
fi

if [[ "$FAIL_COUNT" -eq 0 ]]; then
    printf '[mm-capture-verify] PASS  %d/%d checks passed for: %s\n' "$PASS_COUNT" "$TOTAL" "$STEP_DIR"
    exit 0
else
    printf '[mm-capture-verify] FAIL  %d/%d checks failed for: %s\n' "$FAIL_COUNT" "$TOTAL" "$STEP_DIR" >&2
    printf '[mm-capture-verify] Orchestrator must NOT advance to next step until all files are present.\n' >&2
    exit 1
fi
