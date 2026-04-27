# mm-task-setup.ps1 — register the SYSTEM scheduled task 'MM-Dev-Cycle'
#
# Run ONCE from an admin PowerShell window. After this:
#   - WSL can trigger any phase via `schtasks /run /tn MM-Dev-Cycle` (NO UAC)
#   - The task runs as SYSTEM (highest privilege, no UAC ever)
#   - mm-dev.sh autodetects the task and uses it
#
# To uninstall: .\mm-task-setup.ps1 -Uninstall
#               (or: schtasks /delete /tn MM-Dev-Cycle /f)

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [string]$TaskName = 'MM-Dev-Cycle',
    [string]$RunnerScript = (Join-Path $PSScriptRoot 'mm-task-runner.ps1')
)

# Self-elevate if not admin
function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host "Not admin - re-launching elevated (accept UAC)..." -ForegroundColor Yellow
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSCommandPath")
    if ($Uninstall) { $args += '-Uninstall' }
    $proc = Start-Process powershell.exe -ArgumentList $args -Verb RunAs -Wait -PassThru
    exit $proc.ExitCode
}

if ($Uninstall) {
    Write-Host "Removing scheduled task '$TaskName'..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Done." -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $RunnerScript)) {
    Write-Host "ERROR: runner script not found: $RunnerScript" -ForegroundColor Red
    exit 1
}

Write-Host "Registering scheduled task '$TaskName'..." -ForegroundColor Cyan
Write-Host "  Runner: $RunnerScript" -ForegroundColor Gray

# On-demand action — fires runner script as SYSTEM with no UI
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$RunnerScript`""

# SYSTEM principal, highest privilege — no UAC, no user session needed
$principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -RunLevel Highest -LogonType ServiceAccount

# Settings: on-demand only, no battery restriction, 30-min timeout, deny concurrent
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
    -MultipleInstances IgnoreNew `
    -DisallowDemandStart:$false `
    -Hidden

Register-ScheduledTask -TaskName $TaskName `
    -Action $action `
    -Principal $principal `
    -Settings $settings `
    -Description 'Magic Mouse driver dev cycle - triggered on demand from WSL via schtasks /run' `
    -Force | Out-Null

# Also create the queue dir + grant SYSTEM write access (it already has it as
# admin, but be explicit so we don't surprise ourselves later)
$queueDir = 'C:\mm-dev-queue'
if (-not (Test-Path $queueDir)) { New-Item -ItemType Directory $queueDir -Force | Out-Null }

Write-Host "Task '$TaskName' registered as SYSTEM." -ForegroundColor Green
Write-Host ""
Write-Host "Verify with:" -ForegroundColor Cyan
Write-Host "  schtasks /query /tn $TaskName" -ForegroundColor White
Write-Host ""
Write-Host "Trigger from WSL or anywhere (no UAC):" -ForegroundColor Cyan
Write-Host "  schtasks /run /tn $TaskName" -ForegroundColor White
Write-Host ""
Write-Host "From WSL (uses the task automatically):" -ForegroundColor Cyan
Write-Host "  ./scripts/mm-dev.sh full" -ForegroundColor White
Write-Host ""
Write-Host "Uninstall:" -ForegroundColor Cyan
Write-Host "  .\mm-task-setup.ps1 -Uninstall" -ForegroundColor White
