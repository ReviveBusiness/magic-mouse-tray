#!/usr/bin/env bash
# mm-dev.sh - WSL wrapper for the Magic Mouse driver dev cycle
#
# USAGE (from WSL, inside the repo):
#   ./scripts/mm-dev.sh state          # snapshot current PnP + driver state
#   ./scripts/mm-dev.sh build          # EWDK msbuild
#   ./scripts/mm-dev.sh sign           # signtool
#   ./scripts/mm-dev.sh install        # remove old + install new + restart device
#   ./scripts/mm-dev.sh capture        # (re)start DebugView
#   ./scripts/mm-dev.sh full           # state -> build -> sign -> install -> state
#   ./scripts/mm-dev.sh log            # tail session log
#   ./scripts/mm-dev.sh debug          # tail MagicMouse entries from DebugView log
#   ./scripts/mm-dev.sh commit "msg"   # stage driver/ and commit via git.py
#   ./scripts/mm-dev.sh diff           # show uncommitted driver changes
#
# The loop:
#   1. Edit driver source (WSL)
#   2. ./scripts/mm-dev.sh full
#   3. ./scripts/mm-dev.sh capture
#   4. Test mouse gestures
#   5. ./scripts/mm-dev.sh debug
#   6. ./scripts/mm-dev.sh commit "fix: ..."
#   7. Repeat from 1

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
GIT_PY="/home/lesley/projects/scripts/git.py"
SESSION_LOG="/mnt/c/mm-dev-session.log"
DEBUG_LOG="/mnt/c/mm3-debug.log"

# Windows-side build directory. WSL repo is SSOT — we sync into here.
# The .vcxproj lives at the root of WIN_DRIVER_DIR (NOT in a driver/ subfolder).
WIN_DRIVER_DIR="${WIN_DRIVER_DIR:-/mnt/d/mm3-driver}"

# Sync WSL repo driver/ + scripts/ into Windows build dir.
# Idempotent; safe to call before every phase. Build artefacts (x64/, *.cer)
# in WIN_DRIVER_DIR are preserved (we only overwrite source + scripts).
sync_to_windows() {
    if [[ ! -d "$WIN_DRIVER_DIR" ]]; then
        echo "[mm-dev] ERROR: $WIN_DRIVER_DIR does not exist." >&2
        echo "[mm-dev] Create it and copy the initial files (vcxproj, *.cer) — then re-run." >&2
        return 1
    fi
    # Source files (driver/* → WIN_DRIVER_DIR/)
    cp -f "$REPO_ROOT/driver/"*.c    "$WIN_DRIVER_DIR/" 2>/dev/null || true
    cp -f "$REPO_ROOT/driver/"*.h    "$WIN_DRIVER_DIR/" 2>/dev/null || true
    cp -f "$REPO_ROOT/driver/"*.inf  "$WIN_DRIVER_DIR/" 2>/dev/null || true
    cp -f "$REPO_ROOT/driver/MagicMouseDriver.vcxproj" "$WIN_DRIVER_DIR/" 2>/dev/null || true
    # Scripts (scripts/* → WIN_DRIVER_DIR/scripts/)
    mkdir -p "$WIN_DRIVER_DIR/scripts"
    cp -f "$REPO_ROOT/scripts/"*.ps1 "$WIN_DRIVER_DIR/scripts/" 2>/dev/null || true
    return 0
}

# Resolve PS1 path: prefer Windows-synced copy (so $PSScriptRoot resolves to
# WIN_DRIVER_DIR\scripts and $DriverRoot lands on the vcxproj location).
# Fall back to WSL UNC path only if the sync target is unavailable.
resolve_ps1_path() {
    if [[ -f "$WIN_DRIVER_DIR/scripts/mm-dev.ps1" ]]; then
        # Convert /mnt/d/mm3-driver/scripts/mm-dev.ps1 → D:\mm3-driver\scripts\mm-dev.ps1
        wslpath -w "$WIN_DRIVER_DIR/scripts/mm-dev.ps1"
    else
        wslpath -w "$SCRIPTS_DIR/mm-dev.ps1"
    fi
}

phase="${1:-help}"

# Map lowercase phase names -> PowerShell ValidateSet casing (no GNU-sed dep)
declare -A PHASE_MAP=(
    [state]=State [build]=Build [sign]=Sign [install]=Install
    [verify]=Verify [rollback]=Rollback [capture]=Capture
    [full]=Full   [log]=Log     [debug]=Debug
)

