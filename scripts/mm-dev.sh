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
WIN_PS1="$(wslpath -w "$SCRIPTS_DIR/mm-dev.ps1")"
GIT_PY="/home/lesley/projects/scripts/git.py"
SESSION_LOG="/mnt/c/mm-dev-session.log"
DEBUG_LOG="/mnt/c/mm3-debug.log"

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
    echo "[mm-dev] Running Phase=$phase_arg on Windows..."
    powershell.exe -ExecutionPolicy Bypass -File "$WIN_PS1" -Phase "$phase_arg"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "[mm-dev] Windows phase FAILED (exit=$rc) - check $SESSION_LOG" >&2
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
