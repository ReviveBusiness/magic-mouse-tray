<#
.SYNOPSIS
    M13 Phase 3 helper -- discover where the BTHPORT cache for a Magic Mouse
    actually lives. The plan assumed CachedServices\00010000 exists but Cell 1
    showed it doesn't; this script enumerates the entire device subtree and
    dumps every value found, so we can see the actual schema.

.PARAMETER Mac
    Mouse MAC. Default = d0c050cc8c4d.

.EXAMPLE
    Set-ExecutionPolicy -Scope Process Bypass -Force
    & '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\scripts\mm-bthport-discover.ps1'

    Output goes to .ai/test-runs/2026-04-27-154930-T-V3-AF/bthport-discovery.txt
#>
[CmdletBinding()]
param(
    [string]$Mac = 'd0c050cc8c4d',
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF',
    [switch]$AllDevices
)

$ErrorActionPreference = 'Continue'

function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
    Write-Host "[discover] ERROR: must run from admin PowerShell" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }

$lines = @()
$entries = @()

function Walk-Key {
    param([string]$Path, [int]$Depth = 0)
    $indent = '  ' * $Depth
    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    } catch {
        $script:lines += "${indent}!! could not open: $Path -- $_"
        return
    }
    $script:lines += "${indent}KEY: $($key.PSPath -replace 'Microsoft.PowerShell.Core\\Registry::','')"

    foreach ($vn in $key.GetValueNames()) {
        $vname = if ($vn -eq '') { '(default)' } else { $vn }
        $vdata = $key.GetValue($vn)
        $vtype = $key.GetValueKind($vn)
        $size = if ($vdata -is [byte[]]) { $vdata.Length } elseif ($vdata -is [string[]]) { ($vdata -join ',').Length } elseif ($vdata) { $vdata.ToString().Length } else { 0 }
        $script:lines += "${indent}  VAL: $vname (kind=$vtype size=$size)"
        $script:entries += [pscustomobject]@{
            Path = $key.PSPath -replace 'Microsoft.PowerShell.Core\\Registry::',''
            Name = $vname
            Kind = $vtype.ToString()
            Size = $size
            Hex = if ($vdata -is [byte[]] -and $vdata.Length -le 4096) { ($vdata | ForEach-Object { '{0:X2}' -f $_ }) -join ' ' } else { $null }
            String = if ($vdata -is [string]) { $vdata } elseif ($vdata -is [string[]]) { ($vdata -join ' | ') } elseif ($vdata -is [int]) { '{0} (0x{0:X})' -f $vdata } else { $null }
        }
        if ($vdata -is [byte[]] -and $vdata.Length -le 1024) {
            # show first 256 bytes
            $hex = ''
            $maxShow = [Math]::Min(256, $vdata.Length)
            for ($i = 0; $i -lt $maxShow; $i++) {
                if ($i % 16 -eq 0) { $hex += ('{0}    ' + '{1:X4}: ') -f "`n", $i }
                $hex += ('{0:X2} ' -f $vdata[$i])
            }
            $script:lines += "${indent}    BYTES: $hex"
        } elseif ($vdata -is [byte[]]) {
            $script:lines += "${indent}    BYTES: ($size bytes -- too large to inline; saved as binary)"
            # Save big blobs to disk separately
            $safeName = ($vn -replace '[^A-Za-z0-9_-]', '_')
            $blobName = (Split-Path -Leaf $key.Name) + "_${safeName}.bin"
            $blobPath = Join-Path $OutDir "blob_$blobName"
            [System.IO.File]::WriteAllBytes($blobPath, $vdata)
            $script:lines += "${indent}    -> $blobPath"
        } elseif ($vdata -is [string]) {
            $script:lines += "${indent}    STR: $vdata"
        } elseif ($vdata -is [int]) {
            $script:lines += "${indent}    INT: {0} (0x{0:X})" -f $vdata
        } elseif ($vdata -is [long]) {
            $script:lines += "${indent}    LONG: {0} (0x{0:X})" -f $vdata
        } elseif ($vdata -is [string[]]) {
            $script:lines += "${indent}    MULTI_SZ: $($vdata -join ' | ')"
        }
    }

    foreach ($sub in $key.GetSubKeyNames()) {
        Walk-Key -Path "$Path\$sub" -Depth ($Depth + 1)
    }
}

function Find-DeviceRoot {
    param([string]$DevMac)
    $cands = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$DevMac",
        "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$($DevMac.ToUpper())"
    )
    foreach ($c in $cands) { if (Test-Path $c) { return $c } }
    return $null
}

