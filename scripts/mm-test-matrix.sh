#!/usr/bin/env bash
# mm-test-matrix.sh - M13 Phase 2 test orchestrator.
#
# Walks a test cell through the standard sequence:
#   pair -> test -> unpair -> repair -> test -> reboot -> test
# capturing HID state, accept-test results, and user observations at each step.
#
# Usage:
#   ./scripts/mm-test-matrix.sh <cell-id> [step]
#
#   cell-id: T-V3-AF | T-V3-NF | T-V1-AF | T-V1-NF
#   step:    pair-initial | test-1 | unpair | repair | test-2 | reboot | test-3
#            (omit to run interactively)
#
# Output dir: .ai/test-runs/<YYYY-MM-DD-HHMMSS>-<cell-id>/<step>/
#
# v1.2 captures per step:
#   - HID probe (mm-hid-probe.ps1)
#   - mm-accept-test JSON
#   - State snapshot (mm-snapshot-state.sh)
#   - Tray debug.log + kernel debug log tails
#   - Procmon .PML (cell-level: start at cell begin, stop at cell end)
#   - ETW .etl via wpr.exe (cell-level; requires admin PS -- user is prompted)
#   - WM_MOUSEWHEEL event count + per-event timestamps (test steps only, 3s window)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS_BASE="$REPO_ROOT/.ai/test-runs"
TRAY_LOG="/mnt/c/Users/Lesley/AppData/Roaming/MagicMouseTray/debug.log"
KERNEL_LOG="/mnt/c/mm3-debug.log"

cell_id="${1:-}"
step="${2:-}"

if [[ -z "$cell_id" ]]; then
    cat <<EOF
mm-test-matrix.sh - M13 Phase 2 test orchestrator (plan v1.2)

Usage: $0 <cell-id> [step]

Cell IDs:
  T-V3-AF       v3 mouse, AppleFilter mode (current default)
  T-V3-NF       v3 mouse, NoFilter mode (use mm-state-flip first)
  T-V3-AF-USB   v3 mouse, AppleFilter + USB-C cable connected during test
  T-V3-NF-USB   v3 mouse, NoFilter + USB-C cable connected during test
  T-V1-AF       v1 mouse, AppleFilter mode
  T-V1-NF       v1 mouse, NoFilter mode

