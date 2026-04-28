#!/usr/bin/env bash
# mm-queue-submit.sh -- WSL-side helper for the MM-Dev-Cycle scheduled task.
#
# Drops a request into C:\mm-dev-queue\request.txt, triggers the task, polls
# C:\mm-dev-queue\result.txt for a matching nonce. Returns the task exit code.
#
# Usage:
#   ./scripts/mm-queue-submit.sh "FLIP:VerifyOnly"
#   ./scripts/mm-queue-submit.sh "FLIP:AppleFilter"
#   ./scripts/mm-queue-submit.sh "FLIP:NoFilter"
#
# Returns 0 on phase-success, the phase's exit code otherwise.

set -uo pipefail

PHASE="${1:-}"
if [[ -z "$PHASE" ]]; then
    echo "Usage: $0 <phase>" >&2
    echo "Examples: FLIP:VerifyOnly, FLIP:AppleFilter, FLIP:NoFilter" >&2
    exit 2
fi

QUEUE_DIR='/mnt/c/mm-dev-queue'
REQ="$QUEUE_DIR/request.txt"
RES="$QUEUE_DIR/result.txt"

NONCE=$(date +%s%N)
echo "${PHASE}|${NONCE}" > "$REQ"

# trigger the scheduled task
schtasks.exe /run /tn 'MM-Dev-Cycle' >/dev/null 2>&1

# poll for matching nonce up to 30 sec
for i in $(seq 1 30); do
    sleep 1
    res=$(cat "$RES" 2>/dev/null || echo '')
    if [[ "$res" == *"|${NONCE}" ]]; then
        rc="${res%%|*}"
        echo "$res"
        exit "$rc"
    fi
done

echo "[mm-queue-submit] TIMEOUT after 30s waiting for nonce ${NONCE}" >&2
exit 1
