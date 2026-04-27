#!/usr/bin/env bash
# mm-snapshot-state.sh — capture a complete reproducible snapshot of the
# current Magic Mouse / driver / Windows state for safe rollback.
#
# Run BEFORE any LowerFilters mutation, driver install, or PnP cycle.
# Produces a timestamped tarball in .ai/snapshots/.
#
# What's captured:
#   - LowerFilters value for the BTHENUM HID device
#   - Apple driver INF (oem0.inf)
#   - Our driver INF + binary if installed
#   - PnP topology (Get-PnpDevice for the Magic Mouse VID/PID)
#   - HID capabilities probe (caps + value caps for each interface)
#   - Tray app debug.log tail (last 100 lines)
#   - Kernel debug log tail (last 200 MagicMouse lines)
#   - Schedules task definition for MM-Dev-Cycle
#
# Restore (manual): inspect tarball, follow restore-instructions.md inside.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAP_BASE="$REPO_ROOT/.ai/snapshots"

ts=$(date -u +%Y%m%dT%H%M%SZ)
snap_name="mm-state-$ts"
snap_dir="$SNAP_BASE/$snap_name"
install -d "$snap_dir"

echo "[snapshot] Capturing to $snap_dir"

# 1. PnP topology
echo "[snapshot] PnP topology..."
powershell.exe -ExecutionPolicy Bypass -Command "
    Get-PnpDevice | Where-Object { \$_.InstanceId -like '*0001004C_PID&0323*' -or \$_.InstanceId -like '*D0C050CC8C4D*' -or \$_.InstanceId -like '*MAGICMOUSE*' } | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize | Out-String -Width 250
" > "$snap_dir/pnp-topology.txt" 2>&1 || true

# 2. LowerFilters + Device Parameters for BTHENUM HID device
echo "[snapshot] LowerFilters registry..."
powershell.exe -ExecutionPolicy Bypass -Command "
    \$paths = Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue | Where-Object { \$_.InstanceId -match 'BTHENUM\\\\\{00001124[^\\\\]*VID&0001004C_PID&0323' } | Select-Object -ExpandProperty InstanceId
    foreach (\$p in \$paths) {
        Write-Host '=== ' \$p
        Get-ItemProperty (\"HKLM:\\SYSTEM\\CurrentControlSet\\Enum\\\" + \$p) -ErrorAction SilentlyContinue | Select-Object LowerFilters, UpperFilters, Service, Driver, ConfigFlags | Format-List
        Get-ItemProperty (\"HKLM:\\SYSTEM\\CurrentControlSet\\Enum\\\" + \$p + '\\Device Parameters') -ErrorAction SilentlyContinue | Format-List
    }
" > "$snap_dir/registry.txt" 2>&1 || true

# 3. HID caps probe
echo "[snapshot] HID caps probe..."
powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$REPO_ROOT/scripts/mm-hid-probe.ps1")" 2>&1 \
    | grep -v "Add-Content\|+ \|CategoryInfo\|FullyQualified\|At D:\|PermissionDenied" \
    > "$snap_dir/hid-probe.txt" || true
# also grab the persistent log if it exists
[[ -f /mnt/c/Users/Lesley/AppData/Local/mm-hid-probe.log ]] && \
    cp /mnt/c/Users/Lesley/AppData/Local/mm-hid-probe.log "$snap_dir/hid-probe-persistent.log"

# 4. Driver packages (oem*.inf)
echo "[snapshot] Driver packages..."
powershell.exe -ExecutionPolicy Bypass -Command "pnputil /enum-drivers" 2>&1 | head -200 > "$snap_dir/driver-packages.txt" || true

# 5. Apple INF source content (the driver currently providing scroll)
[[ -f /mnt/c/Windows/INF/oem0.inf ]] && cp /mnt/c/Windows/INF/oem0.inf "$snap_dir/oem0-applewirelessmouse.inf" 2>/dev/null || true

# 6. Tray app debug.log tail
[[ -f /mnt/c/Users/Lesley/AppData/Roaming/MagicMouseTray/debug.log ]] && \
    tail -100 /mnt/c/Users/Lesley/AppData/Roaming/MagicMouseTray/debug.log > "$snap_dir/tray-debug-tail.log"

# 7. Kernel DebugView log tail (MagicMouse lines)
[[ -f /mnt/c/mm3-debug.log ]] && \
    grep "MagicMouse" /mnt/c/mm3-debug.log | tail -200 > "$snap_dir/kernel-debug-tail.log" 2>/dev/null || true

# 8. Scheduled task definition
schtasks.exe /query /tn MM-Dev-Cycle /xml 2>&1 > "$snap_dir/mm-dev-cycle-task.xml" || true

# 9. Current git HEAD + working-tree status
git -C "$REPO_ROOT" rev-parse HEAD > "$snap_dir/git-head.txt"
git -C "$REPO_ROOT" status --short > "$snap_dir/git-status.txt"

# 10. Restore instructions (human-readable)
cat > "$snap_dir/restore-instructions.md" <<RESTORE
# Restore from snapshot $snap_name

This snapshot was taken before a state-mutating operation. To restore:

1. Compare current state to this snapshot using ./scripts/mm-snapshot-state.sh
   to take a fresh snapshot, then \`diff\` the two snap_dirs.

2. To restore LowerFilters from this snapshot, read \`registry.txt\`, find the
   LowerFilters line, and run mm-state-flip.ps1 with the matching mode.

3. To uninstall a driver package added since this snapshot:
   pnputil /enum-drivers (compare to driver-packages.txt)
   pnputil /delete-driver <oemN.inf> /uninstall /force

4. If the BTHENUM device is in a confused state, the safest reset is a full
   unpair + repair via Bluetooth Settings.

Captured at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
RESTORE

echo "[snapshot] Complete: $snap_dir"
echo "[snapshot] Files:"
ls -la "$snap_dir" | tail -n +2
