<#
.SYNOPSIS
    Flip Magic Mouse 2024 BTHENUM device between two known states:
      "AppleFilter" - applewirelessmouse in LowerFilters; scroll works, battery N/A.
      "NoFilter"    - applewirelessmouse removed; scroll broken, battery readable.

.DESCRIPTION
    Per PRD-184 + NotebookLM docs (2026-04-26 baseline + 2026-04-27 verification):
      - LowerFilters is read by PnP only on AddDevice (fresh device construction).
      - Reboots reuse existing device object and skip AddDevice -> filter never (re)evaluated.
      - disable+enable forces AddDevice -> rebuilds stack with current LowerFilters value.

    This script edits the LowerFilters MULTI_SZ at:
      HKLM\SYSTEM\CurrentControlSet\Enum\BTHENUM\<HID-class>\<instance>\LowerFilters
    then forces disable+enable. Output state is verified before exit. On failure
    the original LowerFilters value is restored automatically.

.PARAMETER Mode
    Target mode. AppleFilter = scroll path. NoFilter = battery path.

.PARAMETER VerifyOnly
    Just print current LowerFilters + COL02 presence. No mutation.

.EXAMPLE
    .\mm-state-flip.ps1 -Mode NoFilter
    .\mm-state-flip.ps1 -Mode AppleFilter
    .\mm-state-flip.ps1 -VerifyOnly
#>
param(
    [ValidateSet('AppleFilter','NoFilter','VerifyOnly')]
    [string]$Mode = 'VerifyOnly',
    [switch]$VerifyOnly
)

$ErrorActionPreference = 'Stop'
$LogPath = Join-Path $env:LOCALAPPDATA 'mm-state-flip.log'

function Log {
    param([string]$M, [string]$Lvl='INFO')
    $line = "[$(Get-Date -Format 'HH:mm:ss')][$Lvl] $M"
    Add-Content -Path $LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($Lvl -eq 'ERROR') { Write-Host $line -ForegroundColor Red }
    elseif ($Lvl -eq 'OK') { Write-Host $line -ForegroundColor Green }
    else { Write-Host $line }
}

function Get-MagicMouseInstance {
    # Find the BTHENUM HID-class instance for our PID (handles MAC changes).
    $candidates = Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match '^BTHENUM\\\{00001124[^\\]*VID&0001004C_PID&0323' }
    if (-not $candidates) {
        Log "No Magic Mouse 0323 BTHENUM HID instance found" 'ERROR'
        return $null
    }
    $candidates | Select-Object -First 1
}

function Get-LowerFilters {
    param($InstanceId)
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId"
    try {
        return @((Get-ItemProperty $regPath -Name LowerFilters -ErrorAction Stop).LowerFilters)
    } catch { return @() }
}

function Set-LowerFilters {
    param($InstanceId, [string[]]$Value)
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId"
    if ($Value.Count -eq 0) {
        Remove-ItemProperty -Path $regPath -Name LowerFilters -ErrorAction SilentlyContinue
    } else {
        New-ItemProperty -Path $regPath -Name LowerFilters -PropertyType MultiString -Value $Value -Force | Out-Null
    }
}

function Get-Col02Status {
    # Return 'present' / 'missing' based on whether the COL02 vendor TLC is enumerated.
    $col02 = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like '*VID&0001004C_PID&0323&Col02*' -and $_.Status -eq 'OK' }
    if ($col02) { return 'present' } else { return 'missing' }
}

function Disable-EnableDevice {
    param($InstanceId)
    Log "Disabling device: $InstanceId"
    Disable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
    Start-Sleep -Seconds 2
    Log "Enabling device: $InstanceId"
    Enable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
    Start-Sleep -Seconds 4   # let PnP settle
}

# --- Main ---
if (Test-Path $LogPath) { Remove-Item $LogPath -Force }
Log "===== mm-state-flip Mode=$Mode =====" 'OK'

# Admin only required for mutation modes (LowerFilters edit + Disable/Enable-PnpDevice)
if ($Mode -ne 'VerifyOnly' -and -not $VerifyOnly) {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log "Mode=$Mode requires admin (registry edit + PnP disable/enable)" 'ERROR'
        Log "Run from admin PowerShell, or invoke via the MM-Dev-Cycle scheduled task" 'INFO'
        exit 3
    }
}

$dev = Get-MagicMouseInstance
if (-not $dev) { exit 1 }
Log "Device: $($dev.InstanceId)  Status=$($dev.Status)"

$currentLF = Get-LowerFilters -InstanceId $dev.InstanceId
$col02     = Get-Col02Status
Log "Current LowerFilters: $($currentLF -join ',') (count=$($currentLF.Count))"
Log "Current COL02 status: $col02"

if ($Mode -eq 'VerifyOnly' -or $VerifyOnly) {
    $inferredMode = if ($currentLF -contains 'applewirelessmouse') { 'AppleFilter' }
                    elseif ($currentLF -contains 'MagicMouseDriver') { 'CustomFilter' }
                    else { 'NoFilter' }
    Log "Inferred mode: $inferredMode" 'OK'
    exit 0
}

# Compute target LowerFilters
$targetLF = if ($Mode -eq 'AppleFilter') {
    # Add applewirelessmouse if absent
    if ($currentLF -notcontains 'applewirelessmouse') { @($currentLF) + 'applewirelessmouse' } else { $currentLF }
} else {
    # NoFilter - strip applewirelessmouse + MagicMouseDriver
    @($currentLF | Where-Object { $_ -ne 'applewirelessmouse' -and $_ -ne 'MagicMouseDriver' })
}

if ((@($currentLF) -join ',') -eq (@($targetLF) -join ',')) {
    Log "LowerFilters already in target state - only need disable+enable to apply" 'INFO'
} else {
    Log "Setting LowerFilters: $($targetLF -join ',') (count=$($targetLF.Count))"
}

# Save backup, mutate, disable+enable, verify, rollback if broken
$backup = $currentLF
try {
    Set-LowerFilters -InstanceId $dev.InstanceId -Value $targetLF
    Disable-EnableDevice -InstanceId $dev.InstanceId

    $newLF    = Get-LowerFilters -InstanceId $dev.InstanceId
    $newCol02 = Get-Col02Status
    Log "After flip: LowerFilters=$($newLF -join ',') COL02=$newCol02" 'OK'

    # Validate expected outcome
    if ($Mode -eq 'NoFilter' -and $newCol02 -ne 'present') {
        Log "Expected COL02 to appear in NoFilter mode but it is missing - rolling back" 'ERROR'
        Set-LowerFilters -InstanceId $dev.InstanceId -Value $backup
        Disable-EnableDevice -InstanceId $dev.InstanceId
        Log "Rolled back to original LowerFilters" 'INFO'
        exit 2
    }
    Log "Flip successful." 'OK'
    exit 0
} catch {
    Log "Exception: $_  - rolling back" 'ERROR'
    try { Set-LowerFilters -InstanceId $dev.InstanceId -Value $backup } catch { }
    try { Disable-EnableDevice -InstanceId $dev.InstanceId } catch { }
    exit 1
}