function Discover-OneDevice {
    param([string]$DevMac, [string]$OutFileBase)
    $script:lines = @()
    $script:entries = @()
    $root = Find-DeviceRoot -DevMac $DevMac
    if (-not $root) {
        Write-Host "[discover] ERROR: no BTHPORT device key found for $DevMac" -ForegroundColor Red
        return $false
    }
    $script:lines += "[discover] Device root: $root"
    $script:lines += "[discover] Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $script:lines += ""
    Walk-Key -Path $root
    Walk-Key -Path "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\$DevMac" -Depth 0

    $txtOut = "$OutFileBase.txt"
    $jsonOut = "$OutFileBase.json"
    $script:lines | Set-Content -Path $txtOut -Encoding UTF8
    $script:entries | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonOut -Encoding UTF8
    Write-Host "[discover] $DevMac -> $txtOut ($($script:entries.Count) entries)"
    return $true
}

if ($AllDevices) {
    $siblings = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices" -ErrorAction SilentlyContinue
    Write-Host "[discover] AllDevices mode: $($siblings.Count) paired BT device(s) found"
    $summary = @()
    foreach ($sib in $siblings) {
        $devMac = $sib.PSChildName
        $base = Join-Path $OutDir "bthport-discovery-$devMac"
        $ok = Discover-OneDevice -DevMac $devMac -OutFileBase $base
        if ($ok) {
            # also extract the FriendlyName/Name + VID/PID from the device key for the index
            try {
                $devKey = Get-Item $sib.PSPath
                $nameBytes = $devKey.GetValue('Name', $null)
                $name = if ($nameBytes -is [byte[]]) {
                    ([System.Text.Encoding]::UTF8.GetString($nameBytes)).TrimEnd([char]0)
                } else { '' }
                $devVid = $devKey.GetValue('VID', $null)
                $devPid = $devKey.GetValue('PID', $null)
                $cachedHasBlob = $false
                $cs = Join-Path $sib.PSPath 'CachedServices'
                if (Test-Path $cs) {
                    $csk = Get-Item $cs
                    if ($csk.GetValueNames().Count -gt 0) { $cachedHasBlob = $true }
                }
                $summary += [pscustomobject]@{
                    Mac = $devMac
                    Name = $name
                    VID = if ($null -ne $devVid) { '0x{0:X4}' -f $devVid } else { '' }
                    PID = if ($null -ne $devPid) { '0x{0:X4}' -f $devPid } else { '' }
                    HasCachedBlob = $cachedHasBlob
                    OutFile = "bthport-discovery-$devMac.txt"
                }
            } catch {
                Write-Host "  WARN: could not summarize $devMac : $_" -ForegroundColor Yellow
            }
        }
    }
    $idx = Join-Path $OutDir 'bthport-discovery-index.txt'
    $summary | Format-Table -AutoSize | Out-String | Set-Content -Path $idx -Encoding UTF8
    Write-Host ""
    Write-Host "[discover] OK All-devices discovery complete -- index: $idx" -ForegroundColor Green
    $summary | Format-Table -AutoSize
    exit 0
}

# Single-device path (default, for backwards compat)
$root = Find-DeviceRoot -DevMac $Mac
if (-not $root) {
    Write-Host "[discover] ERROR: no BTHPORT device key found for $Mac" -ForegroundColor Red
    exit 2
}
$script:lines += "[discover] Device root: $root"
$script:lines += "[discover] Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$script:lines += ""
Walk-Key -Path $root
Walk-Key -Path "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\$Mac" -Depth 0

$lines += ""
$lines += "=== Sibling devices (for comparison) ==="
$siblings = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices" -ErrorAction SilentlyContinue
foreach ($sib in $siblings) {
    $lines += "  device: $($sib.PSChildName)"
    $cs = Join-Path $sib.PSPath "CachedServices"
    if (Test-Path $cs) {
        $cskey = Get-Item $cs
        $lines += "    CachedServices values: $($cskey.GetValueNames() -join ',')"
        $lines += "    CachedServices subkeys: $($cskey.GetSubKeyNames() -join ',')"
    } else {
        $lines += "    (no CachedServices)"
    }
}

$txtOut = Join-Path $OutDir 'bthport-discovery.txt'
$jsonOut = Join-Path $OutDir 'bthport-discovery.json'
$lines | Set-Content -Path $txtOut -Encoding UTF8
$entries | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonOut -Encoding UTF8

Write-Host ""
Write-Host "[discover] OK Discovery complete: $txtOut" -ForegroundColor Green
Write-Host "[discover] Entry count: $($entries.Count)"
exit 0
