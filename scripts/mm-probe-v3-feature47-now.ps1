# Direct probe — v3 unified HID interface, try HidD_GetFeature(0x47).
# Replicates tray's poll without needing to restart the tray.
# Reports: open result, descriptor caps, GetFeature result with full bytes.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Continue'

$src = @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class Hid {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern SafeFileHandle CreateFile(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
  [DllImport("hid.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.U1)]
  public static extern bool HidD_GetFeature(SafeFileHandle h, byte[] buf, int sz);
  [DllImport("hid.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.U1)]
  public static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr pre);
  [DllImport("hid.dll", SetLastError=true)]
  public static extern int HidP_GetCaps(IntPtr pre, out HIDP_CAPS caps);
  [DllImport("hid.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.U1)]
  public static extern bool HidD_FreePreparsedData(IntPtr pre);
}
[StructLayout(LayoutKind.Sequential)]
public struct HIDP_CAPS {
  public ushort Usage;
  public ushort UsagePage;
  public ushort InputReportByteLength;
  public ushort OutputReportByteLength;
  public ushort FeatureReportByteLength;
  [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)] public ushort[] Reserved;
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
"@
Add-Type -TypeDefinition $src

# Enumerate v3 HID interfaces
$v3Iids = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\HID' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'VID&0001004c.*PID&0323' -or $_.PSChildName -match 'VID&0001004c.*PID&0323' }

# Use Get-PnpDevice to find v3 HID devices
$devs = Get-PnpDevice -Class HIDClass -PresentOnly | Where-Object { $_.InstanceId -match 'VID&0001004C_PID&0323' -and $_.InstanceId -notmatch '&COL' }

foreach ($d in $devs) {
    Write-Host ""
    Write-Host ("=== {0}" -f $d.InstanceId) -ForegroundColor Cyan
    # Build the HID interface path from instance ID
    $iid = $d.InstanceId.ToLower() -replace '\\', '#'
    $path = '\\?\' + $iid + '#{4d1e55b2-f16f-11cf-88cb-001111000030}'
    Write-Host ("path: " + $path) -ForegroundColor DarkGray

    # Open handle (access=0 works for HID GET_REPORT calls)
    $h = [Hid]::CreateFile($path, [uint32]0, [uint32]3, [IntPtr]::Zero, [uint32]3, [uint32]0, [IntPtr]::Zero)
    if ($h.IsInvalid) {
        $gle = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Host ("  open FAIL gle=$gle") -ForegroundColor Yellow
        continue
    }
    Write-Host '  open OK' -ForegroundColor Green

    # Read capabilities
    $pre = [IntPtr]::Zero
    $okPre = [Hid]::HidD_GetPreparsedData($h, [ref]$pre)
    if ($okPre -and $pre -ne [IntPtr]::Zero) {
        $caps = New-Object HIDP_CAPS
        $r = [Hid]::HidP_GetCaps($pre, [ref]$caps)
        Write-Host ("  HIDP_CAPS: TLC=UP:{0:X4}/U:{1:X4} InLen={2} FeatLen={3}" -f $caps.UsagePage, $caps.Usage, $caps.InputReportByteLength, $caps.FeatureReportByteLength) -ForegroundColor Gray
        [Hid]::HidD_FreePreparsedData($pre) | Out-Null
    }

    # Try Feature 0x47 (battery, expected by tray under Apple Mode B)
    $bufLen = 65
    $buf = New-Object byte[] $bufLen
    $buf[0] = 0x47
    $ok = [Hid]::HidD_GetFeature($h, $buf, $bufLen)
    $gle = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($ok) {
        Write-Host ("  GetFeature(0x47): SUCCESS  bytes=[{0}]" -f (($buf[0..15] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')) -ForegroundColor Green
        # Apple's synthesized Feature 0x47 typically returns: byte[0]=0x47, byte[1]=battery%
        $pct = $buf[1]
        Write-Host ("  -> Inferred battery: {0}%" -f $pct) -ForegroundColor Green
    } else {
        Write-Host ("  GetFeature(0x47): FAIL gle=$gle") -ForegroundColor Red
        if ($gle -eq 87) {
            Write-Host '  -> ERR 87 (INVALID_PARAMETER) = "Apple driver traps the Feature 0x47 read" — confirms M12 needed' -ForegroundColor DarkYellow
        }
    }

    $h.Close()
}
Write-Host ''
Write-Host 'DONE'
