#!/usr/bin/env bash
# mm-test.sh — compile and run userland unit tests for driver/InputHandler.c
#
# Tests the pure-logic functions (no WDF/kernel headers required):
#   ScanForSdpHidDescriptor, PatchSdpHidDescriptor,
#   ClampInt8, TouchX, TouchY, TranslateReport12
#
# Usage:
#   ./scripts/mm-test.sh              # from repo root
#
# Exit:
#   0 — all assertions pass
#   1 — compile error or one or more assertions failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SRC="${REPO_ROOT}/tests/test-sdp-scanner.c"
BIN="/tmp/mm-test-sdp"

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------

echo "[mm-test] Compiling ${SRC} ..."

gcc \
    -Wall \
    -Wextra \
    -Wno-unused-parameter \
    -Wno-unused-function \
    -Wno-type-limits \
    -I"${REPO_ROOT}/tests" \
    -o "${BIN}" \
    "${SRC}"

echo "[mm-test] Compile OK → ${BIN}"
echo ""

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

"${BIN}"

# Exit code forwarded from the test binary (0 = all pass, 1 = any fail)
