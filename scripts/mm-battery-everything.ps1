<#
.SYNOPSIS
    Empirical proof: try every channel that could return v3 battery data.
#>
[CmdletBinding()]
param(
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF'
)
$ErrorActionPreference = 'Continue'
$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$log = Join-Path $OutDir 'battery-everything-probe.txt'
"=== Battery probe @ $ts === exhaustive channel scan ===" | Set-Content -Path $log -Encoding UTF8
function W { param([string]$m); Write-Host $m; Add-Content -Path $log -Value $m -Encoding UTF8 }

W ""
W "## Channel 1 -- DEVPKEY enumeration on Apple BT devices"
$apple = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
    $_.InstanceId -match 'PID&0323|PID&030D|PID&0239|D0C050CC8C4D|04F13EEEDE10|E806884B0741'
}
$batKeys = @(
    'DEVPKEY_Device_BatteryLevel',
    'DEVPKEY_Device_BatteryEstimatedRunTime',
    'DEVPKEY_Bluetooth_BatteryLevel',
    'DEVPKEY_BluetoothLE_BatteryLevel'
)
foreach ($d in $apple) {
    foreach ($k in $batKeys) {
        try {
            $r = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName $k -ErrorAction SilentlyContinue
            if ($r -and $r.Data -ne $null) {
                W ("  [HIT] {0} :: {1} = {2}" -f $d.FriendlyName, $k, $r.Data)
            }
        } catch {}
    }
}
W "  (any [HIT] above means battery surfaced via PnP DEVPKEY)"

W ""
W "## Channel 2 -- WMI battery classes"
$wmiClasses = @('AppleWirelessHIDDeviceBattery', 'BatteryStatus', 'BatteryStaticData', 'BatteryFullChargedCapacity', 'BatteryRuntime')
foreach ($c in $wmiClasses) {
    try {
        $i = Get-CimInstance -Namespace 'root\WMI' -ClassName $c -ErrorAction SilentlyContinue
        if ($i) {
            $cnt = ($i | Measure-Object).Count
            W ("  [HIT] root\WMI\{0}: {1} instance(s)" -f $c, $cnt)
            ($i | Format-List | Out-String) | ForEach-Object { Add-Content -Path $log -Value $_ }
        } else {
            W ("  [empty] root\WMI\{0}" -f $c)
        }
    } catch { W ("  [err] {0}: {1}" -f $c, $_.Exception.Message) }
}

