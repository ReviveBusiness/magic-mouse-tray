<#
.SYNOPSIS
    PowerShell hiddescriptor.exe equivalent. Walks HidP_GetValueCaps +
    HidP_GetButtonCaps + HidP_GetLinkCollectionNodes for every Apple HID
    interface and dumps the FULL parsed descriptor — every button cap,
    value cap, link collection, with usage codes, report IDs, bit sizes.

    Output: hid-descriptor-full.{txt,json} per device interface.
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
public static class HidDump {
    [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
    public static extern SafeFileHandle CreateFile(string fn, uint a, uint s, IntPtr sa, uint cd, uint fa, IntPtr t);
    [DllImport("hid.dll")] public static extern void HidD_GetHidGuid(out Guid g);
    [DllImport("hid.dll")] public static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr d);
    [DllImport("hid.dll")] public static extern bool HidD_FreePreparsedData(IntPtr d);
    [DllImport("hid.dll")] public static extern int HidP_GetCaps(IntPtr d, ref CAPS c);
    [DllImport("hid.dll")] public static extern int HidP_GetValueCaps(int reportType, [In, Out] VALUE_CAPS[] caps, ref ushort len, IntPtr d);
    [DllImport("hid.dll")] public static extern int HidP_GetButtonCaps(int reportType, [In, Out] BUTTON_CAPS[] caps, ref ushort len, IntPtr d);
    [DllImport("hid.dll")] public static extern int HidP_GetLinkCollectionNodes([In, Out] LINK_COLLECTION_NODE[] nodes, ref UInt64 len, IntPtr d);

    [DllImport("setupapi.dll", CharSet=CharSet.Auto, SetLastError=true)]
    public static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr p, int f);
    [DllImport("setupapi.dll", SetLastError=true)]
    public static extern bool SetupDiEnumDeviceInterfaces(IntPtr h, IntPtr di, ref Guid g, int idx, ref SP_DID d);
    [DllImport("setupapi.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr h, ref SP_DID d, IntPtr detail, int sz, out int req, IntPtr di);
    [DllImport("setupapi.dll", SetLastError=true)]
    public static extern bool SetupDiDestroyDeviceInfoList(IntPtr h);

    [StructLayout(LayoutKind.Sequential)]
    public struct CAPS {
        public ushort Usage; public ushort UsagePage;
        public ushort In; public ushort Out; public ushort Feat;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=17)] public ushort[] R;
        public ushort NLnk, NIBC, NIVC, NIDI, NOBC, NOVC, NODI, NFBC, NFVC, NFDI;
    }

    [StructLayout(LayoutKind.Sequential, Pack=4)]
    public struct VALUE_CAPS {
        public ushort UsagePage; public byte ReportID;
        [MarshalAs(UnmanagedType.U1)] public bool IsAlias;
        public ushort BitField; public ushort LinkCollection;
        public ushort LinkUsage; public ushort LinkUsagePage;
        [MarshalAs(UnmanagedType.U1)] public bool IsRange;
        [MarshalAs(UnmanagedType.U1)] public bool IsStringRange;
        [MarshalAs(UnmanagedType.U1)] public bool IsDesignatorRange;
        [MarshalAs(UnmanagedType.U1)] public bool IsAbsolute;
        [MarshalAs(UnmanagedType.U1)] public bool HasNull;
        public byte Reserved;
        public ushort BitSize; public ushort ReportCount;
        public ushort R1, R2, R3, R4, R5;
        public uint UnitsExp; public uint Units;
        public int LogicalMin; public int LogicalMax;
        public int PhysicalMin; public int PhysicalMax;
        public ushort UsageMin; public ushort UsageMax;
        public ushort StringMin; public ushort StringMax;
        public ushort DesigMin; public ushort DesigMax;
        public ushort DataIdxMin; public ushort DataIdxMax;
    }

    [StructLayout(LayoutKind.Sequential, Pack=4)]
    public struct BUTTON_CAPS {
        public ushort UsagePage; public byte ReportID;
        [MarshalAs(UnmanagedType.U1)] public bool IsAlias;
        public ushort BitField; public ushort LinkCollection;
        public ushort LinkUsage; public ushort LinkUsagePage;
        [MarshalAs(UnmanagedType.U1)] public bool IsRange;
        [MarshalAs(UnmanagedType.U1)] public bool IsStringRange;
        [MarshalAs(UnmanagedType.U1)] public bool IsDesignatorRange;
        [MarshalAs(UnmanagedType.U1)] public bool IsAbsolute;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst=10)] public uint[] R;
        public ushort UsageMin; public ushort UsageMax;
        public ushort StringMin; public ushort StringMax;
        public ushort DesigMin; public ushort DesigMax;
        public ushort DataIdxMin; public ushort DataIdxMax;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct LINK_COLLECTION_NODE {
        public ushort LinkUsage; public ushort LinkUsagePage;
        public ushort Parent; public ushort NumberOfChildren;
        public ushort NextSibling; public ushort FirstChild;
        public uint Bitfield; public IntPtr UserContext;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SP_DID { public int cb; public Guid g; public int f; public IntPtr r; }
}
"@ -ErrorAction SilentlyContinue

