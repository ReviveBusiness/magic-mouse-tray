<#
.SYNOPSIS
    Dump Magic Mouse + v1 + Keyboard device container registry trees, full
    contents including Properties\ DEVPKEY GUIDs. Admin-required.
#>
[CmdletBinding()]
param(
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF'
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }

# Container IDs to investigate. The v3 mouse one we know from event logs.
# Find others by enumerating BTHENUM device containers and matching VID/PID.
$bthenumDevs = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Enum\BTHENUM' -ErrorAction SilentlyContinue -Recurse |
    Where-Object { $_.PSChildName -match '04F13EEEDE10|D0C050CC8C4D|E806884B0741' -and $_.PSChildName -match 'C00000000$' }

$containerIds = @{
    'v3-mouse'    = '{fbdb1973-434c-5160-a997-ee1429168abe}'  # from event log
}

# Also discover others from device container property
$allContainers = Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceContainers' -ErrorAction SilentlyContinue
foreach ($c in $allContainers) {
    $props = Join-Path $c.PSPath 'Properties'
    if (-not (Test-Path $props)) { continue }
    # Try to find a friendly name property to identify
    try {
        $namePath = Join-Path $props '{78c34fc8-104a-4aca-9ea4-524d52996e57}\0083'  # DEVPKEY_NAME (well-known)
        if (Test-Path $namePath) {
            $k = Get-Item -LiteralPath $namePath
            $v = $k.GetValue('(Default)')
            if ($v -is [byte[]]) {
                $name = [System.Text.Encoding]::Unicode.GetString($v).TrimEnd([char]0)
                if ($name -match 'Magic Mouse|Magic Keyboard|Trevor') {
                    $containerIds[$name] = $c.PSChildName
                }
            }
        }
    } catch {}
}

Write-Host "[container-dump] containers to dump:"
foreach ($k in $containerIds.Keys) {
    Write-Host "  $k -> $($containerIds[$k])"
}

function Dump-Container {
    param([string]$Name, [string]$ContainerId)
    $root = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceContainers\$ContainerId"
    if (-not (Test-Path $root)) { Write-Host "  WARN: $root not present"; return @() }

    $entries = @()
    $lines = @()
    $lines += "=== Container: $Name ($ContainerId) ==="
    $lines += "Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    function Walk { param([string]$Path, [int]$Depth)
        $indent = '  ' * $Depth
        try { $k = Get-Item -LiteralPath $Path -ErrorAction Stop } catch { $script:lines += "$indent!! $($_.Exception.Message)"; return }
        $relPath = $Path -replace '^.*?DeviceContainers\\\\?',''
        $script:lines += "${indent}KEY: $relPath"
        foreach ($vn in $k.GetValueNames()) {
            $nm = if ($vn -eq '') { '(default)' } else { $vn }
            try {
                $kind = $k.GetValueKind($vn)
                $v = $k.GetValue($vn)
            } catch { continue }
            $rec = @{ Path = $relPath; Name = $nm; Kind = $kind.ToString() }
            if ($v -is [byte[]]) {
                $rec.Size = $v.Length
                $rec.Hex = if ($v.Length -le 256) { (($v | ForEach-Object { '{0:X2}' -f $_ }) -join ' ') } else { (($v[0..255] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ') + '...' }
                # try Unicode decode for REG_SZ-ish blobs (DEVPKEY uses raw bytes)
                if ($kind -eq 'Binary' -and $v.Length -ge 2 -and ($v.Length % 2 -eq 0)) {
                    try {
                        $s = [System.Text.Encoding]::Unicode.GetString($v).TrimEnd([char]0)
                        if ($s -match '^[\x20-\x7E]+$' -and $s.Length -gt 1) { $rec.AsString = $s }
                    } catch {}
                }
                $script:lines += "$indent  $nm ($kind, $($v.Length)b): $($rec.Hex)$(if ($rec.AsString) { ' [str=' + $rec.AsString + ']' })"
            } elseif ($v -is [string[]]) {
                $rec.MultiSz = $v
                $script:lines += "$indent  $nm ($kind): $($v -join ' | ')"
            } elseif ($v -is [string]) {
                $rec.Value = $v
                $script:lines += "$indent  $nm ($kind): $v"
            } elseif ($v -is [int] -or $v -is [long]) {
                $rec.Value = $v
                $script:lines += "$indent  $nm ($kind): $v (0x$('{0:X}' -f $v))"
            } else {
                $rec.Value = "$v"
                $script:lines += "$indent  $nm ($kind): $v"
            }
            $script:entries += [pscustomobject]$rec
        }
        foreach ($sub in $k.GetSubKeyNames()) { Walk -Path "$Path\$sub" -Depth ($Depth + 1) }
    }
    $script:entries = @()
    $script:lines = $lines
    Walk -Path $root -Depth 0
    return @{ Entries = $script:entries; Lines = $script:lines }
}

$summary = @()
foreach ($name in $containerIds.Keys) {
    $cid = $containerIds[$name]
    $result = Dump-Container -Name $name -ContainerId $cid
    if (-not $result) { continue }
    $shortName = ($name -replace '[^A-Za-z0-9]', '_').Trim('_').ToLower()
    $base = Join-Path $OutDir "container-dump-$shortName"
    $result.Lines | Set-Content -Path "$base.txt" -Encoding UTF8
    $result.Entries | ConvertTo-Json -Depth 5 | Set-Content -Path "$base.json" -Encoding UTF8
    Write-Host "  [container-dump] $name -> $base.txt ($($result.Entries.Count) values)"
    $summary += [pscustomobject]@{ Name = $name; ContainerId = $cid; ValueCount = $result.Entries.Count }
}

# Index
$idx = Join-Path $OutDir 'container-dump-index.txt'
$summary | Format-Table -AutoSize | Out-String | Set-Content -Path $idx -Encoding UTF8
Write-Host "[container-dump] OK -> $idx" -ForegroundColor Green
exit 0
