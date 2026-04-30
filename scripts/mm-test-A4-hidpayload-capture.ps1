# mm-test-A4-hidpayload-capture.ps1
# Goal: Capture HIDCLASS input-report events WITH raw payload bytes preserved.
#
# Problem with A2: tracerpt CSV/TXT export strips payload fields.
# Fix in A4:
#   1. Use Get-WinEvent -Properties on the ETL directly to access typed
#      event data (including binary buffer fields) without tracerpt.
#   2. Enable HIDCLASS at level=5 (Verbose) with keyword 0xFF to force
#      the provider to emit all available fields including the raw report buffer.
#   3. Use XPath filtering on EventID 12 (DriverInput) which carries the
#      input-report buffer in versions of Windows 10/11 that have the full
#      HIDCLASS manifest.
#
# Admin queue dispatch: HIDPAYLOAD:<nonce> -> this script.
# Deploy to: D:\mm3-driver\scripts\mm-test-A4-hidpayload-capture.ps1
#
# Protocol: drop this file at the D:\mm3-driver\scripts path,
# then update mm-task-runner.ps1 to add the HIDPAYLOAD: case.
# See mm-task-runner-addendum.txt for the patch instructions.

[CmdletBinding()]
param(
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs',
    [int]$RuntimeSec = 60,
    [string]$ExistingEtl = ''
)
$ErrorActionPreference = 'Continue'

# Require admin
$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object System.Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'ERROR: must run as administrator' -ForegroundColor Red
    exit 1
}

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$runDir = Join-Path $OutDir "test-A4-hidpayload-$ts"
if (-not (Test-Path $runDir)) { New-Item -ItemType Directory $runDir -Force | Out-Null }

$logFile = Join-Path $runDir 'capture.log'
$outFrames = Join-Path $runDir 'rid27-frames.json'
$outSummary = Join-Path $runDir "test-A4-summary-$ts.md"

function Log([string]$Msg) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Msg"
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding ASCII
}

Log "mm-test-A4-hidpayload-capture.ps1 started"
Log "Output dir: $runDir"

# --- Path A: Fresh ETW capture ---
$useExisting = -not [string]::IsNullOrEmpty($ExistingEtl)
$etlPath = $ExistingEtl

if (-not $useExisting) {
    $tmpDir = "C:\mm-a4-etw-$ts"
    New-Item -ItemType Directory $tmpDir -Force | Out-Null
    $etlPath = Join-Path $tmpDir 'a4-capture.etl'
    $session = "mmhidpayload$ts"

    # Provider GUIDs
    $prov_HIDCLASS = '{6465DA78-E7A0-4F39-B084-8F53C7C30DC6}'  # Microsoft-Windows-Input-HIDCLASS
    $prov_BTHPORT  = '{8A1F9517-3A8C-4A9E-A018-4F17A200F277}'  # Microsoft-Windows-BTH-BTHPORT
    $prov_BTHUSB   = '{33693E1D-246A-471B-83BE-3E75F47A832D}'  # Microsoft-Windows-BTH-BTHUSB

    Log "Starting ETW session: $session"
    Log "IMPORTANT: Move and click the Magic Mouse v3 now for $RuntimeSec seconds"

    & logman.exe stop $session -ets 2>&1 | Out-Null

    # Create session with 256 MB buffers (HID input can be high-volume)
    $c = & logman.exe create trace $session -o $etlPath -bs 128 -nb 512 512 -ow -ets 2>&1
    Log ("logman create: " + ($c -join ' '))

    # HIDCLASS at level=5 (Verbose) with ALL keywords (0xFFFFFFFFFFFFFFFF)
    # Keyword 0x2 = input events in HIDCLASS manifest; 0xFF covers all
    $u1 = & logman.exe update trace $session -p $prov_HIDCLASS 0xFFFFFFFFFFFFFFFF 5 -ets 2>&1
    $u2 = & logman.exe update trace $session -p $prov_BTHPORT  0xFFFFFFFFFFFFFFFF 5 -ets 2>&1
    $u3 = & logman.exe update trace $session -p $prov_BTHUSB   0xFFFFFFFFFFFFFFFF 5 -ets 2>&1
    Log ("HIDCLASS level=5: " + ($u1 -join ' '))
    Log ("BTHPORT level=5:  " + ($u2 -join ' '))
    Log ("BTHUSB level=5:   " + ($u3 -join ' '))

    Log "Capture running for $RuntimeSec seconds..."
    Start-Sleep -Seconds $RuntimeSec

    $stop = & logman.exe stop $session -ets 2>&1
    Log ("logman stop: " + ($stop -join ' '))

    if (-not (Test-Path $etlPath)) {
        Log "ERROR: ETL not created at $etlPath"
        exit 2
    }
    $etlMB = [math]::Round((Get-Item $etlPath).Length / 1MB, 2)
    Log "ETL created: $etlPath ($etlMB MB)"

    # Copy ETL to output dir for WSL-side analysis
    $etlCopy = Join-Path $runDir "a4-capture-$ts.etl"
    Copy-Item $etlPath $etlCopy -Force
    Log "ETL copied to: $etlCopy"
    $etlPath = $etlCopy
} else {
    Log "Using existing ETL: $etlPath"
    $etlMB = [math]::Round((Get-Item $etlPath).Length / 1MB, 2)
    Log "ETL size: $etlMB MB"
}

# --- Path B: Parse ETL for RID=0x27 frames via Get-WinEvent ---
#
# Strategy: Get-WinEvent returns events with a .Properties array.
# HIDCLASS EventID 12 (DriverInput) and related events in some Windows versions
# include a binary Buffer property with the raw HID report bytes.
# We scan all events, check for binary properties > 10 bytes where byte[0] == 0x27.