function Get-CapName { param([int]$rt); switch ($rt) { 0 {'Input'} 1 {'Output'} 2 {'Feature'} default {"?$rt"} } }

function Dump-OneInterface {
    param([string]$Path, [string]$Label)
    $outBase = Join-Path $OutDir "hid-descriptor-full-$Label"
    $lines = @()
    $lines += "=== HID descriptor dump: $Label ==="
    $lines += "Path: $Path"
    $lines += "Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += ""
    $h = [HidDump]::CreateFile($Path, 0, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h.IsInvalid) {
        $lines += "OPEN FAILED: 0x{0:X}" -f [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $lines | Set-Content "$outBase.txt" -Encoding UTF8
        return
    }
    $jsonObj = [ordered]@{ Path=$Path; Caps=$null; LinkCollections=@(); ButtonCaps=@(); ValueCaps=@() }
    try {
        $pp = [IntPtr]::Zero
        if (-not [HidDump]::HidD_GetPreparsedData($h, [ref]$pp)) {
            $lines += "HidD_GetPreparsedData FAILED"
            $lines | Set-Content "$outBase.txt" -Encoding UTF8
            return
        }
        try {
            $caps = New-Object HidDump+CAPS
            [HidDump]::HidP_GetCaps($pp, [ref]$caps) | Out-Null
            $lines += "HIDP_CAPS:"
            $lines += "  TLC: UsagePage=0x{0:X4} Usage=0x{1:X4}" -f $caps.UsagePage, $caps.Usage
            $lines += "  Report lengths: Input={0} Output={1} Feature={2}" -f $caps.In, $caps.Out, $caps.Feat
            $lines += "  Counts: LinkColl={0} InpBC={1} InpVC={2} OutBC={3} OutVC={4} FeatBC={5} FeatVC={6}" -f $caps.NLnk, $caps.NIBC, $caps.NIVC, $caps.NOBC, $caps.NOVC, $caps.NFBC, $caps.NFVC
            $jsonObj.Caps = @{ TLC_UP=$caps.UsagePage; TLC_U=$caps.Usage; InLen=$caps.In; OutLen=$caps.Out; FeatLen=$caps.Feat; NLnk=$caps.NLnk; NIBC=$caps.NIBC; NIVC=$caps.NIVC; NOBC=$caps.NOBC; NOVC=$caps.NOVC; NFBC=$caps.NFBC; NFVC=$caps.NFVC }

            # Link Collections
            if ($caps.NLnk -gt 0) {
                $lines += ""
                $lines += "## Link Collection Nodes ($($caps.NLnk))"
                $nodes = New-Object HidDump+LINK_COLLECTION_NODE[] $caps.NLnk
                $len = [uint64]$caps.NLnk
                [HidDump]::HidP_GetLinkCollectionNodes($nodes, [ref]$len, $pp) | Out-Null
                for ($i = 0; $i -lt $len; $i++) {
                    $n = $nodes[$i]
                    # Bitfield encoding: bit 0 = Application, bits 0-7 = collection type
                    $type = [int]($n.Bitfield -band 0xff)
                    $typeStr = switch ($type) { 0 {'Physical'} 1 {'Application'} 2 {'Logical'} 3 {'Report'} 4 {'NamedArray'} 5 {'UsageSwitch'} 6 {'UsageModifier'} default {"$type"} }
                    $lines += "  [$i] UP=0x{0:X4} U=0x{1:X4} type={2} parent={3} children={4} firstChild={5} nextSibling={6}" -f $n.LinkUsagePage, $n.LinkUsage, $typeStr, $n.Parent, $n.NumberOfChildren, $n.FirstChild, $n.NextSibling
                    $jsonObj.LinkCollections += @{ Idx=$i; UP=$n.LinkUsagePage; U=$n.LinkUsage; Type=$typeStr; Parent=$n.Parent; Children=$n.NumberOfChildren; FirstChild=$n.FirstChild; NextSibling=$n.NextSibling }
                }
            }

            # Button caps + value caps for each report type
            foreach ($rt in 0,1,2) {
                $rtName = Get-CapName $rt
                $bcCount = switch ($rt) { 0 {$caps.NIBC} 1 {$caps.NOBC} 2 {$caps.NFBC} }
                $vcCount = switch ($rt) { 0 {$caps.NIVC} 1 {$caps.NOVC} 2 {$caps.NFVC} }
                if ($bcCount -gt 0) {
                    $lines += ""
                    $lines += "## $rtName Button Caps ($bcCount)"
                    $bcaps = New-Object HidDump+BUTTON_CAPS[] $bcCount
                    $blen = [UInt16]$bcCount
                    [HidDump]::HidP_GetButtonCaps($rt, $bcaps, [ref]$blen, $pp) | Out-Null
                    for ($i = 0; $i -lt $blen; $i++) {
                        $c = $bcaps[$i]
                        $usage = if ($c.IsRange) { "MIN=0x{0:X} MAX=0x{1:X}" -f $c.UsageMin, $c.UsageMax } else { "0x{0:X}" -f $c.UsageMin }
                        $lines += "  [$i] RID=0x{0:X2} UP=0x{1:X4} Usage={2} BitField=0x{3:X4} LinkColl={4} DataIdx={5}-{6}" -f $c.ReportID, $c.UsagePage, $usage, $c.BitField, $c.LinkCollection, $c.DataIdxMin, $c.DataIdxMax
                        $jsonObj.ButtonCaps += @{ ReportType=$rtName; RID=$c.ReportID; UP=$c.UsagePage; UsageMin=$c.UsageMin; UsageMax=$c.UsageMax; IsRange=$c.IsRange; BitField=$c.BitField; LinkColl=$c.LinkCollection }
                    }
                }
                if ($vcCount -gt 0) {
                    $lines += ""
                    $lines += "## $rtName Value Caps ($vcCount)"
                    $vcaps = New-Object HidDump+VALUE_CAPS[] $vcCount
                    $vlen = [UInt16]$vcCount
                    [HidDump]::HidP_GetValueCaps($rt, $vcaps, [ref]$vlen, $pp) | Out-Null
                    for ($i = 0; $i -lt $vlen; $i++) {
                        $c = $vcaps[$i]
                        $usage = if ($c.IsRange) { "MIN=0x{0:X} MAX=0x{1:X}" -f $c.UsageMin, $c.UsageMax } else { "0x{0:X}" -f $c.UsageMin }
                        $lines += "  [$i] RID=0x{0:X2} UP=0x{1:X4} Usage={2} BitField=0x{3:X4} LinkColl={4} BitSize={5} ReportCount={6} LogMin={7} LogMax={8} PhysMin={9} PhysMax={10}" -f $c.ReportID, $c.UsagePage, $usage, $c.BitField, $c.LinkCollection, $c.BitSize, $c.ReportCount, $c.LogicalMin, $c.LogicalMax, $c.PhysicalMin, $c.PhysicalMax
                        $jsonObj.ValueCaps += @{ ReportType=$rtName; RID=$c.ReportID; UP=$c.UsagePage; UsageMin=$c.UsageMin; UsageMax=$c.UsageMax; IsRange=$c.IsRange; BitField=$c.BitField; LinkColl=$c.LinkCollection; BitSize=$c.BitSize; ReportCount=$c.ReportCount; LogMin=$c.LogicalMin; LogMax=$c.LogicalMax; PhysMin=$c.PhysicalMin; PhysMax=$c.PhysicalMax }
                    }
                }
            }
        } finally {
            [HidDump]::HidD_FreePreparsedData($pp) | Out-Null
        }
    } finally { $h.Close() }
    $lines | Set-Content "$outBase.txt" -Encoding UTF8
    $jsonObj | ConvertTo-Json -Depth 6 | Set-Content "$outBase.json" -Encoding UTF8
    Write-Host "[hid-desc-dump] $Label -> $outBase.txt"
}

# Enumerate Apple HID interfaces (via SetupDi, like our prior probe)
$hidGuid = [Guid]::Empty
[HidDump]::HidD_GetHidGuid([ref]$hidGuid)
$DIGCF_PRESENT = 0x2; $DIGCF_DEVICEINTERFACE = 0x10
$dev = [HidDump]::SetupDiGetClassDevs([ref]$hidGuid, [IntPtr]::Zero, [IntPtr]::Zero, ($DIGCF_PRESENT -bor $DIGCF_DEVICEINTERFACE))
$applePaths = New-Object System.Collections.Generic.List[object]
$idx = 0
while ($true) {
    $did = New-Object HidDump+SP_DID
    $did.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($did)
    if (-not [HidDump]::SetupDiEnumDeviceInterfaces($dev, [IntPtr]::Zero, [ref]$hidGuid, $idx, [ref]$did)) { break }
    $idx++
    $req = 0
    [HidDump]::SetupDiGetDeviceInterfaceDetail($dev, [ref]$did, [IntPtr]::Zero, 0, [ref]$req, [IntPtr]::Zero) | Out-Null
    if ($req -le 0) { continue }
    $detail = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($req)
    try {
        [System.Runtime.InteropServices.Marshal]::WriteInt32($detail, 8)
        if ([HidDump]::SetupDiGetDeviceInterfaceDetail($dev, [ref]$did, $detail, $req, [ref]$req, [IntPtr]::Zero)) {
            $p = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([IntPtr]::Add($detail, 4))
            $pl = $p.ToLowerInvariant()
            $isApple = ($pl -match 'vid&0001004c_pid&0323') -or ($pl -match 'vid&000205ac_pid&030d') -or ($pl -match 'vid&000205ac_pid&0239')
            if ($isApple) {
                $isCol = $pl -match '&col(\d+)#'
                $col = if ($isCol) { [int]$matches[1] } else { 0 }
                $allow = (-not $isCol) -or ($col -eq 1)
                if ($allow) { $applePaths.Add($p) | Out-Null }
            }
        }
    } finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($detail) }
}
[HidDump]::SetupDiDestroyDeviceInfoList($dev) | Out-Null
Write-Host "[hid-desc-dump] Apple HID interfaces: $($applePaths.Count)"

foreach ($p in $applePaths) {
    $tag = if ($p -match 'pid&0323') { 'v3' } elseif ($p -match 'pid&030d') { 'v1' } elseif ($p -match 'pid&0239') { 'kbd' } else { 'unknown' }
    if ($p -match '&col(\d+)#') { $tag += "-col$($matches[1])" }
    Dump-OneInterface -Path $p -Label $tag
}

Write-Host "[hid-desc-dump] DONE -> $OutDir"
exit 0
