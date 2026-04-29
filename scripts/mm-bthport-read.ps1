<#
.SYNOPSIS
    M13 Phase 3 -- read and decode the BTHPORT SDP cache for the Magic Mouse,
    extract the embedded HID descriptor, decode it item-by-item.

.DESCRIPTION
    Reads HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\
    <mac>\CachedServices\00010000 (REG_BINARY -- the SDP record blob HidBth
    uses to enumerate the HID device on the BT side).

    Then:
      1. Parses the outer SDP TLV (DataElement SEQUENCE)
      2. Walks attribute records, locates attribute ID 0x0206 (HIDDescriptorList)
      3. Inside, finds the framing 08 22 25 NN where NN is descriptor byte count
      4. Extracts the embedded HID descriptor bytes
      5. Decodes the HID descriptor item-by-item per the HID 1.11 spec
      6. Outputs JSON + a human-readable summary

    NO writes. NO mutations. Read-only. Safe to run anytime.

    Requires admin PS to read the BTHPORT\Parameters\Devices subtree.

.PARAMETER Mac
    Mouse MAC address (12-hex-chars, no separators). Default = d0c050cc8c4d
    (the Magic Mouse 2024 paired on this host).

.PARAMETER OutputDir
    Where to drop the JSON + decoded markdown. Defaults to the current cell
    run dir if MM_CELL_RUN_DIR is set, otherwise %TEMP%.

.EXAMPLE
    Set-ExecutionPolicy -Scope Process Bypass -Force
    & '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\scripts\mm-bthport-read.ps1'
#>
[CmdletBinding()]
param(
    [string]$Mac = 'd0c050cc8c4d',
    [string]$OutputDir = ''
)

$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
    Write-Host "[bthport-read] ERROR: must run from admin PowerShell" -ForegroundColor Red
    exit 1
}

# --- output dir ---
if (-not $OutputDir) {
    if ($env:MM_CELL_RUN_DIR) {
        $OutputDir = $env:MM_CELL_RUN_DIR
    } else {
        $OutputDir = $env:TEMP
    }
}
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}

$jsonPath = Join-Path $OutputDir "bthport-cache-decoded.json"
$mdPath   = Join-Path $OutputDir "bthport-cache-decoded.md"
$rawPath  = Join-Path $OutputDir "bthport-cache-raw.bin"

# --- read the REG_BINARY ---
$macUpper = $Mac.ToUpper()
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$macUpper\CachedServices\00010000"
Write-Host "[bthport-read] Reading $regPath" -ForegroundColor Cyan

$blob = $null
try {
    $blob = (Get-ItemProperty -Path $regPath -Name '(default)' -ErrorAction Stop)."(default)"
} catch {
    # Try the (default) value via different name access
    try {
        $key = Get-Item $regPath -ErrorAction Stop
        $blob = $key.GetValue('')
    } catch {
        Write-Host "[bthport-read] ERROR: could not read $regPath" -ForegroundColor Red
        Write-Host "  $_" -ForegroundColor Red
        # Try lowercase mac as fallback
        $regPathLower = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$Mac\CachedServices\00010000"
        Write-Host "  Trying lowercase: $regPathLower" -ForegroundColor Yellow
        try {
            $key = Get-Item $regPathLower -ErrorAction Stop
            $blob = $key.GetValue('')
        } catch {
            Write-Host "[bthport-read] FAIL on both case variants. Listing CachedServices subkey contents..." -ForegroundColor Red
            $devicesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices"
            if (Test-Path $devicesPath) {
                Get-ChildItem $devicesPath | ForEach-Object {
                    Write-Host "  device: $($_.PSChildName)"
                    $cs = Join-Path $_.PSPath "CachedServices"
                    if (Test-Path $cs) {
                        Get-ChildItem $cs | ForEach-Object { Write-Host "    cache: $($_.PSChildName)" }
                    }
                }
            }
            exit 2
        }
    }
}

if (-not $blob -or $blob.Length -eq 0) {
    Write-Host "[bthport-read] ERROR: blob is empty or null" -ForegroundColor Red
    exit 3
}

