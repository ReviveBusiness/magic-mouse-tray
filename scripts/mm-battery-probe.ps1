# mm-battery-probe.ps1 — confirm battery is at Feature Report 0x47 on unified interface.

$ErrorActionPreference = 'Continue'
$ProbeLog = Join-Path $env:LOCALAPPDATA 'mm-battery-probe.log'

function Log { param([string]$M) "[$(Get-Date -Format 'HH:mm:ss')] $M" | Tee-Object -FilePath $ProbeLog -Append | Out-Null; Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $M" }

if (Test-Path $ProbeLog) { Remove-Item $ProbeLog -Force }

$cs = @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class H {
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern SafeFileHandle CreateFile(string n, uint a, uint s, IntPtr p, uint d, uint f, IntPtr t);
    [DllImport("hid.dll", SetLastError = true)] public static extern bool HidD_GetFeature(SafeFileHandle h, byte[] b, int l);
    [DllImport("hid.dll", SetLastError = true)] public static extern bool HidD_GetInputReport(SafeFileHandle h, byte[] b, int l);
    [DllImport("setupapi.dll", SetLastError = true)] public static extern IntPtr SetupDiGetClassDevs(ref Guid g, string e, IntPtr p, uint f);
    [DllImport("setupapi.dll", SetLastError = true)] public static extern bool SetupDiEnumDeviceInterfaces(IntPtr s, IntPtr d, ref Guid g, uint i, ref SP r);
    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr s, ref SP d, ref SD b, uint sz, out uint r, IntPtr di);
    [DllImport("setupapi.dll")] public static extern bool SetupDiDestroyDeviceInfoList(IntPtr s);
    [StructLayout(LayoutKind.Sequential)] public struct SP { public uint cb; public Guid g; public uint f; public IntPtr r; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)] public struct SD { public uint cb; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=512)] public string p; }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'H').Type) {
    Add-Type -TypeDefinition $cs -Language CSharp
}

$hidGuid = [Guid]'4d1e55b2-f16f-11cf-88cb-001111000030'
$devs = [H]::SetupDiGetClassDevs([ref]$hidGuid, $null, [IntPtr]::Zero, 0x12)
$index = 0
$paths = @()
while ($true) {
    $iface = New-Object H+SP
    $iface.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($iface)
    if (-not [H]::SetupDiEnumDeviceInterfaces($devs, [IntPtr]::Zero, [ref]$hidGuid, $index, [ref]$iface)) { break }
    $detail = New-Object H+SD
    $detail.cb = if ([IntPtr]::Size -eq 8) { 8 } else { 6 }
    [H]::SetupDiGetDeviceInterfaceDetail($devs, [ref]$iface, [ref]$detail, 512, [ref]$null, [IntPtr]::Zero) | Out-Null
    if ($detail.p -and ($detail.p -match 'pid&0323|pid_0323')) { $paths += $detail.p }
    $index++
}
[H]::SetupDiDestroyDeviceInfoList($devs) | Out-Null

Log "Probing $($paths.Count) Magic Mouse interface(s) for Feature Report 0x47 (battery)"
foreach ($path in $paths) {
    Log ""
    Log "Path: $path"

    # Try multiple access modes - Apple's driver may require specific access for features
    $modes = @(
        @{Name='ZeroAccess'; A=[uint32]0},
        @{Name='ReadOnly';   A=[uint32]([Convert]::ToUInt32('80000000', 16))},
        @{Name='ReadWrite';  A=[uint32]([Convert]::ToUInt32('C0000000', 16))}
    )
    foreach ($accessMode in $modes) {
    Log "  --- Access mode: $($accessMode.Name) (0x$('{0:X8}' -f $accessMode.A)) ---"
    $h = [H]::CreateFile($path, $accessMode.A, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h.IsInvalid) {
        Log "    CreateFile FAIL err=$([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        continue
    }
    try {
        # Test Feature Report 0x47 with various buffer sizes
        foreach ($len in @(2, 3, 4, 8, 16, 64)) {
            $buf = New-Object byte[] $len
            $buf[0] = 0x47
            $ok = [H]::HidD_GetFeature($h, $buf, $buf.Length)
            $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            if ($ok) {
                $end = [Math]::Min($buf.Length-1, 7)
                $hex = ($buf[0..$end] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
                Log "  Feat 0x47 len=${len}: OK   bytes=[$hex]"
            } else {
                Log "  Feat 0x47 len=${len}: FAIL err=$err"
            }
        }
        # Also try Input Report 0x47 just to be thorough
        foreach ($len in @(2, 4, 16, 64)) {
            $buf = New-Object byte[] $len
            $buf[0] = 0x47
            $ok = [H]::HidD_GetInputReport($h, $buf, $buf.Length)
            $err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            if ($ok) {
                $end = [Math]::Min($buf.Length-1, 7)
                $hex = ($buf[0..$end] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
                Log "  InRpt 0x47 len=${len}: OK   bytes=[$hex]"
            } else {
                Log "  InRpt 0x47 len=${len}: FAIL err=$err"
            }
        }
    } finally {
        $h.Close()
    }
    }  # end accessMode loop
}
Log ""
Log "===== complete ====="
