# TouchpadProbe.ps1
# Reads raw HID input reports from Magic Mouse 3 COL01 (touch) and COL02 (battery).
# Run elevated. Move your finger on the mouse surface while it runs.
# Press Ctrl+C to stop.
# Output: C:\Temp\TouchpadProbe_reports.txt

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
public class TouchProbe {
    [DllImport("hid.dll", SetLastError=true)]
    public static extern bool HidD_GetInputReport(IntPtr h, byte[] buf, int len);
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
    public static extern IntPtr CreateFile(string n, uint a, uint sh, IntPtr sec, uint cd, uint fl, IntPtr t);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool ReadFile(IntPtr h, byte[] buf, uint sz, ref uint read, IntPtr ov);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr h);
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

function Get-MM3DevicePath {
    param([string]$ColSuffix)
    $hidGuid = [Guid]"{4d1e55b2-f16f-11cf-88cb-001111000030}"
    $devs = [TouchProbe]::SetupDiGetClassDevs([ref]$hidGuid, $null, [IntPtr]::Zero, 0x12)
    $iface = New-Object TouchProbe+SPDI
    $iface.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($iface)
    $result = $null; $i = 0
    while ([TouchProbe]::SetupDiEnumDeviceInterfaces($devs, [IntPtr]::Zero, [ref]$hidGuid, $i, [ref]$iface)) {
        $req = [uint32]0
        [TouchProbe]::SetupDiGetDeviceInterfaceDetail($devs, [ref]$iface, [IntPtr]::Zero, 0, [ref]$req, [IntPtr]::Zero) | Out-Null
        if ($req -gt 0) {
            $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal([int]$req)
            $detCbSize = if ([IntPtr]::Size -eq 8) { 8 } else { 6 }
            [Runtime.InteropServices.Marshal]::WriteInt32($ptr, $detCbSize)
            if ([TouchProbe]::SetupDiGetDeviceInterfaceDetail($devs, [ref]$iface, $ptr, $req, [ref]$req, [IntPtr]::Zero)) {
                $path = [Runtime.InteropServices.Marshal]::PtrToStringAuto([IntPtr]($ptr.ToInt64() + 4))
                if ($path -match '0323' -and $path -match $ColSuffix) { $result = $path }
            }
            [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
        }
        $i++
    }
    [TouchProbe]::SetupDiDestroyDeviceInfoList($devs) | Out-Null
    return $result
}

$logPath  = "C:\Temp\TouchpadProbe_reports.txt"
$log      = [System.Collections.Generic.List[string]]::new()
$INVALID  = [IntPtr](-1)
$SHARE_RW = [uint32]3
$OPEN_EX  = [uint32]3

# --- Locate devices ---
$col01Path = Get-MM3DevicePath 'col01'
$col02Path = Get-MM3DevicePath 'col02'
Write-Host "COL01: $col01Path"
Write-Host "COL02: $col02Path"

# --- Open COL02 (battery) with zero-access + HidD_GetInputReport ---
$hCol02 = $null
if ($col02Path) {
    $h = [TouchProbe]::CreateFile($col02Path, 0, $SHARE_RW, [IntPtr]::Zero, $OPEN_EX, 0, [IntPtr]::Zero)
    if ($h -ne $INVALID) {
        $pp = [IntPtr]::Zero; $caps = New-Object TouchProbe+HIDP_CAPS
        [TouchProbe]::HidD_GetPreparsedData($h, [ref]$pp) | Out-Null
        [TouchProbe]::HidP_GetCaps($pp, [ref]$caps) | Out-Null
        [TouchProbe]::HidD_FreePreparsedData($pp) | Out-Null
        $buf = [byte[]]::new($caps.InputReportByteLength)
        $buf[0] = 0x90
        if ([TouchProbe]::HidD_GetInputReport($h, $buf, $buf.Length)) {
            $hex = ($buf | ForEach-Object { $_.ToString('X2') }) -join ' '
            Write-Host "COL02 battery report: $hex"
            Write-Host "  Battery = $($buf[2])%"
            $log.Add("COL02 battery: $hex  (battery=$($buf[2])%)")
        } else {
            Write-Host "COL02 GetInputReport failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
        [TouchProbe]::CloseHandle($h) | Out-Null
    }
}

# --- Open COL01 (touch) --- try GENERIC_READ first, then zero-access ---
$hCol01       = $INVALID
$col01Access  = 'none'
$GENERIC_READ = [uint32]0x80000000

if ($col01Path) {
    # GENERIC_READ allows ReadFile (blocking); mouhid may share the device
    $h = [TouchProbe]::CreateFile($col01Path, $GENERIC_READ, $SHARE_RW, [IntPtr]::Zero, $OPEN_EX, 0, [IntPtr]::Zero)
    if ($h -ne $INVALID) {
        $hCol01 = $h; $col01Access = 'GENERIC_READ'
        Write-Host "COL01 opened with GENERIC_READ — ReadFile loop starting"
        Write-Host "Move your finger on the mouse surface. Ctrl+C to stop."
    } else {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Host "COL01 GENERIC_READ failed err=$err — trying zero-access + HidD_GetInputReport"
        $h = [TouchProbe]::CreateFile($col01Path, 0, $SHARE_RW, [IntPtr]::Zero, $OPEN_EX, 0, [IntPtr]::Zero)
        if ($h -ne $INVALID) {
            $hCol01 = $h; $col01Access = 'zero-access'
        } else {
            Write-Host "COL01 zero-access also failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
        }
    }
}

if ($hCol01 -eq $INVALID) {
    Write-Host "COL01 not accessible — cannot read touch reports. Moving on."
} else {
    $pp = [IntPtr]::Zero; $caps = New-Object TouchProbe+HIDP_CAPS
    [TouchProbe]::HidD_GetPreparsedData($hCol01, [ref]$pp) | Out-Null
    [TouchProbe]::HidP_GetCaps($pp, [ref]$caps) | Out-Null
    [TouchProbe]::HidD_FreePreparsedData($pp) | Out-Null
    $reportLen = [Math]::Max([int]$caps.InputReportByteLength, 64)
    Write-Host "COL01 InputReportByteLength=$($caps.InputReportByteLength)  reading with bufSize=$reportLen"

    $seen = @{}  # deduplicate identical consecutive reports
    $count = 0

    try {
        if ($col01Access -eq 'GENERIC_READ') {
            # Blocking ReadFile loop — each call returns one raw HID input report
            $buf  = [byte[]]::new($reportLen)
            $read = [uint32]0
            while ($true) {
                $buf  = [byte[]]::new($reportLen)
                $read = [uint32]0
                $ok = [TouchProbe]::ReadFile($hCol01, $buf, [uint32]$reportLen, [ref]$read, [IntPtr]::Zero)
                if ($ok -and $read -gt 0) {
                    $trimmed = $buf[0..($read-1)]
                    $hex = ($trimmed | ForEach-Object { $_.ToString('X2') }) -join ' '
                    $rid = '0x' + $trimmed[0].ToString('X2')
                    if ($hex -ne $seen['last']) {
                        $seen['last'] = $hex
                        $count++
                        $line = "[$count] reportId=$rid  bytes=$read  $hex"
                        Write-Host $line
                        $log.Add($line)
                    }
                } else {
                    $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                    Write-Host "ReadFile failed err=$err"; break
                }
            }
        } else {
            # Zero-access: poll HidD_GetInputReport for known report IDs
            Write-Host "Polling Report IDs 0x01, 0x12, 0x90 via HidD_GetInputReport (move finger now)..."
            $reportIds = @(0x01, 0x12, 0x02, 0x03)
            for ($poll = 0; $poll -lt 100; $poll++) {
                foreach ($rid in $reportIds) {
                    $buf = [byte[]]::new($reportLen); $buf[0] = $rid
                    if ([TouchProbe]::HidD_GetInputReport($hCol01, $buf, $buf.Length)) {
                        $hex = ($buf[0..15] | ForEach-Object { $_.ToString('X2') }) -join ' '
                        if ($hex -ne $seen[$rid]) {
                            $seen[$rid] = $hex
                            $count++
                            $line = "[$count] reportId=0x$($rid.ToString('X2'))  $hex ..."
                            Write-Host $line
                            $log.Add($line)
                        }
                    }
                }
                Start-Sleep -Milliseconds 50
            }
        }
    } finally {
        [TouchProbe]::CloseHandle($hCol01) | Out-Null
    }
}

Write-Host ""
Write-Host "Captured $($log.Count) unique report(s). Saving to $logPath"
$log | Set-Content $logPath
Write-Host "Done."
