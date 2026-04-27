#!/usr/bin/env bash
# mm-rev-eng-context.sh — locate the function(s) in disasm.txt that reference
# specific byte constants, and dump surrounding instructions for human review.
#
# Use case: we know Apple's applewirelessmouse.sys references SDP attribute
# 0x0206 (9 hits) somewhere. To replicate their pattern-match logic in our
# filter, we need to read those references in context.
#
# This script:
#   1. Searches the analyzed binary's disasm.txt for the byte constants
#   2. For each hit, finds the enclosing function (nearest 'push rbp' / function start)
#   3. Dumps ~80 lines of disassembly around the hit
#   4. Outputs to .ai/rev-eng/<sha>/contexts/<constant>.txt
#
# Usage:
#   ./scripts/mm-rev-eng-context.sh <sha-prefix> [constant ...]
#
# Examples:
#   ./scripts/mm-rev-eng-context.sh 08f33d7e3ece
#   ./scripts/mm-rev-eng-context.sh 08f33d7e3ece 0x206 0x1124

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_BASE="$REPO_ROOT/.ai/rev-eng"

sha_prefix="${1:-}"
shift || true

if [[ -z "$sha_prefix" ]]; then
    echo "usage: $0 <sha-prefix> [constant ...]" >&2
    exit 1
fi

work_dir="$WORK_BASE/$sha_prefix"
disasm="$work_dir/disasm.txt"
ctx_dir="$work_dir/contexts"

if [[ ! -f "$disasm" ]]; then
    echo "[ERROR] disasm.txt not found at $disasm — run mm-rev-eng.sh first" >&2
    exit 1
fi

install -d "$ctx_dir"

# Default constants if none given — the empirically-found-FOUND signatures
# from a typical BRB filter analysis.
constants=("$@")
if [[ ${#constants[@]} -eq 0 ]]; then
    constants=(
        '0x206'         # SDP_ATTR_HID_DESCRIPTOR_LIST
        '0x1124'        # HID Service UUID
        '0x90'          # Vendor battery report ID
        '0x47'          # Apple unified battery report ID
        '0x410003'      # IOCTL_INTERNAL_BTH_SUBMIT_BRB (full IOCTL value)
        '0x105'         # BRB_L2CA_ACL_TRANSFER
    )
fi

echo "[mm-rev-eng-context] Scanning $disasm for constants: ${constants[*]}"

for c in "${constants[@]}"; do
    out="$ctx_dir/${c//\//_}.txt"
    : > "$out"
    {
        echo "# Disassembly context for constant: $c"
        echo "# binary: $(grep '^/' "$disasm" | head -1)"
        echo "# generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo ""
        # objdump output uses lower-case hex with 'h' suffix or just '0x' prefix
        # Match either form, plus the pattern as 4-hex-digit immediates
        # Strategy: grep with line numbers, then dump 30 lines before + 50 after each hit
        grep -nE "(${c//x/x[0-9a-f]*})" "$disasm" 2>/dev/null \
            | awk -F: 'BEGIN { last=-1 }
                       { if ($1 - last > 80) {
                             print "=== HIT at line " $1 " ==="
                             cmd = "sed -n " ($1-30) "," ($1+50) "p '"$disasm"'"
                             system(cmd)
                             print ""
                             last=$1
                       } }' 2>/dev/null || true
    } > "$out"
    hits=$(grep -c '=== HIT' "$out" 2>/dev/null || echo 0)
    echo "  $c -> $hits hit-region(s) -> $out"
done

# Also identify likely BRB completion routine entry points - functions that
# manipulate stack near a BRB header field offset (e.g., +0x16 type field).
{
    echo "# Function-entry candidates near BRB type offset (+0x16) accesses"
    echo "# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    grep -nE 'movzx? .* \[r[a-z0-9]+\+0x16\]' "$disasm" \
        | head -20 \
        | while IFS= read -r line; do
            ln="${line%%:*}"
            # back-walk to find the enclosing function start
            sed -n "$((ln-200)),${ln}p" "$disasm" \
                | tac | grep -m1 '^[0-9a-f]\+ <' || true
            echo "  -> hit at line $ln: ${line:0:120}"
            echo ""
        done
} > "$ctx_dir/brb-handler-candidates.txt"

echo "[mm-rev-eng-context] Function entry candidates -> $ctx_dir/brb-handler-candidates.txt"
echo "[mm-rev-eng-context] Done."
