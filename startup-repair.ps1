# startup-repair.ps1 - MagicMouseTray COL02 Battery Collection Repair
# SPDX-License-Identifier: MIT
#
# Runs at startup via Windows Scheduled Task (SYSTEM account, 30s delay).
# Detects whether COL02 (battery HID collection) is missing - this happens every
# reboot when applewirelessmouse is in LowerFilters, because the filter modifies
# the HID descriptor during fresh BTHENUM enumeration and strips the battery
# collection. If missing, cycles the BTHENUM parent to restore COL01+COL02.
#
# Usage (manual): powershell -ExecutionPolicy Bypass -File startup-repair.ps1
# Usage (scheduled task): registered by install-driver.ps1 - runs automatically.

param(
    [string]$LogFile = "C:\ProgramData\MagicMouseTray\startup-repair.log",
    [int]$SettleSeconds = 2    # wait after re-enable before checking result
)

# Maximum log size before rotation (bytes)
$MaxLogBytes = 512KB

function Write-Log {
    param([string]$Msg)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# PS5-compatible pnputil output helper - Out-String -NoNewline is PS6+ only
function Get-PnpOutput {
    param([string[]]$Lines)
    return ($Lines | Select-Object -Last 2 | Out-String).TrimEnd()
}

# ---- bootstrap ----
$logDir = Split-Path $LogFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Rotate log if over limit
if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt $MaxLogBytes) {
    $archive = [System.IO.Path]::ChangeExtension($LogFile, "1.log")
    Move-Item $LogFile $archive -Force
}

Write-Log "startup-repair: begin"

# Apple Magic Mouse PIDs covered by AppleWirelessMouse.inf
# (matches DriverHealthChecker.cs KnownPids list)
$knownPids = @("0323", "030d", "0269", "0310")

$anyRepaired = $false

foreach ($mmPid in $knownPids) {
    # Find BTHENUM parent device for this Magic Mouse pairing.
    # Must match HID service UUID {00001124} - not PnP Info {00001200} or other profiles.
    $btDevice = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match "BTHENUM" -and
                       $_.InstanceId -match "00001124" -and
                       $_.InstanceId -match "_PID&$mmPid" -and
                       $_.Status -eq 'OK' } |
        Select-Object -First 1

    if (-not $btDevice) {
        continue  # PID not paired - normal, skip silently
    }

    Write-Log "PID 0x$($mmPid.ToUpper()): BTHENUM = $($btDevice.InstanceId)"

    # COL02 exists when there are 2+ HID-class child devices with this PID and Status OK.
    # One collapsed device (filter stripped COL02) = Count 1. Healthy = Count 2+.
    $hidDevices = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.Class -eq 'HIDClass' -and
                       $_.InstanceId -match $mmPid -and
                       $_.Status -eq 'OK' }

    $hidCount = @($hidDevices).Count   # @() wraps $null -> 0 in PS5
    if ($hidCount -ge 2) {
        Write-Log "PID 0x$($mmPid.ToUpper()): COL02 present ($hidCount HID device(s)) - no repair needed"
        continue
    }

    Write-Log "PID 0x$($mmPid.ToUpper()): COL02 missing ($hidCount HID device(s)) - starting repair"

    $btRegPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\" + $btDevice.InstanceId

    if (-not (Test-Path $btRegPath)) {
        Write-Log "ERROR: registry path not found: $btRegPath"
        continue
    }

    # Read current LowerFilters (need to restore after cycling)
    $lowerFilters = (Get-ItemProperty -Path $btRegPath -Name LowerFilters -ErrorAction SilentlyContinue).LowerFilters
    if (-not ($lowerFilters -contains 'applewirelessmouse')) {
        Write-Log "PID 0x$($mmPid.ToUpper()): applewirelessmouse not in LowerFilters - no filter conflict, skipping"
        continue
    }

    Write-Log "LowerFilters = $($lowerFilters -join ', ')"

    # Repair: remove filter -> cycle BTHENUM -> restore filter
    # Cycling BTHENUM forces a fresh HID descriptor negotiation without the filter,
    # creating COL01 (scroll) and COL02 (battery) as separate child devices.
    # Re-adding the filter afterward adds scroll support to COL01 without collapsing COL02.
    try {
        Write-Log "Step 1: removing LowerFilters..."
        Remove-ItemProperty -Path $btRegPath -Name LowerFilters -ErrorAction Stop

        Write-Log "Step 2: disabling BTHENUM device..."
        $out = pnputil /disable-device "$($btDevice.InstanceId)" 2>&1
        Write-Log "  $(Get-PnpOutput $out)"

        Start-Sleep -Milliseconds 500

        Write-Log "Step 3: enabling BTHENUM device..."
        $out = pnputil /enable-device "$($btDevice.InstanceId)" 2>&1
        Write-Log "  $(Get-PnpOutput $out)"

        Start-Sleep -Seconds $SettleSeconds

        Write-Log "Step 4: restoring LowerFilters..."
        Set-ItemProperty -Path $btRegPath -Name LowerFilters -Value $lowerFilters -Type MultiString -ErrorAction Stop

        # Step 5: soft-restart the BTHENUM HID device so the filter loads into the running
        # driver stack immediately. pnputil /restart-device reloads the stack without
        # re-enumerating from scratch, so COL02 (already in the device tree) is preserved.
        Write-Log "Step 5: restarting BTHENUM device to load filter into running stack..."
        $out = pnputil /restart-device "$($btDevice.InstanceId)" 2>&1
        Write-Log "  $(Get-PnpOutput $out)"

        # Verify
        Start-Sleep -Seconds 1
        $hidAfter = Get-PnpDevice -ErrorAction SilentlyContinue |
            Where-Object { $_.Class -eq 'HIDClass' -and
                           $_.InstanceId -match $mmPid -and
                           $_.Status -eq 'OK' }
        $hidAfterCount = @($hidAfter).Count

        if ($hidAfterCount -ge 2) {
            Write-Log "REPAIRED: COL02 present ($hidAfterCount HID device(s)) - battery + scroll restored"
            $anyRepaired = $true
        } else {
            Write-Log "WARNING: repair attempted - COL02 still not visible ($hidAfterCount HID device(s))"
        }

    } catch {
        Write-Log "ERROR during repair: $($_.Exception.Message)"
        # Re-enable device in case we failed after Step 2 (disable) but before Step 3 (enable)
        $reEnableOut = pnputil /enable-device "$($btDevice.InstanceId)" 2>&1
        Write-Log "  recovery re-enable: $(Get-PnpOutput $reEnableOut)"
        # Restore LowerFilters
        try {
            Set-ItemProperty -Path $btRegPath -Name LowerFilters -Value $lowerFilters -Type MultiString
            Write-Log "LowerFilters restored after error"
        } catch {
            Write-Log "CRITICAL: could not restore LowerFilters: $($_.Exception.Message)"
        }
    }
}

Write-Log "startup-repair: complete (repaired=$anyRepaired)"
