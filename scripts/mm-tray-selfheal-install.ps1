<#
.SYNOPSIS
    Install (or verify) the MagicMouseTray-SelfHeal scheduled task. Phase 4-Ω
    requires admin-context PnP recycle; the tray runs in user context, so it
    delegates the recycle to a pre-registered admin scheduled task and signals
    via the existing C:\mm-dev-queue protocol.

.DESCRIPTION
    Registration steps (admin required, one UAC prompt at install time only):
      1. Create C:\mm-dev-queue\ if missing
      2. Register scheduled task 'MagicMouseTray-SelfHeal'
         - Principal: current user, RunLevel=HighestAvailable
         - Trigger:  none (run on demand via schtasks /run)
         - Action:   powershell.exe -File mm-state-flip.ps1 -Mode AppleFilter

    The tray will trigger this task via Process.Start("schtasks.exe /run") when
    it detects split-mode degradation. mm-state-flip.ps1 -Mode AppleFilter is
    a no-op for LowerFilters (already set) but does fire Disable+Enable, which
    is the recycle.

    Idempotent -- if the task already exists, just verify its principal/action
    match. Does NOT modify the existing MM-Dev-Cycle task (used for dev work).

    NOTE: As an alternative, you can reuse the existing MM-Dev-Cycle task and
    omit this install entirely. The tray's SelfHealRequest already targets
    'MM-Dev-Cycle' by default. Use this script to register a dedicated
    self-heal task if you want to keep dev and self-heal channels separate.

.PARAMETER Reuse
    If set, do nothing -- documents that we're reusing MM-Dev-Cycle. Default.

.PARAMETER Install
    Actually install MagicMouseTray-SelfHeal as a separate task.

.EXAMPLE
    Set-ExecutionPolicy -Scope Process Bypass -Force
    & '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\scripts\mm-tray-selfheal-install.ps1' -Install
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Reuse
)

$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $Reuse -and -not $Install) {
    Write-Host "[selfheal-install] No action requested. Use -Reuse or -Install."
    Write-Host "  -Reuse:   Do nothing; document reuse of MM-Dev-Cycle (recommended)"
    Write-Host "  -Install: Register MagicMouseTray-SelfHeal as a separate task"
    exit 0
}

if ($Reuse) {
    Write-Host "[selfheal-install] Reuse mode: tray will trigger MM-Dev-Cycle for self-heal." -ForegroundColor Cyan
    Write-Host "  Verifying MM-Dev-Cycle task exists..."
    $existing = schtasks.exe /query /tn 'MM-Dev-Cycle' /fo csv 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: MM-Dev-Cycle task not found. Run mm-task-setup.ps1 first or use -Install." -ForegroundColor Red
        exit 1
    }
    Write-Host "  OK: MM-Dev-Cycle exists. No further action needed." -ForegroundColor Green
    Write-Host "  Tray's SelfHealRequest writes to C:\mm-dev-queue\request.txt and triggers MM-Dev-Cycle."
    exit 0
}

# Install path
if (-not (Test-IsAdmin)) {
    Write-Host "[selfheal-install] ERROR: -Install requires admin PowerShell" -ForegroundColor Red
    exit 1
}

# Make sure queue dir exists
$queueDir = 'C:\mm-dev-queue'
if (-not (Test-Path $queueDir)) {
    New-Item -Path $queueDir -ItemType Directory -Force | Out-Null
    Write-Host "[selfheal-install] Created queue dir: $queueDir"
}

$taskName = 'MagicMouseTray-SelfHeal'
$flipScript = 'D:\mm3-driver\scripts\mm-state-flip.ps1'

# Verify the script the task will invoke actually exists
if (-not (Test-Path $flipScript)) {
    Write-Host "[selfheal-install] ERROR: $flipScript not found. Install MM-Dev-Cycle scripts first." -ForegroundColor Red
    exit 2
}

# Build the task XML (mirrors MM-Dev-Cycle structure)
$user = "$env:USERDOMAIN\$env:USERNAME"
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>MagicMouseTray Phase 4-Ω self-heal -- triggers BTHENUM PnP recycle to restore unified mode</Description>
    <URI>\$taskName</URI>
  </RegistrationInfo>
  <Principals>
    <Principal id="Author">
      <UserId>$([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Hidden>true</Hidden>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <StartWhenAvailable>true</StartWhenAvailable>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
  </Settings>
  <Triggers />
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$flipScript" -Mode AppleFilter</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$tmpXml = Join-Path $env:TEMP "$taskName.xml"
[System.IO.File]::WriteAllText($tmpXml, $xml, [System.Text.Encoding]::Unicode)

# Register (or update if exists)
$existing = schtasks.exe /query /tn $taskName /fo csv 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[selfheal-install] Task already exists -- updating"
    schtasks.exe /delete /tn $taskName /f | Out-Null
}

schtasks.exe /create /tn $taskName /xml "$tmpXml" /f
if ($LASTEXITCODE -ne 0) {
    Write-Host "[selfheal-install] ERROR: schtasks /create failed" -ForegroundColor Red
    exit 3
}

Remove-Item $tmpXml -Force -ErrorAction SilentlyContinue

Write-Host "[selfheal-install] OK Registered task '$taskName'" -ForegroundColor Green
Write-Host "  Trigger via: schtasks.exe /run /tn '$taskName'"
exit 0
