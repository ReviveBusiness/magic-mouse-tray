<#
.SYNOPSIS
    Pause (or resume) Windows Update via the same registry mechanism the Settings
    UI uses. Used as M13 Phase 0.1 — prevents mid-test driver swaps during the
    cleanup + capture + hypothesis-test phases.

.DESCRIPTION
    Writes Pause* keys under HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings.
    Reversible at any time with -Resume.

    Default pause = 7 days, matching the M13 plan's expected duration.

.PARAMETER Days
    Pause duration in days (default 7). Maximum 35 (Windows enforces this).

.PARAMETER Resume
    Clear all Pause* keys, immediately resuming Windows Update.

.EXAMPLE
    .\mm-pause-windows-update.ps1               # pause 7 days
    .\mm-pause-windows-update.ps1 -Days 14      # pause 14 days
    .\mm-pause-windows-update.ps1 -Resume       # resume immediately
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateRange(1,35)][int]$Days = 7,
    [switch]$Resume
)

$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
    Write-Host "[pause-wu] ERROR: must run from admin PowerShell" -ForegroundColor Red
    exit 1
}

$reg  = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
$keys = @(
    'PauseUpdatesExpiryTime',
    'PauseFeatureUpdatesStartTime',
    'PauseFeatureUpdatesEndTime',
    'PauseQualityUpdatesStartTime',
    'PauseQualityUpdatesEndTime'
)

if ($Resume) {
    Write-Host "[pause-wu] Resuming Windows Update..." -ForegroundColor Cyan
    if (-not (Test-Path $reg)) {
        Write-Host "  ... nothing to clear (key path missing)" -ForegroundColor Gray
        exit 0
    }
    foreach ($n in $keys) {
        if ($PSCmdlet.ShouldProcess("$reg\$n", "Remove-ItemProperty")) {
            Remove-ItemProperty -Path $reg -Name $n -ErrorAction SilentlyContinue
        }
    }
    Write-Host "[pause-wu] OK Windows Update pause cleared" -ForegroundColor Green
    exit 0
}

# --- pause path ---
$now  = Get-Date
$end  = $now.AddDays($Days)
$nowS = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$endS = $end.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

Write-Host "[pause-wu] Pausing Windows Update for $Days day(s) -> $endS UTC" -ForegroundColor Cyan

if ($PSCmdlet.ShouldProcess($reg, "Set Pause* keys for $Days days")) {
    if (-not (Test-Path $reg)) { New-Item -Path $reg -Force | Out-Null }
    Set-ItemProperty -Path $reg -Name 'PauseUpdatesExpiryTime'       -Value $endS -Type String
    Set-ItemProperty -Path $reg -Name 'PauseFeatureUpdatesStartTime' -Value $nowS -Type String
    Set-ItemProperty -Path $reg -Name 'PauseFeatureUpdatesEndTime'   -Value $endS -Type String
    Set-ItemProperty -Path $reg -Name 'PauseQualityUpdatesStartTime' -Value $nowS -Type String
    Set-ItemProperty -Path $reg -Name 'PauseQualityUpdatesEndTime'   -Value $endS -Type String
}

# verify
if (-not $WhatIfPreference) {
    $expiry = (Get-ItemProperty -Path $reg -Name 'PauseUpdatesExpiryTime' -ErrorAction SilentlyContinue).PauseUpdatesExpiryTime
    if ($expiry -eq $endS) {
        Write-Host "[pause-wu] OK Verified: PauseUpdatesExpiryTime = $expiry" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "[pause-wu] FAIL Verification: expected $endS, got '$expiry'" -ForegroundColor Red
        exit 2
    }
}