Write-Host "[bthport-read] OK: read $($blob.Length) bytes" -ForegroundColor Green

# Save raw binary for offline analysis
[System.IO.File]::WriteAllBytes($rawPath, [byte[]]$blob)
Write-Host "[bthport-read] Raw blob -> $rawPath" -ForegroundColor Cyan

# --- SDP TLV parser ---
# SDP DataElement format: 1-byte header (TYPE | SIZE_INDEX), variable-length data
# Type values: 0=Nil, 1=UInt, 2=Int, 3=UUID, 4=String, 5=Bool, 6=Sequence, 7=Alt, 8=URL
# Size index 0..4 = fixed sizes 1/2/4/8/16; 5=1-byte len follows; 6=2-byte len; 7=4-byte len

function Read-SdpDE {
    param(
        [byte[]]$Buf,
        [ref]$Pos
    )
    $start = $Pos.Value
    if ($start -ge $Buf.Length) { return $null }
    $hdr = $Buf[$start]
    $type = ($hdr -shr 3) -band 0x1F
    $sizeIdx = $hdr -band 0x07
    $Pos.Value = $start + 1

    $dataLen = 0
    switch ($sizeIdx) {
        0 { if ($type -eq 0) { $dataLen = 0 } else { $dataLen = 1 } }
        1 { $dataLen = 2 }
        2 { $dataLen = 4 }
        3 { $dataLen = 8 }
        4 { $dataLen = 16 }
        5 {
            $dataLen = $Buf[$Pos.Value]
            $Pos.Value += 1
        }
        6 {
            $dataLen = ([int]$Buf[$Pos.Value] -shl 8) -bor [int]$Buf[$Pos.Value+1]
            $Pos.Value += 2
        }
        7 {
            $dataLen = ([int]$Buf[$Pos.Value] -shl 24) -bor ([int]$Buf[$Pos.Value+1] -shl 16) -bor ([int]$Buf[$Pos.Value+2] -shl 8) -bor [int]$Buf[$Pos.Value+3]
            $Pos.Value += 4
        }
    }

    $dataStart = $Pos.Value
    $dataEnd = $dataStart + $dataLen
    $Pos.Value = $dataEnd

    return @{
        Type = $type
        SizeIdx = $sizeIdx
        DataStart = $dataStart
        DataEnd = $dataEnd
        DataLen = $dataLen
        HeaderStart = $start
    }
}

# --- find HIDDescriptorList attribute (0x0206) and extract embedded descriptor ---
$bytes = [byte[]]$blob
$pos = 0

# Outer container is typically a SEQUENCE of attribute records
$outer = Read-SdpDE -Buf $bytes -Pos ([ref]$pos)
Write-Host "[bthport-read] outer DE: type=$($outer.Type) sizeIdx=$($outer.SizeIdx) dataLen=$($outer.DataLen)" -ForegroundColor Cyan

# Inside the outer SEQUENCE: pairs of (UInt16 attribute ID, value)
# We scan for attribute ID 0x0206
$endOfOuter = $outer.DataEnd
$pos = $outer.DataStart

$hidDescriptorBytes = $null
$attrLog = @()

