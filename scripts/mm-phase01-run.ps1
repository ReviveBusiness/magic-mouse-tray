<#
.SYNOPSIS
    M13 Phase 0+1 orchestrator. One-shot from admin PowerShell.

.DESCRIPTION
    Sequence:
      0.1  Pause Windows Update for $PauseDays days
      1.1  Cleanup script -WhatIf (dry-run, prints what would change)
      [CONFIRM Y/n unless -AutoConfirmCleanup]
      1.2  Cleanup script real run (halts on per-step verify fail)

    Everything teed to a transcript at .ai/test-runs/m13-phase0/phase01-run-<ts>.log
    so the post-run report has a verbatim record.

    Self-elevation check; exits non-zero if not admin.
    Stops on first failure; the cleanup script's halt-on-fail is preserved.

.PARAMETER PauseDays
    Days to pause Windows Update (default 7, max 35).

.PARAMETER AutoConfirmCleanup
    Skip the y/n between -WhatIf and real run. Use only if you've already
    reviewed the -WhatIf output in a prior session.

.EXAMPLE
    Set-ExecutionPolicy -Scope Process Bypass -Force
    & '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\scripts\mm-phase01-run.ps1'
#>
[CmdletBinding()]
param(
    [ValidateRange(1,35)][int]$PauseDays = 7,
    [switch]$AutoConfirmCleanup
)

$ErrorActionPreference = 'Stop'

# --- self-elevate check ---
function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
    Write-Host "[phase01-run] ERROR: must run from admin PowerShell" -ForegroundColor Red
    exit 1
}

# --- ensure process-scope policy permits unsigned UNC scripts (we are one) ---
try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
} catch {
    Write-Host "[phase01-run] WARN: could not set process ExecutionPolicy: $_" -ForegroundColor Yellow
}

# --- resolve repo + log dir ---
$scriptsDir = $PSScriptRoot
$repo       = Split-Path -Parent $scriptsDir
$logDir     = Join-Path $repo '.ai\test-runs\m13-phase0'
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
$ts  = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$log = Join-Path $logDir "phase01-run-$ts.log"

Start-Transcript -Path $log -Append | Out-Null

try {
    Write-Host ""
    Write-Host "===== M13 Phase 0+1 orchestrator =====" -ForegroundColor Cyan
    Write-Host "  repo:       $repo"
    Write-Host "  log:        $log"
    Write-Host "  pause-days: $PauseDays"
    Write-Host "  auto-conf:  $AutoConfirmCleanup"
    Write-Host ""

    # === 0.1 Pause Windows Update ===
    Write-Host "----- 0.1 Pause Windows Update -----" -ForegroundColor Cyan
    & (Join-Path $scriptsDir 'mm-pause-windows-update.ps1') -Days $PauseDays
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[phase01-run] 0.1 FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
        exit 10
    }

    # === 1.1 Cleanup -WhatIf ===
    Write-Host ""
    Write-Host "----- 1.1 Cleanup script -WhatIf (dry-run) -----" -ForegroundColor Cyan
    & (Join-Path $scriptsDir 'mm-phase1-cleanup.ps1') -WhatIf
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[phase01-run] 1.1 FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
        exit 11
    }

    # === confirm gate ===
    if (-not $AutoConfirmCleanup) {
        Write-Host ""
        Write-Host "Review the -WhatIf output above." -ForegroundColor Yellow
        $resp = Read-Host "Proceed with REAL cleanup? [y/N]"
        if ($resp -notmatch '^[Yy]$') {
            Write-Host "[phase01-run] Real run skipped by user. Phase 0 (pause WU + WhatIf) committed." -ForegroundColor Yellow
            exit 0
        }
    }

    # === 1.2 Cleanup real run ===
    Write-Host ""
    Write-Host "----- 1.2 Cleanup script REAL RUN -----" -ForegroundColor Cyan
    & (Join-Path $scriptsDir 'mm-phase1-cleanup.ps1')
    $cleanupExit = $LASTEXITCODE
    if ($cleanupExit -ne 0) {
        Write-Host "[phase01-run] 1.2 FAILED (exit $cleanupExit) - see log + cleanup script per-step output" -ForegroundColor Red
        exit 12
    }

    Write-Host ""
    Write-Host "===== Phase 0+1 complete =====" -ForegroundColor Green
    Write-Host "Next steps (run from WSL, no admin needed):"
    Write-Host "  cd $repo"
    Write-Host "  ./scripts/mm-reg-export.sh post-cleanup    # export post-state"
    Write-Host "  ./scripts/mm-reg-diff.sh --auto            # MOP gate: confirm mutations match plan"
    Write-Host "  ./scripts/mm-snapshot-state.sh             # PnP/HID/driver topology"
    Write-Host ""
    Write-Host "  (or run the bundle: ./scripts/mm-phase1-closeout.sh — does all three.)"
    Write-Host ""
    Write-Host "Transcript: $log"
    exit 0
}
finally {
    Stop-Transcript | Out-Null
}
