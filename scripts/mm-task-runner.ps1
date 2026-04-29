# mm-task-runner.ps1 - invoked by the SYSTEM scheduled task 'MM-Dev-Cycle'.
#
# Protocol (filesystem queue, ASCII text, pipe-delimited):
#   Request:  C:\mm-dev-queue\request.txt   "PHASE|NONCE"
#   Result:   C:\mm-dev-queue\result.txt    "EXITCODE|NONCE"
#   Lock:     C:\mm-dev-queue\running.lock  (created on enter, removed on exit)
#
# WSL drops a request, triggers `schtasks /run /tn MM-Dev-Cycle`, and polls
# result.txt for a matching nonce. The nonce prevents reading a stale result
# from a previous run.

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$QueueDir   = 'C:\mm-dev-queue'
$ReqFile    = Join-Path $QueueDir 'request.txt'
$ResFile    = Join-Path $QueueDir 'result.txt'
$LockFile   = Join-Path $QueueDir 'running.lock'
$TaskLog    = 'C:\mm-dev-task.log'

function Log {
    param([string]$Msg)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$ts] $Msg" | Add-Content -Path $TaskLog -Encoding UTF8
}

if (-not (Test-Path $QueueDir)) { New-Item -ItemType Directory $QueueDir -Force | Out-Null }

# Reject concurrent runs (Settings/MultipleInstances=IgnoreNew should prevent
# this anyway, but belt-and-braces against a stale lock from a crashed run)
if (Test-Path $LockFile) {
    $lockAge = (Get-Date) - (Get-Item $LockFile).LastWriteTime
    if ($lockAge.TotalMinutes -lt 30) {
        Log "Concurrent run detected (lock $($lockAge.TotalSeconds)s old) - exiting"
        exit 75
    } else {
        Log "Stale lock found ($($lockAge.TotalMinutes) min old) - removing"
        Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    }
}

New-Item -Path $LockFile -ItemType File -Force | Out-Null
Log "===== task started ====="

