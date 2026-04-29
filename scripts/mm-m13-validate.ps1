<#
.SYNOPSIS
    M13 Phase 4 validation -- atomic admin-context operations invoked by
    mm-task-runner.ps1 via the M13:<Subcommand> phase prefix.

.DESCRIPTION
    Subcommands (one per invocation, ~5 sec each):
      READ                  -- dump current state (LF, SS, COL02, hid-probe-equivalent)
      DISABLE_SUSPEND       -- set SelectiveSuspendEnabled=0 on BT HID + recycle device
      ENABLE_SUSPEND        -- set SelectiveSuspendEnabled=1 (default) + recycle device
      RECYCLE               -- disable+enable BTHENUM HID device (force AddDevice)

    Output goes to %TEMP%\mm-m13-validate-<timestamp>-<subcommand>.json so WSL
    can pick it up via /mnt/c/Users/<user>/AppData/Local/Temp/.

.PARAMETER Subcommand
    Operation to perform.

.EXAMPLE
    # via mm-task-runner queue -- request file content:
    M13:READ|<nonce>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('READ','DISABLE_SUSPEND','ENABLE_SUSPEND','RECYCLE')]
    [string]$Subcommand
)

$ErrorActionPreference = 'Continue'
$Timestamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
$OutDir = $env:TEMP
$OutPath = Join-Path $OutDir ("mm-m13-validate-${Timestamp}-${Subcommand}.json")

# Index file -- WSL polls this to know latest result
$IndexPath = Join-Path $OutDir 'mm-m13-validate-latest.txt'

function Get-MagicMouseInstance {
    Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match '^BTHENUM\\\{00001124[^\\]*VID&0001004C_PID&0323' } |
        Select-Object -First 1
}

function Get-LowerFiltersValue {
    param($InstanceId)
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId"
    try {
        return @((Get-ItemProperty $regPath -Name LowerFilters -ErrorAction Stop).LowerFilters)
    } catch { return @() }
}

function Get-SelectiveSuspendValue {
    param($InstanceId)
    $dpPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId\Device Parameters"
    if (-not (Test-Path $dpPath)) { return $null }
    $candidates = @('SelectiveSuspendEnabled','DeviceSelectiveSuspended','EnableSelectiveSuspend','SelectiveSuspendOn','IdleEnable')
    $vals = @{}
    foreach ($n in $candidates) {
        try {
            $v = (Get-ItemProperty -Path $dpPath -Name $n -ErrorAction Stop).$n
            $vals[$n] = $v
        } catch {}
    }
    return $vals
}

function Set-SelectiveSuspend {
    param($InstanceId, [int]$Value)
    $dpPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$InstanceId\Device Parameters"
    if (-not (Test-Path $dpPath)) {
        New-Item -Path $dpPath -Force | Out-Null
    }
    Set-ItemProperty -Path $dpPath -Name 'SelectiveSuspendEnabled' -Value $Value -Type DWord -Force
    return @{ path = $dpPath; written = $Value }
}

function Get-Col02Status {
    $col02 = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like '*VID&0001004C_PID&0323&Col02*' }
    if (-not $col02) { return @{ present = $false; status = 'absent' } }
    return @{ present = $true; status = $col02.Status; instance = $col02.InstanceId }
}

function Get-HidPaths {
    Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like '*VID&0001004C_PID&0323*' } |
        Select-Object Status, Class, FriendlyName, InstanceId
}

function Recycle-Device {
    param($InstanceId)
    $log = @()
    try {
        $log += "Disabling $InstanceId"
        Disable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 3
        $log += "Enabling $InstanceId"
        Enable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 5
        $log += "Recycle complete"
        return @{ success = $true; log = $log }
    } catch {
        $log += "FAIL: $_"
        return @{ success = $false; log = $log; error = "$_" }
    }
}

# === Build common state snapshot ===
$dev = Get-MagicMouseInstance
$result = [pscustomobject]@{
    captured_at = (Get-Date).ToString('o')
    subcommand = $Subcommand
    device_found = $dev -ne $null
    instance_id = if ($dev) { $dev.InstanceId } else { $null }
    device_status = if ($dev) { "$($dev.Status)" } else { $null }
    lower_filters_before = if ($dev) { Get-LowerFiltersValue $dev.InstanceId } else { @() }
    selective_suspend_before = if ($dev) { Get-SelectiveSuspendValue $dev.InstanceId } else { @{} }
    col02_before = Get-Col02Status
    hid_paths_before = Get-HidPaths
    actions = @()
    lower_filters_after = $null
    selective_suspend_after = $null
    col02_after = $null
    hid_paths_after = $null
    success = $true
    error = $null
}

if (-not $dev) {
    $result.success = $false
    $result.error = 'BTHENUM HID instance for Magic Mouse 0x0323 not found'
    $result | ConvertTo-Json -Depth 8 | Set-Content $OutPath -Encoding UTF8
    Set-Content -Path $IndexPath -Value $OutPath -Encoding UTF8
    exit 1
}

# === Dispatch subcommand ===
try {
    switch ($Subcommand) {
        'READ' {
            $result.actions += 'read-only state snapshot'
        }
        'DISABLE_SUSPEND' {
            $result.actions += "Set SelectiveSuspendEnabled=0 on $($dev.InstanceId)"
            $r = Set-SelectiveSuspend -InstanceId $dev.InstanceId -Value 0
            $result.actions += "wrote $($r.path) = $($r.written)"
            $result.actions += 'recycling device to apply policy'
            $rc = Recycle-Device -InstanceId $dev.InstanceId
            $result.actions += $rc.log
            if (-not $rc.success) {
                $result.success = $false
                $result.error = $rc.error
            }
        }
        'ENABLE_SUSPEND' {
            $result.actions += "Set SelectiveSuspendEnabled=1 on $($dev.InstanceId)"
            $r = Set-SelectiveSuspend -InstanceId $dev.InstanceId -Value 1
            $result.actions += "wrote $($r.path) = $($r.written)"
            $result.actions += 'recycling device to apply policy'
            $rc = Recycle-Device -InstanceId $dev.InstanceId
            $result.actions += $rc.log
            if (-not $rc.success) {
                $result.success = $false
                $result.error = $rc.error
            }
        }
        'RECYCLE' {
            $result.actions += 'recycle BTHENUM device (no policy change)'
            $rc = Recycle-Device -InstanceId $dev.InstanceId
            $result.actions += $rc.log
            if (-not $rc.success) {
                $result.success = $false
                $result.error = $rc.error
            }
        }
    }

    # Re-read state after action
    $devAfter = Get-MagicMouseInstance
    if ($devAfter) {
        $result.lower_filters_after = Get-LowerFiltersValue $devAfter.InstanceId
        $result.selective_suspend_after = Get-SelectiveSuspendValue $devAfter.InstanceId
    }
    $result.col02_after = Get-Col02Status
    $result.hid_paths_after = Get-HidPaths
} catch {
    $result.success = $false
    $result.error = "$_"
}

# Write JSON output + update index
$result | ConvertTo-Json -Depth 8 | Set-Content $OutPath -Encoding UTF8
Set-Content -Path $IndexPath -Value $OutPath -Encoding UTF8

if ($result.success) { exit 0 } else { exit 1 }
