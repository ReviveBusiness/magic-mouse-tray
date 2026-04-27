#!/usr/bin/env bash
# mm-dev.sh — WSL wrapper for the Magic Mouse driver dev cycle
#
# USAGE (from WSL, inside the repo):
#   ./scripts/mm-dev.sh state          # snapshot current PnP + driver state
#   ./scripts/mm-dev.sh build          # EWDK msbuild
#   ./scripts/mm-dev.sh sign           # signtool
#   ./scripts/mm-dev.sh install        # remove old + install new + restart device
#   ./scripts/mm-dev.sh capture        # (re)start DebugView
#   ./scripts/mm-dev.sh full           # state → build → sign → install → state
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

run_ps1() {
    local phase_arg
    # Capitalize first letter for PowerShell ValidateSet
    phase_arg="$(echo "${1}" | sed 's/./\u&/')"
    echo "[mm-dev] Running Phase=$phase_arg on Windows..."
    powershell.exe -ExecutionPolicy Bypass -File "$WIN_PS1" -Phase "$phase_arg"
    echo "[mm-dev] Windows phase complete."
}

case "$phase" in
    state|build|sign|install|capture|full|log|debug)
        run_ps1 "$phase"
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
mm-dev.sh — Magic Mouse driver dev cycle (WSL wrapper)

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
  capture     (Re)start DebugView → C:\mm3-debug.log
  full        state + build + sign + install + state
  log         Tail C:\mm-dev-session.log
  debug       Tail MagicMouse lines from C:\mm3-debug.log
  commit MSG  Stage driver/ and commit via git.py
  diff        Show uncommitted changes in driver/
  read-log N  Read last N lines of session log (default 50)
  read-debug N Read last N MagicMouse debug lines (default 40)
EOF
        ;;
esac