Log "Parsing ETL via Get-WinEvent..."

$rid27Frames = New-Object System.Collections.Generic.List[object]
$totalEvents = 0
$hidclassEvents = 0
$parseErrors = 0

try {
    Get-WinEvent -Path $etlPath -Oldest -ErrorAction Stop | ForEach-Object {
        $ev = $_
        $totalEvents++

        # Focus on HIDCLASS events
        if ($ev.ProviderName -notlike '*HIDCLASS*' -and
            $ev.ProviderName -notlike '*Hid*') {
            return
        }
        $hidclassEvents++

        # Scan every property for a binary buffer starting with 0x27
        $props = @($ev.Properties)
        for ($i = 0; $i -lt $props.Count; $i++) {
            $val = $props[$i].Value
            if ($val -is [byte[]]) {
                if ($val.Length -ge 2 -and $val[0] -eq 0x27) {
                    # Candidate RID=0x27 payload
                    $hexPayload = ($val | ForEach-Object { '{0:X2}' -f $_ }) -join ''
                    $frame = [pscustomobject]@{
                        Time          = $ev.TimeCreated.ToString('o')
                        EventId       = $ev.Id
                        Provider      = $ev.ProviderName
                        PropertyIndex = $i
                        PayloadLength = $val.Length
                        PayloadHex    = $hexPayload
                    }
                    $rid27Frames.Add($frame) | Out-Null
                }
                elseif ($val.Length -ge 47) {
                    # 47-byte buffer might be a full HID report (RID+46 payload)
                    # Check if any byte could be 0x27 at position 0
                    # Also check position 1 in case buffer layout shifts
                    if ($val.Length -ge 47 -and $val[1] -eq 0x27) {
                        $hexPayload = ($val | ForEach-Object { '{0:X2}' -f $_ }) -join ''
                        $frame = [pscustomobject]@{
                            Time          = $ev.TimeCreated.ToString('o')
                            EventId       = $ev.Id
                            Provider      = $ev.ProviderName
                            PropertyIndex = $i
                            PayloadLength = $val.Length
                            PayloadHex    = $hexPayload
                            Note          = 'RID at offset 1'
                        }
                        $rid27Frames.Add($frame) | Out-Null
                    }
                }
            }
        }
    }
} catch {
    $parseErrors++
    Log "Get-WinEvent parse error: $_"
}

Log "Total events scanned: $totalEvents"
Log "HIDCLASS events: $hidclassEvents"
Log "RID=0x27 frames found: $($rid27Frames.Count)"
Log "Parse errors: $parseErrors"

# Save frames as JSON for Python analysis
$rid27Frames | ConvertTo-Json -Depth 5 | Set-Content $outFrames -Encoding ASCII
Log "Frames JSON: $outFrames"

# --- Summary ---
$summaryLines = New-Object System.Collections.Generic.List[string]
$summaryLines.Add('# Test A4 -- HIDCLASS Payload Capture Summary') | Out-Null
$summaryLines.Add('') | Out-Null
$summaryLines.Add("Timestamp: $ts") | Out-Null
$summaryLines.Add("ETL: $etlPath ($etlMB MB)") | Out-Null
$summaryLines.Add("Total events scanned: $totalEvents") | Out-Null
$summaryLines.Add("HIDCLASS events: $hidclassEvents") | Out-Null
$summaryLines.Add("RID=0x27 frames found: $($rid27Frames.Count)") | Out-Null
$summaryLines.Add("Parse errors: $parseErrors") | Out-Null
$summaryLines.Add('') | Out-Null

if ($rid27Frames.Count -gt 0) {
    $summaryLines.Add('## RID=0x27 Frame Samples (first 5)') | Out-Null
    $rid27Frames | Select-Object -First 5 | ForEach-Object {
        $summaryLines.Add("- $($_.Time) EventId=$($_.EventId) Len=$($_.PayloadLength) Hex=$($_.PayloadHex.Substring(0, [Math]::Min(94, $_.PayloadHex.Length)))...") | Out-Null
    }
    $summaryLines.Add('') | Out-Null
    $summaryLines.Add("STATUS: SUCCESS -- RID=0x27 payloads captured. Run mm-rid27-etl-parser.py against $outFrames") | Out-Null
} else {
    $summaryLines.Add('## STATUS: BLOCKED -- No RID=0x27 payloads in ETL') | Out-Null
    $summaryLines.Add('') | Out-Null
    $summaryLines.Add('HIDCLASS ETW at Verbose level still does not emit raw HID report buffers') | Out-Null
    $summaryLines.Add('for this device class on this Windows version.') | Out-Null
    $summaryLines.Add('') | Out-Null
    $summaryLines.Add('FALLBACK REQUIRED: Use Bluetooth HCI sniff (Wireshark + btsnoop or') | Out-Null
    $summaryLines.Add('npcap BT capture) to capture L2CAP CID=0x13 interrupt channel frames.') | Out-Null
    $summaryLines.Add('RID=0x27 frames appear as 47-byte payloads on that channel.') | Out-Null
    $summaryLines.Add('') | Out-Null
    $summaryLines.Add('ALTERNATIVE: Run the M12 driver with LogShadowBuffer() enabled.') | Out-Null
    $summaryLines.Add('Every Feature 0x47 query triggers a DbgPrint of all 46 shadow bytes.') | Out-Null
    $summaryLines.Add('Use WinDbg or DebugView to capture the log at known battery levels.') | Out-Null
    $summaryLines.Add('This is the RECOMMENDED Phase 3 empirical validation path.') | Out-Null
}

$summaryLines | Set-Content $outSummary -Encoding ASCII
Log "Summary: $outSummary"
Log "A4 capture complete"
exit 0
