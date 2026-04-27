# mm-hid-probe.ps1 - Dump HID capabilities of every Apple Magic Mouse interface.
#
# Goal: figure out which interface (and via which API: Input vs Feature vs streaming)
# exposes the battery report 0x90 when Apple's applewirelessmouse.inf is in
# unified-interface mode (after re-pair on PID 0x0323).
#
# Output: C:\mm-hid-probe.log with full HIDP_CAPS, value caps, and a per-report-ID
# breakdown. Tries HidD_GetInputReport AND HidD_GetFeature for report IDs 0x01..0xFF
# to find where battery actually lives.

$ErrorActionPreference = 'Continue'
$ProbeLog = Join-Path $env:LOCALAPPDATA 'mm-hid-probe.log'

function Log {
    param([string]$M)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $M"
    Add-Content -Path $ProbeLog -Value $line -Encoding UTF8
    Write-Host $line
}

# --- P/Invoke shims (compiled once per session) ---
$cs = @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class Hid {
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern SafeFileHandle CreateFile(string lpFileName, uint dwDesiredAccess,
        uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("hid.dll", SetLastError = true)]
    public static extern bool HidD_GetInputReport(SafeFileHandle h, byte[] buf, int len);
    [DllImport("hid.dll", SetLastError = true)]
    public static extern bool HidD_GetFeature(SafeFileHandle h, byte[] buf, int len);
    [DllImport("hid.dll")]
    public static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr data);
    [DllImport("hid.dll")]
    public static extern bool HidD_FreePreparsedData(IntPtr data);
    [DllImport("hid.dll")]
    public static extern int HidP_GetCaps(IntPtr data, ref HIDP_CAPS caps);
    [DllImport("hid.dll")]
    public static extern int HidP_GetValueCaps(int reportType, [Out] HIDP_VALUE_CAPS[] caps,
        ref ushort capsLength, IntPtr preparsedData);
    [DllImport("hid.dll")]
    public static extern int HidP_GetButtonCaps(int reportType, [Out] HIDP_BUTTON_CAPS[] caps,
        ref ushort capsLength, IntPtr preparsedData);

    [StructLayout(LayoutKind.Sequential)]
    public struct HIDP_CAPS {
        public ushort Usage, UsagePage, InputReportByteLength, OutputReportByteLength,
            FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)]
        public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes, NumberInputButtonCaps, NumberInputValueCaps,
            NumberInputDataIndices, NumberOutputButtonCaps, NumberOutputValueCaps,
            NumberOutputDataIndices, NumberFeatureButtonCaps, NumberFeatureValueCaps,
            NumberFeatureDataIndices;
    }

    [StructLayout(LayoutKind.Sequential, Pack=4)]
    public struct HIDP_VALUE_CAPS {
        public ushort UsagePage;
        public byte ReportID;
        [MarshalAs(UnmanagedType.U1)] public bool IsAlias;
        public ushort BitField, LinkCollection, LinkUsage, LinkUsagePage;
        [MarshalAs(UnmanagedType.U1)] public bool IsRange, IsStringRange, IsDesignatorRange, IsAbsolute;
        [MarshalAs(UnmanagedType.U1)] public bool HasNull;
        public byte Reserved;
        public ushort BitSize, ReportCount;
        public ushort R1, R2, R3, R4, R5;
        public uint UnitsExp, Units;
        public int LogicalMin, LogicalMax, PhysicalMin, PhysicalMax;
        // Range/NotRange union - use first 4 ushorts as Usage/UsageMin
        public ushort UsageOrUsageMin, UsageMax, StringIdxOrMin, StringIdxMax;
        public ushort DesigIdxOrMin, DesigIdxMax, DataIdxOrMin, DataIdxMax;
    }

    [StructLayout(LayoutKind.Sequential, Pack=4)]
    public struct HIDP_BUTTON_CAPS {
        public ushort UsagePage;
        public byte ReportID;
        [MarshalAs(UnmanagedType.U1)] public bool IsAlias;
        public ushort BitField, LinkCollection, LinkUsage, LinkUsagePage;
        [MarshalAs(UnmanagedType.U1)] public bool IsRange, IsStringRange, IsDesignatorRange, IsAbsolute;
        public ushort R1, R2, R3, R4, R5, R6, R7, R8, R9, R10;
        public ushort UsageOrUsageMin, UsageMax, StringIdxOrMin, StringIdxMax;
        public ushort DesigIdxOrMin, DesigIdxMax, DataIdxOrMin, DataIdxMax;
    }
}