Steps (omit to run interactively):
  pair-initial   Initial pair via Bluetooth Settings
  test-1         Test sequence: pointer + 2-finger scroll (3s) + AC-Pan + click + tray
  unpair         Remove from Bluetooth Settings
  repair         Re-pair via Bluetooth Settings (long-press button on bottom)
  test-2         Test sequence (post-repair)
  sleep-wake     S3 suspend → resume → 30s settle → test (G1 #1 axis)
  test-2b        Test sequence (post-sleep-wake)
  reboot         Reboot Windows host
  test-3         Test sequence (post-reboot)
  usb-plug       (USB cells only) plug USB-C cable
  usb-unplug     (USB cells only) unplug USB-C cable

Output: .ai/test-runs/<ts>-<cell-id>/<step>/
EOF
    exit 0
fi

valid_cells="T-V3-AF T-V3-NF T-V3-AF-USB T-V3-NF-USB T-V1-AF T-V1-NF"
if [[ ! " $valid_cells " =~ \ $cell_id\  ]]; then
    echo "[mm-test-matrix] ERROR: invalid cell-id '$cell_id'. Valid: $valid_cells" >&2
    exit 2
fi

# Establish run dir (one per session; reused across steps within a session)
run_marker="$RUNS_BASE/.current-${cell_id}"
if [[ -f "$run_marker" ]]; then
    run_dir=$(cat "$run_marker")
else
    ts=$(date '+%Y-%m-%d-%H%M%S')
    run_dir="$RUNS_BASE/${ts}-${cell_id}"
    install -d "$run_dir"
    echo "$run_dir" > "$run_marker"
fi
echo "[mm-test-matrix] Cell $cell_id, run dir: $run_dir"

# Per-step subdir
make_step_dir() {
    local s="$1"
    local d="$run_dir/$s"
    install -d "$d"
    echo "$d"
}

# ---------------------------------------------------------------------------
# Capture functions
# ---------------------------------------------------------------------------

capture_hid_probe() {
    local step_dir="$1"
    echo "[capture] HID probe..."
    powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$REPO_ROOT/scripts/mm-hid-probe.ps1")" \
        2>&1 | grep -v "Add-Content\|+ \|CategoryInfo\|FullyQualified\|At D:\|PermissionDenied" \
        > "$step_dir/hid-probe.txt" || true
    echo "[capture]   -> $step_dir/hid-probe.txt"
}

capture_accept_test() {
    local step_dir="$1"
    echo "[capture] Acceptance test..."
    "$REPO_ROOT/scripts/mm-accept-test.sh" 2>&1 > "$step_dir/accept-test.log" || true
    # Find the JSON the test wrote
    local latest_json
    latest_json=$(ls -t /mnt/c/Users/Lesley/AppData/Local/mm-accept-test-*.json 2>/dev/null | head -1)
    if [[ -n "$latest_json" ]]; then
        cp "$latest_json" "$step_dir/accept-test.json"
        echo "[capture]   -> $step_dir/accept-test.json"
    fi
}

capture_state_snapshot() {
    local step_dir="$1"
    echo "[capture] State snapshot..."
    # mm-snapshot-state.sh produces a dir; we'll point it at our step_dir
    MM_SNAPSHOT_OVERRIDE="$step_dir/snapshot" \
    "$REPO_ROOT/scripts/mm-snapshot-state.sh" >/dev/null 2>&1 || true
    echo "[capture]   -> $step_dir/snapshot/"
}

capture_log_tails() {
    local step_dir="$1"
    if [[ -f "$TRAY_LOG" ]]; then
        tail -50 "$TRAY_LOG" > "$step_dir/tray-debug-tail.log" 2>/dev/null || true
    fi
    if [[ -f "$KERNEL_LOG" ]]; then
        grep "MagicMouse" "$KERNEL_LOG" 2>/dev/null | tail -100 > "$step_dir/kernel-debug-tail.log" || true
    fi
    echo "[capture]   tray + kernel log tails"
}

# Procmon path (confirmed available on host)
PROCMON_EXE="C:\\Users\\Lesley\\AppData\\Local\\Microsoft\\WindowsApps\\Procmon.exe"

start_procmon() {
    local run_dir_win
    run_dir_win=$(wslpath -w "$run_dir")
    local pml_path="${run_dir_win}\\procmon.PML"
    echo "[capture] Starting Procmon -> ${pml_path}..."
    # Launch unfiltered; filter post-hoc (simpler, adequate for data sizes we expect)
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
        "Start-Process -FilePath '${PROCMON_EXE}' -ArgumentList '/BackingFile','${pml_path}','/Quiet','/Minimized','/AcceptEula' -WindowStyle Minimized" \
        2>/dev/null || true
    echo "[capture]   -> Procmon running, output: ${pml_path}"
}

stop_procmon() {
    echo "[capture] Stopping Procmon..."
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
        "Start-Process -FilePath '${PROCMON_EXE}' -ArgumentList '/Terminate'" \
        2>/dev/null || true
    echo "[capture]   -> Procmon terminated, .PML saved to run dir"
}

# wpr.exe path (in-box Windows tool)
WPR_EXE="C:\\Windows\\System32\\wpr.exe"

start_wpr() {
    local run_dir_win
    run_dir_win=$(wslpath -w "$run_dir")
    cat <<EOF

==== ETW capture ====
wpr.exe requires an ADMIN PowerShell session. From your admin PowerShell, run:
    wpr -start GeneralProfile -filemode

Press ENTER once wpr has started (you will see "Recording is now on." or similar).
EOF
    read -r -p "" _
    echo "[capture]   -> ETW recording started"
}

stop_wpr() {
    local run_dir_win
    run_dir_win=$(wslpath -w "$run_dir")
    local etl_path="${run_dir_win}\\etw-trace.etl"
    cat <<EOF

==== Stop ETW capture ====
From your admin PowerShell, run:
    wpr -stop ${etl_path}

This will take ~30 seconds to finalize the trace. Press ENTER once wpr has finished
(you will see "Recording has been saved." or the PS prompt returns).
EOF
    read -r -p "" _
    echo "[capture]   -> ETW trace saved to ${etl_path}"
}

capture_wheel_events() {
    local step_dir="$1"
    local step_name="$2"
    # Only run for test steps (step name contains "test")
    if [[ "$step_name" != *"test"* ]]; then
        return
    fi
    local wheel_json_win
    wheel_json_win="$(wslpath -w "${step_dir}/wheel-events.json")"
    local ps_script_win
    ps_script_win="$(wslpath -w "${REPO_ROOT}/scripts/mm-wheel-counter.ps1")"
    cat <<EOF

==== Wheel-event capture ====
Start your 3-second 2-finger scroll gesture NOW. Capturing for 3s.
EOF
    powershell.exe -NoProfile -ExecutionPolicy Bypass \
        -File "$ps_script_win" -DurationSec 3 -OutputJson "$wheel_json_win" || true
    if [[ -f "${step_dir}/wheel-events.json" ]]; then
        python3 -c "
import sys, json
d = json.load(open('${step_dir}/wheel-events.json'))
print('  -> ' + str(d['event_count']) + ' wheel events captured')
" 2>/dev/null || true
    fi
    echo "[capture]   -> ${step_dir}/wheel-events.json"
}

prompt_user_observations() {
    local step_dir="$1"
    local step_name="$2"
    cat <<EOF

==== Manual test for step: $step_name ====
Please perform the following on the mouse and report observations:

  1. Move pointer corner-to-corner across screen
     -> smooth movement?              [yes/no/partial]
  2. 2-finger vertical scroll for 3 seconds in any window with scrollable content
     -> continuous wheel events?      [yes/no/partial]
     -> direction correct?            [yes/no]
  3. 2-finger horizontal swipe (left + right)
     -> AC-Pan / horizontal scroll?   [yes/no/n/a]
  4. Click left button
     -> registered?                   [yes/no]
  5. Click right button (or 2-finger click for v3)
     -> registered?                   [yes/no]
  6. Look at tray icon tooltip
     -> battery percentage shown?     [yes/no/N-A]
     -> tooltip text:                 [paste here]

Type your notes. End with a line containing ONLY '<<<END' to finish.
EOF
    cat > "$step_dir/observations.txt" <<EOF
=== Manual test observations ===
Step:  $step_name
When:  $(date '+%Y-%m-%d %H:%M:%S')
Cell:  $cell_id

EOF
    while IFS= read -r line; do
        [[ "$line" == "<<<END" ]] && break
        echo "$line" >> "$step_dir/observations.txt"
    done
    echo "[capture]   -> $step_dir/observations.txt"
}

# ---------------------------------------------------------------------------
# Step runners
# ---------------------------------------------------------------------------

run_test_step() {
    local step_name="$1"
    local step_dir; step_dir=$(make_step_dir "$step_name")
    echo "==== Running test step: $step_name ===="
    capture_hid_probe        "$step_dir"
    capture_accept_test      "$step_dir"
    capture_state_snapshot   "$step_dir"
    capture_log_tails        "$step_dir"
    capture_wheel_events     "$step_dir" "$step_name"
    prompt_user_observations "$step_dir" "$step_name"
    echo "==== Step complete: $step_name ===="
}

run_action_step() {
    local step_name="$1"
    local prompt_text="$2"
    local step_dir; step_dir=$(make_step_dir "$step_name")
    echo "==== Action step: $step_name ===="
    echo
    echo "$prompt_text"
    echo
    read -r -p "Press ENTER when complete (or type 'skip' to skip): " resp
    if [[ "$resp" == "skip" ]]; then
        echo "skipped" > "$step_dir/note.txt"
        return
    fi
    capture_state_snapshot "$step_dir"
    capture_log_tails      "$step_dir"
    echo "completed at $(date '+%Y-%m-%d %H:%M:%S')" > "$step_dir/note.txt"
    echo "==== Action complete: $step_name ===="
}

# G1 #1 axis: S3 sleep + wake transition.
# rundll32 SetSuspendState requires admin PS; we prompt the user to invoke from
# their existing admin shell rather than UAC-prompting from WSL.
run_sleep_wake_step() {
    local step_dir; step_dir=$(make_step_dir "sleep-wake")
    echo "==== Sleep/wake step ===="
    echo
    echo "From your admin PowerShell, run:"
    echo "    rundll32.exe powrprof.dll,SetSuspendState 0,1,0"
    echo
    echo "Wait ~10 seconds for S3, then wake the host (mouse click or keypress)."
    echo "After wake, wait 30 seconds for the BT stack to re-settle before pressing ENTER."
    echo
    read -r -p "Press ENTER once awake + 30s settle complete: " _
    capture_state_snapshot "$step_dir"
    capture_log_tails      "$step_dir"
    echo "sleep-wake completed at $(date '+%Y-%m-%d %H:%M:%S')" > "$step_dir/note.txt"
    echo "==== Sleep/wake complete ===="
}

run_full_sequence() {
    # Start cell-level captures (Procmon + ETW) before any step runs.
    # Procmon launches silently; wpr requires admin PS so the user is prompted.
    start_procmon
    start_wpr

    case "$cell_id" in
        T-V3-AF)
            echo "Cell T-V3-AF: v3 mouse, AppleFilter mode (current default state)"
            run_test_step "test-1-initial"
            run_action_step "unpair" "On the Windows host, open Bluetooth Settings -> Magic Mouse -> ... -> Remove device. Wait for the device to disappear from the list."
            run_action_step "repair" "Long-press the button on the bottom of the Magic Mouse until the orange light shows. Add the mouse back via Windows Bluetooth Settings."
            run_test_step "test-2-post-repair"
            run_sleep_wake_step
            run_test_step "test-2b-post-sleep-wake"
            run_action_step "reboot" "Reboot Windows. After reboot, log back in, wait for the mouse to reconnect (~30 sec), then re-run this script with step=test-3."
            ;;
        T-V3-NF)
            echo "Cell T-V3-NF: v3 mouse, NoFilter mode"
            echo "Pre-step: flipping to NoFilter mode..."
            "$REPO_ROOT/scripts/mm-dev.sh" full 2>/dev/null || true
            # Use the FLIP:NoFilter task harness if available; otherwise direct
            printf 'FLIP:NoFilter|%s\r\n' "$(date +%s%N)" > /mnt/c/mm-dev-queue/request.txt
            schtasks.exe /run /tn 'MM-Dev-Cycle' >/dev/null 2>&1 || true
            sleep 8
            run_test_step "test-1-noflag"
            run_action_step "unpair" "Bluetooth Settings -> Magic Mouse -> Remove device."
            run_action_step "repair" "Re-pair via long-press + Bluetooth Settings."
            run_test_step "test-2-post-repair"
            run_sleep_wake_step
            run_test_step "test-2b-post-sleep-wake"
            run_action_step "reboot" "Reboot. Re-run with step=test-3 after."
            ;;
        T-V3-AF-USB | T-V3-NF-USB)
            # USB-C cell variant: tests USB+BT path interaction + Code-39 hazard.
            local mode="${cell_id#T-V3-}"
            echo "Cell $cell_id: v3 mouse, $mode + USB-C connected"
            if [[ "$cell_id" == "T-V3-NF-USB" ]]; then
                echo "Pre-step: flipping to NoFilter mode..."
                "$REPO_ROOT/scripts/mm-dev.sh" full 2>/dev/null || true
                printf 'FLIP:NoFilter|%s\r\n' "$(date +%s%N)" > /mnt/c/mm-dev-queue/request.txt
                schtasks.exe /run /tn 'MM-Dev-Cycle' >/dev/null 2>&1 || true
                sleep 8
            fi
            run_action_step "usb-plug" "Plug the USB-C charging cable into the Magic Mouse and into a USB port on the host. Wait 10 seconds for USB enumeration."
            run_test_step "test-1-usb-plugged"
            run_action_step "usb-unplug" "Unplug the USB-C cable. Wait 5 seconds."
            run_test_step "test-2-usb-unplugged"
            run_action_step "reboot" "Reboot. Re-run with step=test-3 after; PLUG USB-C cable BACK IN before logging in if you want post-reboot USB state."
            ;;
        T-V1-AF | T-V1-NF)
            echo "Cell $cell_id: v1 (AA-battery) Magic Mouse"
            echo "PREREQUISITE: pair the v1 mouse via Bluetooth Settings before continuing."
            read -r -p "Is the v1 mouse paired and connected now? [y/N]: " ok
            if [[ "$ok" != "y" && "$ok" != "Y" ]]; then
                echo "Pair the v1 mouse first. Aborting."
                exit 3
            fi
            if [[ "$cell_id" == "T-V1-NF" ]]; then
                # Flip to NoFilter for v1 too (different MAC; manual reg edit needed)
                echo "WARN: flipping v1 to NoFilter requires manual reg edit (v1 MAC differs from v3)."
                echo "      mm-state-flip.ps1 currently targets v3 PID 0x0323 only."
                echo "      Skipping auto-flip; if you want NoFilter for v1, edit registry manually first."
                read -r -p "v1 currently in NoFilter mode? [y/N]: " ok2
                if [[ "$ok2" != "y" && "$ok2" != "Y" ]]; then
                    echo "Aborting T-V1-NF cell."
                    exit 4
                fi
            fi
            run_test_step "test-1-initial"
            run_action_step "unpair" "Remove v1 from Bluetooth Settings."
            run_action_step "repair" "Re-pair v1."
            run_test_step "test-2-post-repair"
            run_sleep_wake_step
            run_test_step "test-2b-post-sleep-wake"
            run_action_step "reboot" "Reboot. Re-run with step=test-3 after."
            ;;
    esac

    # Stop cell-level captures.
    stop_procmon
    stop_wpr

    echo "==== Cell $cell_id sequence complete (or paused for reboot) ===="
    echo "Run dir: $run_dir"
    echo
    echo "After reboot completes:"
    echo "  $0 $cell_id test-3"
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

if [[ -z "$step" ]]; then
    run_full_sequence
else
    case "$step" in
        test-1|test-2|test-2b|test-3|test-1-initial|test-1-noflag|test-1-usb-plugged|test-2-post-repair|test-2-usb-unplugged|test-2b-post-sleep-wake|test-3-post-reboot)
            run_test_step "$step"
            ;;
        unpair)      run_action_step "unpair"     "Remove the mouse from Bluetooth Settings." ;;
        repair)      run_action_step "repair"     "Re-pair the mouse." ;;
        reboot)      run_action_step "reboot"     "Reboot the host." ;;
        usb-plug)    run_action_step "usb-plug"   "Plug the USB-C cable into the Magic Mouse." ;;
        usb-unplug)  run_action_step "usb-unplug" "Unplug the USB-C cable from the Magic Mouse." ;;
        sleep-wake)  run_sleep_wake_step ;;
        clean)
            echo "Removing run marker for cell $cell_id (next run starts fresh dir)"
            rm -f "$run_marker"
            ;;
        *)
            echo "Unknown step: $step"
            exit 5
            ;;
    esac
fi