while ($pos -lt $endOfOuter) {
    $attrIdDE = Read-SdpDE -Buf $bytes -Pos ([ref]$pos)
    if (-not $attrIdDE) { break }
    if ($attrIdDE.Type -ne 1 -or $attrIdDE.DataLen -ne 2) {
        # not a 2-byte UInt -- unexpected, skip
        $attrLog += "  skipped DE type=$($attrIdDE.Type) at $($attrIdDE.HeaderStart)"
        continue
    }
    $attrId = ([int]$bytes[$attrIdDE.DataStart] -shl 8) -bor [int]$bytes[$attrIdDE.DataStart + 1]
    $valueDE = Read-SdpDE -Buf $bytes -Pos ([ref]$pos)
    $attrLog += "  attr 0x{0:X4} type={1} sizeIdx={2} dataLen={3}" -f $attrId, $valueDE.Type, $valueDE.SizeIdx, $valueDE.DataLen

    if ($attrId -eq 0x0206) {
        # HIDDescriptorList: SEQUENCE of SEQUENCE of (DescriptorType UInt8, DescriptorData String)
        # Inside: 35 LL (sequence) 35 LL (inner seq) 08 22 25 NN ... where 22=descriptor type Report
        # Actually format per HID-over-BT spec:
        #   HIDDescriptorList = SEQUENCE of HIDDescriptor
        #   HIDDescriptor     = SEQUENCE of { DescriptorType (UInt8 = 0x22 for Report Descriptor), DescriptorData (String) }
        # Encoded SDP: outer seq -> inner seq -> 0x08 0x22 (UInt8 type 0x22), 0x25 0xNN (String len NN), <NN bytes>

        # Walk into the value sequence
        $innerPos = $valueDE.DataStart
        $innerEnd = $valueDE.DataEnd

        while ($innerPos -lt $innerEnd) {
            $hidDescDE = Read-SdpDE -Buf $bytes -Pos ([ref]$innerPos)
            if (-not $hidDescDE) { break }
            # hidDescDE should be a SEQUENCE (type 6)
            if ($hidDescDE.Type -eq 6) {
                # Walk into it: typeDE then dataDE
                $hpos = $hidDescDE.DataStart
                $hend = $hidDescDE.DataEnd
                $typeDE = Read-SdpDE -Buf $bytes -Pos ([ref]$hpos)
                $dataDE = Read-SdpDE -Buf $bytes -Pos ([ref]$hpos)
                if ($typeDE.Type -eq 1 -and $typeDE.DataLen -eq 1) {
                    $descType = $bytes[$typeDE.DataStart]
                    if ($descType -eq 0x22) {
                        # this is a Report Descriptor
                        $descBytes = New-Object byte[] $dataDE.DataLen
                        [Array]::Copy($bytes, $dataDE.DataStart, $descBytes, 0, $dataDE.DataLen)
                        $hidDescriptorBytes = $descBytes
                        $attrLog += "    -> found HID Report Descriptor at offset $($dataDE.DataStart), $($dataDE.DataLen) bytes"
                    }
                }
            }
        }
    }
}

if (-not $hidDescriptorBytes) {
    Write-Host "[bthport-read] WARN: HIDDescriptorList (attr 0x0206) not found OR no Report Descriptor inside" -ForegroundColor Yellow
    Write-Host "Attribute scan log:" -ForegroundColor Yellow
    $attrLog | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
}

# --- HID Descriptor item decoder (HID 1.11 spec) ---
# Items have a 1-byte header: bSize (lo 2 bits) | bType (next 2) | bTag (top 4)
# bSize encoding: 0->0 bytes, 1->1 byte, 2->2 bytes, 3->4 bytes
# Long item: header byte = 0xFE (rare); we don't decode those