public static class Setup {
    [DllImport("setupapi.dll", SetLastError = true)]
    public static extern IntPtr SetupDiGetClassDevs(ref Guid g, string e, IntPtr p, uint f);
    [DllImport("setupapi.dll", SetLastError = true)]
    public static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g,
        uint i, ref SP_DEVICE_INTERFACE_DATA r);
    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s,
        ref SP_DEVICE_INTERFACE_DATA d, ref SP_DEVICE_INTERFACE_DETAIL_DATA b,
        uint sz, out uint req, IntPtr di);
    [DllImport("setupapi.dll")] public static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);

    [StructLayout(LayoutKind.Sequential)]
    public struct SP_DEVICE_INTERFACE_DATA {
        public uint cbSize; public Guid InterfaceClassGuid; public uint Flags; public IntPtr R;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct SP_DEVICE_INTERFACE_DETAIL_DATA {
        public uint cbSize;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=512)]
        public string DevicePath;
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'Hid').Type) {
    Add-Type -TypeDefinition $cs -Language CSharp
}

# Clear log
if (Test-Path $ProbeLog) { Remove-Item $ProbeLog -Force }
Log "===== Magic Mouse HID interface probe ====="

$hidGuid = [Guid]'4d1e55b2-f16f-11cf-88cb-001111000030'
$devs = [Setup]::SetupDiGetClassDevs([ref]$hidGuid, $null, [IntPtr]::Zero, 0x12)  # PRESENT|DEVICEINTERFACE
$index = 0
$paths = @()

while ($true) {
    $iface = New-Object Setup+SP_DEVICE_INTERFACE_DATA
    $iface.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($iface)
    if (-not [Setup]::SetupDiEnumDeviceInterfaces($devs, [IntPtr]::Zero, [ref]$hidGuid, $index, [ref]$iface)) {
        break
    }
    $detail = New-Object Setup+SP_DEVICE_INTERFACE_DETAIL_DATA
    $detail.cbSize = if ([IntPtr]::Size -eq 8) { 8 } else { 6 }
    [Setup]::SetupDiGetDeviceInterfaceDetail($devs, [ref]$iface, [ref]$detail, 512, [ref]$null, [IntPtr]::Zero) | Out-Null
    if ($detail.DevicePath -and ($detail.DevicePath -match 'vid_05ac.*pid_0323|vid&0001004c.*pid&0323')) {
        $paths += $detail.DevicePath
    }
    $index++
}
[Setup]::SetupDiDestroyDeviceInfoList($devs) | Out-Null

Log "Found $($paths.Count) Magic Mouse HID interface(s)"
foreach ($p in $paths) { Log "  $p" }

