<#
.SYNOPSIS
    M13 Phase 2 cell orchestrator — admin-PS wrapper around mm-test-matrix.sh.

.DESCRIPTION
    Mirrors the mm-phase01-run.ps1 pattern: this script runs in your admin PS,
    so it can launch Procmon (with kernel-driver capture rights) and wpr.exe
    (ETW) directly in elevated context. It then invokes the WSL-side
    mm-test-matrix.sh for the non-admin captures (HID probe, accept-test,
    state snapshot, log tails, wheel counter, observations), passing
    MM_PHASE2_ADMIN=1 + MM_PHASE2_RUN_DIR through WSLENV so the bash side
    knows admin-side captures are already running and SKIPS its own Procmon /
    wpr prompts.

    Sequence per cell:
      1. Pre-flight: self-elevation check, set ExecutionPolicy
      2. Compute timestamped run dir under .ai/test-runs/<ts>-<cell-id>/
      3. Launch Procmon -> <run-dir>/procmon.PML (admin context, kernel capture)
      4. Launch wpr -start GeneralProfile -filemode
      5. Invoke wsl.exe ./scripts/mm-test-matrix.sh <cell-id> [step] with
         WSLENV pass-through
      6. Stop wpr -stop <run-dir>/etw-trace.etl
      7. Procmon /Terminate

    The WSL bash side handles everything that doesn't need admin: HID probe,
    accept-test, snapshot, log tails, wheel counter, observation prompts,
    sleep/wake step (still prompts user since SetSuspendState doesn't auto-
    invoke nicely from background).

.PARAMETER CellId
    Test cell ID. Required first positional. One of:
      T-V3-AF | T-V3-NF | T-V3-AF-USB | T-V3-NF-USB | T-V1-AF | T-V1-NF

.PARAMETER Step
    Optional individual step name (omit for full interactive cell flow).
    Useful for resuming after reboot: -CellId T-V3-AF -Step test-3-post-reboot.

.PARAMETER SkipProcmon
    Skip Procmon launch/terminate. Use if Procmon is misbehaving or you only
    want ETW capture for this run.

.PARAMETER SkipETW
    Skip wpr.exe ETW capture. Use if wpr is misbehaving or you only want
    Procmon for this run.

.EXAMPLE
    Set-ExecutionPolicy -Scope Process Bypass -Force
    & '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\scripts\mm-phase2-run.ps1' -CellId T-V3-AF
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('T-V3-AF','T-V3-NF','T-V3-AF-USB','T-V3-NF-USB','T-V1-AF','T-V1-NF')]
    [string]$CellId,
    [string]$Step = '',
    [switch]$SkipProcmon,
    [switch]$SkipETW
)

$ErrorActionPreference = 'Stop'

# --- self-elevate check ---
function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
    Write-Host "[phase2-run] ERROR: must run from admin PowerShell (Procmon kernel capture + wpr ETW require it)" -ForegroundColor Red
    exit 1
}

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
} catch {
    Write-Host "[phase2-run] WARN: could not set process ExecutionPolicy: $_" -ForegroundColor Yellow
}

# --- resolve repo paths (script lives in <repo>/scripts/) ---
$scriptsDir = $PSScriptRoot
$repoWin    = Split-Path -Parent $scriptsDir
$repoWsl    = (& wsl.exe -e wslpath -u "$repoWin" 2>$null) -replace '\s',''
if (-not $repoWsl) {
    Write-Host "[phase2-run] ERROR: could not resolve WSL path for $repoWin" -ForegroundColor Red
    exit 2
}

# --- compute timestamped run dir (mirrors mm-test-matrix.sh's logic) ---
# We honor an existing marker if present (so step= sub-invocations reuse the
# cell's run dir); otherwise we create a fresh ts-cell directory.
$runsBaseWin = Join-Path $repoWin ".ai\test-runs"
if (-not (Test-Path $runsBaseWin)) {
    New-Item -Path $runsBaseWin -ItemType Directory -Force | Out-Null
}
$markerWin = Join-Path $runsBaseWin ".current-$CellId"
if (Test-Path $markerWin) {
    $runDirWsl = (Get-Content $markerWin -Raw).Trim()
    $runDirWin = (& wsl.exe -e wslpath -w "$runDirWsl" 2>$null) -replace '\s',''
    Write-Host "[phase2-run] Reusing existing cell run dir: $runDirWin" -ForegroundColor Cyan
} else {
    $ts = Get-Date -Format 'yyyy-MM-dd-HHmmss'
    $runDirWin = Join-Path $runsBaseWin "${ts}-${CellId}"
    New-Item -Path $runDirWin -ItemType Directory -Force | Out-Null
    $runDirWsl = (& wsl.exe -e wslpath -u "$runDirWin" 2>$null) -replace '\s',''
    Set-Content -Path $markerWin -Value $runDirWsl -NoNewline
    Write-Host "[phase2-run] New cell run dir: $runDirWin" -ForegroundColor Cyan
}

