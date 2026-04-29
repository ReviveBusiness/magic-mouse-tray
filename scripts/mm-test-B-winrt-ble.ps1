<#
.SYNOPSIS
    Test B: try to query v3 Magic Mouse via WinRT BLE API. If the device has
    an LE side, GATT services should be enumerable; battery would be at
    Service 0x180F / Characteristic 0x2A19.
#>
[CmdletBinding()]
param(
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF',
    [uint64]$BluetoothAddress = 0xD0C050CC8C4D
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }

$log = Join-Path $OutDir 'test-B-winrt-ble.txt'
function W { param([string]$m); Write-Host $m; Add-Content -Path $log -Value $m -Encoding UTF8 }

W "=== Test B: WinRT BluetoothLEDevice query ==="
W "Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Target BT address: 0x$('{0:X12}' -f $BluetoothAddress)"
W ""

# Load WinRT types
[Windows.Devices.Bluetooth.BluetoothLEDevice, Windows.Devices.Bluetooth, ContentType=WindowsRuntime] | Out-Null
[Windows.Foundation.IAsyncOperation`1, Windows.Foundation, ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Bluetooth.GenericAttributeProfile.GattDeviceServicesResult, Windows.Devices.Bluetooth, ContentType=WindowsRuntime] | Out-Null

# WinRT async helper for PS5
Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })

function Await { param($op, $type)
    $task = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
    $task.Wait(15000) | Out-Null
    return $task.Result
}

# 1. Try FromBluetoothAddressAsync
W "## Step 1: BluetoothLEDevice.FromBluetoothAddressAsync(0x$('{0:X12}' -f $BluetoothAddress))"
try {
    $op = [Windows.Devices.Bluetooth.BluetoothLEDevice]::FromBluetoothAddressAsync($BluetoothAddress)
    $device = Await $op ([Windows.Devices.Bluetooth.BluetoothLEDevice])
    if ($null -eq $device) {
        W "  RESULT: null — v3 mouse does NOT have a BLE side accessible via this API"
    } else {
        W "  RESULT: device returned"
        W "    Name: $($device.Name)"
        W "    DeviceId: $($device.DeviceId)"
        W "    BluetoothAddressType: $($device.BluetoothAddressType)"
        W "    ConnectionStatus: $($device.ConnectionStatus)"
        W ""
        W "## Step 2: enumerate GATT services"
        $svcOp = $device.GetGattServicesAsync()
        $svcRes = Await $svcOp ([Windows.Devices.Bluetooth.GenericAttributeProfile.GattDeviceServicesResult])
        if ($null -eq $svcRes) {
            W "  GATT enumeration returned null"
        } else {
            W "  GATT Status: $($svcRes.Status)"
            W "  Services: $($svcRes.Services.Count)"
            foreach ($svc in $svcRes.Services) {
                W "    - UUID: $($svc.Uuid)"
                if ($svc.Uuid -eq [Guid]'0000180f-0000-1000-8000-00805f9b34fb') {
                    W "      ★ BATTERY SERVICE! ★"
                    $charOp = $svc.GetCharacteristicsAsync()
                    $charRes = Await $charOp ([Windows.Devices.Bluetooth.GenericAttributeProfile.GattCharacteristicsResult])
                    foreach ($ch in $charRes.Characteristics) {
                        W "        characteristic: $($ch.Uuid) properties=$($ch.CharacteristicProperties)"
                        if ($ch.Uuid -eq [Guid]'00002a19-0000-1000-8000-00805f9b34fb') {
                            W "          ★ Battery Level characteristic! Reading…"
                            $rdOp = $ch.ReadValueAsync()
                            $rdRes = Await $rdOp ([Windows.Devices.Bluetooth.GenericAttributeProfile.GattReadResult])
                            if ($rdRes.Status -eq 'Success') {
                                $reader = [Windows.Storage.Streams.DataReader]::FromBuffer($rdRes.Value)
                                $byteCount = $rdRes.Value.Length
                                $bytes = New-Object byte[] $byteCount
                                $reader.ReadBytes($bytes)
                                $hex = ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
                                W "          ★★★ BATTERY READ: bytes=$hex (percent=$($bytes[0])) ★★★"
                            } else {
                                W "          read failed: $($rdRes.Status)"
                            }
                        }
                    }
                }
            }
        }
    }
} catch {
    W "  EXCEPTION: $($_.Exception.Message)"
    W "  $($_.ScriptStackTrace)"
}

W ""
W "## Step 3: try BluetoothDevice (Classic) for completeness"
try {
    [Windows.Devices.Bluetooth.BluetoothDevice, Windows.Devices.Bluetooth, ContentType=WindowsRuntime] | Out-Null
    $btOp = [Windows.Devices.Bluetooth.BluetoothDevice]::FromBluetoothAddressAsync($BluetoothAddress)
    $btDevice = Await $btOp ([Windows.Devices.Bluetooth.BluetoothDevice])
    if ($null -eq $btDevice) {
        W "  Classic BluetoothDevice query: null"
    } else {
        W "  Classic BluetoothDevice query: device returned"
        W "    Name: $($btDevice.Name)"
        W "    ConnectionStatus: $($btDevice.ConnectionStatus)"
        W "    DeviceId: $($btDevice.DeviceId)"
        W "    SdpRecordsCount: $($btDevice.SdpRecords.Count)"
    }
} catch { W "  Classic query EXCEPTION: $($_.Exception.Message)" }

W ""
W "=== Test B done @ $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
exit 0
