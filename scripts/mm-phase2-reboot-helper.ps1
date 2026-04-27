<#
.SYNOPSIS
    M13 Phase 2 reboot helper -- stops captures cleanly before reboot, restarts
    + runs test-3 + stops cleanly after reboot. One command per phase.

.DESCRIPTION
    Run from your admin PS. Two modes:

    prereboot:
      1. Stops wpr ETW (saves the trace cleanly to .etl)
      2. Terminates Procmon (flushes the .PML)
      3. Renames captures to *-pre-reboot.{PML,etl}
      4. Tells you what to do next (ENTER on bash + reboot)

    postreboot:
      1. Starts fresh Procmon and wpr
      2. Invokes mm-test-matrix.sh <cell> test-3 from WSL
      3. Stops wpr + Procmon cleanly
      4. Renames new captures to *-post-reboot.{PML,etl}

    The cell run dir is auto-discovered from the marker file
    (.ai/test-runs/.current-<CellId>) so you don't have to type the timestamp.

.PARAMETER Phase
    'prereboot' or 'postreboot'.

.PARAMETER CellId
    Test cell ID, e.g. T-V3-AF.

.EXAMPLE
    # Before rebooting (from your existing admin PS):
    & '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\scripts\mm-phase2-reboot-helper.ps1' prereboot T-V3-AF

    # After reboot + login + ~30s mouse reconnect (from a new admin PS):
    & '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\scripts\mm-phase2-reboot-helper.ps1' postreboot T-V3-AF
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('prereboot','postreboot')]
    [string]$Phase,
    [Parameter(Mandatory=$true, Position=1)]
    [string]$CellId
)

$ErrorActionPreference = 'Stop'

# --- self-elevate check ---
function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
    Write-Host "[reboot-helper] ERROR: must run from admin PowerShell" -ForegroundColor Red
    exit 1
}

try {
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop
} catch { }

# --- resolve run dir from marker ---
$scriptsDir = $PSScriptRoot
$repoWin    = Split-Path -Parent $scriptsDir
$markerWin  = Join-Path $repoWin ".ai\test-runs\.current-$CellId"

if (-not (Test-Path $markerWin)) {
    Write-Host "[reboot-helper] ERROR: no run dir marker at $markerWin" -ForegroundColor Red
    Write-Host "  Did you start the cell with mm-test-matrix.sh first?" -ForegroundColor Yellow
    exit 2
}

$runDirWsl = (Get-Content $markerWin -Raw).Trim()
$runDirWin = (& wsl.exe -e wslpath -w "$runDirWsl" 2>$null) -replace '\s+$',''
if (-not $runDirWin) {
    Write-Host "[reboot-helper] ERROR: could not resolve Windows path for $runDirWsl" -ForegroundColor Red
    exit 3
}

$pmlPath = Join-Path $runDirWin "procmon.PML"
$etlPath = Join-Path $runDirWin "etw-trace.etl"
$ProcmonExe = "C:\Users\Lesley\AppData\Local\Microsoft\WindowsApps\Procmon.exe"

Write-Host ""
Write-Host "===== Phase 2 reboot helper ($Phase, $CellId) =====" -ForegroundColor Cyan
Write-Host "  run dir: $runDirWin"
Write-Host ""

# ---------------------------------------------------------------------------
# PREREBOOT MODE
# ---------------------------------------------------------------------------
if ($Phase -eq 'prereboot') {
    # 1. Stop wpr (CRITICAL: trace data is in kernel buffer, lost if we don't -stop)
    Write-Host "[1/3] Stopping wpr ETW -> $etlPath" -ForegroundColor Cyan
    & wpr.exe -stop $etlPath 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARN: wpr -stop returned $LASTEXITCODE (was wpr running?)" -ForegroundColor Yellow
    }
    Start-Sleep -Seconds 3

    # 2. Stop Procmon (flushes .PML)
    Write-Host "[2/3] Terminating Procmon" -ForegroundColor Cyan
    if (Get-Process Procmon* -ErrorAction SilentlyContinue) {
        & $ProcmonExe /Terminate 2>&1 | ForEach-Object { Write-Host "  $_" }
        Start-Sleep -Seconds 3
    } else {
        Write-Host "  (no Procmon process found -- nothing to stop)" -ForegroundColor Yellow
    }

    # 3. Rename pre-reboot captures
    Write-Host "[3/3] Renaming pre-reboot captures" -ForegroundColor Cyan
    if (Test-Path $pmlPath) {
        $newPml = Join-Path $runDirWin "procmon-pre-reboot.PML"
        Move-Item $pmlPath $newPml -Force
        $sz = [math]::Round((Get-Item $newPml).Length / 1MB, 1)
        Write-Host "  -> $newPml ($sz MB)"
    } else {
        Write-Host "  (no procmon.PML to rename)" -ForegroundColor Yellow
    }
    if (Test-Path $etlPath) {
        $newEtl = Join-Path $runDirWin "etw-trace-pre-reboot.etl"
        Move-Item $etlPath $newEtl -Force
        $sz = [math]::Round((Get-Item $newEtl).Length / 1MB, 1)
        Write-Host "  -> $newEtl ($sz MB)"
    } else {
        Write-Host "  (no etw-trace.etl to rename)" -ForegroundColor Yellow
    }

    # 4. Save the postreboot command somewhere user can find it after reboot.
    #    Set-ExecutionPolicy bypass is required because UNC-loaded scripts
    #    are treated as unsigned/untrusted in a fresh PS process.
    $cheatPath = "$env:USERPROFILE\Desktop\m13-phase2-resume.txt"
    $resumeCmd = "Set-ExecutionPolicy -Scope Process Bypass -Force; & '$PSCommandPath' postreboot $CellId"
    @"
