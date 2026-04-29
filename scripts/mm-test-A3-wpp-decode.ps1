# Test A3: WPP TMF decode of existing BTHPORT ETL capture
# Pure read-only operations: download PDBs from Microsoft public symbol server,
# extract TMF from each, render existing ETL with tracefmt. No state change,
# no reboot, no service touch.
[CmdletBinding()]
param(
    [string]$OutDir = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\.ai\test-runs\2026-04-27-154930-T-V3-AF',
    [string]$EtlPath = ''
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $OutDir)) { New-Item -Path $OutDir -ItemType Directory -Force | Out-Null }

$id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object System.Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'ERROR: must run as administrator (ETL files have restrictive ACLs)' -ForegroundColor Red
    exit 1
}

$symchk    = 'F:\Program Files\Windows Kits\10\Debuggers\x64\symchk.exe'
$tracepdb  = 'F:\Program Files\Windows Kits\10\bin\10.0.26100.0\x64\tracepdb.exe'
$tracefmt  = 'F:\Program Files\Windows Kits\10\bin\10.0.26100.0\x64\tracefmt.exe'
foreach ($t in $symchk, $tracepdb, $tracefmt) {
    if (-not (Test-Path $t)) { Write-Host "ERROR: tool missing: $t" -ForegroundColor Red; exit 2 }
}

$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$symRoot = 'C:\m13-symbols'
$tmfDir  = 'C:\m13-tmf'
$decodedTxt = Join-Path $OutDir "test-A3-wpp-decoded-$ts.txt"
$summaryMd  = Join-Path $OutDir "test-A3-wpp-decoded-$ts-summary.md"
New-Item -ItemType Directory -Path $symRoot -Force | Out-Null
New-Item -ItemType Directory -Path $tmfDir -Force | Out-Null

# Find ETL to decode
if (-not $EtlPath) {
    $etl = Get-ChildItem 'C:\m13-etw-*\capture.etl' -ErrorAction SilentlyContinue |
           Sort-Object LastWriteTime -Descending |
           Select-Object -First 1
    if (-not $etl) {
        Write-Host 'ERROR: no ETL found in C:\m13-etw-*' -ForegroundColor Red
        exit 3
    }
    $EtlPath = $etl.FullName
}
Write-Host ("ETL to decode: $EtlPath")
$etlSize = (Get-Item $EtlPath).Length
Write-Host ("Size: $([math]::Round($etlSize/1MB,2)) MB")

# Step 1 -- download PDBs from Microsoft public symbol server
$env:_NT_SYMBOL_PATH = "SRV*$symRoot*https://msdl.microsoft.com/download/symbols"
$drivers = @(
    'C:\Windows\System32\drivers\bthport.sys',
    'C:\Windows\System32\drivers\bthusb.sys',
    'C:\Windows\System32\drivers\hidclass.sys'
)
foreach ($drv in $drivers) {
    Write-Host ("`nFetching PDB for $drv ...")
    $out = & $symchk /v $drv 2>&1
    Write-Host (($out | Select-Object -First 5) -join "`n")
}

# Step 2 -- locate the downloaded PDBs and extract TMF
$pdbs = Get-ChildItem -Path $symRoot -Filter '*.pdb' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in 'bthport.pdb','bthusb.pdb','hidclass.pdb' }
Write-Host ("`nPDBs found: $($pdbs.Count)")
foreach ($p in $pdbs) {
    Write-Host ("  " + $p.FullName + " (" + [math]::Round($p.Length/1MB,2) + " MB)")
}

if ($pdbs.Count -eq 0) {
    Write-Host 'No PDBs downloaded. Decoding may yield no WPP messages.' -ForegroundColor Yellow
} else {
    foreach ($p in $pdbs) {
        Write-Host ("`nExtracting TMF from $($p.Name) ...")
        $tmfSubDir = Join-Path $tmfDir ($p.BaseName)
        New-Item -ItemType Directory -Path $tmfSubDir -Force | Out-Null
        $rpt = & $tracepdb -f $p.FullName -p $tmfSubDir 2>&1
        $rpt | Select-Object -First 5 | ForEach-Object { Write-Host ("  " + $_) }
        $tmfCount = (Get-ChildItem $tmfSubDir -Filter '*.tmf' -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host ("  TMF files extracted: $tmfCount")
    }
}

# Step 3 -- run tracefmt against the ETL with all TMF directories
Write-Host ("`nRunning tracefmt against $EtlPath ...")
$tmfArgs = @()
if (Test-Path $tmfDir) {
    Get-ChildItem $tmfDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $tmfArgs += '-p'
        $tmfArgs += $_.FullName
    }
}
$tracefmtArgs = @($EtlPath, '-o', $decodedTxt) + $tmfArgs + @('-r', $tmfDir, '-displayonly')
Write-Host ('tracefmt args: ' + ($tracefmtArgs -join ' '))
$rpt = & $tracefmt @tracefmtArgs 2>&1
$rpt | Select-Object -First 20 | ForEach-Object { Write-Host ("  " + $_) }

