<#
.SYNOPSIS
    Admin service control for E1/E2 (Stop-Service applewirelessmouse + restart).
    Requires admin (called via MM-Dev-Cycle queue).
.PARAMETER Action
    Stop | Start | Status
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Stop','Start','Status')]
    [string]$Action,
    [string]$ServiceName = 'applewirelessmouse',
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF'
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }

$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$logFile = Join-Path $OutDir 'svc-control.log'

function Append-Log { param([string]$m) "[$ts] $m" | Add-Content -Path $logFile -Encoding UTF8 }

switch ($Action) {
    'Stop' {
        try {
            Stop-Service $ServiceName -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            $svc = Get-Service $ServiceName
            Append-Log "STOP via Stop-Service $ServiceName status=$($svc.Status)"
            Write-Host "[svc-ctrl] stopped via Stop-Service: $($svc.Status)"
        } catch {
            Append-Log "Stop-Service FAILED for $ServiceName : $($_.Exception.Message) ; trying sc.exe"
            Write-Host "[svc-ctrl] Stop-Service failed; trying sc.exe stop"
            $output = & sc.exe stop $ServiceName 2>&1
            Append-Log "sc.exe stop output: $($output -join '|')"
            Write-Host "[svc-ctrl] sc.exe output:"
            $output | ForEach-Object { Write-Host "  $_" }
            Start-Sleep -Seconds 2
            $svc = Get-Service $ServiceName -ErrorAction SilentlyContinue
            $drv = Get-CimInstance Win32_SystemDriver -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
            Append-Log "after sc.exe: svc=$($svc.Status) drv=$($drv.State)"
            Write-Host "[svc-ctrl] post sc.exe: svc=$($svc.Status) drv=$($drv.State)"
            if ($drv.State -ne 'Stopped') { exit 1 }
        }
    }
    'Start' {
        try {
            Start-Service $ServiceName -ErrorAction Stop
            Start-Sleep -Seconds 2
            $svc = Get-Service $ServiceName
            Append-Log "START $ServiceName status=$($svc.Status)"
            Write-Host "[svc-ctrl] started: $($svc.Status)"
        } catch {
            Append-Log "START_FAILED $ServiceName : $($_.Exception.Message)"
            Write-Host "[svc-ctrl] START FAILED: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    'Status' {
        $svc = Get-Service $ServiceName -ErrorAction SilentlyContinue
        if ($svc) {
            Append-Log "STATUS $ServiceName = $($svc.Status)"
            Write-Host "[svc-ctrl] status: $($svc.Status)"
        } else {
            Append-Log "STATUS $ServiceName = NOT_REGISTERED"
            Write-Host "[svc-ctrl] not registered"
        }
    }
}

# Also check loaded driver state via Win32_SystemDriver
$drv = Get-CimInstance Win32_SystemDriver -Filter "Name='$ServiceName'" -ErrorAction SilentlyContinue
if ($drv) {
    Append-Log "DRV $ServiceName state=$($drv.State) started=$($drv.Started)"
    Write-Host "[svc-ctrl] driver state=$($drv.State) started=$($drv.Started)"
}
exit 0