try {
    if (-not (Test-Path $ReqFile)) {
        Log "No request file - exiting cleanly"
        exit 0
    }

    $raw = (Get-Content $ReqFile -Raw -Encoding ASCII).Trim()
    if (-not $raw) {
        Log "Empty request - exiting"
        exit 0
    }

    $parts = $raw -split '\|', 2
    $phase = $parts[0].Trim()
    $nonce = if ($parts.Count -gt 1) { $parts[1].Trim() } else { 'no-nonce' }
    Log "Request parsed: phase='$phase' nonce='$nonce'"

    $rc = 0

    # Special phase prefix "SNAPSHOT:Stack" routes to mm-bt-stack-snapshot.ps1
    if ($phase -like 'SNAPSHOT:*') {
        $snapScript = 'D:\mm3-driver\scripts\mm-bt-stack-snapshot.ps1'
        if (-not (Test-Path $snapScript)) {
            Log "ERROR: mm-bt-stack-snapshot.ps1 not found at $snapScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $snapScript"
        try {
            & $snapScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-bt-stack-snapshot.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "WPPDECODE:*" routes to mm-test-A3-wpp-decode.ps1
    elseif ($phase -like 'WPPDECODE:*') {
        $wppScript = 'D:\mm3-driver\scripts\mm-test-A3-wpp-decode.ps1'
        if (-not (Test-Path $wppScript)) {
            Log "ERROR: mm-test-A3-wpp-decode.ps1 not found at $wppScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $wppScript"
        try {
            & $wppScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-test-A3-wpp-decode.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "ETWBTH:*" routes to mm-test-A2-etw-bth-hid.ps1
    elseif ($phase -like 'ETWBTH:*') {
        $eScript = 'D:\mm3-driver\scripts\mm-test-A2-etw-bth-hid.ps1'
        if (-not (Test-Path $eScript)) {
            Log "ERROR: mm-test-A2-etw-bth-hid.ps1 not found at $eScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $eScript"
        try {
            & $eScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-test-A2-etw-bth-hid.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "PROCMONIO:*" routes to mm-test-C-procmon-iotest.ps1
    elseif ($phase -like 'PROCMONIO:*') {
        $pmScript = 'D:\mm3-driver\scripts\mm-test-C-procmon-iotest.ps1'
        if (-not (Test-Path $pmScript)) {
            Log "ERROR: mm-test-C-procmon-iotest.ps1 not found at $pmScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $pmScript"
        try {
            & $pmScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-test-C-procmon-iotest.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "CTRDUMP:*" routes to mm-container-dump.ps1
    elseif ($phase -like 'CTRDUMP:*') {
        $cdScript = 'D:\mm3-driver\scripts\mm-container-dump.ps1'
        if (-not (Test-Path $cdScript)) {
            Log "ERROR: mm-container-dump.ps1 not found at $cdScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $cdScript"
        try {
            & $cdScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-container-dump.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "DEVMGR:*" routes to mm-devmgr-dump.ps1
    elseif ($phase -like 'DEVMGR:*') {
        $dmScript = 'D:\mm3-driver\scripts\mm-devmgr-dump.ps1'
        if (-not (Test-Path $dmScript)) {
            Log "ERROR: mm-devmgr-dump.ps1 not found at $dmScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $dmScript"
        try {
            & $dmScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-devmgr-dump.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "EVTLOG:*" routes to mm-pnp-eventlog.ps1
    elseif ($phase -like 'EVTLOG:*') {
        $eScript = 'D:\mm3-driver\scripts\mm-pnp-eventlog.ps1'
        if (-not (Test-Path $eScript)) {
            Log "ERROR: mm-pnp-eventlog.ps1 not found at $eScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $eScript"
        try {
            & $eScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-pnp-eventlog.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "SVCCTRL:Action" routes to mm-svc-control.ps1
    elseif ($phase -like 'SVCCTRL:*') {
        $svcAction = ($phase -split ':', 2)[1]
        $svcScript = 'D:\mm3-driver\scripts\mm-svc-control.ps1'
        if (-not (Test-Path $svcScript)) {
            Log "ERROR: mm-svc-control.ps1 not found at $svcScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $svcScript Action=$svcAction"
        try {
            & $svcScript -Action $svcAction
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-svc-control.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "HIDREAD:*" routes to mm-hid-feature-read.ps1
    elseif ($phase -like 'HIDREAD:*') {
        $hrScript = 'D:\mm3-driver\scripts\mm-hid-feature-read.ps1'
        if (-not (Test-Path $hrScript)) {
            Log "ERROR: mm-hid-feature-read.ps1 not found at $hrScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $hrScript"
        try {
            & $hrScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-hid-feature-read.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "BATPROBE:*" routes to mm-battery-probe-deep.ps1
    elseif ($phase -like 'BATPROBE:*') {
        $bpScript = 'D:\mm3-driver\scripts\mm-battery-probe-deep.ps1'
        if (-not (Test-Path $bpScript)) {
            Log "ERROR: mm-battery-probe-deep.ps1 not found at $bpScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $bpScript"
        try {
            & $bpScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-battery-probe-deep.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "DISCOVER:Target" routes to mm-bthport-discover.ps1
    elseif ($phase -like 'DISCOVER:*') {
        $target = ($phase -split ':', 2)[1]
        $discScript = 'D:\mm3-driver\scripts\mm-bthport-discover.ps1'
        if (-not (Test-Path $discScript)) {
            Log "ERROR: mm-bthport-discover.ps1 not found at $discScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $discScript Target=$target"
        try {
            if ($target -eq 'All') {
                & $discScript -AllDevices
            } else {
                & $discScript -Mac $target
            }
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-bthport-discover.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "FLIP:Mode" routes to mm-state-flip.ps1 (LowerFilters mutation)
    elseif ($phase -like 'FLIP:*') {
        $mode = ($phase -split ':', 2)[1]
        $flipScript = 'D:\mm3-driver\scripts\mm-state-flip.ps1'
        if (-not (Test-Path $flipScript)) {
            Log "ERROR: mm-state-flip.ps1 not found at $flipScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $flipScript Mode=$mode"
        try {
            & $flipScript -Mode $mode
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-state-flip.ps1: $_"
            $rc = 99
        }
    } else {
        # Default: route to mm-dev.ps1 -Phase $phase
        $candidates = @(
            'D:\mm3-driver\scripts\mm-dev.ps1',
            'C:\mm3-pkg\scripts\mm-dev.ps1'
        )
        $devScript = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $devScript) {
            Log "ERROR: mm-dev.ps1 not found in candidates"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $devScript"

        try {
            & $devScript -Phase $phase -NoElevate
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-dev.ps1: $_"
            $rc = 99
        }
    }

    Log "Phase '$phase' exited $rc"
    "$rc|$nonce" | Set-Content $ResFile -Encoding ASCII
    exit $rc

} finally {
    Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    Log "===== task complete ====="
}
