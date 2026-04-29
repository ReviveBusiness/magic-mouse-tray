<#
.SYNOPSIS
    Raw HID Feature read across Apple HID devices (Magic Mouse v1, v3, Keyboard).
    Tries Feature 0x47 (standard battery), 0x90 (vendor v3), 0x55 (touchpad mode),
    0x52 (vendor), 0x12 (mouse).

    Output: hid-feature-read.{txt,json}
#>
[CmdletBinding()]
param(
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF'
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class HidNative {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern SafeFileHandle CreateFile(
        string lpFileName, uint dwDesiredAccess, uint dwShareMode,
        IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("hid.dll", SetLastError=true)]
    public static extern bool HidD_GetFeature(SafeFileHandle h, byte[] buf, int size);

    [DllImport("hid.dll", SetLastError=true)]
    public static extern bool HidD_GetAttributes(SafeFileHandle h, ref HIDD_ATTRIBUTES attr);

    [DllImport("hid.dll", SetLastError=true)]
    public static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr data);

    [DllImport("hid.dll", SetLastError=true)]
    public static extern int HidP_GetCaps(IntPtr data, ref HIDP_CAPS caps);

    [DllImport("hid.dll", SetLastError=true)]
    public static extern bool HidD_FreePreparsedData(IntPtr data);

    [StructLayout(LayoutKind.Sequential)]
    public struct HIDD_ATTRIBUTES {
        public int Size;
        public ushort VendorID;
        public ushort ProductID;
        public ushort VersionNumber;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct HIDP_CAPS {
        public ushort Usage;
        public ushort UsagePage;
        public ushort InputReportByteLength;
        public ushort OutputReportByteLength;
        public ushort FeatureReportByteLength;
        public ushort NumberLinkCollectionNodes;
        public ushort NumberInputButtonCaps;
        public ushort NumberInputValueCaps;
        public ushort NumberInputDataIndices;
        public ushort NumberOutputButtonCaps;
        public ushort NumberOutputValueCaps;
        public ushort NumberOutputDataIndices;
        public ushort NumberFeatureButtonCaps;
        public ushort NumberFeatureValueCaps;
        public ushort NumberFeatureDataIndices;
    }
}

public static class HidEnum {
    [DllImport("hid.dll")]
    public static extern void HidD_GetHidGuid(out Guid guid);

    [DllImport("setupapi.dll", CharSet=CharSet.Auto, SetLastError=true)]
    public static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr enumerator, IntPtr hwndParent, int flags);

    [DllImport("setupapi.dll", SetLastError=true)]
    public static extern bool SetupDiEnumDeviceInterfaces(IntPtr hDev, IntPtr di, ref Guid g, int idx, ref SP_DEVICE_INTERFACE_DATA data);

    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr hDev, ref SP_DEVICE_INTERFACE_DATA didata, IntPtr detail, int detailSize, out int reqSize, IntPtr devInfoData);

    [DllImport("setupapi.dll", SetLastError=true)]
    public static extern bool SetupDiDestroyDeviceInfoList(IntPtr hDev);

    [StructLayout(LayoutKind.Sequential)]
    public struct SP_DEVICE_INTERFACE_DATA {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }
}
"@ -ErrorAction SilentlyContinue

$hidGuid = [Guid]::Empty
[HidEnum]::HidD_GetHidGuid([ref]$hidGuid)

$DIGCF_PRESENT = 0x2
$DIGCF_DEVICEINTERFACE = 0x10
$hDevInfo = [HidEnum]::SetupDiGetClassDevs([ref]$hidGuid, [IntPtr]::Zero, [IntPtr]::Zero, ($DIGCF_PRESENT -bor $DIGCF_DEVICEINTERFACE))
if ($hDevInfo -eq [IntPtr]::Zero -or $hDevInfo.ToInt64() -eq -1) {
    Write-Host "[hid-read] SetupDiGetClassDevs failed" -ForegroundColor Red
    exit 1
}

# First pass: enumerate all paths and filter by string match BEFORE any CreateFile.
# The HID device interface path encodes VID&PID, so we never need to open hostile devices.
$applePaths = @()
$idx = 0
$totalPaths = 0
while ($true) {
    $did = New-Object HidEnum+SP_DEVICE_INTERFACE_DATA
    $did.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($did)
    $ok = [HidEnum]::SetupDiEnumDeviceInterfaces($hDevInfo, [IntPtr]::Zero, [ref]$hidGuid, $idx, [ref]$did)
    if (-not $ok) { break }
    $idx++

    $reqSize = 0
    [HidEnum]::SetupDiGetDeviceInterfaceDetail($hDevInfo, [ref]$did, [IntPtr]::Zero, 0, [ref]$reqSize, [IntPtr]::Zero) | Out-Null
    if ($reqSize -le 0) { continue }
    $detail = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($reqSize)
    try {
        [System.Runtime.InteropServices.Marshal]::WriteInt32($detail, 8)
        $ok2 = [HidEnum]::SetupDiGetDeviceInterfaceDetail($hDevInfo, [ref]$did, $detail, $reqSize, [ref]$reqSize, [IntPtr]::Zero)
        if (-not $ok2) { continue }
        $path = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([IntPtr]::Add($detail, 4))
        $totalPaths++
        # String-match filter -- do NOT open hostile devices.
        # Path examples:
        #   \\?\HID#{guid}_VID&000205AC_PID&030D&...   (BT v1)
        #   \\?\HID#{guid}_VID&0001004C_PID&0323&...   (BT v3)
        #   \\?\HID#{guid}_VID&000205AC_PID&0239&...   (BT keyboard)
        $pl = $path.ToLowerInvariant()
        $isApplePath = (
            ($pl -match 'vid&0001004c_pid&0323') -or
            ($pl -match 'vid&000205ac_pid&030d') -or
            ($pl -match 'vid&000205ac_pid&0239')
        )
        # Allow no-collection paths (mice) AND keyboard COL01 (the actual Keyboard TLC
        # which carries the standard Feature 0x47 battery report). Skip COL02/COL03
        # (consumer-control collections — Windows guards them and CreateFile hangs).
        $isCol = $pl -match '&col(\d+)#'
        $colNum = if ($isCol) { [int]$matches[1] } else { -1 }
        $allowed = (-not $isCol) -or ($colNum -eq 1)
        if ($isApplePath -and $allowed) {
            $applePaths += [pscustomobject]@{ Path = $path }
        }
    } finally {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($detail)
    }
}
[HidEnum]::SetupDiDestroyDeviceInfoList($hDevInfo) | Out-Null