foreach ($path in $paths) {
    Log ""
    Log "===== INTERFACE: $path ====="

    $h = [Hid]::CreateFile($path, 0, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)  # zero-access
    if ($h.IsInvalid) {
        Log "  CreateFile failed: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        continue
    }

    try {
        $pd = [IntPtr]::Zero
        if (-not [Hid]::HidD_GetPreparsedData($h, [ref]$pd)) {
            Log "  HidD_GetPreparsedData failed"
            continue
        }
        try {
            $caps = New-Object Hid+HIDP_CAPS
            $caps.Reserved = [uint16[]]::new(17)
            [Hid]::HidP_GetCaps($pd, [ref]$caps) | Out-Null
            $up   = '{0:X4}' -f $caps.UsagePage
            $usg  = '{0:X4}' -f $caps.Usage
            Log "  CAPS: UP=0x$up Usage=0x$usg InLen=$($caps.InputReportByteLength) OutLen=$($caps.OutputReportByteLength) FeatLen=$($caps.FeatureReportByteLength)"
            Log "        InputValueCaps=$($caps.NumberInputValueCaps) FeatureValueCaps=$($caps.NumberFeatureValueCaps) ButtonCaps=$($caps.NumberInputButtonCaps)"

            # Dump value caps for each report type (0=Input, 2=Feature)
            foreach ($rt in @(0, 2)) {
                $rtName = if ($rt -eq 0) { 'Input' } else { 'Feature' }
                $count = if ($rt -eq 0) { [int]$caps.NumberInputValueCaps } else { [int]$caps.NumberFeatureValueCaps }
                if ($count -eq 0) { continue }
                $arr = [Hid+HIDP_VALUE_CAPS[]]::new($count)
                $len = [uint16]$count
                $r = [Hid]::HidP_GetValueCaps($rt, $arr, [ref]$len, $pd)
                Log "  ${rtName}ValueCaps (n=$len, hr=0x$('{0:X8}' -f $r)):"
                for ($i=0; $i -lt $len; $i++) {
                    $v = $arr[$i]
                    $rid = '{0:X2}' -f $v.ReportID
                    $vup = '{0:X4}' -f $v.UsagePage
                    $vu  = '{0:X4}' -f $v.UsageOrUsageMin
                    Log "    [$i] ReportID=0x$rid UP=0x$vup Usage=0x$vu BitSize=$($v.BitSize) Count=$($v.ReportCount) Min=$($v.LogicalMin) Max=$($v.LogicalMax)"
                }
            }

            # Try GetInputReport for every plausible report ID
            Log "  --- HidD_GetInputReport probing report IDs ---"
            $bufLen = [Math]::Max([int]$caps.InputReportByteLength, 64)
            foreach ($rid in @(0x01, 0x02, 0x03, 0x06, 0x10, 0x11, 0x12, 0x29, 0x52, 0x80, 0x81, 0x82, 0x83, 0x90, 0xA1, 0xF0, 0xFF)) {
                $buf = New-Object byte[] $bufLen
                $buf[0] = [byte]$rid
                $ok = [Hid]::HidD_GetInputReport($h, $buf, $buf.Length)
                $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                $ridHex = '{0:X2}' -f $rid
                if ($ok) {
                    $end = [Math]::Min(15, $buf.Length-1)
                    $hex = ($buf[0..$end] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
                    Log "    InRpt 0x${ridHex}: OK    bytes=[$hex...]"
                } else {
                    Log "    InRpt 0x${ridHex}: FAIL  err=$err"
                }
            }

            # Try GetFeature similarly
            Log "  --- HidD_GetFeature probing report IDs ---"
            $featLen = [Math]::Max([int]$caps.FeatureReportByteLength, 64)
            foreach ($rid in @(0x01, 0x02, 0x03, 0x06, 0x10, 0x11, 0x12, 0x29, 0x52, 0x80, 0x81, 0x82, 0x83, 0x90, 0xA1, 0xF0, 0xFF)) {
                $buf = New-Object byte[] $featLen
                $buf[0] = [byte]$rid
                $ok = [Hid]::HidD_GetFeature($h, $buf, $buf.Length)
                $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                $ridHex = '{0:X2}' -f $rid
                if ($ok) {
                    $end = [Math]::Min(15, $buf.Length-1)
                    $hex = ($buf[0..$end] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
                    Log "    Feat  0x${ridHex}: OK    bytes=[$hex...]"
                } else {
                    Log "    Feat  0x${ridHex}: FAIL  err=$err"
                }
            }
        } finally {
            [Hid]::HidD_FreePreparsedData($pd) | Out-Null
        }
    } finally {
        $h.Close()
    }
}

Log ""
Log "===== probe complete ====="