if (Test-Path $decodedTxt) {
    $decodedSize = (Get-Item $decodedTxt).Length
    Write-Host ("`nDecoded output: $decodedTxt ($([math]::Round($decodedSize/1MB,2)) MB)")
} else {
    Write-Host ("`nWARN: decoded output not produced") -ForegroundColor Yellow
    # fallback: tracefmt without TMF args (will emit raw bytes)
    $rpt2 = & $tracefmt $EtlPath -o $decodedTxt -displayonly 2>&1
    $rpt2 | Select-Object -First 5 | ForEach-Object { Write-Host ("  " + $_) }
}

# Step 4 -- grep summary
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Test A3 -- WPP TMF decode of BTHPORT/HIDCLASS ETL') | Out-Null
$lines.Add('') | Out-Null
$lines.Add('Captured: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) | Out-Null
$lines.Add('Source ETL: ' + $EtlPath) | Out-Null
$lines.Add('Decoded text: ' + $decodedTxt) | Out-Null
$lines.Add('') | Out-Null

if (Test-Path $decodedTxt) {
    $lines.Add('## Total decoded lines: ' + ((Get-Content $decodedTxt | Measure-Object).Count)) | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## v3 MAC (D0C050CC8C4D / 4D8CCC50C0D0) hits') | Out-Null
    $lines.Add('') | Out-Null
    $macHits = Get-Content $decodedTxt | Select-String -Pattern 'D0C050CC8C4D|4D8CCC50C0D0|D0:C0:50|D0 C0 50'
    $lines.Add('Total: ' + (($macHits | Measure-Object).Count)) | Out-Null
    if ($macHits) {
        $lines.Add('First 10 samples:') | Out-Null
        $macHits | Select-Object -First 10 | ForEach-Object {
            $sample = [string]$_.Line
            if ($sample.Length -gt 250) { $sample = $sample.Substring(0, 250) }
            $lines.Add('  ' + $sample) | Out-Null
        }
    }
    $lines.Add('') | Out-Null

    $lines.Add('## ReportID 0x90 (vendor battery) signature in HID payloads') | Out-Null
    $rid90 = Get-Content $decodedTxt | Select-String -Pattern 'A1[ ]?90|ReportID.*0x90|RID=0x90|RID 90'
    $lines.Add('Total: ' + (($rid90 | Measure-Object).Count)) | Out-Null
    if ($rid90) {
        $lines.Add('First 10 samples:') | Out-Null
        $rid90 | Select-Object -First 10 | ForEach-Object {
            $sample = [string]$_.Line
            if ($sample.Length -gt 250) { $sample = $sample.Substring(0, 250) }
            $lines.Add('  ' + $sample) | Out-Null
        }
    }
    $lines.Add('') | Out-Null

    $lines.Add('## ReportID 0x47 (standard battery) signature') | Out-Null
    $rid47 = Get-Content $decodedTxt | Select-String -Pattern 'A1[ ]?47|ReportID.*0x47|RID=0x47'
    $lines.Add('Total: ' + (($rid47 | Measure-Object).Count)) | Out-Null
    $lines.Add('') | Out-Null

    $lines.Add('## Connection handle 0x032 / 0x32 references (v3 mouse handle inferred earlier)') | Out-Null
    $h032 = Get-Content $decodedTxt | Select-String -Pattern 'handle.*0x032|handle.*0x32|connection.*0x32|HCI_HANDLE.*32'
    $lines.Add('Total: ' + (($h032 | Measure-Object).Count)) | Out-Null
    $lines.Add('') | Out-Null

    $lines.Add('## Battery / BAT keywords') | Out-Null
    $bat = Get-Content $decodedTxt | Select-String -Pattern 'battery|BAT_|charging|AbsoluteState' -CaseSensitive:$false
    $lines.Add('Total: ' + (($bat | Measure-Object).Count)) | Out-Null
    if ($bat) {
        $lines.Add('First 10 samples:') | Out-Null
        $bat | Select-Object -First 10 | ForEach-Object {
            $sample = [string]$_.Line
            if ($sample.Length -gt 250) { $sample = $sample.Substring(0, 250) }
            $lines.Add('  ' + $sample) | Out-Null
        }
    }
}

$lines | Set-Content $summaryMd -Encoding UTF8
Write-Host ("`nSummary: $summaryMd")
Write-Host 'DONE'
exit 0
