# capture-hid-descriptor.ps1
# Captures HID report descriptors from Magic Mouse 3 (PID 0323) devices.
# Run elevated (Admin PowerShell). If "type already exists" error appears, open a NEW PowerShell window and re-run.
# Output: C:\Temp\mm3_desc_col01.bin, mm3_desc_col02.bin

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class HidCapV2 {
    [DllImport("hid.dll", SetLastError=true)]
    public static extern bool HidD_GetPreparsedData(IntPtr h, out IntPtr p);
    [DllImport("hid.dll", SetLastError=true)]
    public static extern bool HidD_FreePreparsedData(IntPtr p);
    [DllImport("hid.dll", SetLastError=true)]
    public static extern int HidP_GetCaps(IntPtr p, ref HIDP_CAPS c);
    [DllImport("setupapi.dll", CharSet=CharSet.Auto, SetLastError=true)]
    public static extern IntPtr SetupDiGetClassDevs(ref Guid g, string e, IntPtr hw, uint f);
    [DllImport("setupapi.dll", SetLastError=true)]
    public static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, uint i, ref SPDI data);
    [DllImport("setupapi.dll", CharSet=CharSet.Auto, SetLastError=true)]
    public static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref SPDI d, IntPtr det, uint sz, ref uint req, IntPtr inf);
    [DllImport("setupapi.dll", SetLastError=true)]
    public static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
    [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
    public static extern IntPtr CreateFile(string n, uint a, uint sh, IntPtr sec, uint cd, uint f, IntPtr t);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool DeviceIoControl(IntPtr dev, uint code,
        IntPtr inBuf, uint inSz, byte[] outBuf, uint outSz, ref uint ret, IntPtr ov);
    [StructLayout(LayoutKind.Sequential)]
    public struct SPDI { public uint cbSize; public Guid Guid; public uint Flags; public UIntPtr Reserved; }
    [StructLayout(LayoutKind.Sequential)]
    public struct HIDP_CAPS {
        public ushort Usage, UsagePage, InputReportByteLength, OutputReportByteLength, FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)] public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes;
        public ushort NumberInputButtonCaps, NumberInputValueCaps, NumberInputDataIndices;
        public ushort NumberOutputButtonCaps, NumberOutputValueCaps, NumberOutputDataIndices;
        public ushort NumberFeatureButtonCaps, NumberFeatureValueCaps, NumberFeatureDataIndices;
    }
}
"@

# IOCTL_HID_GET_REPORT_DESCRIPTOR = CTL_CODE(FILE_DEVICE_KEYBOARD=0xB, 0x20, METHOD_NEITHER=3, FILE_ANY_ACCESS=0)
$IOCTL_DESC    = [uint32]0x000B0083
$hidGuid       = [Guid]"{4d1e55b2-f16f-11cf-88cb-001111000030}"
$INVALID       = [IntPtr](-1)
$OPEN_EXISTING = [uint32]3
$SHARE_RW      = [uint32]3

$devs = [HidCapV2]::SetupDiGetClassDevs([ref]$hidGuid, $null, [IntPtr]::Zero, 0x12)
if ($devs -eq $INVALID) { Write-Host "FATAL: SetupDiGetClassDevs err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"; exit 1 }

$iface        = New-Object HidCapV2+SPDI
$iface.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($iface)
$saved = 0; $i = 0

while ([HidCapV2]::SetupDiEnumDeviceInterfaces($devs, [IntPtr]::Zero, [ref]$hidGuid, $i, [ref]$iface)) {

    $req = [uint32]0
    [HidCapV2]::SetupDiGetDeviceInterfaceDetail($devs, [ref]$iface, [IntPtr]::Zero, 0, [ref]$req, [IntPtr]::Zero) | Out-Null
    if ($req -eq 0) { $i++; continue }

    $ptr       = [Runtime.InteropServices.Marshal]::AllocHGlobal([int]$req)
    $detCbSize = if ([IntPtr]::Size -eq 8) { 8 } else { 6 }
    [Runtime.InteropServices.Marshal]::WriteInt32($ptr, $detCbSize)
    $ok = [HidCapV2]::SetupDiGetDeviceInterfaceDetail($devs, [ref]$iface, $ptr, $req, [ref]$req, [IntPtr]::Zero)
    $path = if ($ok) { [Runtime.InteropServices.Marshal]::PtrToStringAuto([IntPtr]($ptr.ToInt64() + 4)) } else { '' }
    [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)

    if ($path -notmatch '0323') { $i++; continue }

    $suffix = if ($path -match 'col01') { 'col01' } elseif ($path -match 'col02') { 'col02' } else { "idx$i" }
    Write-Host "`nMM3 $suffix : $path"

    $h = [HidCapV2]::CreateFile($path, 0, $SHARE_RW, [IntPtr]::Zero, $OPEN_EXISTING, 0, [IntPtr]::Zero)
    if ($h -eq $INVALID) { Write-Host "  OPEN_FAIL err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"; $i++; continue }

    $pp = [IntPtr]::Zero; $caps = New-Object HidCapV2+HIDP_CAPS
    if ([HidCapV2]::HidD_GetPreparsedData($h, [ref]$pp)) {
        [HidCapV2]::HidP_GetCaps($pp, [ref]$caps) | Out-Null
        [HidCapV2]::HidD_FreePreparsedData($pp) | Out-Null
        Write-Host "  UsagePage=0x$($caps.UsagePage.ToString('X4'))  Usage=0x$($caps.Usage.ToString('X4'))  InputReportLen=$($caps.InputReportByteLength)"
    }

    $descSaved = $false
    foreach ($sz in @(512, 1024, 2048, 4096)) {
        $buf = [byte[]]::new($sz); $ret = [uint32]0
        if ([HidCapV2]::DeviceIoControl($h, $IOCTL_DESC, [IntPtr]::Zero, 0, $buf, [uint32]$sz, [ref]$ret, [IntPtr]::Zero) -and $ret -gt 0) {
            $out = "C:\Temp\mm3_desc_$suffix.bin"
            [IO.File]::WriteAllBytes($out, $buf[0..($ret-1)])
            Write-Host "  SAVED $out ($ret bytes)"
            Write-Host "  Hex: $(($buf[0..([Math]::Min(31,$ret-1))] | ForEach-Object { $_.ToString('X2') }) -join ' ')"
            $saved++; $descSaved = $true; break
        }
    }
    if (-not $descSaved) {
        Write-Host "  DESC_FAIL err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }

    [HidCapV2]::CloseHandle($h) | Out-Null
    $i++
}

[HidCapV2]::SetupDiDestroyDeviceInfoList($devs) | Out-Null
Write-Host "`nDone. $saved descriptor(s) saved."