# --- transcript ---
$logPath = Join-Path $runDirWin "phase2-run.log"
Start-Transcript -Path $logPath -Append | Out-Null

# --- admin capture endpoints ---
$ProcmonExe = "C:\Users\Lesley\AppData\Local\Microsoft\WindowsApps\Procmon.exe"
$pmlPath    = Join-Path $runDirWin "procmon.PML"
$etlPath    = Join-Path $runDirWin "etw-trace.etl"

$procmonStarted = $false
$wprStarted     = $false

function Stop-AdminCaptures {
    if ($script:wprStarted -and -not $SkipETW) {
        Write-Host "[phase2-run] Stopping wpr ETW -> $etlPath" -ForegroundColor Cyan
        try { & wpr.exe -stop $etlPath } catch { Write-Host "[phase2-run] WARN: wpr -stop failed: $_" -ForegroundColor Yellow }
        $script:wprStarted = $false
    }
    if ($script:procmonStarted -and -not $SkipProcmon) {
        Write-Host "[phase2-run] Stopping Procmon" -ForegroundColor Cyan
        try { & $ProcmonExe /Terminate } catch { Write-Host "[phase2-run] WARN: Procmon /Terminate failed: $_" -ForegroundColor Yellow }
        $script:procmonStarted = $false
    }
}

try {
    Write-Host ""
    Write-Host "===== M13 Phase 2 orchestrator =====" -ForegroundColor Cyan
    Write-Host "  cell:    $CellId"
    Write-Host "  step:    $(if ($Step) { $Step } else { '(interactive)' })"
    Write-Host "  run dir: $runDirWin"
    Write-Host "  log:     $logPath"
    Write-Host ""

    # --- start admin captures ---
    if (-not $SkipProcmon) {
        Write-Host "----- Starting Procmon -> $pmlPath -----" -ForegroundColor Cyan
        Start-Process -FilePath $ProcmonExe `
            -ArgumentList @('/BackingFile', $pmlPath, '/Quiet', '/Minimized', '/AcceptEula') `
            -WindowStyle Minimized
        Start-Sleep -Seconds 2
        $procmonStarted = $true
    } else {
        Write-Host "----- Procmon SKIPPED (-SkipProcmon) -----" -ForegroundColor Yellow
    }

    if (-not $SkipETW) {
        Write-Host "----- Starting wpr ETW (GeneralProfile) -----" -ForegroundColor Cyan
        & wpr.exe -start GeneralProfile -filemode
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[phase2-run] WARN: wpr -start exited $LASTEXITCODE; continuing without ETW" -ForegroundColor Yellow
        } else {
            $wprStarted = $true
        }
    } else {
        Write-Host "----- wpr ETW SKIPPED (-SkipETW) -----" -ForegroundColor Yellow
    }

    # --- invoke WSL bash for cell flow ---
    Write-Host ""
    Write-Host "----- Invoking mm-test-matrix.sh for cell flow -----" -ForegroundColor Cyan

    # Pass MM_PHASE2_ADMIN=1 + MM_PHASE2_RUN_DIR=<wsl-path> through WSLENV so
    # the bash side knows admin-side captures are running and skips its own
    # Procmon / wpr prompts.
    $env:MM_PHASE2_ADMIN   = '1'
    $env:MM_PHASE2_RUN_DIR = $runDirWsl
    $existingWslEnv = $env:WSLENV
    if ($existingWslEnv) {
        $env:WSLENV = "$existingWslEnv:MM_PHASE2_ADMIN/u:MM_PHASE2_RUN_DIR/u"
    } else {
        $env:WSLENV = "MM_PHASE2_ADMIN/u:MM_PHASE2_RUN_DIR/u"
    }

    $bashCmd = "$repoWsl/scripts/mm-test-matrix.sh $CellId"
    if ($Step) { $bashCmd += " $Step" }
    & wsl.exe -e bash -c $bashCmd
    $bashExit = $LASTEXITCODE
    if ($bashExit -ne 0) {
        Write-Host "[phase2-run] mm-test-matrix.sh exited $bashExit" -ForegroundColor Yellow
    }
}
finally {
    Stop-AdminCaptures
    Write-Host ""
    Write-Host "===== Phase 2 cell $CellId run complete =====" -ForegroundColor Green
    Write-Host "  Procmon: $(if ($procmonStarted -or $SkipProcmon) { $pmlPath } else { '(not started)' })"
    Write-Host "  ETW:     $(if ($wprStarted -or $SkipETW) { $etlPath } else { '(not started)' })"
    Write-Host "  Log:     $logPath"
    Write-Host ""
    Write-Host "Per-phase close-out gate (after this cell + before next):"
    Write-Host "  ./scripts/mm-phase1-closeout.sh m13-phase2     # Block 1 + checklist"
    Write-Host "  Then Blocks 2-5 (PSN/plan/playbook/issues/PRD/commit)"
    Stop-Transcript | Out-Null
}
exit 0