M13 Phase 2 -- resume after reboot

After Windows finishes booting + you log in + wait ~30s for the mouse to
reconnect (verify scroll works manually first), open a NEW admin PowerShell
and paste this single line:

    $resumeCmd

This will start fresh Procmon + wpr captures, run test-3 in WSL, then stop
the captures and rename them to *-post-reboot.{PML,etl}.

Cell run dir: $runDirWin
"@ | Set-Content -Path $cheatPath -Encoding UTF8

    Write-Host ""
    Write-Host "===== Pre-reboot done -- captures saved =====" -ForegroundColor Green
    Write-Host ""
    Write-Host "Resume instructions saved to:" -ForegroundColor Cyan
    Write-Host "  $cheatPath"
    Write-Host ""
    Write-Host "NEXT, in this order:" -ForegroundColor Yellow
    Write-Host "  1. Switch to your WSL bash terminal and press ENTER on the reboot prompt"
    Write-Host "  2. Reboot Windows (Start > Power > Restart)"
    Write-Host "  3. After login + ~30s mouse-reconnect, open a NEW admin PS and paste:"
    Write-Host ""
    Write-Host "       $resumeCmd" -ForegroundColor Green
    Write-Host ""
    exit 0
}

# ---------------------------------------------------------------------------
# POSTREBOOT MODE
# ---------------------------------------------------------------------------
if ($Phase -eq 'postreboot') {
    # 1. Start fresh Procmon
    Write-Host "[1/4] Starting Procmon -> $pmlPath" -ForegroundColor Cyan
    Start-Process -FilePath $ProcmonExe `
        -ArgumentList @('/BackingFile', $pmlPath, '/Quiet', '/Minimized', '/AcceptEula') `
        -WindowStyle Minimized
    Start-Sleep -Seconds 3
    if (-not (Get-Process Procmon* -ErrorAction SilentlyContinue)) {
        Write-Host "  WARN: Procmon process not detected after launch" -ForegroundColor Yellow
    } else {
        Write-Host "  -> Procmon running"
    }

    # 2. Start fresh wpr
    Write-Host "[2/4] Starting wpr ETW (GeneralProfile)" -ForegroundColor Cyan
    & wpr.exe -start GeneralProfile -filemode 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  WARN: wpr -start returned $LASTEXITCODE -- continuing without ETW" -ForegroundColor Yellow
    }

    # 3. Invoke WSL test-3
    Write-Host ""
    Write-Host "[3/4] Running mm-test-matrix.sh $CellId test-3 in WSL" -ForegroundColor Cyan
    Write-Host "  (when prompted, perform the post-reboot scroll/click test)"
    Write-Host ""
    $repoWsl = (& wsl.exe -e wslpath -u "$repoWin" 2>$null) -replace '\s+$',''
    $env:MM_PHASE2_ADMIN = '1'
    $env:WSLENV = if ($env:WSLENV) { "$($env:WSLENV):MM_PHASE2_ADMIN/u" } else { "MM_PHASE2_ADMIN/u" }
    & wsl.exe -e bash -c "$repoWsl/scripts/mm-test-matrix.sh $CellId test-3"

    # 4. Stop captures + rename
    Write-Host ""
    Write-Host "[4/4] Stopping captures + renaming as *-post-reboot.*" -ForegroundColor Cyan
    & wpr.exe -stop $etlPath 2>&1 | ForEach-Object { Write-Host "  $_" }
    Start-Sleep -Seconds 3
    if (Get-Process Procmon* -ErrorAction SilentlyContinue) {
        & $ProcmonExe /Terminate 2>&1 | ForEach-Object { Write-Host "  $_" }
        Start-Sleep -Seconds 3
    }
    if (Test-Path $pmlPath) {
        $newPml = Join-Path $runDirWin "procmon-post-reboot.PML"
        Move-Item $pmlPath $newPml -Force
        $sz = [math]::Round((Get-Item $newPml).Length / 1MB, 1)
        Write-Host "  -> $newPml ($sz MB)"
    }
    if (Test-Path $etlPath) {
        $newEtl = Join-Path $runDirWin "etw-trace-post-reboot.etl"
        Move-Item $etlPath $newEtl -Force
        $sz = [math]::Round((Get-Item $newEtl).Length / 1MB, 1)
        Write-Host "  -> $newEtl ($sz MB)"
    }

    Write-Host ""
    Write-Host "===== Cell $CellId complete =====" -ForegroundColor Green
    Write-Host ""
    Write-Host "Captures saved:" -ForegroundColor Cyan
    Get-ChildItem $runDirWin -Filter "*reboot*" | Format-Table Name, @{Name='MB';Expression={[math]::Round($_.Length/1MB,1)}}, LastWriteTime -AutoSize | Out-Host
    Write-Host ""
    Write-Host "Per-phase close-out gate (next step):"
    Write-Host "  wsl ./scripts/mm-phase1-closeout.sh m13-phase2"
    Write-Host ""

    # Clean up the resume cheat-sheet from desktop
    $cheatPath = "$env:USERPROFILE\Desktop\m13-phase2-resume.txt"
    if (Test-Path $cheatPath) { Remove-Item $cheatPath -Force }

    exit 0
}
