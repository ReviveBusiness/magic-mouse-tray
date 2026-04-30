<#
.SYNOPSIS
    M13 v3 battery probe — tests user hypothesis that HidD_GetInputReport(0x90)
    on v3 (PID 0x0323) returns battery via Apple's stock applewirelessmouse filter,
    with NO M12 kernel filter installed.

    Per cross-session memory: RID=0x90, 3-byte report, UP=0xFF00 U=0x0014, buf[2]=pct.

    Approach:
      1. Enumerate every present HID device interface
      2. Filter to v3 (path contains VID&0001004C_PID&0323)
      3. Open each with zero access, dump caps, dump device path
      4. On any path where caps look right (vendor TLC OR generic mouse), try:
           - HidD_GetInputReport(0x90) — primary hypothesis
           - HidD_GetFeature(0x47)     — fallback (Apple unified mode)
           - HidD_GetFeature(0x90)     — completeness
      5. Print 3-byte payload + battery percent (buf[2]) when InputReport(0x90) hits.

    Output: <outdir>/v3-battery-stockfilter-<ts>.txt and .json
#>
[CmdletBinding()]
param(
    [string]$OutDir = 'C:\mm-dev-queue'
)
$ErrorActionPreference = 'Continue'
$ts = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$txt = Join-Path $OutDir "v3-battery-stockfilter-$ts.txt"
$json = Join-Path $OutDir "v3-battery-stockfilter-$ts.json"

$lines = New-Object System.Collections.Generic.List[string]
function W { param([string]$m) Write-Host $m; $lines.Add($m) }

W "=== M13 v3 Battery Probe (Apple stock filter, no M12) @ $ts ==="
W "Hypothesis: HidD_GetInputReport(0x90) on v3 returns 3-byte payload, buf[2] = battery %"
W ""

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class N {
    [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
    public static extern SafeFileHandle CreateFile(string fn, uint a, uint s, IntPtr sa, uint cd, uint fa, IntPtr t);
    [DllImport("hid.dll")] public static extern void HidD_GetHidGuid(out Guid g);
    [DllImport("hid.dll", SetLastError=true)] public static extern bool HidD_GetFeature(SafeFileHandle h, byte[] b, int n);
    [DllImport("hid.dll", SetLastError=true)] public static extern bool HidD_GetInputReport(SafeFileHandle h, byte[] b, int n);
    [DllImport("hid.dll", SetLastError=true)] public static extern bool HidD_GetAttributes(SafeFileHandle h, ref ATTR a);
    [DllImport("hid.dll", SetLastError=true)] public static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr d);
    [DllImport("hid.dll", SetLastError=true)] public static extern bool HidD_FreePreparsedData(IntPtr d);
    [DllImport("hid.dll", SetLastError=true)] public static extern int HidP_GetCaps(IntPtr d, ref CAPS c);
    [DllImport("hid.dll", SetLastError=true)] public static extern int HidP_GetValueCaps(int rt, [In,Out] VCAP[] vc, ref ushort len, IntPtr d);
    [DllImport("setupapi.dll", CharSet=CharSet.Auto, SetLastError=true)] public static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr p, int f);
    [DllImport("setupapi.dll", SetLastError=true)] public static extern bool SetupDiEnumDeviceInterfaces(IntPtr h, IntPtr di, ref Guid g, int i, ref DID d);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr h, ref DID d, IntPtr p, int sz, out int rs, IntPtr di);
    [DllImport("setupapi.dll", SetLastError=true)] public static extern bool SetupDiDestroyDeviceInfoList(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct ATTR { public int Size; public ushort VID, PID, Ver; }
    [StructLayout(LayoutKind.Sequential)] public struct DID { public int cb; public Guid g; public int f; public IntPtr r; }
    [StructLayout(LayoutKind.Sequential)] public struct CAPS {
        public ushort Usage, UsagePage, In, Out, Feat;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)] public ushort[] R;
        public ushort NLnk, NIBC, NIVC, NIDI, NOBC, NOVC, NODI, NFBC, NFVC, NFDI;
    }
    [StructLayout(LayoutKind.Sequential, Pack=4)] public struct VCAP {
        public ushort UsagePage; public byte ReportID;
        [MarshalAs(UnmanagedType.U1)] public bool IsAlias;
        public ushort BitField, LinkCollection, LinkUsage, LinkUsagePage;
        [MarshalAs(UnmanagedType.U1)] public bool IsRange, IsStringRange, IsDesignatorRange, IsAbsolute, HasNull;
        public byte Reserved;
        public ushort BitSize, ReportCount, R1, R2, R3, R4, R5;
        public uint UnitsExp, Units;
        public int LMin, LMax, PMin, PMax;
        public ushort Usage, UsageMax, StrMin, StrMax, DesMin, DesMax, DataMin, DataMax;
    }
}
"@ -ErrorAction SilentlyContinue