function Decode-HidDescriptor {
    param([byte[]]$Desc)

    $items = @()
    $pos = 0
    $depth = 0
    $usagePage = 0
    $reportId = 0
    $logicalMin = 0
    $logicalMax = 0
    $reportSize = 0
    $reportCount = 0

    $tagNames = @{
        # Main items (bType=0)
        '0_8' = 'Input'; '0_9' = 'Output'; '0_A' = 'Collection'; '0_B' = 'Feature'; '0_C' = 'EndCollection'
        # Global items (bType=1)
        '1_0' = 'UsagePage'; '1_1' = 'LogicalMin'; '1_2' = 'LogicalMax'; '1_3' = 'PhysicalMin'
        '1_4' = 'PhysicalMax'; '1_5' = 'UnitExponent'; '1_6' = 'Unit'; '1_7' = 'ReportSize'
        '1_8' = 'ReportID'; '1_9' = 'ReportCount'; '1_A' = 'Push'; '1_B' = 'Pop'
        # Local items (bType=2)
        '2_0' = 'Usage'; '2_1' = 'UsageMin'; '2_2' = 'UsageMax'; '2_3' = 'DesignatorIdx'
        '2_4' = 'DesignatorMin'; '2_5' = 'DesignatorMax'; '2_7' = 'StringIdx'
        '2_8' = 'StringMin'; '2_9' = 'StringMax'; '2_A' = 'Delimiter'
    }

    while ($pos -lt $Desc.Length) {
        $hdr = $Desc[$pos]
        if ($hdr -eq 0xFE) {
            # Long item -- skip
            $longSize = $Desc[$pos+1]
            $pos += 3 + $longSize
            continue
        }
        $bSize = $hdr -band 0x03
        $bType = ($hdr -shr 2) -band 0x03
        $bTag  = ($hdr -shr 4) -band 0x0F
        $dataLen = if ($bSize -eq 3) { 4 } else { $bSize }

        $dataValue = 0
        for ($i = 0; $i -lt $dataLen; $i++) {
            $dataValue = $dataValue -bor ([int]$Desc[$pos + 1 + $i] -shl ($i * 8))
        }
        # Sign-extend for signed contexts (LogicalMin/Max can be negative)
        $signedValue = $dataValue
        if ($dataLen -gt 0 -and ($Desc[$pos + $dataLen] -band 0x80)) {
            # Could be negative; we'll let JSON serialize as-is
        }

        $itemKey = "$bType`_$([Convert]::ToString($bTag,16).ToUpper())"
        $name = $tagNames[$itemKey]
        if (-not $name) { $name = "Unknown(bType=$bType,bTag=$bTag)" }

        # Collection start increments depth, EndCollection decrements
        if ($name -eq 'Collection') { $depth += 1 }
        if ($name -eq 'EndCollection') { $depth -= 1 }

        # Track key state for human-friendly readout
        if ($name -eq 'UsagePage') { $usagePage = $dataValue }
        if ($name -eq 'ReportID') { $reportId = $dataValue }
        if ($name -eq 'LogicalMin') { $logicalMin = $dataValue }
        if ($name -eq 'LogicalMax') { $logicalMax = $dataValue }
        if ($name -eq 'ReportSize') { $reportSize = $dataValue }
        if ($name -eq 'ReportCount') { $reportCount = $dataValue }

        $hex = ('{0:X2}' -f $hdr)
        for ($i = 0; $i -lt $dataLen; $i++) {
            $hex += ' {0:X2}' -f $Desc[$pos + 1 + $i]
        }

        $items += [pscustomobject]@{
            Offset = $pos
            Hex = $hex
            BType = $bType
            BTag = $bTag
            BSize = $bSize
            Tag = $name
            Data = $dataValue
            Depth = $depth
            UsagePageContext = $usagePage
            ReportIdContext = $reportId
        }
        $pos += 1 + $dataLen
    }
    return $items
}

$decoded = $null
if ($hidDescriptorBytes) {
    $decoded = Decode-HidDescriptor -Desc $hidDescriptorBytes
}

# --- emit JSON ---
$result = [pscustomobject]@{
    captured_at = (Get-Date).ToString('o')
    mac = $Mac
    registry_path = $regPath
    blob_size_bytes = $blob.Length
    hid_descriptor_size_bytes = if ($hidDescriptorBytes) { $hidDescriptorBytes.Length } else { 0 }
    hid_descriptor_hex = if ($hidDescriptorBytes) { ($hidDescriptorBytes | ForEach-Object { '{0:X2}' -f $_ }) -join ' ' } else { $null }
    decoded_items = $decoded
    sdp_attribute_log = $attrLog
}
$result | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

