<#
.SYNOPSIS
    M13 Phase 1 - clean up orphan registry/PnP residue from MagicUtilities and
    overnight driver experimentation. Read-and-verify after each step; halts on
    any verification failure.

.DESCRIPTION
    This script makes the following changes (all reversible from the pre-cleanup
    registry backup):

      1. Removes HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseDriver service key.
         (No .sys binary exists; orphan from overnight experiments.)

      2. Removes orphan LowerFilters="MagicMouse" from
         HKLM\...\Enum\USB\VID_05AC&PID_0323&MI_01\<inst>\
         (MU residue; would Code-39 the device when plugged via USB-C.)

      3. Removes the MAGICMOUSERAWPDO orphan PnP node:
         {7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo\<inst>
         (MU left this behind after uninstall.)

      4. Removes orphan oem*.inf packages whose Original Name was magicmousedriver.inf
         (our overnight-experiment packages, all replaced by current main).

    After each step, verifies that:
      - applewirelessmouse is still LowerFilters on the BTHENUM HID device
      - COL01 is still enumerated as Status=OK
      - No new device errors

    If verification fails, the script aborts immediately. Pre-cleanup registry
    export is your rollback path.

.PARAMETER WhatIf
    Show what would be done without making any changes. Recommended first run.

.EXAMPLE
    .\mm-phase1-cleanup.ps1 -WhatIf
    .\mm-phase1-cleanup.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# --- self-elevate check ---
function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
    Write-Host "[phase1] ERROR: must run from admin PowerShell" -ForegroundColor Red
    exit 1
}

# --- colored output helpers ---
function Step  { param($n, $t) Write-Host "`n=== Step $n - $t ===" -ForegroundColor Cyan }
function OK    { param($t)    Write-Host "  OK  $t" -ForegroundColor Green }
function Warn  { param($t)    Write-Host "  WARN $t" -ForegroundColor Yellow }
function Fail  { param($t)    Write-Host "  FAIL $t" -ForegroundColor Red }
function Info  { param($t)    Write-Host "  ... $t" -ForegroundColor Gray }

