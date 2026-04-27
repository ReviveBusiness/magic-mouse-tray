# mm-task-runner.ps1 — invoked by the SYSTEM scheduled task 'MM-Dev-Cycle'.
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

    # Locate mm-dev.ps1 (synced by WSL into D:\mm3-driver\scripts)
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

    # Already SYSTEM (highest privilege) — pass -NoElevate so mm-dev.ps1 skips UAC re-launch
    $rc = 0
    try {
        & $devScript -Phase $phase -NoElevate
        $rc = $LASTEXITCODE
        if ($null -eq $rc) { $rc = 0 }
    } catch {
        Log "Exception running mm-dev.ps1: $_"
        $rc = 99
    }

    Log "Phase '$phase' exited $rc"
    "$rc|$nonce" | Set-Content $ResFile -Encoding ASCII
    exit $rc

} finally {
    Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    Log "===== task complete ====="
}