run_ps1() {
    local lookup="${1,,}"  # bash 4+ lowercase
    local phase_arg="${PHASE_MAP[$lookup]}"
    if [[ -z "$phase_arg" ]]; then
        echo "[mm-dev] ERROR: unknown phase '$1'" >&2
        return 2
    fi
    # Sync source/scripts into Windows build dir so $PSScriptRoot resolves correctly
    if ! sync_to_windows; then
        return 1
    fi
    local win_ps1; win_ps1="$(resolve_ps1_path)"
    # Mark log boundary so we can show only output from this phase
    local start_marker="==== mm-dev BEGIN $phase_arg $(date '+%Y-%m-%d %H:%M:%S') ===="
    echo "$start_marker" | tee -a "$SESSION_LOG" >/dev/null 2>&1 || true
    echo "[mm-dev] Running Phase=$phase_arg on Windows (UAC prompt may appear)..."
    powershell.exe -ExecutionPolicy Bypass -File "$win_ps1" -Phase "$phase_arg"
    local rc=$?
    # Show all session log lines written since the marker
    if [[ -f "$SESSION_LOG" ]]; then
        echo "----- session log (this phase) -----"
        awk -v m="$start_marker" 'found{print} $0==m{found=1}' "$SESSION_LOG" || true
        echo "------------------------------------"
    fi
    if [[ $rc -ne 0 ]]; then
        echo "[mm-dev] Windows phase FAILED (exit=$rc) - full log: $SESSION_LOG" >&2
    else
        echo "[mm-dev] Windows phase OK (exit=0)"
    fi
    return $rc
}

case "$phase" in
    state|build|sign|install|verify|rollback|capture|full|log|debug)
        run_ps1 "$phase"
        exit $?
        ;;

    commit)
        msg="${2:-chore: driver update}"
        echo "[mm-dev] Staging driver/ ..."
        git -C "$REPO_ROOT" add driver/
        echo "[mm-dev] Committing: $msg"
        python3 "$GIT_PY" commit --branch main --message "$msg

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
        echo "[mm-dev] Committed."
        ;;

    diff)
        echo "[mm-dev] Uncommitted driver changes:"
        git -C "$REPO_ROOT" diff driver/
        git -C "$REPO_ROOT" status driver/
        ;;

    read-log)
        lines="${2:-50}"
        echo "[mm-dev] Session log (last $lines lines):"
        tail -n "$lines" "$SESSION_LOG" 2>/dev/null || echo "(no session log yet)"
        ;;

    read-debug)
        lines="${2:-40}"
        echo "[mm-dev] MagicMouse debug entries (last $lines):"
        grep "MagicMouse" "$DEBUG_LOG" 2>/dev/null | tail -n "$lines" || echo "(no entries yet)"
        ;;

    help|*)
        cat <<EOF
mm-dev.sh - Magic Mouse driver dev cycle (WSL wrapper)

LOOP:
  1. Edit driver/ in WSL
  2. ./scripts/mm-dev.sh full          ← build + sign + install + state snapshot
  3. ./scripts/mm-dev.sh capture       ← (re)start DebugView
  4. Test mouse gestures on Windows
  5. ./scripts/mm-dev.sh debug         ← read what happened
  6. ./scripts/mm-dev.sh commit "msg"  ← commit the change
  7. Repeat

COMMANDS:
  state       Snapshot PnP devices, driver, registry, debug log tail
  build       EWDK msbuild Rebuild
  sign        signtool sign .sys + .cat
  install     Remove old driver, install new, restart device
  verify      Post-install health check (LowerFilters, COL01 Started)
  rollback    Remove our filter driver entirely (recovery path)
  capture     (Re)start DebugView -> C:\mm3-debug.log
  full        state + build + sign + install + verify + state
  log         Tail C:\mm-dev-session.log
  debug       Tail MagicMouse lines from C:\mm3-debug.log
  commit MSG  Stage driver/ and commit via git.py
  diff        Show uncommitted changes in driver/
  read-log N  Read last N lines of session log (default 50)
  read-debug N Read last N MagicMouse debug lines (default 40)

EXIT CODES: 0=ok, 1=phase failure (build/sign/install/verify failed), 2=usage
EOF
        ;;
esac
