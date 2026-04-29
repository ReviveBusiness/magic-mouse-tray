# Test unsolicited interrupt-channel reads on v3 vendor TLC (col02).
# In MU's Mode A, vendor TLC is exposed as col02 with InLen=64. If v3 firmware
# pushes battery as unsolicited input reports on the interrupt channel,
# ReadFile returns them. If nothing arrives, battery is poll-only and the
# poll mechanism is something other than HidD_GetInputReport (likely a
# vendor IOCTL through MU's kernel filter; needs Ghidra to find).
#
# Per-iteration opens a fresh handle in a background job so we can timeout
# blocking reads (HID interrupt channel reads block until a report arrives).
[CmdletBinding()]
param(
    [int]$DurationSec = 12,
    [int]$ReadTimeoutSec = 3
)
$ErrorActionPreference = 'Continue'

$paths = @{
    'v3-vendor-col02' = '\\?\hid#{00001124-0000-1000-8000-00805f9b34fb}_vid&0001004c_pid&0323&col02#a&31e5d054&c&0001#{4d1e55b2-f16f-11cf-88cb-001111000030}'
    'v3-mouse-col01'  = '\\?\hid#{00001124-0000-1000-8000-00805f9b34fb}_vid&0001004c_pid&0323&col01#a&31e5d054&c&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}'
    'v1-vendor-col03' = '\\?\hid#{00001124-0000-1000-8000-00805f9b34fb}_vid&000205ac_pid&030d&col03#a&137e1bf2&2&0002#{4d1e55b2-f16f-11cf-88cb-001111000030}'
}

$jobBlock = {
    param($path)
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class HidJ {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern SafeFileHandle CreateFile(string name, uint access, uint share,
    IntPtr sa, uint creation, uint flags, IntPtr template);
  [DllImport("kernel32.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.U1)]
  public static extern bool ReadFile(SafeFileHandle h, byte[] buf, uint sz, out uint nread, IntPtr ovl);
}
"@
    # GENERIC_READ=0x80000000. PS5's parameter binder fails inconsistently on
    # the literal/cast — use Convert.ToUInt32 from hex string for stability.
    [uint32]$accessRead = [Convert]::ToUInt32('80000000', 16)
    [uint32]$shareRW    = 3
    [uint32]$openExist  = 3
    [uint32]$noFlags    = 0
    $h = [HidJ]::CreateFile($path, $accessRead, $shareRW, [IntPtr]::Zero, $openExist, $noFlags, [IntPtr]::Zero)
    if ($h.IsInvalid) {
        return @{ok=$false; stage='open'; gle=[System.Runtime.InteropServices.Marshal]::GetLastWin32Error()}
    }
    $b = New-Object byte[] 65
    $rd = 0
    $ok = [HidJ]::ReadFile($h, $b, 65, [ref]$rd, [IntPtr]::Zero)
    $gle = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $h.Close()
    if ($ok) {
        $hex = ($b[0..([Math]::Min(31, $rd-1))] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
        return @{ok=$true; stage='read'; n=$rd; bytes=$hex}
    }
    return @{ok=$false; stage='read'; gle=$gle}
}

Write-Host ""
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "  ReadFile probe on Apple HID vendor TLCs (Mode A)" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "*** WIGGLE THE V3 MOUSE during this test ***" -ForegroundColor Yellow
Write-Host "    Battery reports often piggyback on motion/click activity."
Write-Host "    Test runs $DurationSec sec per path, with $ReadTimeoutSec sec read timeouts."
Write-Host ""

foreach ($k in $paths.Keys) {
    Write-Host ""
    Write-Host ("--- $k ---") -ForegroundColor Cyan
    $deadline = (Get-Date).AddSeconds($DurationSec)
    $reads = 0
    $opens = 0
    $openFails = 0
    while ((Get-Date) -lt $deadline) {
        $job = Start-Job -ScriptBlock $jobBlock -ArgumentList $paths[$k]
        $finished = Wait-Job -Job $job -Timeout $ReadTimeoutSec
        if ($finished) {
            $r = Receive-Job $job
            Remove-Job $job -Force
            if ($r.ok) {
                Write-Host ("  [+] READ n={0,3}  bytes[0..]={1}" -f $r.n, $r.bytes) -ForegroundColor Green
                $reads++
            } elseif ($r.stage -eq 'open') {
                Write-Host ("  [-] open FAIL gle={0}" -f $r.gle) -ForegroundColor DarkRed
                $openFails++
                Start-Sleep -Milliseconds 500
            } else {
                Write-Host ("  [-] read FAIL gle={0}" -f $r.gle) -ForegroundColor DarkGray
            }
            $opens++
        } else {
            Stop-Job $job 2>$null
            Remove-Job $job -Force 2>$null
            Write-Host ("  [.] read timeout ({0}s, no data)" -f $ReadTimeoutSec) -ForegroundColor DarkYellow
            $opens++
        }
    }
    Write-Host ("  SUMMARY: {0} reads, {1} attempts, {2} open-fails" -f $reads, $opens, $openFails)
}
Write-Host ''
Write-Host 'DONE'
