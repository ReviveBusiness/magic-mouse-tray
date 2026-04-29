<#
.SYNOPSIS
    Test A: USBPcap HCI capture on the BT root hub (USB\ROOT_HUB30\5&60c3eac&0&0).
    Run AFTER USBPcap is installed + reboot completed. Captures BT-over-USB
    HCI for 90 sec during user mouse activity, then decodes via tshark filtered
    to the v3 mouse MAC and HID interrupt channel.

    Prereqs:
      - USBPcap installed (filter active, control devices \\.\USBPcap1..N exist)
      - tshark.exe at C:\Program Files\Wireshark\tshark.exe (verified)
      - Run elevated (admin) — USBPcap capture requires it
#>
[CmdletBinding()]
param(
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF',
    [int]$RuntimeSec = 90,
    [string]$V3Mac = 'd0:c0:50:cc:8c:4d',
    [string]$UsbPcapCmd = 'C:\Program Files\USBPcap\USBPcapCMD.exe',
    [string]$Tshark    = 'C:\Program Files\Wireshark\tshark.exe'
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $UsbPcapCmd)) { Write-Host "ERROR: USBPcap not at $UsbPcapCmd"; exit 1 }
if (-not (Test-Path $Tshark))     { Write-Host "ERROR: tshark not at $Tshark"; exit 1 }

# Pre-flight: must run elevated
$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object System.Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: must run as administrator (USBPcap requires it)" -ForegroundColor Red
    exit 2
}

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$tmpDir = "C:\m13-usbpcap-$ts"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$pcap = Join-Path $tmpDir 'capture.pcapng'

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Test A: USBPcap + tshark HCI capture for v3 Magic Mouse" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: enumerate USBPcap interfaces and pick the BT one.
# The BT controller is on USB\ROOT_HUB30\5&60c3eac&0&0 (third root hub from
# Get-PnpDevice probe). USBPcap names them \\.\USBPcap1, USBPcap2, USBPcap3.
# We try all three; the right one will see HCI traffic to/from $V3Mac.

# USBPcapCMD --help shows -d takes a control device path.
# Without an interactive enumeration, we'll capture from \\.\USBPcap3 first
# (heuristic: third root hub = third filter). If empty, try USBPcap1, USBPcap2.
$candidates = '\\.\USBPcap3','\\.\USBPcap1','\\.\USBPcap2'

foreach ($iface in $candidates) {
    Write-Host "[test-A] Attempting capture on $iface for $RuntimeSec sec..."
    Write-Host "[test-A] DURING capture: move v3 mouse + open Settings -> BT & devices."
    Write-Host ""

    Start-Sleep -Seconds 3

    # USBPcapCMD: -d <device> -o <pcap>. -A captures from all USB devices on hub.
    # No built-in stop-after — must kill the process after RuntimeSec.
    $proc = Start-Process -FilePath $UsbPcapCmd -ArgumentList @(
        '-d', $iface,
        '-o', $pcap,
        '-A'
    ) -PassThru -WindowStyle Hidden

    Start-Sleep -Seconds $RuntimeSec
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2

    if (-not (Test-Path $pcap) -or (Get-Item $pcap).Length -lt 1024) {
        Write-Host "[test-A]   $iface produced no/empty capture. Trying next."
        if (Test-Path $pcap) { Remove-Item $pcap -Force -ErrorAction SilentlyContinue }
        continue
    }
    $sz = (Get-Item $pcap).Length
    Write-Host "[test-A] Capture: $pcap ($([math]::Round($sz/1KB,1)) KB)"

    # Decode with tshark — HCI dissector + filter for v3 MAC + HID interrupt channel
    Write-Host "[test-A] Decoding with tshark..."
    $jsonOut = Join-Path $OutDir "test-A-usbpcap-$ts-decoded.json"
    $txtOut  = Join-Path $OutDir "test-A-usbpcap-$ts-summary.txt"

    # Filter: any packet involving the v3 MAC, plus any HID Control / Interrupt packets
    $filter = "bluetooth.addr == $V3Mac or bthid"
    & $Tshark -r $pcap -Y $filter -V 2>&1 | Set-Content $txtOut -Encoding UTF8
    & $Tshark -r $pcap -Y $filter -T json 2>&1 | Set-Content $jsonOut -Encoding UTF8

    $matchedLines = (Get-Content $txtOut -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host "[test-A] Filter '$filter' matched $matchedLines lines"
    Write-Host "[test-A] Verbose decode: $txtOut"
    Write-Host "[test-A] JSON decode:    $jsonOut"

    # Quick analysis: report any HID Input reports with ReportID 0x90 (vendor battery)
    Write-Host ""
    Write-Host "[test-A] Looking for ReportID 0x90 (vendor battery) in interrupt channel..."
    $rid90 = & $Tshark -r $pcap -Y 'bthid.report_id == 0x90' -T fields -e frame.time_relative -e bluetooth.src -e bluetooth.dst -e bthid.report_id -e bthid.report_data 2>&1
    if ($rid90) {
        Write-Host "[test-A]   ★ FOUND ReportID 0x90 traffic ★"
        $rid90 | Set-Content (Join-Path $OutDir "test-A-usbpcap-$ts-rid90.txt") -Encoding UTF8
    } else {
        Write-Host "[test-A]   No ReportID 0x90 in this capture window"
    }

    # Also check for any traffic on the HID Control PSM (0x11) — GET_REPORT requests
    Write-Host "[test-A] Looking for L2CAP HID Control channel activity..."
    $hidctrl = & $Tshark -r $pcap -Y 'l2cap.psm == 0x0011' -T fields -e frame.time_relative -e bluetooth.src -e bluetooth.dst -e l2cap.cid 2>&1
    if ($hidctrl) {
        Write-Host "[test-A]   $((($hidctrl | Measure-Object).Count)) HID Control packets"
    }

    Write-Host ""
    Write-Host "[test-A] DONE on $iface"
    Write-Host "[test-A] Raw pcap kept at: $pcap"
    Write-Host "[test-A] Open in Wireshark: wireshark $pcap"
    exit 0
}

Write-Host "[test-A] ERROR: no USBPcap interface produced data. Check that USBPcap is installed + reboot completed." -ForegroundColor Red
exit 3
