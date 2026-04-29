<#
.SYNOPSIS
    Pulls Microsoft-Windows-Kernel-PnP/Configuration + Microsoft-Windows-UserPnp
    events for the four Apple device instance IDs we care about. All passive.
.OUTPUTS
    pnp-eventlog.{txt,json} in the test-run dir.
#>
[CmdletBinding()]
param(
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF'
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }

# Devices to investigate — exactly the InstanceIDs from the user's XML queries
$targets = @(
    @{ Name = 'v3 BTHENUM HID PDO';  InstanceId = 'BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0323\9&73B8B28&0&D0C050CC8C4D_C00000000' },
    @{ Name = 'v3 HID Mouse child';  InstanceId = 'HID\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0323\A&31E5D054&C&0000' },
    @{ Name = 'v1 BTHENUM HID PDO';  InstanceId = 'BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&000205AC_PID&030D\9&73B8B28&0&04F13EEEDE10_C00000000' },
    @{ Name = 'v1 HID Mouse child';  InstanceId = 'HID\{00001124-0000-1000-8000-00805F9B34FB}_VID&000205AC_PID&030D\A&137E1BF2&2&0000' },
    @{ Name = 'Keyboard BTHENUM PDO'; InstanceId = 'BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&000205AC_PID&0239\9&73B8B28&0&E806884B0741_C00000000' }
)

$allEvents = @()

foreach ($t in $targets) {
    Write-Host "[pnp-evt] $($t.Name) - $($t.InstanceId)"

    # Query 1: Microsoft-Windows-Kernel-PnP/Configuration log
    # Match any event whose EventData has any Data element equal to the instance id
    $xpath = "*[EventData/Data='$($t.InstanceId)']"
    $logName = 'Microsoft-Windows-Kernel-PnP/Configuration'
    try {
        $events = Get-WinEvent -LogName $logName -FilterXPath $xpath -ErrorAction SilentlyContinue -MaxEvents 500
        foreach ($e in $events) {
            $allEvents += [pscustomobject]@{
                Target = $t.Name
                Log = $logName
                TimeCreated = $e.TimeCreated.ToString('o')
                Id = $e.Id
                Provider = $e.ProviderName
                LevelDisplay = $e.LevelDisplayName
                Message = ($e.Message -replace '\s+', ' ').Substring(0, [Math]::Min(800, ($e.Message -replace '\s+', ' ').Length))
            }
        }
    } catch {
        Write-Host "  Kernel-PnP query failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Query 2: System log (UserPnp / Kernel-PnP / Plug & Play events)
    $xpath2 = "*[EventData/Data='$($t.InstanceId)']"
    try {
        $events2 = Get-WinEvent -LogName System -FilterXPath $xpath2 -ErrorAction SilentlyContinue -MaxEvents 500
        foreach ($e in $events2) {
            $allEvents += [pscustomobject]@{
                Target = $t.Name
                Log = 'System'
                TimeCreated = $e.TimeCreated.ToString('o')
                Id = $e.Id
                Provider = $e.ProviderName
                LevelDisplay = $e.LevelDisplayName
                Message = ($e.Message -replace '\s+', ' ').Substring(0, [Math]::Min(800, ($e.Message -replace '\s+', ' ').Length))
            }
        }
    } catch {
        Write-Host "  System log query failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Query 3: System log via UserData/*/DeviceInstanceID — UserPnP events use this nesting
    $xpath3 = "*[UserData/*/DeviceInstanceID='$($t.InstanceId)']"
    try {
        $events3 = Get-WinEvent -LogName System -FilterXPath $xpath3 -ErrorAction SilentlyContinue -MaxEvents 500
        foreach ($e in $events3) {
            $allEvents += [pscustomobject]@{
                Target = $t.Name
                Log = 'System (UserPnp)'
                TimeCreated = $e.TimeCreated.ToString('o')
                Id = $e.Id
                Provider = $e.ProviderName
                LevelDisplay = $e.LevelDisplayName
                Message = ($e.Message -replace '\s+', ' ').Substring(0, [Math]::Min(800, ($e.Message -replace '\s+', ' ').Length))
            }
        }
    } catch {
        Write-Host "  UserPnp query failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Sort by time
$allEvents = $allEvents | Sort-Object TimeCreated

$jsonOut = Join-Path $OutDir 'pnp-eventlog.json'
$txtOut  = Join-Path $OutDir 'pnp-eventlog.txt'
$allEvents | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonOut -Encoding UTF8

# Human-readable
$lines = @()
$lines += "=== PnP event log capture @ $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="
$lines += "Total events: $($allEvents.Count)"
$lines += ""

# Group by target then chronological
foreach ($t in $targets) {
    $lines += ""
    $lines += "### $($t.Name)"
    $lines += "    InstanceId: $($t.InstanceId)"
    $tEvents = $allEvents | Where-Object { $_.Target -eq $t.Name }
    if (-not $tEvents) {
        $lines += "    (no events found)"
        continue
    }
    foreach ($e in $tEvents) {
        $lines += ('  [{0}] [Id={1}] [{2}] {3}' -f $e.TimeCreated, $e.Id, $e.Provider, $e.Message)
    }
}

$lines | Set-Content -Path $txtOut -Encoding UTF8
Write-Host "[pnp-evt] OK -> $jsonOut" -ForegroundColor Green
Write-Host "[pnp-evt] OK -> $txtOut" -ForegroundColor Green
Write-Host "[pnp-evt] events captured: $($allEvents.Count)"
exit 0