# --- verification function called between every cleanup step ---
function Verify-WorkingState {
    Info "Verifying scroll-path is intact..."
    # 1. applewirelessmouse must still be in LowerFilters
    $bthenum = Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue | `
        Where-Object { $_.InstanceId -match '^BTHENUM\\\{00001124[^\\]*VID&0001004C_PID&0323' } | `
        Select-Object -First 1
    if (-not $bthenum) {
        Fail "BTHENUM Magic Mouse 0323 HID device not found - device disconnected or worse"
        return $false
    }
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($bthenum.InstanceId)"
    try {
        $lf = (Get-ItemProperty $regPath -Name LowerFilters -ErrorAction Stop).LowerFilters
    } catch {
        Fail "Cannot read LowerFilters at $regPath"
        return $false
    }
    if ($lf -notcontains 'applewirelessmouse') {
        Fail "applewirelessmouse no longer in LowerFilters: $($lf -join ',')"
        return $false
    }
    OK "applewirelessmouse in LowerFilters"

    # 2. COL01 must be present and Started
    $col01 = Get-PnpDevice -ErrorAction SilentlyContinue | `
        Where-Object { $_.InstanceId -like '*VID&0001004C_PID&0323&Col01*' -and $_.Status -eq 'OK' }
    if (-not $col01) {
        Fail "COL01 not enumerated or not Started"
        return $false
    }
    OK "COL01 enumerated, Status=OK"

    # 3. Device must not have an error code
    if ($bthenum.Status -ne 'OK') {
        Fail "BTHENUM device Status=$($bthenum.Status) (expected OK)"
        return $false
    }
    OK "BTHENUM device Status=OK"

    return $true
}

# === Pre-flight check ===
Step "Pre" "Pre-flight: confirm initial scroll path works"
if (-not (Verify-WorkingState)) {
    Fail "Initial state already broken. Restore from registry backup before running this script."
    exit 1
}

# === Step 1: Remove dead MagicMouseDriver service key ===
Step "1" "Remove dead MagicMouseDriver service key"
$key1 = 'HKLM:\SYSTEM\CurrentControlSet\Services\MagicMouseDriver'
if (Test-Path $key1) {
    if ($PSCmdlet.ShouldProcess($key1, "Remove-Item")) {
        Remove-Item $key1 -Recurse -Force
        OK "Removed $key1"
    }
} else {
    Info "Service key already gone; nothing to do"
}
if (-not $WhatIfPreference) {
    if (-not (Verify-WorkingState)) {
        Fail "Verification failed after step 1. RESTORE FROM PRE-CLEANUP BACKUP."
        exit 2
    }
}

# === Step 2: Remove stale USB MI_01 LowerFilters=MagicMouse ===
Step "2" "Remove stale USB MI_01 LowerFilters=MagicMouse"
$usbDevs = Get-PnpDevice -ErrorAction SilentlyContinue | `
    Where-Object { $_.InstanceId -like 'USB\VID_05AC&PID_0323&MI_01*' }
foreach ($d in $usbDevs) {
    $usbReg = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($d.InstanceId)"
    try {
        $lf = (Get-ItemProperty $usbReg -Name LowerFilters -ErrorAction Stop).LowerFilters
        if ($lf -contains 'MagicMouse') {
            $newLf = @($lf | Where-Object { $_ -ne 'MagicMouse' })
            if ($PSCmdlet.ShouldProcess($usbReg, "Remove MagicMouse from LowerFilters")) {
                if ($newLf.Count -eq 0) {
                    Remove-ItemProperty -Path $usbReg -Name LowerFilters
                } else {
                    Set-ItemProperty -Path $usbReg -Name LowerFilters -Value $newLf -Type MultiString
                }
                OK "Removed MagicMouse from $usbReg LowerFilters"
            }
        }
    } catch {
        Info "USB instance has no LowerFilters: $($d.InstanceId)"
    }
}
if (-not $WhatIfPreference) {
    if (-not (Verify-WorkingState)) {
        Fail "Verification failed after step 2."
        exit 3
    }
}

# === Step 3: Remove MAGICMOUSERAWPDO orphan PnP node ===
Step "3" "Remove MAGICMOUSERAWPDO orphan PnP node"
$rawPdo = Get-PnpDevice -ErrorAction SilentlyContinue | `
    Where-Object { $_.InstanceId -like '{7D55502A-2C87-441F-9993-0761990E0C7A}\\MagicMouseRawPdo*' }
if ($rawPdo) {
    foreach ($d in $rawPdo) {
        if ($PSCmdlet.ShouldProcess($d.InstanceId, "pnputil /remove-device")) {
            $out = pnputil /remove-device "$($d.InstanceId)" 2>&1
            OK "pnputil /remove-device returned: $out"
        }
    }
} else {
    Info "MAGICMOUSERAWPDO node already gone"
}
if (-not $WhatIfPreference) {
    if (-not (Verify-WorkingState)) {
        Fail "Verification failed after step 3."
        exit 4
    }
}

# === Step 4: Enumerate orphan oem*.inf packages from overnight experiments ===
Step "4" "Enumerate orphan oem*.inf packages (manual delete recommended)"
$pkgs = pnputil /enum-drivers
$orphans = @()
$current = $null
foreach ($line in ($pkgs -split "`n")) {
    if ($line -match 'Published Name:\s+(oem\d+\.inf)') {
        $current = $matches[1]
    }
    if ($line -match 'Original Name:\s+magicmousedriver\.inf' -and $current) {
        $orphans += $current
    }
}
if ($orphans.Count -gt 0) {
    Warn "Orphan oem*.inf packages from MagicMouseDriver:"
    $orphans | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    Info "Review then run manually: pnputil /delete-driver oemNN.inf /uninstall /force"
    Info "(Not auto-deleting in case any are still bound; use the audit report to decide.)"
} else {
    Info "No orphan MagicMouseDriver oem*.inf packages found"
}

# === Final verification ===
Step "Final" "Final verification + ready for Phase 1 close-out"
if (-not (Verify-WorkingState)) {
    Fail "Final verification failed. Investigate before continuing."
    exit 5
}
OK "Cleanup complete. Phase 1 close-out:"
Write-Host ""
Write-Host "  1. From WSL: ./scripts/mm-reg-export.sh post-cleanup" -ForegroundColor Cyan
Write-Host "  2. From WSL: ./scripts/mm-snapshot-state.sh" -ForegroundColor Cyan
Write-Host "  3. Confirm physical scroll still works (move pointer, 2-finger scroll)" -ForegroundColor Cyan
Write-Host "  4. Notify Claude Code: ready for Phase 2" -ForegroundColor Cyan
Write-Host ""
exit 0