$hidGuid = [Guid]::Empty
[N]::HidD_GetHidGuid([ref]$hidGuid)
$h = [N]::SetupDiGetClassDevs([ref]$hidGuid, [IntPtr]::Zero, [IntPtr]::Zero, 0x12) # PRESENT|DEVICEINTERFACE
if ($h -eq [IntPtr]::Zero -or $h.ToInt64() -eq -1) { W "FAIL: SetupDiGetClassDevs"; exit 1 }

$v3Paths = @()
$allPaths = 0
$idx = 0
while ($true) {
    $did = New-Object N+DID
    $did.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($did)
    if (-not [N]::SetupDiEnumDeviceInterfaces($h, [IntPtr]::Zero, [ref]$hidGuid, $idx, [ref]$did)) { break }
    $idx++
    $rs = 0
    [N]::SetupDiGetDeviceInterfaceDetail($h, [ref]$did, [IntPtr]::Zero, 0, [ref]$rs, [IntPtr]::Zero) | Out-Null
    if ($rs -le 0) { continue }
    $detail = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($rs)
    try {
        [System.Runtime.InteropServices.Marshal]::WriteInt32($detail, 8)
        if ([N]::SetupDiGetDeviceInterfaceDetail($h, [ref]$did, $detail, $rs, [ref]$rs, [IntPtr]::Zero)) {
            $path = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([IntPtr]::Add($detail, 4))
            $allPaths++
            if ($path.ToLowerInvariant() -match 'vid&0001004c_pid&0323') {
                $v3Paths += $path
            }
        }
    } finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($detail) }
}
[N]::SetupDiDestroyDeviceInfoList($h) | Out-Null

W "Total HID interfaces: $allPaths"
W "v3 (PID 0x0323) interfaces: $($v3Paths.Count)"
W ""

