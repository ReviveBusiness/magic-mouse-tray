# Test reading ReportID 0x90 from v3 vendor TLC (col02) while in Mode A.
# This validates the M12 Approach B premise: passthrough-vendor-TLC + tray-reads-0x90
# is sufficient for v3 battery without kernel-side translation.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Continue'

$src = @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class Hid {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern SafeFileHandle CreateFile(string name, uint access, uint share,
    IntPtr sa, uint creation, uint flags, IntPtr template);
  [DllImport("hid.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.U1)]
  public static extern bool HidD_GetInputReport(SafeFileHandle h, byte[] buf, int sz);
  [DllImport("hid.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.U1)]
  public static extern bool HidD_GetFeature(SafeFileHandle h, byte[] buf, int sz);
}
"@
Add-Type -TypeDefinition $src

# v3 vendor TLC path (col02, UP:FF00) — from current tray debug.log
$v3Vendor = '\\?\hid#{00001124-0000-1000-8000-00805f9b34fb}_vid&0001004c_pid&0323&col02#a&31e5d054&c&0001#{4d1e55b2-f16f-11cf-88cb-001111000030}'
# v3 mouse TLC path (col01, UP:0001/U:0002) — for comparison
$v3Mouse  = '\\?\hid#{00001124-0000-1000-8000-00805f9b34fb}_vid&0001004c_pid&0323&col01#a&31e5d054&c&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}'

$rids = 0x90, 0x47, 0x12, 0x09, 0x10, 0x01, 0x02

foreach ($pair in @(@{n='v3-vendor-col02'; p=$v3Vendor}, @{n='v3-mouse-col01'; p=$v3Mouse})) {
  Write-Host ""
  Write-Host ("=== {0} ===" -f $pair.n) -ForegroundColor Cyan
  Write-Host ("path: " + $pair.p)
  # Try multiple access modes
  foreach ($am in @{name='0';val=0}, @{name='RW';val=3221225472}) {
    $h = [Hid]::CreateFile($pair.p, [uint32]$am.val, [uint32]3, [IntPtr]::Zero, [uint32]3, [uint32]0, [IntPtr]::Zero)
    if ($h.IsInvalid) {
      $gle = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
      Write-Host ("  open access={0} FAIL gle={1}" -f $am.name, $gle) -ForegroundColor Yellow
      continue
    }
    Write-Host ("  open access={0} OK" -f $am.name) -ForegroundColor Green
    foreach ($rid in $rids) {
      foreach ($call in 'GetInputReport','GetFeature') {
        $sz = 65
        $buf = New-Object byte[] $sz
        $buf[0] = [byte]$rid
        if ($call -eq 'GetInputReport') {
          $ok = [Hid]::HidD_GetInputReport($h, $buf, $sz)
        } else {
          $ok = [Hid]::HidD_GetFeature($h, $buf, $sz)
        }
        $gle = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($ok) {
          $hex = ($buf[0..15] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
          Write-Host ("    {0,-15} RID=0x{1:X2}  ok=True   bytes[0..15]={2}" -f $call, $rid, $hex) -ForegroundColor Green
        } else {
          Write-Host ("    {0,-15} RID=0x{1:X2}  ok=False  gle={2}" -f $call, $rid, $gle) -ForegroundColor DarkGray
        }
      }
    }
    $h.Close()
    break  # don't try RW if 0 worked
  }
}
Write-Host ''
Write-Host 'DONE'
