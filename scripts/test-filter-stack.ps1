#Requires -RunAsAdministrator
# test-filter-stack.ps1
# Tests whether applewirelessmouse loads into the BTHENUM device stack
# and whether COL02 (battery) survives with the filter active.
# If COL02 is stripped, runs &6& recovery automatically.
#
# Usage:
#   .\test-filter-stack.ps1           # live run
#   .\test-filter-stack.ps1 -DryRun   # read-only preview, no changes

param(
    [switch]$DryRun
)

if ($DryRun) {
    Write-Host "*** DRY RUN — no changes will be made ***" -ForegroundColor Magenta
    Write-Host ""
}

$bthenumId  = 'BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0323\9&73B8B28&0&D0C050CC8C4D_C00000000'
$bthenumKey = "HKLM:\SYSTEM\CurrentControlSet\Enum\$bthenumId"

function Get-MouseDevices {
    Get-PnpDevice | Where-Object { $_.InstanceId -match '0323' -and $_.Status -eq 'OK' } |
        Select-Object Status, InstanceId
}

function Has-COL02 {
    $null -ne (Get-PnpDevice | Where-Object {
        $_.InstanceId -match '0323' -and
        $_.InstanceId -match 'COL02' -and
        $_.Status -eq 'OK'
    })
}

# ─────────────────────────────────────────────────────────────
# PHASE 0 — Baseline
# ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== PHASE 0: BASELINE ===" -ForegroundColor Cyan
Write-Host "Devices before test:"
Get-MouseDevices | Format-Table -AutoSize
$col02Before = Has-COL02
Write-Host "COL02 present: $col02Before"
Write-Host ""

if (-not $col02Before) {
    Write-Host "WARNING: COL02 already missing before test. Aborting." -ForegroundColor Yellow
    exit 1
}

# ─────────────────────────────────────────────────────────────
# PHASE 1 — Cycle BTHENUM with filter in LowerFilters
# Forces fresh device stack construction — PnP reads Enum key
# LowerFilters and loads applewirelessmouse during AddDevice.
# ─────────────────────────────────────────────────────────────
Write-Host "=== PHASE 1: CYCLE BTHENUM (filter active) ===" -ForegroundColor Cyan
Write-Host "Disabling BTHENUM device..."
if ($DryRun) { Write-Host "  [DRY RUN] pnputil /disable-device $bthenumId" -ForegroundColor Magenta }
else { pnputil /disable-device "$bthenumId"; Start-Sleep -Seconds 2 }
Write-Host "Enabling BTHENUM device..."
if ($DryRun) { Write-Host "  [DRY RUN] pnputil /enable-device $bthenumId" -ForegroundColor Magenta }
else { pnputil /enable-device "$bthenumId"; Start-Sleep -Seconds 10 }

# ─────────────────────────────────────────────────────────────
# PHASE 2 — Check results
# ─────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== PHASE 2: RESULTS ===" -ForegroundColor Cyan

Write-Host "Device stack after cycle:"
(Get-PnpDeviceProperty -InstanceId $bthenumId -KeyName DEVPKEY_Device_Stack).Data

Write-Host ""
Write-Host "Devices after cycle:"
Get-MouseDevices | Format-Table -AutoSize

$col02After = Has-COL02
if ($DryRun) {
    Write-Host "  [DRY RUN] Would check DEVPKEY_Device_Stack for \Driver\applewirelessmouse" -ForegroundColor Magenta
    Write-Host "  [DRY RUN] Would check COL02 presence"  -ForegroundColor Magenta
    Write-Host ""
    Write-Host "Current (unchanged) device stack:"
    (Get-PnpDeviceProperty -InstanceId $bthenumId -KeyName DEVPKEY_Device_Stack).Data
    Write-Host "Current devices:"
    Get-MouseDevices | Format-Table -AutoSize
    Write-Host "Dry run complete. No changes made." -ForegroundColor Magenta
    exit 0
}
$filterInStack = (Get-PnpDeviceProperty -InstanceId $bthenumId -KeyName DEVPKEY_Device_Stack).Data -contains '\Driver\applewirelessmouse'

