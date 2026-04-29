<#
.SYNOPSIS
    Test C: Procmon capture filtered to \Device\AppleBluetoothMultitouch IOCTL traffic.
    Captures for 90 seconds while user interacts with v3 mouse + Settings.
    Converts PML -> CSV filtered to the Apple device.
#>
[CmdletBinding()]
param(
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF',
    [int]$RuntimeSec = 90
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }

$procmon = 'C:\Users\Lesley\AppData\Local\Microsoft\WindowsApps\Procmon.exe'
if (-not (Test-Path $procmon)) {
    Write-Host "[test-C] ERROR: Procmon not found at $procmon" -ForegroundColor Red
    exit 1
}

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$tmpDir = "C:\m13-procmon-iotest-$ts"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$pml = Join-Path $tmpDir 'capture.pml'
$csvFull = Join-Path $tmpDir 'capture-all.csv'
$csvFiltered = Join-Path $OutDir "test-C-procmon-applebmt-$ts.csv"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Test C: Procmon AppleBluetoothMultitouch IOCTL capture" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Procmon will capture for $RuntimeSec seconds starting in 5 seconds."
Write-Host ""
Write-Host "DURING THE CAPTURE, please:"
Write-Host "  1. Move and click the v3 Magic Mouse"
Write-Host "  2. Open Settings -> Bluetooth & devices"
Write-Host "  3. Click on 'Magic Mouse' and view its properties / device details"
Write-Host "  4. Toggle to 'View more devices' and back"
Write-Host "  5. If the BT Settings page exposes a 'More options' for Magic Mouse, open that"
Write-Host ""
Write-Host "These actions trigger any system-side battery query that uses the"
Write-Host "AppleBluetoothMultitouch device, if such a query exists."
Write-Host ""
Start-Sleep -Seconds 5
Write-Host "[test-C] Starting Procmon capture (PID will be visible in tray)..."
Write-Host "[test-C] Capture will auto-stop in $RuntimeSec sec."
Write-Host "[test-C] Backing file: $pml"
Write-Host ""

# Procmon /Runtime captures for N seconds with default (everything) filter.
# Capture all events; we'll filter the resulting CSV for AppleBluetoothMultitouch traffic.
Start-Process -FilePath $procmon -ArgumentList @(
    '/AcceptEula',
    '/Quiet',
    '/Minimized',
    '/BackingFile', $pml,
    '/Runtime', "$RuntimeSec"
) -Wait

if (-not (Test-Path $pml)) {
    Write-Host "[test-C] ERROR: capture file not created" -ForegroundColor Red
    exit 2
}

$pmlSize = (Get-Item $pml).Length
Write-Host "[test-C] Capture complete. Size: $([math]::Round($pmlSize/1MB,2)) MB"
Write-Host "[test-C] Converting PML to CSV (this can take a minute on a busy machine)..."

# Convert to CSV (full)
Start-Process -FilePath $procmon -ArgumentList @(
    '/AcceptEula',
    '/Quiet',
    '/Minimized',
    '/OpenLog', $pml,
    '/SaveAs', $csvFull
) -Wait

if (-not (Test-Path $csvFull)) {
    Write-Host "[test-C] ERROR: full CSV not created" -ForegroundColor Red
    exit 3
}
Write-Host "[test-C] Full CSV: $csvFull ($([math]::Round((Get-Item $csvFull).Length/1MB,2)) MB)"

# Filter for AppleBluetoothMultitouch traffic in PowerShell — way faster than Procmon UI filter
Write-Host "[test-C] Filtering for AppleBluetoothMultitouch / applewirelessmouse..."
$pattern = 'AppleBluetoothMultitouch|applewirelessmouse|Apple.*HID|MagicMouse'
$matched = Get-Content -LiteralPath $csvFull -ReadCount 1000 -ErrorAction Continue |
    ForEach-Object { $_ } |
    Select-String -Pattern $pattern -CaseSensitive:$false
Write-Host "[test-C] Matched lines: $($matched.Count)"
if ($matched.Count -gt 0) {
    # write header + matches
    $header = Get-Content -LiteralPath $csvFull -TotalCount 1
    $header | Set-Content -Path $csvFiltered -Encoding UTF8
    $matched | ForEach-Object { $_.Line } | Add-Content -Path $csvFiltered -Encoding UTF8
    Write-Host "[test-C] Filtered CSV: $csvFiltered"
    Write-Host ""
    Write-Host "Top 10 unique Path values:"
    $matched | ForEach-Object {
        $cols = $_.Line -split ',(?=(?:[^"]*"[^"]*")*[^"]*$)'  # CSV-aware split
        if ($cols.Count -ge 5) { ($cols[4] -replace '"','') }
    } | Group-Object | Sort-Object Count -Descending | Select-Object -First 10 |
      ForEach-Object { Write-Host ("  {0,5} {1}" -f $_.Count, $_.Name) }
} else {
    Write-Host "[test-C] NO matches for the AppleBluetoothMultitouch pattern."
    Write-Host "[test-C] This means: nothing on the system queried Apple's IOCTL device during the $RuntimeSec sec capture."
    Write-Host "[test-C] If Apple's userland tool isn't installed, no system component natively reads battery via this channel."
}

Write-Host ""
Write-Host "[test-C] DONE"
exit 0