W ""
W "## Channel 3 -- AppleBluetoothMultitouch IOCTL device"
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class IOCTL {
    [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
    public static extern SafeFileHandle CreateFile(string fn, uint a, uint s, IntPtr sa, uint cd, uint fa, IntPtr t);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool DeviceIoControl(SafeFileHandle h, uint code, byte[] inb, uint inl, byte[] outb, uint outl, out uint ret, IntPtr ovr);
}
"@ -ErrorAction SilentlyContinue

$abmt = '\\.\AppleBluetoothMultitouch'
$h = [IOCTL]::CreateFile($abmt, 3221225472, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
if ($h.IsInvalid) {
    $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    W ("  CreateFile R/W FAILED: err=0x{0:X} ({0})" -f $e)
    $h = [IOCTL]::CreateFile($abmt, 0, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h.IsInvalid) {
        $e2 = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        W ("  CreateFile 0-access FAILED: err=0x{0:X} ({0})" -f $e2)
    } else {
        W "  CreateFile 0-access OK"
    }
}
if (-not $h.IsInvalid) {
    W "  Device opened. Probing IOCTL 0x800-0x830 (range METHOD_BUFFERED)"
    $base = 0x00220000
    $hits = 0
    for ($fn = 0x800; $fn -le 0x830; $fn++) {
        $code = [uint32]($base -bor ($fn -shl 2))
        $inb = New-Object byte[] 256
        $outb = New-Object byte[] 256
        $ret = [uint32]0
        $ok = [IOCTL]::DeviceIoControl($h, $code, $inb, [uint32]0, $outb, [uint32]256, [ref]$ret, [IntPtr]::Zero)
        if ($ok) {
            $hex = if ($ret -gt 0) { ($outb[0..([Math]::Min(15,[int]$ret-1))] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ' } else { '' }
            W ("  [HIT] IOCTL 0x{0:X8} ret={1} bytes: {2}" -f $code, $ret, $hex)
            $hits++
        }
    }
    if ($hits -eq 0) { W "  No IOCTL in range returned data" }
    $h.Close()
}

W ""
W "## Channel 4 -- direct HidD on v3 BTHENUM HID PDO with every ReportID"
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class HidProbe {
    [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
    public static extern SafeFileHandle CreateFile(string fn, uint a, uint s, IntPtr sa, uint cd, uint fa, IntPtr t);
    [DllImport("hid.dll", SetLastError=true)] public static extern bool HidD_GetFeature(SafeFileHandle h, byte[] b, int n);
    [DllImport("hid.dll", SetLastError=true)] public static extern bool HidD_GetInputReport(SafeFileHandle h, byte[] b, int n);
    [DllImport("hid.dll")] public static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr d);
    [DllImport("hid.dll")] public static extern bool HidD_FreePreparsedData(IntPtr d);
    [DllImport("hid.dll")] public static extern int HidP_GetCaps(IntPtr d, ref CAPS c);
    [StructLayout(LayoutKind.Sequential)] public struct CAPS {
        public ushort Usage; public ushort UsagePage; public ushort In; public ushort Out; public ushort Feat;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)] public ushort[] R;
        public ushort NLnk, NIBC, NIVC, NIDI, NOBC, NOVC, NODI, NFBC, NFVC, NFDI;
    }
}
"@ -ErrorAction SilentlyContinue

$pV3 = '\\?\hid#' + '{00001124-0000-1000-8000-00805f9b34fb}_vid' + '&0001004c_pid' + '&0323#a' + '&31e5d054' + '&c' + '&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}'
W ("  Path: {0}" -f $pV3)
$h2 = [HidProbe]::CreateFile($pV3, 0, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
if ($h2.IsInvalid) {
    $e3 = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    W ("  OPEN FAILED: 0x{0:X}" -f $e3)
} else {
    try {
        $pp = [IntPtr]::Zero
        if ([HidProbe]::HidD_GetPreparsedData($h2, [ref]$pp)) {
            $caps = New-Object HidProbe+CAPS
            [HidProbe]::HidP_GetCaps($pp, [ref]$caps) | Out-Null
            W ("  CAPS: TLC=UP:{0:X4}/U:{1:X4} InLen={2} FeatLen={3} OutLen={4}" -f $caps.UsagePage, $caps.Usage, $caps.In, $caps.Feat, $caps.Out)
            [HidProbe]::HidD_FreePreparsedData($pp) | Out-Null
        }
        $featHits = New-Object System.Collections.Generic.List[string]
        $inputHits = New-Object System.Collections.Generic.List[string]
        for ($rid = 1; $rid -le 0xFE; $rid++) {
            $buf = New-Object byte[] 64
            $buf[0] = [byte]$rid
            if ([HidProbe]::HidD_GetFeature($h2, $buf, $buf.Length)) {
                $hex = ($buf[0..15] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
                $featHits.Add(("RID 0x{0:X2}: {1}" -f $rid, $hex)) | Out-Null
            }
            $buf2 = New-Object byte[] 64
            $buf2[0] = [byte]$rid
            if ([HidProbe]::HidD_GetInputReport($h2, $buf2, $buf2.Length)) {
                $hex2 = ($buf2[0..15] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
                $inputHits.Add(("RID 0x{0:X2}: {1}" -f $rid, $hex2)) | Out-Null
            }
        }
        W ("  HidD_GetFeature successes: {0}" -f $featHits.Count)
        foreach ($x in $featHits) { W ("    " + $x) }
        W ("  HidD_GetInputReport successes: {0}" -f $inputHits.Count)
        foreach ($x in $inputHits) { W ("    " + $x) }
    } finally { $h2.Close() }
}

W ""
W "## Channel 5 -- orphaned COL02 PDO direct open"
$pCol02 = '\\?\hid#' + '{00001124-0000-1000-8000-00805f9b34fb}_vid' + '&0001004c_pid' + '&0323' + '&col02#a' + '&31e5d054' + '&c' + '&0001#{4d1e55b2-f16f-11cf-88cb-001111000030}'
W ("  Path: {0}" -f $pCol02)
$h3 = [HidProbe]::CreateFile($pCol02, 0, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
if ($h3.IsInvalid) {
    $e4 = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    W ("  OPEN FAILED: 0x{0:X} (PDO is orphan, expected to fail)" -f $e4)
} else {
    W "  COL02 OPEN OK"
    $buf = New-Object byte[] 32
    $buf[0] = 0x90
    if ([HidProbe]::HidD_GetInputReport($h3, $buf, $buf.Length)) {
        W ("  [HIT] HidD_GetInputReport(0x90) = {0}" -f (($buf[0..15] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))
    } else {
        W ("  HidD_GetInputReport(0x90) failed: 0x{0:X}" -f [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    $h3.Close()
}

W ""
W "## Channel 6 -- HID Battery class enumeration"
$batDevs = Get-PnpDevice -Class Battery -ErrorAction SilentlyContinue
W ("  Battery class devices: {0}" -f (($batDevs | Measure-Object).Count))
foreach ($d in $batDevs) { W ("    {0} :: {1} :: Status={2}" -f $d.FriendlyName, $d.InstanceId, $d.Status) }

W ""
W "=== DONE @ $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
exit 0
