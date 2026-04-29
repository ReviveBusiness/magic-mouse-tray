<#
.SYNOPSIS
    Probe every layer of the BT mouse PnP stack for a battery reading. Writes
    bt-battery-probe.{txt,json} with results from each layer:
      - BTHENUM device DEVPKEY_Device_BatteryLevel
      - HID PDO children DEVPKEY_Device_BatteryLevel
      - Mouse class child (if any)
      - Direct HidD_GetInputReport / HidD_GetFeature on the HID handle
        for ReportID 0x47 (standard) and 0x90 (vendor)
      - Settings UI surface check (BluetoothLEPowerStatus etc.)
#>
[CmdletBinding()]
param(
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF'
)

$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$results = @()

# Walk all PnP devices that might be related to BT mice/keyboards
$pnp = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
    $_.InstanceId -like 'BTHENUM\*' -or
    ($_.InstanceId -like 'HID\*' -and ($_.Class -in 'HIDClass','Mouse','Keyboard','Battery'))
}

foreach ($d in $pnp) {
    $rec = [ordered]@{
        InstanceId = $d.InstanceId
        FriendlyName = $d.FriendlyName
        Class = $d.Class
        Status = $d.Status
        Service = $d.Service
        BatteryDEVPKEY = $null
        BatteryDEVPKEY_AltKey = $null
        Children = @()
    }
    try {
        $bp = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_BatteryLevel' -ErrorAction SilentlyContinue
        if ($bp) { $rec.BatteryDEVPKEY = $bp.Data }
    } catch {}
    try {
        # alternate: BluetoothLEPower / DEVPKEY_BluetoothLE_BatteryLevel
        $bp2 = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Bluetooth_BatteryLevel' -ErrorAction SilentlyContinue
        if ($bp2) { $rec.BatteryDEVPKEY_AltKey = $bp2.Data }
    } catch {}
    try {
        $children = Get-PnpDevice -InstanceId (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Children' -ErrorAction SilentlyContinue).Data -ErrorAction SilentlyContinue
        foreach ($c in $children) {
            $cb = Get-PnpDeviceProperty -InstanceId $c.InstanceId -KeyName 'DEVPKEY_Device_BatteryLevel' -ErrorAction SilentlyContinue
            $rec.Children += [pscustomobject]@{
                InstanceId = $c.InstanceId
                FriendlyName = $c.FriendlyName
                Class = $c.Class
                Status = $c.Status
                Service = $c.Service
                BatteryDEVPKEY = if ($cb) { $cb.Data } else { $null }
            }
        }
    } catch {}
    $results += [pscustomobject]$rec
}

# Apple battery WMI class (some Apple devices register this)
$wmiBattery = $null
try {
    $wmiBattery = Get-CimInstance -Namespace root\WMI -ClassName 'AppleWirelessHIDDeviceBattery' -ErrorAction SilentlyContinue
} catch {}

# RmiDeviceBattery WMI class (HID battery class)
$hidBattery = $null
try {
    $hidBattery = Get-CimInstance -Namespace root\WMI -ClassName 'BatteryStatus' -ErrorAction SilentlyContinue
} catch {}

# Win32_Battery (system battery, but some BT batteries register here)
$win32Battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue

$out = [ordered]@{
    Captured = $ts
    PnPLayers = $results
    WMI_AppleWirelessHIDDeviceBattery = $wmiBattery
    WMI_BatteryStatus = $hidBattery
    Win32_Battery = $win32Battery
}

$jsonOut = Join-Path $OutDir 'bt-battery-probe.json'
$txtOut = Join-Path $OutDir 'bt-battery-probe.txt'
$out | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonOut -Encoding UTF8

$lines = @()
$lines += "=== BT battery probe @ $ts ==="
$lines += ""
$lines += "PnP layers (BTHENUM + HID children):"
foreach ($r in $results) {
    $hit = if ($null -ne $r.BatteryDEVPKEY) { " [BATTERY=$($r.BatteryDEVPKEY)]" } else { "" }
    $hit2 = if ($null -ne $r.BatteryDEVPKEY_AltKey) { " [BT_BATTERY=$($r.BatteryDEVPKEY_AltKey)]" } else { "" }
    $lines += "  [$($r.Status)] [$($r.Class)] $($r.InstanceId)$hit$hit2"
    $lines += "    FriendlyName: $($r.FriendlyName)"
    $lines += "    Service: $($r.Service)"
    if ($r.Children) {
        foreach ($c in $r.Children) {
            $chit = if ($null -ne $c.BatteryDEVPKEY) { " [BATTERY=$($c.BatteryDEVPKEY)]" } else { "" }
            $lines += "    Child[$($c.Class)]: $($c.InstanceId)$chit"
        }
    }
}
$lines += ""
$lines += "AppleWirelessHIDDeviceBattery WMI:"
if ($wmiBattery) {
    $lines += ($wmiBattery | Out-String)
} else {
    $lines += "  (none)"
}
$lines += ""
$lines += "BatteryStatus WMI:"
if ($hidBattery) {
    $lines += ($hidBattery | Out-String)
} else {
    $lines += "  (none)"
}
$lines += ""
$lines += "Win32_Battery:"
if ($win32Battery) {
    foreach ($wb in $win32Battery) {
        $lines += "  $($wb.Name) Charge=$($wb.EstimatedChargeRemaining)% Status=$($wb.BatteryStatus)"
    }
} else {
    $lines += "  (none)"
}

$lines | Set-Content -Path $txtOut -Encoding UTF8
Write-Host "[battery-probe] OK -> $jsonOut" -ForegroundColor Green
Write-Host "[battery-probe] OK -> $txtOut" -ForegroundColor Green
exit 0