Write-Host "Filter in stack: $filterInStack"
Write-Host "COL02 present:   $col02After"
Write-Host ""

# ─────────────────────────────────────────────────────────────
# PHASE 3 — Outcome
# ─────────────────────────────────────────────────────────────
Write-Host "=== PHASE 3: OUTCOME ===" -ForegroundColor Cyan

if ($filterInStack -and $col02After) {
    Write-Host "SUCCESS: Filter in stack AND COL02 present." -ForegroundColor Green
    Write-Host "Scroll and battery should both work."
    Write-Host "Reboot to confirm both survive across a reboot."
    exit 0
}

if ($filterInStack -and -not $col02After) {
    Write-Host "PARTIAL: Filter loaded (scroll works) but COL02 was stripped (battery broken)." -ForegroundColor Yellow
    Write-Host "Driver still modifies descriptor. Running &6& recovery to restore COL02..."
    Write-Host ""
}

if (-not $filterInStack) {
    Write-Host "FAIL: Filter did not load into device stack." -ForegroundColor Red
    Write-Host "sc query result:"
    sc query applewirelessmouse
    exit 1
}

# ─────────────────────────────────────────────────────────────
# PHASE 4 — &6& Recovery (only runs if COL02 was stripped)
# ─────────────────────────────────────────────────────────────
Write-Host "=== PHASE 4: &6& RECOVERY ===" -ForegroundColor Cyan

Write-Host "Step 4.1 — Removing LowerFilters from Enum key (registry only)..."
if ($DryRun) { Write-Host "  [DRY RUN] Remove-ItemProperty $bthenumKey LowerFilters" -ForegroundColor Magenta }
else { Remove-ItemProperty -Path $bthenumKey -Name LowerFilters -ErrorAction SilentlyContinue }

Write-Host "Step 4.2 — Cycling BTHENUM without filter (creates COL01+COL02)..."
if ($DryRun) {
    Write-Host "  [DRY RUN] pnputil /disable-device $bthenumId" -ForegroundColor Magenta
    Write-Host "  [DRY RUN] pnputil /enable-device $bthenumId" -ForegroundColor Magenta
} else {
    pnputil /disable-device "$bthenumId"
    Start-Sleep -Seconds 2
    pnputil /enable-device "$bthenumId"
}

Write-Host "Step 4.3 — Waiting for COL02 to appear (up to 30s)..."
$waited = 0
while (-not (Has-COL02) -and $waited -lt 30) {
    Start-Sleep -Seconds 3
    $waited += 3
}

if (Has-COL02) {
    Write-Host "COL02 restored." -ForegroundColor Green
} else {
    Write-Host "ERROR: COL02 did not appear after 30s. Manual intervention required." -ForegroundColor Red
    exit 1
}

Write-Host "Step 4.4 — Restoring LowerFilters to Enum key (no device restart)..."
if ($DryRun) { Write-Host "  [DRY RUN] Set-ItemProperty $bthenumKey LowerFilters = applewirelessmouse" -ForegroundColor Magenta }
else { Set-ItemProperty -Path $bthenumKey -Name LowerFilters -Value @('applewirelessmouse') -Type MultiString }

Write-Host "Step 4.5 — Restoring LowerFilters to driver instance key..."
$driverKey = (Get-ItemProperty $bthenumKey).Driver
if ($DryRun) { Write-Host "  [DRY RUN] Set-ItemProperty HKLM:\...\Control\Class\$driverKey LowerFilters = applewirelessmouse" -ForegroundColor Magenta }
else {
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey" `
        -Name LowerFilters -Value @('applewirelessmouse') -Type MultiString
}

Write-Host ""
Write-Host "=== RECOVERY COMPLETE ===" -ForegroundColor Cyan
Write-Host "Final device state:"
Get-MouseDevices | Format-Table -AutoSize
Write-Host ""
Write-Host "COL02 restored. Battery works. Scroll still broken (driver strips descriptor)." -ForegroundColor Yellow
Write-Host "Do NOT reboot or run pnputil again — just close this window."
Write-Host "Next step: KMDF function driver."