$results = @()
foreach ($p in $v3Paths) {
    W "----------------------------------------------------------------"
    W "PATH: $p"
    $rec = [ordered]@{ Path=$p; OpenError=$null; Caps=$null; ValueCaps=@(); Reads=[ordered]@{} }

    $hh = [N]::CreateFile($p, 0, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($hh.IsInvalid) {
        $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $rec.OpenError = "0x{0:X}" -f $e
        W ("  OPEN_FAILED err=0x{0:X}" -f $e)
        $results += [pscustomobject]$rec
        continue
    }
    try {
        $attr = New-Object N+ATTR
        $attr.Size = [System.Runtime.InteropServices.Marshal]::SizeOf($attr)
        [N]::HidD_GetAttributes($hh, [ref]$attr) | Out-Null
        W ("  VID=0x{0:X4} PID=0x{1:X4} Ver=0x{2:X4}" -f $attr.VID, $attr.PID, $attr.Ver)

        $pp = [IntPtr]::Zero
        if ([N]::HidD_GetPreparsedData($hh, [ref]$pp)) {
            $caps = New-Object N+CAPS
            if ([N]::HidP_GetCaps($pp, [ref]$caps) -eq 0x110000) {
                $rec.Caps = [pscustomobject]@{
                    UsagePage="0x{0:X4}" -f $caps.UsagePage; Usage="0x{0:X4}" -f $caps.Usage
                    InLen=$caps.In; OutLen=$caps.Out; FeatLen=$caps.Feat
                    NumIVC=$caps.NIVC; NumFVC=$caps.NFVC
                }
                W ("  TLC: UP=0x{0:X4} U=0x{1:X4}  In={2} Out={3} Feat={4}" -f $caps.UsagePage, $caps.Usage, $caps.In, $caps.Out, $caps.Feat)
                W ("  ValueCaps: input={0} feature={1}" -f $caps.NIVC, $caps.NFVC)

                # Dump input value caps to find vendor TLC fields (UP=0xFF00 U=0x0014)
                if ($caps.NIVC -gt 0) {
                    $vcaps = New-Object N+VCAP[] $caps.NIVC
                    $len = [uint16]$caps.NIVC
                    if ([N]::HidP_GetValueCaps(0, $vcaps, [ref]$len, $pp) -eq 0x110000) {
                        for ($i = 0; $i -lt $len; $i++) {
                            $vc = $vcaps[$i]
                            W ("    [INPUT VC] UP=0x{0:X4} U=0x{1:X4} RID=0x{2:X2} BitSz={3} Cnt={4}" -f $vc.UsagePage, $vc.Usage, $vc.ReportID, $vc.BitSize, $vc.ReportCount)
                            $rec.ValueCaps += [pscustomobject]@{
                                Type='Input'; UsagePage="0x{0:X4}" -f $vc.UsagePage; Usage="0x{0:X4}" -f $vc.Usage
                                ReportID="0x{0:X2}" -f $vc.ReportID; BitSize=$vc.BitSize; Count=$vc.ReportCount
                            }
                        }
                    }
                }
                if ($caps.NFVC -gt 0) {
                    $fcaps = New-Object N+VCAP[] $caps.NFVC
                    $flen = [uint16]$caps.NFVC
                    if ([N]::HidP_GetValueCaps(2, $fcaps, [ref]$flen, $pp) -eq 0x110000) {
                        for ($i = 0; $i -lt $flen; $i++) {
                            $vc = $fcaps[$i]
                            W ("    [FEAT  VC] UP=0x{0:X4} U=0x{1:X4} RID=0x{2:X2} BitSz={3} Cnt={4}" -f $vc.UsagePage, $vc.Usage, $vc.ReportID, $vc.BitSize, $vc.ReportCount)
                            $rec.ValueCaps += [pscustomobject]@{
                                Type='Feature'; UsagePage="0x{0:X4}" -f $vc.UsagePage; Usage="0x{0:X4}" -f $vc.Usage
                                ReportID="0x{0:X2}" -f $vc.ReportID; BitSize=$vc.BitSize; Count=$vc.ReportCount
                            }
                        }
                    }
                }
            }
            [N]::HidD_FreePreparsedData($pp) | Out-Null
        }

        # PRIMARY TEST: HidD_GetInputReport(0x90), 3-byte buffer, expect buf[2]=pct
        W ""
        W "  >>> PRIMARY: HidD_GetInputReport(0x90) buf=3"
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $buf = New-Object byte[] 3
            $buf[0] = 0x90
            if ([N]::HidD_GetInputReport($hh, $buf, $buf.Length)) {
                $hex = ($buf | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
                $pct = $buf[2]
                W ("  [HIT attempt=$attempt] InputReport(0x90) = $hex -> buf[2] = $pct%")
                $rec.Reads['InputReport_0x90'] = @{ Hex=$hex; Pct=$pct; Attempt=$attempt }
                break
            } else {
                $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                W ("  [miss attempt=$attempt] InputReport(0x90) err=0x{0:X}" -f $e)
                if ($attempt -lt 3) { Start-Sleep -Milliseconds 50 }
                else { $rec.Reads['InputReport_0x90'] = "ERR=0x{0:X}" -f $e }
            }
        }

        # Try wider InputReport(0x90) buffer in case caps disagree
        if (-not $rec.Reads['InputReport_0x90'] -or $rec.Reads['InputReport_0x90'] -is [string]) {
            W ""
            W "  >>> PRIMARY-wide: HidD_GetInputReport(0x90) buf=64"
            $buf = New-Object byte[] 64
            $buf[0] = 0x90
            if ([N]::HidD_GetInputReport($hh, $buf, $buf.Length)) {
                $hex = ($buf[0..15] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
                W ("  [HIT-wide] InputReport(0x90) buf64 first16: $hex")
                $rec.Reads['InputReport_0x90_buf64'] = $hex
            } else {
                $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                W ("  [miss-wide] err=0x{0:X}" -f $e)
            }
        }

        # FALLBACK 1: HidD_GetFeature(0x47) — Apple unified mode
        W ""
        W "  >>> FALLBACK1: HidD_GetFeature(0x47)"
        $buf = New-Object byte[] 32
        $buf[0] = 0x47
        if ([N]::HidD_GetFeature($hh, $buf, $buf.Length)) {
            $hex = ($buf[0..7] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            W ("  [HIT] Feature(0x47) = $hex (likely buf[1] = pct: $($buf[1]))")
            $rec.Reads['Feature_0x47'] = @{ Hex=$hex; PctMaybe=$buf[1] }
        } else {
            $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            W ("  [miss] Feature(0x47) err=0x{0:X}" -f $e)
            $rec.Reads['Feature_0x47'] = "ERR=0x{0:X}" -f $e
        }

        # FALLBACK 2: HidD_GetFeature(0x90)
        W ""
        W "  >>> FALLBACK2: HidD_GetFeature(0x90)"
        $buf = New-Object byte[] 32
        $buf[0] = 0x90
        if ([N]::HidD_GetFeature($hh, $buf, $buf.Length)) {
            $hex = ($buf[0..7] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            W ("  [HIT] Feature(0x90) = $hex")
            $rec.Reads['Feature_0x90'] = $hex
        } else {
            $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            W ("  [miss] Feature(0x90) err=0x{0:X}" -f $e)
            $rec.Reads['Feature_0x90'] = "ERR=0x{0:X}" -f $e
        }

        # FALLBACK 3: HidD_GetInputReport(0x27) — declared value cap UP=0x0006 U=0x0001 BitSz=8 Cnt=46
        W ""
        W "  >>> FALLBACK3: HidD_GetInputReport(0x27) buf=64 (RID=0x27 declared 46 bytes)"
        $buf = New-Object byte[] 64
        $buf[0] = 0x27
        if ([N]::HidD_GetInputReport($hh, $buf, $buf.Length)) {
            $hex = ($buf[0..47] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            W ("  [HIT] InputReport(0x27) first48: $hex")
            $rec.Reads['InputReport_0x27'] = $hex
        } else {
            $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            W ("  [miss] InputReport(0x27) err=0x{0:X}" -f $e)
            $rec.Reads['InputReport_0x27'] = "ERR=0x{0:X}" -f $e
        }

        # FALLBACK 4: HidD_GetFeature(0x27)
        W ""
        W "  >>> FALLBACK4: HidD_GetFeature(0x27) buf=64"
        $buf = New-Object byte[] 64
        $buf[0] = 0x27
        if ([N]::HidD_GetFeature($hh, $buf, $buf.Length)) {
            $hex = ($buf[0..47] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            W ("  [HIT] Feature(0x27) first48: $hex")
            $rec.Reads['Feature_0x27'] = $hex
        } else {
            $e = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            W ("  [miss] Feature(0x27) err=0x{0:X}" -f $e)
            $rec.Reads['Feature_0x27'] = "ERR=0x{0:X}" -f $e
        }
    } finally { $hh.Close() }

    $results += [pscustomobject]$rec
    W ""
}

W "=== DONE @ $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

$lines | Set-Content -Path $txt -Encoding UTF8
[pscustomobject]@{ Captured=$ts; AppleHIDInterfaces=$allPaths; V3Interfaces=$v3Paths.Count; Results=$results } | ConvertTo-Json -Depth 8 | Set-Content -Path $json -Encoding UTF8
Write-Host ""
Write-Host "Output: $txt" -ForegroundColor Green
Write-Host "Output: $json" -ForegroundColor Green
exit 0