# --- emit human-readable markdown ---
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# BTHPORT cache decoded -- $Mac")
$md.Add("")
$md.Add("**Captured:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
$md.Add("")
$md.Add("**Registry path:** ``$regPath``")
$md.Add("")
$md.Add("**Blob size:** $($blob.Length) bytes")
$md.Add("")
$md.Add("**HID descriptor size:** $(if ($hidDescriptorBytes) { $hidDescriptorBytes.Length } else { 0 }) bytes")
$md.Add("")
if ($hidDescriptorBytes) {
    $md.Add("## HID descriptor (raw hex)")
    $md.Add("")
    $md.Add('```')
    $hexLines = @()
    for ($i = 0; $i -lt $hidDescriptorBytes.Length; $i += 16) {
        $line = '{0:X4}: ' -f $i
        for ($j = 0; $j -lt 16 -and ($i + $j) -lt $hidDescriptorBytes.Length; $j++) {
            $line += ('{0:X2} ' -f $hidDescriptorBytes[$i + $j])
        }
        $hexLines += $line
    }
    $md.AddRange($hexLines)
    $md.Add('```')
    $md.Add("")
}
$md.Add("## Decoded HID descriptor items")
$md.Add("")
$md.Add("| Off | Hex | Tag | Data | UsagePageCtx | ReportIDCtx | Depth |")
$md.Add("|---|---|---|---|---|---|---|")
foreach ($item in $decoded) {
    $line = "| {0} | ``{1}`` | {2} | 0x{3:X} ({3}) | 0x{4:X} | 0x{5:X} | {6} |" -f $item.Offset, $item.Hex, $item.Tag, $item.Data, $item.UsagePageContext, $item.ReportIdContext, $item.Depth
    $md.Add($line)
}
$md.Add("")
$md.Add("## SDP attribute log")
$md.Add("")
$md.Add('```')
$md.AddRange($attrLog)
$md.Add('```')
$md.Add("")
$md.Add("## Wheel usage check (the M13 question)")
$md.Add("")
$wheelItems = $decoded | Where-Object { $_.Tag -eq 'Usage' -and $_.UsagePageContext -eq 1 -and $_.Data -eq 0x38 }
if ($wheelItems) {
    $md.Add("**WHEEL USAGE PRESENT** in cached descriptor at offset(s): " + (($wheelItems | ForEach-Object { $_.Offset }) -join ', '))
} else {
    $md.Add("**WHEEL USAGE ABSENT** -- no Usage=0x0038 (Wheel) on Generic Desktop page (0x01) found in the cached descriptor.")
}
$md.Add("")
$acpanItems = $decoded | Where-Object { $_.Tag -eq 'Usage' -and $_.UsagePageContext -eq 0x0C -and $_.Data -eq 0x238 }
if ($acpanItems) {
    $md.Add("**AC-PAN USAGE PRESENT** in cached descriptor at offset(s): " + (($acpanItems | ForEach-Object { $_.Offset }) -join ', '))
} else {
    $md.Add("**AC-PAN USAGE ABSENT** -- no Usage=0x0238 (AC Pan) on Consumer page (0x0C) found.")
}
$md.Add("")
$col02Items = $decoded | Where-Object { $_.Tag -eq 'UsagePage' -and $_.Data -eq 0xFF00 }
if ($col02Items) {
    $md.Add("**VENDOR PAGE 0xFF00 PRESENT** in cached descriptor (likely COL02 battery TLC) at offset(s): " + (($col02Items | ForEach-Object { $_.Offset }) -join ', '))
} else {
    $md.Add("**VENDOR PAGE 0xFF00 ABSENT** -- no UsagePage=0xFF00 found.")
}

$md -join "`n" | Set-Content -Path $mdPath -Encoding UTF8

Write-Host ""
Write-Host "[bthport-read] OK Outputs:" -ForegroundColor Green
Write-Host "  raw blob:     $rawPath"
Write-Host "  JSON decoded: $jsonPath"
Write-Host "  MD report:    $mdPath"
Write-Host ""
Write-Host "[bthport-read] Headline:" -ForegroundColor Cyan
if ($wheelItems) {
    Write-Host "  WHEEL USAGE PRESENT in cache (Agent A's mechanism likely correct)" -ForegroundColor Green
} else {
    Write-Host "  WHEEL USAGE ABSENT in cache (Agent C's mechanism likely correct)" -ForegroundColor Yellow
}
exit 0