Write-Host "[hid-read] Total HID interfaces enumerated: $totalPaths -- Apple matches: $($applePaths.Count)"

# Second pass: open each Apple device with R/W and try Feature reads.
$results = @()
foreach ($p in $applePaths) {
    Write-Host "[hid-read] reading $($p.Path)"
    # dwDesiredAccess=0 -- HidD_GetFeature dispatches via IOCTL_HID_GET_FEATURE
    # which doesn't need R/W file access. Mouse-class HID devices are held
    # exclusively by mouhid.sys so any GENERIC_* open returns ERROR_ACCESS_DENIED.
    $h = [HidNative]::CreateFile($p.Path, 0, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h.IsInvalid) {
        $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $results += [pscustomobject]@{
            Path = $p.Path
            OpenError = '0x{0:X}' -f $err
            Reads = @{}
        }
        continue
    }
    try {
        $attr = New-Object HidNative+HIDD_ATTRIBUTES
        $attr.Size = [System.Runtime.InteropServices.Marshal]::SizeOf($attr)
        $attrOk = [HidNative]::HidD_GetAttributes($h, [ref]$attr)
        $caps = New-Object HidNative+HIDP_CAPS
        $featureLen = 0; $usage = 0; $usagePage = 0
        $pp = [IntPtr]::Zero
        if ([HidNative]::HidD_GetPreparsedData($h, [ref]$pp)) {
            if ([HidNative]::HidP_GetCaps($pp, [ref]$caps) -eq 0x110000) {
                $featureLen = $caps.FeatureReportByteLength
                $usage = $caps.Usage
                $usagePage = $caps.UsagePage
            }
            [HidNative]::HidD_FreePreparsedData($pp) | Out-Null
        }
        $rec = [ordered]@{
            Path = $p.Path
            VID = if ($attrOk) { '0x{0:X4}' -f $attr.VendorID } else { '?' }
            PID = if ($attrOk) { '0x{0:X4}' -f $attr.ProductID } else { '?' }
            Version = if ($attrOk) { '0x{0:X4}' -f $attr.VersionNumber } else { '?' }
            Usage = '0x{0:X}' -f $usage
            UsagePage = '0x{0:X}' -f $usagePage
            FeatureReportByteLength = $featureLen
            Reads = [ordered]@{}
        }
        $tryLen = if ($featureLen -ge 1) { $featureLen } else { 65 }
        foreach ($rid in 0x47, 0x90, 0x55, 0x52, 0x12) {
            $buf = New-Object byte[] $tryLen
            $buf[0] = [byte]$rid
            $ok3 = [HidNative]::HidD_GetFeature($h, $buf, $buf.Length)
            $key = "RID_0x{0:X2}" -f $rid
            if ($ok3) {
                $hex = (($buf | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
                $rec.Reads[$key] = $hex
            } else {
                $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                $rec.Reads[$key] = "ERR=0x{0:X}" -f $err
            }
        }
        $results += [pscustomobject]$rec
    } finally {
        $h.Close()
    }
}

$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$out = [ordered]@{
    Captured = $ts
    AppleHIDInterfaces_Count = $applePaths.Count
    Results = $results
}
$jsonOut = Join-Path $OutDir 'hid-feature-read.json'
$txtOut  = Join-Path $OutDir 'hid-feature-read.txt'
$out | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonOut -Encoding UTF8

$lines = @()
$lines += "=== Apple HID Feature reads @ $ts ==="
$lines += "Apple HID interfaces found: $($applePaths.Count)"
$lines += ""
foreach ($r in $results) {
    $lines += "Path: $($r.Path)"
    if ($r.OpenError) {
        $lines += "  OPEN_FAILED: $($r.OpenError)"
        $lines += ""
        continue
    }
    $lines += "  VID=$($r.VID) PID=$($r.PID) Ver=$($r.Version) Usage=$($r.Usage)/UP=$($r.UsagePage) FeatLen=$($r.FeatureReportByteLength)"
    foreach ($k in $r.Reads.Keys) {
        $lines += "  $k -> $($r.Reads[$k])"
    }
    $lines += ""
}
$lines | Set-Content -Path $txtOut -Encoding UTF8
Write-Host "[hid-read] OK -> $jsonOut" -ForegroundColor Green
Write-Host "[hid-read] OK -> $txtOut" -ForegroundColor Green
exit 0
