# Test A2: ETW capture of Bluetooth HCI + HID class events for v3 mouse.
# Uses logman to capture Microsoft-Windows-BTH-BTHUSB (HCI traffic) and
# Microsoft-Windows-Input-HIDCLASS (HID Get/Set Feature, Input Report I/O).
[CmdletBinding()]
param(
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF',
    [int]$RuntimeSec = 90
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }

$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object System.Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'ERROR: must run as administrator' -ForegroundColor Red
    exit 1
}

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$tmpDir = "C:\m13-etw-$ts"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$etl = Join-Path $tmpDir 'capture.etl'
$txtOut = Join-Path $OutDir "test-A2-etw-bth-hid-$ts.txt"
$summaryOut = Join-Path $OutDir "test-A2-etw-bth-hid-$ts-summary.md"
$session = "mmbthhid$ts"

$prov_BTHUSB   = '{33693E1D-246A-471B-83BE-3E75F47A832D}'
$prov_BTHPORT  = '{8A1F9517-3A8C-4A9E-A018-4F17A200F277}'
$prov_HIDCLASS = '{6465DA78-E7A0-4F39-B084-8F53C7C30DC6}'
$prov_BTPOLICY = '{0602ECEF-6381-4BC0-AEDA-EB9BB919B276}'

Write-Host 'ETW capture starting...'
Write-Host "Session: $session"
Write-Host "Runtime: $RuntimeSec seconds"
Write-Host 'INTERACT WITH MOUSE NOW: move/click v3 mouse, open Settings -> BT & devices -> Magic Mouse properties'

& logman.exe stop $session -ets 2>&1 | Out-Null

$createOut = & logman.exe create trace $session -o $etl -bs 64 -nb 256 256 -ow -ets 2>&1
Write-Host ("logman create: " + ($createOut -join ' '))

$u1 = & logman.exe update trace $session -p $prov_BTHUSB '0xFFFFFFFFFFFFFFFF' '5' -ets 2>&1
$u2 = & logman.exe update trace $session -p $prov_BTHPORT '0xFFFFFFFFFFFFFFFF' '5' -ets 2>&1
$u3 = & logman.exe update trace $session -p $prov_HIDCLASS '0xFFFFFFFFFFFFFFFF' '5' -ets 2>&1
$u4 = & logman.exe update trace $session -p $prov_BTPOLICY '0xFFFFFFFFFFFFFFFF' '5' -ets 2>&1
Write-Host ("provider BTHUSB: " + ($u1 -join ' '))
Write-Host ("provider BTHPORT: " + ($u2 -join ' '))
Write-Host ("provider HIDCLASS: " + ($u3 -join ' '))
Write-Host ("provider BTPOLICY: " + ($u4 -join ' '))

Write-Host ("Capture started: " + (Get-Date -Format 'HH:mm:ss'))
Start-Sleep -Seconds $RuntimeSec
Write-Host ("Capture window done: " + (Get-Date -Format 'HH:mm:ss'))

$stopOut = & logman.exe stop $session -ets 2>&1
Write-Host ("logman stop: " + ($stopOut -join ' '))

if (-not (Test-Path $etl)) {
    Write-Host 'ERROR: ETL not created' -ForegroundColor Red
    exit 2
}

$etlSize = (Get-Item $etl).Length
$etlMB = [math]::Round($etlSize/1MB, 2)
Write-Host ("ETL: $etl ($etlMB MB)")

# Decode via tracerpt to CSV (most reliable for ETW manifest+TMF mixed)
$csv = Join-Path $tmpDir 'capture.csv'
$xml = Join-Path $tmpDir 'capture.xml'
$summary = Join-Path $tmpDir 'tracerpt-summary.txt'
$report = Join-Path $tmpDir 'tracerpt-report.html'

Write-Host 'Running tracerpt -of CSV ...'
$rpt1 = & tracerpt.exe $etl -o $csv -of CSV -summary $summary -report $report -y 2>&1
Write-Host ([string]::Join(' ', $rpt1) | Select-Object -First 300)

Write-Host 'Running tracerpt -of XML ...'
$rpt2 = & tracerpt.exe $etl -o $xml -of XML -y 2>&1
Write-Host ([string]::Join(' ', $rpt2) | Select-Object -First 300)

# Open ACL on the captured artifacts so non-admin can read
foreach ($f in @($etl, $csv, $xml, $summary, $report)) {
    if (Test-Path $f) {
        try { icacls $f /grant '*S-1-1-0:R' /T 2>&1 | Out-Null } catch {}
    }
}

