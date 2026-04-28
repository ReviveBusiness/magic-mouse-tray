<#
.SYNOPSIS
    Comprehensive Device Manager equivalent dump for the four Apple devices we
    care about (v1 mouse, v3 mouse, keyboard) PLUS their HID children. Captures
    every DEVPKEY, driver file inventory, registry-side filter chain, and INF
    metadata. All passive (read-only).

    Output:
      - devmgr-dump-<short-name>.json   per device
      - devmgr-dump-summary.md          flat human-readable index
      - devmgr-drivers.txt              pnputil /enum-drivers
#>
[CmdletBinding()]
param(
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF'
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }

# Apple devices + their known children. Snapshot from earlier state.
$targets = @(
    @{ Short='v3-bthenum'; InstanceId='BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0323\9&73B8B28&0&D0C050CC8C4D_C00000000' }
    @{ Short='v3-hid-mouse'; InstanceId='HID\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0323\A&31E5D054&C&0000' }
    @{ Short='v1-bthenum'; InstanceId='BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&000205AC_PID&030D\9&73B8B28&0&04F13EEEDE10_C00000000' }
    @{ Short='v1-hid-mouse'; InstanceId='HID\{00001124-0000-1000-8000-00805F9B34FB}_VID&000205AC_PID&030D\A&137E1BF2&2&0000' }
    @{ Short='kbd-bthenum'; InstanceId='BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&000205AC_PID&0239\9&73B8B28&0&E806884B0741_C00000000' }
    @{ Short='kbd-col01'; InstanceId='HID\{00001124-0000-1000-8000-00805F9B34FB}_VID&000205AC_PID&0239&Col01\A&EAF9D13&2&0000' }
    @{ Short='kbd-col02'; InstanceId='HID\{00001124-0000-1000-8000-00805F9B34FB}_VID&000205AC_PID&0239&Col02\A&EAF9D13&2&0001' }
    @{ Short='kbd-col03'; InstanceId='HID\{00001124-0000-1000-8000-00805F9B34FB}_VID&000205AC_PID&0239&Col03\A&EAF9D13&2&0002' }
    @{ Short='kbd-mac-level'; InstanceId='BTHENUM\DEV_E806884B0741\9&73B8B28&0&BLUETOOTHDEVICE_E806884B0741' }
    @{ Short='v3-mac-level'; InstanceId='BTHENUM\DEV_D0C050CC8C4D\9&73B8B28&0&BLUETOOTHDEVICE_D0C050CC8C4D' }
    @{ Short='v1-mac-level'; InstanceId='BTHENUM\DEV_04F13EEEDE10\9&73B8B28&0&BLUETOOTHDEVICE_04F13EEEDE10' }
)

