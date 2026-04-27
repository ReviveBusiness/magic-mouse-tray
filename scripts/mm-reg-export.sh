#!/usr/bin/env bash
# mm-reg-export.sh - Snapshot HKLM\SYSTEM to a timestamped .reg file.
#
# Used as a pre/post-mutation registry backup at major M13 phase boundaries
# and any time we want a clean reference state. No admin needed (reg.exe export
# is a normal user operation; we only export, not mutate).
#
# Usage:
#   ./scripts/mm-reg-export.sh [tag]
#
# Output:
#   D:\Users\Lesley\Documents\Backups\<YYYY-MM-DD-HHMMSS>[-tag].reg
#
# Tag is optional; defaults to no tag. Recommended tags:
#   pre-cleanup       Before Phase 1 cleanup runs
#   post-cleanup      After Phase 1 cleanup verified
#   pre-patch         Before any BTHPORT cache patch attempt
#   post-test-matrix  After Phase 2 test cells complete
#
# Returns 0 on success, 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_BASE="${MM_BACKUP_DIR:-/mnt/d/Users/Lesley/Documents/Backups}"
HIVE="${MM_REG_HIVE:-HKLM\\SYSTEM}"

tag="${1:-}"
ts=$(date '+%Y-%m-%d-%H%M%S')

if [[ ! -d "$BACKUP_BASE" ]]; then
    echo "[mm-reg-export] ERROR: backup dir not found: $BACKUP_BASE" >&2
    echo "[mm-reg-export] Set MM_BACKUP_DIR env var to override." >&2
    exit 1
fi

if [[ -n "$tag" ]]; then
    fname="${ts}-${tag}.reg"
else
    fname="${ts}.reg"
fi

# Convert WSL path to Windows path for reg.exe
win_dest="$(wslpath -w "$BACKUP_BASE/$fname")"

echo "[mm-reg-export] Exporting $HIVE -> $win_dest"
echo "[mm-reg-export] (this can take 1-2 minutes for large hives)"

# reg.exe is reachable from WSL; runs in the Windows context with the user's privileges.
# /y suppresses overwrite prompt (we never collide because filename is timestamped).
if reg.exe export "$HIVE" "$win_dest" /y >/dev/null; then
    win_size=$(stat -c %s "$BACKUP_BASE/$fname" 2>/dev/null || echo 0)
    win_size_mb=$((win_size / 1024 / 1024))
    echo "[mm-reg-export] OK: $win_dest (${win_size_mb} MB)"
    exit 0
else
    rc=$?
    echo "[mm-reg-export] FAIL: reg.exe export returned $rc" >&2
    exit 1
fi