# Try Get-WinEvent as a backup
$decoded = New-Object System.Collections.Generic.List[string]
try {
    Get-WinEvent -Path $etl -Oldest -ErrorAction Stop | ForEach-Object {
        $ev = $_
        $msg = ([string]$ev.Message) -replace '\s+',' '
        $msgLen = $msg.Length
        $trunc = $msg
        if ($msgLen -gt 300) { $trunc = $msg.Substring(0, 300) }
        $line = $ev.TimeCreated.ToString('o') + ' | ' + $ev.ProviderName + '/' + $ev.Id + ' | ' + $ev.LevelDisplayName + ' | ' + $trunc
        $decoded.Add($line) | Out-Null
    }
} catch {
    $errmsg = [string]$_
    Write-Host ('Get-WinEvent failed: ' + $errmsg) -ForegroundColor Yellow
}
$decoded | Set-Content $txtOut -Encoding UTF8

# Also dump CSV first lines for visibility
$csvHead = @()
if (Test-Path $csv) {
    $csvSize = (Get-Item $csv).Length
    Write-Host ("CSV: $csv ($csvSize bytes)")
    $csvHead = Get-Content $csv -TotalCount 30
}
Write-Host ("Get-WinEvent decoded: " + $decoded.Count + " events")
Write-Host ("CSV first 30 lines (count: " + $csvHead.Count + ")")
$totalEvents = $decoded.Count

# Copy CSV to OutDir if non-empty
if ((Test-Path $csv) -and ((Get-Item $csv).Length -gt 0)) {
    $csvOut = $txtOut -replace '\.txt$', '.csv'
    Copy-Item $csv $csvOut -Force
    Write-Host ("CSV copied to OutDir: $csvOut")
}

# Build summary with greps
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Test A2 -- ETW Bluetooth HCI + HID class capture summary') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('Captured: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) | Out-Null
$lines.Add('ETL file: ' + $etl + ' (' + $etlMB + ' MB)') | Out-Null
$lines.Add('Decoded events: ' + $totalEvents) | Out-Null
$lines.Add('Decoded text:  ' + $txtOut) | Out-Null
$lines.Add('') | Out-Null

# Provider counts
$lines.Add('## Per-provider event counts') | Out-Null
foreach ($pname in 'Microsoft-Windows-BTH-BTHUSB','Microsoft-Windows-BTH-BTHPORT','Microsoft-Windows-Input-HIDCLASS','Microsoft-Windows-Bluetooth-Policy') {
    $pcount = ($decoded | Select-String -Pattern $pname -SimpleMatch | Measure-Object).Count
    $lines.Add('- ' + $pname + ': ' + $pcount) | Out-Null
}
$lines.Add('') | Out-Null

# Magic Mouse references
$btmac = $decoded | Select-String -Pattern 'D0C050CC8C4D|Magic Mouse|0001004C.*0323'
$btmacCount = ($btmac | Measure-Object).Count
$lines.Add('## Magic Mouse / D0C050CC8C4D references: ' + $btmacCount) | Out-Null
if ($btmacCount -gt 0) {
    $btmac | Select-Object -First 10 | ForEach-Object {
        $sample = [string]$_.Line
        if ($sample.Length -gt 220) { $sample = $sample.Substring(0, 220) }
        $lines.Add('  ' + $sample) | Out-Null
    }
}
$lines.Add('') | Out-Null

# ReportID 0x90 (vendor battery) signature
$rid90 = $decoded | Select-String -Pattern '0x90|0x0090|ReportID 90|reportid.*90'
$rid90Count = ($rid90 | Measure-Object).Count
$lines.Add('## ReportID 0x90 (vendor battery) matches: ' + $rid90Count) | Out-Null
if ($rid90Count -gt 0) {
    $rid90 | Select-Object -First 10 | ForEach-Object {
        $sample = [string]$_.Line
        if ($sample.Length -gt 220) { $sample = $sample.Substring(0, 220) }
        $lines.Add('  ' + $sample) | Out-Null
    }
}
$lines.Add('') | Out-Null

# ReportID 0x47 (standard battery) signature
$rid47 = $decoded | Select-String -Pattern '0x47|0x0047|ReportID 47|reportid.*47'
$rid47Count = ($rid47 | Measure-Object).Count
$lines.Add('## ReportID 0x47 (standard battery) matches: ' + $rid47Count) | Out-Null
if ($rid47Count -gt 0) {
    $rid47 | Select-Object -First 10 | ForEach-Object {
        $sample = [string]$_.Line
        if ($sample.Length -gt 220) { $sample = $sample.Substring(0, 220) }
        $lines.Add('  ' + $sample) | Out-Null
    }
}

$lines | Set-Content $summaryOut -Encoding UTF8
Write-Host ("Summary: $summaryOut")
Write-Host 'DONE'
exit 0