function Convert-Datum {
    param($value)
    if ($null -eq $value) { return $null }
    if ($value -is [byte[]]) {
        $hex = ($value | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
        return @{ kind = 'bytes'; len = $value.Length; hex = $hex }
    }
    if ($value -is [string[]]) { return @{ kind = 'strarr'; values = $value } }
    if ($value -is [DateTime]) { return @{ kind = 'datetime'; iso = $value.ToString('o') } }
    return $value
}

function Dump-Device {
    param([string]$InstanceId)
    $rec = [ordered]@{
        InstanceId = $InstanceId
        Found = $false
        Properties = @{}
        DriverPath = $null
        DriverFiles = @()
        DriverPackageRegPath = $null
        DriverPackageReg = @{}
        EnumKey_LowerFilters = @()
        EnumKey_UpperFilters = @()
        EnumKey_Service = $null
        EnumKey_HardwareID = @()
        EnumKey_CompatibleID = @()
        EnumKey_AllValues = @{}
        ChildrenInstanceIds = @()
        ParentInstanceId = $null
    }

    # 1) PnP DEVPKEY enumeration
    try {
        $props = Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction Stop
        $rec.Found = $true
        foreach ($p in $props) {
            $rec.Properties[$p.KeyName] = Convert-Datum $p.Data
        }
    } catch {
        $rec.PropertyError = $_.Exception.Message
        return $rec
    }

    # 2) Registry Enum key
    $enumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId"
    if (Test-Path $enumPath) {
        try {
            $k = Get-Item -LiteralPath $enumPath -ErrorAction Stop
            foreach ($v in $k.GetValueNames()) {
                $val = $k.GetValue($v)
                $rec.EnumKey_AllValues[$v] = Convert-Datum $val
            }
            $rec.EnumKey_HardwareID = @($k.GetValue('HardwareID', @()))
            $rec.EnumKey_CompatibleID = @($k.GetValue('CompatibleIDs', @()))
            $rec.EnumKey_Service = $k.GetValue('Service', '')
            $rec.DriverPath = $k.GetValue('Driver', '')

            # Device Parameters
            $dpPath = Join-Path $enumPath 'Device Parameters'
            if (Test-Path $dpPath) {
                $dpk = Get-Item -LiteralPath $dpPath
                $rec.EnumKey_LowerFilters = @($dpk.GetValue('LowerFilters', @()))
                $rec.EnumKey_UpperFilters = @($dpk.GetValue('UpperFilters', @()))
                $rec.DeviceParameters = @{}
                foreach ($v in $dpk.GetValueNames()) {
                    $rec.DeviceParameters[$v] = Convert-Datum $dpk.GetValue($v)
                }
            }
        } catch {
            $rec.EnumKeyError = $_.Exception.Message
        }
    } else {
        $rec.EnumKeyMissing = $true
    }

    # 3) Driver class node (Control\Class\<ClassGUID>\<Driver>)
    if ($rec.DriverPath) {
        $clsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$($rec.DriverPath)"
        if (Test-Path $clsPath) {
            try {
                $clsk = Get-Item -LiteralPath $clsPath
                $rec.DriverPackageRegPath = $clsPath
                foreach ($v in $clsk.GetValueNames()) {
                    $rec.DriverPackageReg[$v] = Convert-Datum $clsk.GetValue($v)
                }
            } catch {
                $rec.DriverPackageRegError = $_.Exception.Message
            }
        }
    }

    # 4) Children + parent via DEVPKEY (already in Properties)
    if ($rec.Properties.ContainsKey('DEVPKEY_Device_Children')) {
        $kids = $rec.Properties['DEVPKEY_Device_Children']
        if ($kids -is [hashtable] -and $kids.values) { $rec.ChildrenInstanceIds = $kids.values }
        elseif ($kids -is [string[]]) { $rec.ChildrenInstanceIds = $kids }
        elseif ($kids) { $rec.ChildrenInstanceIds = @($kids) }
    }
    if ($rec.Properties.ContainsKey('DEVPKEY_Device_Parent')) {
        $rec.ParentInstanceId = $rec.Properties['DEVPKEY_Device_Parent']
    }

    return [pscustomobject]$rec
}

# Collect
$summary = @()
foreach ($t in $targets) {
    Write-Host "[devmgr] dumping $($t.Short)..."
    $dump = Dump-Device -InstanceId $t.InstanceId
    if (-not $dump.Found) {
        Write-Host "  WARN: not found" -ForegroundColor Yellow
        $summary += [pscustomobject]@{ Short=$t.Short; InstanceId=$t.InstanceId; Found=$false }
        continue
    }
    $jsonOut = Join-Path $OutDir "devmgr-dump-$($t.Short).json"
    $dump | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonOut -Encoding UTF8
    Write-Host "  -> $jsonOut"

    # quick summary fields
    $svc = $dump.EnumKey_Service
    $lf = ($dump.EnumKey_LowerFilters -join ',')
    $uf = ($dump.EnumKey_UpperFilters -join ',')
    $infName = $dump.Properties['DEVPKEY_Device_DriverInfPath']
    $infSection = $dump.Properties['DEVPKEY_Device_DriverInfSection']
    $infProvider = $dump.Properties['DEVPKEY_Device_DriverProvider']
    $driverDate = $dump.Properties['DEVPKEY_Device_DriverDate']
    $driverVer = $dump.Properties['DEVPKEY_Device_DriverVersion']
    $status = $dump.Properties['DEVPKEY_Device_DevNodeStatus']
    $problem = $dump.Properties['DEVPKEY_Device_ProblemCode']
    $friendly = $dump.Properties['DEVPKEY_Device_FriendlyName']
    if (-not $friendly) { $friendly = $dump.Properties['DEVPKEY_NAME'] }
    if (-not $friendly) { $friendly = $dump.Properties['DEVPKEY_Device_DeviceDesc'] }
    $summary += [pscustomobject]@{
        Short = $t.Short
        InstanceId = $t.InstanceId
        Found = $true
        FriendlyName = $friendly
        Service = $svc
        LowerFilters = $lf
        UpperFilters = $uf
        InfName = $infName
        InfSection = $infSection
        InfProvider = $infProvider
        DriverDate = $driverDate
        DriverVer = $driverVer
        Status = $status
        Problem = $problem
        ChildCount = ($dump.ChildrenInstanceIds | Measure-Object).Count
    }
}

# pnputil enum-drivers (full list)
Write-Host ""
Write-Host "[devmgr] running pnputil /enum-drivers..."
$pnputilOut = Join-Path $OutDir 'devmgr-drivers.txt'
$null = & pnputil.exe /enum-drivers 2>&1 | Out-File -FilePath $pnputilOut -Encoding UTF8
Write-Host "  -> $pnputilOut"

# pnputil enum-devices for HID + Bluetooth classes, restricted to instance ids of interest
$pnputilDevsOut = Join-Path $OutDir 'devmgr-devices.txt'
$lines = @()
$lines += "=== pnputil /enum-devices /class HIDClass ==="
$lines += (& pnputil.exe /enum-devices /class HIDClass 2>&1)
$lines += ""
$lines += "=== pnputil /enum-devices /class Mouse ==="
$lines += (& pnputil.exe /enum-devices /class Mouse 2>&1)
$lines += ""
$lines += "=== pnputil /enum-devices /class Keyboard ==="
$lines += (& pnputil.exe /enum-devices /class Keyboard 2>&1)
$lines += ""
$lines += "=== pnputil /enum-devices /class Bluetooth ==="
$lines += (& pnputil.exe /enum-devices /class Bluetooth 2>&1)
$lines | Out-File -FilePath $pnputilDevsOut -Encoding UTF8
Write-Host "  -> $pnputilDevsOut"

# Summary index
$summaryFile = Join-Path $OutDir 'devmgr-dump-summary.md'
$md = @()
$md += "# Device Manager dump summary"
$md += ""
$md += "Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$md += ""
$md += "| Device | Service | LowerFilters | UpperFilters | INF | Section | Provider | DriverVer | Status | Problem |"
$md += "|---|---|---|---|---|---|---|---|---|---|"
foreach ($s in $summary) {
    if (-not $s.Found) { $md += "| $($s.Short) | (NOT FOUND) | | | | | | | | |"; continue }
    $md += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |" -f
        $s.Short, $s.Service, $s.LowerFilters, $s.UpperFilters,
        $s.InfName, $s.InfSection, $s.InfProvider, $s.DriverVer, $s.Status, $s.Problem)
}
$md | Out-File -FilePath $summaryFile -Encoding UTF8
Write-Host "  -> $summaryFile"

Write-Host ""
Write-Host "[devmgr] DONE" -ForegroundColor Green
exit 0
