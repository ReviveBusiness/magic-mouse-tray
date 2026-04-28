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
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF'
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
$txtOut = Join-Path $OutDir 'bthport-discovery.txt'
$jsonOut = Join-Path $OutDir 'bthport-discovery.json'

# Try both case variants for the device subkey
$candidates = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$Mac",
    "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$($Mac.ToUpper())",
    "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\$Mac",
    "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\$($Mac.ToUpper())"
)

$deviceRoot = $null
foreach ($c in $candidates) {
    if (Test-Path $c) { $deviceRoot = $c; break }
}
if (-not $deviceRoot) {
    Write-Host "[discover] ERROR: no BTHPORT device key found for $Mac" -ForegroundColor Red
    exit 2
}

$lines = @()
$lines += "[discover] Device root: $deviceRoot"
$lines += "[discover] Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""

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

Walk-Key -Path $deviceRoot
Walk-Key -Path "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys\$Mac" -Depth 0

# Also enumerate any SDP/HID-related top-level BT keys for context
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

$lines | Set-Content -Path $txtOut -Encoding UTF8
$entries | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonOut -Encoding UTF8

Write-Host ""
Write-Host "[discover] OK Discovery complete:" -ForegroundColor Green
Write-Host "  Text dump:   $txtOut"
Write-Host "  JSON entries: $jsonOut"
Write-Host "  Any large binary values were saved as blob_*.bin in the same dir."
Write-Host ""
Write-Host "[discover] Entry count: $($entries.Count)"
$bigBlobs = $entries | Where-Object { $_.Size -gt 100 -and $_.Kind -eq 'Binary' }
if ($bigBlobs) {
    Write-Host "[discover] Candidate SDP/HID-cache blobs:" -ForegroundColor Cyan
    $bigBlobs | ForEach-Object {
        Write-Host "  $($_.Size) bytes  $($_.Path)\$($_.Name)"
    }
}
exit 0
