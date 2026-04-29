<#
.SYNOPSIS
    Magic Utilities Trial Capture — preserves a complete snapshot of an installed
    Magic Utilities (paid 3rd-party Apple Magic Mouse driver) deployment during
    its 28-day free trial, in case we ever need to reinstall just the kernel
    driver later (without the userland app/service).

.DESCRIPTION
    This is a LAST-RESORT preservation capture. The user may never use it. But if
    Magic Utilities ever goes unavailable (vendor disappears, driver yanked from
    distribution, etc.), this snapshot may allow re-installation of the
    Microsoft-WHQL-signed kernel driver via `pnputil /add-driver`.

    What this script captures (in strict order — fail-closed; partial backups
    are deleted):

      a. Driver package directory (DriverStore FileRepository)
      b. Active driver binary + catalog (System32\drivers\MagicMouse.sys + .cat)
      c. Userland install tree (C:\Program Files\MagicUtilities\)
      d. Full registry exports (.reg files) for HKLM software, services,
         driver database, PnP lockdown, MSI installer products, custom bus enum
      e. Per-user registry (HKCU\Software\MagicUtilities\) if present
      f. PnP topology snapshot (Get-PnpDevice JSON dump)
      g. DEVPKEY dump for v1/v3 BTHENUM PDOs (LowerFilters, Service, etc.)
      h. Service config for MagicMouse + MagicUtilitiesService (sc qc/qdescription)
      i. File dependencies of MagicMouse.sys (Win32_PnPSignedDriver)
      j. README.md documenting capture date, version, trial dates, restore steps,
         caveats, and license terms

.NOTES
    LICENSE CAVEAT
    --------------
    Magic Utilities is paid commercial software. Redistributing the captured
    files outside the bounds of its EULA is NOT authorized. This capture is for
    PERSONAL PRESERVATION ONLY. Do not share, publish, upload, or otherwise
    distribute the contents of the output directory.

    EMPIRICAL CAVEAT
    ----------------
    The kernel-mode driver MagicMouse.sys may or may not function correctly
    without the userland MagicUtilitiesService running. This has not been tested.
    The capture preserves both kernel + userland so future-you has options.

    RESTORE SEQUENCE (DO NOT RUN BLINDLY — read README.md first)
    ------------------------------------------------------------
        # 1. Verify capture integrity
        sha256sum -c manifest.txt

        # 2. Re-stage driver package into DriverStore + install
        pnputil /add-driver "<capture>\driver-package\magicmouse.inf" /install

        # 3. (Optional) Re-import service registry keys if pnputil didn't
        reg import "<capture>\registry\hklm-services-magicmouse.reg"

        # 4. Reboot, then re-pair the Magic Mouse via Bluetooth Settings.

    REQUIREMENTS
    ------------
      - Windows 11
      - PowerShell 5.1+ (default on Win11)
      - Administrator elevation
      - ~2 GB free space on D: drive
      - Magic Utilities currently installed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputRoot = 'D:\Backups'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference   = 'Continue'

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
$script:DriverStoreGlobs  = @(
    'C:\Windows\System32\DriverStore\FileRepository\magicmouse.inf_amd64_*',
    'C:\Windows\System32\DriverStore\FileRepository\magickeyboard.inf_amd64_*',
    'C:\Windows\System32\DriverStore\FileRepository\magictrackpad.inf_amd64_*'
)
# Back-compat single glob for code paths that haven't been refactored yet
$script:DriverStoreGlob   = $script:DriverStoreGlobs[0]
$script:DriverBinaryGlob  = 'C:\Windows\System32\drivers\Magic*.sys'
$script:DriverBinaryPath  = 'C:\Windows\System32\drivers\MagicMouse.sys'
$script:DriverCatalogGlob = 'C:\Windows\System32\drivers\Magic*.cat'
$script:ProgramFilesPath  = 'C:\Program Files\MagicUtilities'
$script:RequiredFreeBytes = 2GB

# Custom bus / device class GUIDs documented in the Magic Utilities footprint
$script:CustomBusInterfaceGuid = '{7D55502A-2C87-441F-9993-0761990E0C7A}'
$script:CustomBusDeviceClassGuid = '{fae1ef32-137e-485e-8d89-95d0d3bd8479}'

# Registry keys to export (key path -> output filename)
$script:RegExports = @(
    @{ Key = 'HKLM\SOFTWARE\MagicUtilities';                                                                File = 'hklm-software-magicutilities.reg' }
    @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Services\MagicMouse';                                           File = 'hklm-services-magicmouse.reg' }
    @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Services\MagicUtilitiesService';                                File = 'hklm-services-magicutilitiesservice.reg' }
    @{ Key = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\PnpLockdownFiles';                       File = 'hklm-pnp-lockdown-files.reg' }
    @{ Key = 'HKCU\Software\MagicUtilities';                                                                File = 'hkcu-software-magicutilities.reg'; Optional = $true }
)

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Gray
}

function Write-Ok {
    param([string]$Message)
    Write-Host "    [OK] $Message" -ForegroundColor Green
}

function Write-Warn2 {
    param([string]$Message)
    Write-Host "    [WARN] $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "    [FAIL] $Message" -ForegroundColor Red
}

# -----------------------------------------------------------------------------
# Pre-flight
# -----------------------------------------------------------------------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-MagicUtilitiesInstalled {
    $anyDriverPkg = $false
    foreach ($g in $script:DriverStoreGlobs) {
        if (Test-Path $g) { $anyDriverPkg = $true; break }
    }
    $anyMagicSys = (@(Get-ChildItem -Path $script:DriverBinaryGlob -ErrorAction SilentlyContinue).Count -gt 0)
    $checks = @{
        'Driver INF (DriverStore, any Magic*)' = $anyDriverPkg
        'Driver binary (Magic*.sys)' = $anyMagicSys
        'Program Files tree'         = (Test-Path $script:ProgramFilesPath)
        'HKLM\SOFTWARE\MagicUtilities' = (Test-Path 'HKLM:\SOFTWARE\MagicUtilities')
    }
    $missing = @()
    foreach ($k in $checks.Keys) {
        if ($checks[$k]) {
            Write-Info "$k : present"
        } else {
            Write-Warn2 "$k : MISSING"
            $missing += $k
        }
    }
    return ($missing.Count -eq 0)
}

function Get-MagicUtilitiesVersion {
    $candidates = @(
        (Join-Path $script:ProgramFilesPath 'Service\MagicUtilities_Service.exe'),
        (Join-Path $script:ProgramFilesPath 'MagicUtilities.exe')
    )
    foreach ($exe in $candidates) {
        if (Test-Path $exe) {
            try {
                $vi = (Get-Item $exe).VersionInfo
                if ($vi.FileVersion) { return $vi.FileVersion }
                if ($vi.ProductVersion) { return $vi.ProductVersion }
            } catch {
                # fall through
            }
        }
    }
    return 'unknown'
}

function Get-TrialExpiryRaw {
    # Captured AS-IS — obfuscated 8 bytes. We do NOT decode.
    $val = $null
    try {
        $val = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\MagicUtilities\App' -Name 'TrialExpiryDate' -ErrorAction Stop).TrialExpiryDate
    } catch {
        return 'not-present'
    }
    if ($null -eq $val) { return 'not-present' }
    if ($val -is [byte[]]) {
        return ($val | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
    }
    return [string]$val
}

# -----------------------------------------------------------------------------
# Capture functions
# -----------------------------------------------------------------------------
function Copy-WithManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$SourcePath,
        [Parameter(Mandatory)] [string]$DestPath,
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$ManifestLines,
        [Parameter(Mandatory)] [string]$ManifestPrefix
    )

    if (-not (Test-Path $SourcePath)) {
        throw "Source not found: $SourcePath"
    }

    # Resolve wildcard sources
    $resolved = @(Resolve-Path -Path $SourcePath -ErrorAction Stop)
    foreach ($src in $resolved) {
        $srcPath = $src.Path
        Write-Info "copy: $srcPath -> $DestPath"

        if (Test-Path $srcPath -PathType Container) {
            Copy-Item -Path $srcPath -Destination $DestPath -Recurse -Force -ErrorAction Stop
        } else {
            if (-not (Test-Path $DestPath)) {
                New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
            }
            Copy-Item -Path $srcPath -Destination $DestPath -Force -ErrorAction Stop
        }
    }

    # Hash everything we just placed under $DestPath
    Get-ChildItem -Path $DestPath -Recurse -File -Force -ErrorAction Stop | ForEach-Object {
        $hash = Get-FileHash -Path $_.FullName -Algorithm SHA256 -ErrorAction Stop
        $rel = $_.FullName.Substring($DestPath.Length).TrimStart('\','/')
        $line = '{0}  {1}/{2}  {3}' -f $hash.Hash.ToLowerInvariant(), $ManifestPrefix, ($rel -replace '\\','/'), $_.Length
        $ManifestLines.Add($line) | Out-Null
    }
}

function Export-RegKey {
    param(
        [string]$Key,
        [string]$DestFile,
        [bool]$Optional = $false
    )

    # Convert HKLM\... / HKCU\... to PowerShell PSDrive form for existence check
    $psPath = $Key -replace '^HKLM\\','HKLM:\' -replace '^HKCU\\','HKCU:\'
    if (-not (Test-Path $psPath)) {
        if ($Optional) {
            Write-Warn2 "skip (not present): $Key"
            return $false
        }
        throw "Required registry key missing: $Key"
    }

    Write-Info "reg export: $Key -> $(Split-Path $DestFile -Leaf)"
    # /y = overwrite if exists; reg.exe writes UTF-16 .reg files
    $proc = Start-Process -FilePath 'reg.exe' -ArgumentList @('export', $Key, $DestFile, '/y') `
        -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\reg-out.txt" -RedirectStandardError "$env:TEMP\reg-err.txt"
    if ($proc.ExitCode -ne 0) {
        $err = Get-Content "$env:TEMP\reg-err.txt" -ErrorAction SilentlyContinue
        throw "reg export failed for $Key (exit=$($proc.ExitCode)): $err"
    }
    return $true
}

function Export-DriverDatabaseKeys {
    param([string]$RegistryDir)
    # DriverDatabase keys carry a hash suffix matching the package id; enumerate
    # to find any magicmouse.inf_amd64_* package(s).
    $base = 'HKLM:\SYSTEM\DriverDatabase\DriverPackages'
    if (-not (Test-Path $base)) {
        throw "DriverDatabase root not found: $base"
    }
    $matches = Get-ChildItem -Path $base -ErrorAction Stop | Where-Object {
        ($_.PSChildName -like 'magicmouse.inf_amd64_*') -or
        ($_.PSChildName -like 'magickeyboard.inf_amd64_*') -or
        ($_.PSChildName -like 'magictrackpad.inf_amd64_*')
    }
    if (-not $matches) {
        throw 'No magic*.inf_amd64_* DriverDatabase entries found.'
    }
    foreach ($m in $matches) {
        $sanitized = $m.PSChildName -replace '[^A-Za-z0-9._-]','_'
        $dest = Join-Path $RegistryDir "hklm-driverdatabase-$sanitized.reg"
        $key = 'HKLM\SYSTEM\DriverDatabase\DriverPackages\' + $m.PSChildName
        [void](Export-RegKey -Key $key -DestFile $dest -Optional $false)
    }
}

function Export-CustomBusEnumKeys {
    param([string]$RegistryDir)
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Enum'
    $candidates = @(
        $script:CustomBusInterfaceGuid,
        $script:CustomBusDeviceClassGuid
    )
    foreach ($g in $candidates) {
        $psPath = Join-Path $base $g
        if (Test-Path $psPath) {
            $sanitized = $g -replace '[{}]',''
            $dest = Join-Path $RegistryDir "hklm-enum-$sanitized.reg"
            $key = 'HKLM\SYSTEM\CurrentControlSet\Enum\' + $g
            [void](Export-RegKey -Key $key -DestFile $dest -Optional $false)
        } else {
            Write-Warn2 "Enum key not present (custom bus may not be enumerated right now): $psPath"
        }
    }
}

function Export-MsiInstallerProductKey {
    param([string]$RegistryDir)
    # Walk HKLM:\SOFTWARE\Classes\Installer\Products\* and find the entry whose
    # ProductName matches Magic Utilities. Export that subkey.
    $root = 'HKLM:\SOFTWARE\Classes\Installer\Products'
    if (-not (Test-Path $root)) {
        Write-Warn2 "MSI installer products root missing: $root"
        return
    }
    $found = $false
    Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            $name = $props.ProductName
            if ($name -and ($name -match 'Magic\s*Utilities')) {
                $sanitized = $_.PSChildName -replace '[^A-Za-z0-9._-]','_'
                $dest = Join-Path $RegistryDir "hklm-installer-products-$sanitized.reg"
                $key = 'HKLM\SOFTWARE\Classes\Installer\Products\' + $_.PSChildName
                [void](Export-RegKey -Key $key -DestFile $dest -Optional $false)
                $found = $true
            }
        } catch {
            # ignore individual key failures
        }
    }
    if (-not $found) {
        Write-Warn2 'No MSI installer ProductName matching Magic Utilities found (may be EXE-installed, not MSI).'
    }
}

function Capture-PnpTopology {
    param([string]$PnpDir)

    $all = Get-PnpDevice -ErrorAction Stop
    $magic = $all | Where-Object {
        ($_.FriendlyName -match 'Magic') -or
        ($_.InstanceId -match 'VID_05AC') -or
        ($_.InstanceId -match 'BTHENUM') -or
        ($_.Service -match 'MagicMouse|MagicUtilities')
    }

    $magic | Select-Object FriendlyName, Status, Class, ClassGuid, Manufacturer, Service, InstanceId, Present |
        ConvertTo-Json -Depth 6 | Out-File -FilePath (Join-Path $PnpDir 'pnp-magic-devices.json') -Encoding utf8

    # Full topology dump (small enough)
    $all | Select-Object FriendlyName, Status, Class, Service, InstanceId |
        ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path $PnpDir 'pnp-all-devices.json') -Encoding utf8

    # DEVPKEY dump on each Magic-related PDO
    $devpkeyDump = @()
    foreach ($d in $magic) {
        try {
            $props = Get-PnpDeviceProperty -InstanceId $d.InstanceId -ErrorAction Stop
            $devpkeyDump += [pscustomobject]@{
                InstanceId   = $d.InstanceId
                FriendlyName = $d.FriendlyName
                Service      = $d.Service
                Properties   = ($props | Select-Object KeyName, Type, Data)
            }
        } catch {
            Write-Warn2 "Could not enumerate DEVPKEYs for $($d.InstanceId): $($_.Exception.Message)"
        }
    }
    $devpkeyDump | ConvertTo-Json -Depth 8 | Out-File -FilePath (Join-Path $PnpDir 'pnp-devpkey-dump.json') -Encoding utf8
}

function Capture-ServiceConfig {
    param([string]$PnpDir)
    # Discover all Magic* services + the userland MagicUtilitiesService(s)
    $allSvc = Get-Service -ErrorAction SilentlyContinue | Where-Object {
        ($_.Name -like 'Magic*') -or ($_.DisplayName -like 'Magic*')
    } | Select-Object -ExpandProperty Name -Unique
    if (-not $allSvc -or $allSvc.Count -eq 0) {
        $allSvc = @('MagicMouse', 'MagicKeyboard', 'MagicTrackpad', 'MagicUtilitiesService')
    }
    foreach ($svc in $allSvc) {
        $qcOut = Join-Path $PnpDir "sc-qc-$svc.txt"
        $qdOut = Join-Path $PnpDir "sc-qdescription-$svc.txt"
        & sc.exe qc $svc 2>&1 | Out-File -FilePath $qcOut -Encoding utf8
        & sc.exe qdescription $svc 2>&1 | Out-File -FilePath $qdOut -Encoding utf8
    }
}

function Capture-DriverDependencies {
    param([string]$PnpDir)

    # Win32_PnPSignedDriver gives us the driver metadata + InfName + DriverVersion
    Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.InfName -like 'magic*.inf*' -or $_.DeviceName -match 'Magic' -or $_.Description -match 'Magic' } |
        Select-Object DeviceName, Description, DriverVersion, DriverDate, InfName, Manufacturer, Signer, DriverProviderName, DeviceID |
        ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path $PnpDir 'win32-pnpsigneddriver.json') -Encoding utf8

    # File-level metadata for MagicMouse.sys
    if (Test-Path $script:DriverBinaryPath) {
        $vi = (Get-Item $script:DriverBinaryPath).VersionInfo
        $vi | Select-Object * | ConvertTo-Json -Depth 4 |
            Out-File -FilePath (Join-Path $PnpDir 'magicmouse-sys-versioninfo.json') -Encoding utf8

        # pnputil enumerate of driver packages, filtered to magicmouse
        $enumOut = Join-Path $PnpDir 'pnputil-enum-drivers.txt'
        & pnputil.exe /enum-drivers 2>&1 | Out-File -FilePath $enumOut -Encoding utf8
    }
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
try {
    Write-Step 'Magic Utilities Trial Capture — pre-flight'

    if (-not (Test-IsAdmin)) {
        throw 'This script must be run from an elevated (Administrator) PowerShell.'
    }
    Write-Ok 'Running as Administrator.'

    Write-Info 'Verifying Magic Utilities is installed...'
    if (-not (Test-MagicUtilitiesInstalled)) {
        Write-Host ''
        Write-Host 'Magic Utilities does not appear to be installed.' -ForegroundColor Yellow
        Write-Host 'Please install it first (https://magicutilities.net/), start the trial,' -ForegroundColor Yellow
        Write-Host 'pair your Magic Mouse, confirm it works, then re-run this capture.'      -ForegroundColor Yellow
        exit 2
    }
    Write-Ok 'Magic Utilities is installed.'

    # Resolve output directory
    if (-not (Test-Path $OutputRoot)) {
        New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    }

    # Free space check on the drive backing $OutputRoot
    $driveLetter = (Split-Path -Qualifier (Resolve-Path $OutputRoot)).TrimEnd(':')
    $drive = Get-PSDrive -Name $driveLetter -ErrorAction Stop
    if ($drive.Free -lt $script:RequiredFreeBytes) {
        throw ("Insufficient free space on {0}: have {1:N1} GB, need {2:N1} GB." -f `
            $driveLetter, ($drive.Free / 1GB), ($script:RequiredFreeBytes / 1GB))
    }
    Write-Ok ("Free space on {0}: {1:N1} GB" -f $driveLetter, ($drive.Free / 1GB))

    $stamp = Get-Date -Format 'yyyy-MM-dd-HHmm'
    $captureDir = Join-Path $OutputRoot "MagicUtilities-Capture-$stamp"
    if (Test-Path $captureDir) {
        throw "Output directory already exists, refusing to overwrite: $captureDir"
    }

    $driverPkgDir   = Join-Path $captureDir 'driver-package'
    $driverBinDir   = Join-Path $captureDir 'driver-binary'
    $programDir     = Join-Path $captureDir 'program-files'
    $registryDir    = Join-Path $captureDir 'registry'
    $pnpDir         = Join-Path $captureDir 'pnp'
    $manifestPath   = Join-Path $captureDir 'manifest.txt'
    $readmePath     = Join-Path $captureDir 'README.md'

    foreach ($d in @($captureDir, $driverPkgDir, $driverBinDir, $programDir, $registryDir, $pnpDir)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
    Write-Ok "Capture root: $captureDir"

    $manifestLines = New-Object System.Collections.Generic.List[string]
    $muVersion = Get-MagicUtilitiesVersion
    $trialExpiryRaw = Get-TrialExpiryRaw
    Write-Info "Magic Utilities version: $muVersion"
    Write-Info "Trial expiry (raw bytes): $trialExpiryRaw"

    # -- (a) Driver package directories (mouse + keyboard + trackpad) -------
    Write-Step '(a) Capture driver package directories (DriverStore FileRepository)'
    $pkgFound = 0
    foreach ($glob in $script:DriverStoreGlobs) {
        if (Test-Path $glob) {
            Copy-WithManifest -SourcePath $glob -DestPath $driverPkgDir `
                -ManifestLines $manifestLines -ManifestPrefix 'driver-package'
            $pkgFound++
        } else {
            Write-Warn2 "Driver package glob not present (skipping): $glob"
        }
    }
    if ($pkgFound -eq 0) {
        throw 'No Magic* driver packages found in DriverStore. Is Magic Utilities installed?'
    }
    Write-Ok "Driver packages copied + hashed ($pkgFound found)."

    # -- (b) Active driver binaries + catalogs (Magic*.sys / Magic*.cat) ----
    Write-Step '(b) Capture active driver binaries + catalogs (System32\drivers)'
    $sysFound = @(Get-ChildItem -Path $script:DriverBinaryGlob -ErrorAction SilentlyContinue)
    if ($sysFound.Count -gt 0) {
        Copy-WithManifest -SourcePath $script:DriverBinaryGlob -DestPath $driverBinDir `
            -ManifestLines $manifestLines -ManifestPrefix 'driver-binary'
        Write-Ok ("Captured {0} Magic*.sys binaries." -f $sysFound.Count)
    } else {
        Write-Warn2 'No Magic*.sys files in System32\drivers.'
    }
    $catFound = @(Get-ChildItem -Path $script:DriverCatalogGlob -ErrorAction SilentlyContinue)
    if ($catFound.Count -gt 0) {
        Copy-WithManifest -SourcePath $script:DriverCatalogGlob -DestPath $driverBinDir `
            -ManifestLines $manifestLines -ManifestPrefix 'driver-binary'
        Write-Ok ("Captured {0} Magic*.cat catalogs." -f $catFound.Count)
    } else {
        Write-Warn2 'No Magic*.cat files in System32\drivers (may not be required).'
    }

    # -- (c) Userland install tree -------------------------------------------
    Write-Step '(c) Capture userland install tree (Program Files\MagicUtilities)'
    Copy-WithManifest -SourcePath $script:ProgramFilesPath -DestPath $programDir `
        -ManifestLines $manifestLines -ManifestPrefix 'program-files'
    Write-Ok 'Userland tree copied + hashed.'

    # -- (d) Registry exports ------------------------------------------------
    Write-Step '(d) Export registry hives (.reg)'
    foreach ($r in $script:RegExports) {
        $opt = $false
        if ($r.ContainsKey('Optional')) { $opt = [bool]$r.Optional }
        $dest = Join-Path $registryDir $r.File
        [void](Export-RegKey -Key $r.Key -DestFile $dest -Optional $opt)
    }
    Export-DriverDatabaseKeys     -RegistryDir $registryDir
    Export-CustomBusEnumKeys      -RegistryDir $registryDir
    Export-MsiInstallerProductKey -RegistryDir $registryDir

    # Hash all .reg files into manifest
    Get-ChildItem -Path $registryDir -Recurse -File | ForEach-Object {
        $hash = Get-FileHash -Path $_.FullName -Algorithm SHA256
        $rel = $_.FullName.Substring($registryDir.Length).TrimStart('\','/')
        $line = '{0}  registry/{1}  {2}' -f $hash.Hash.ToLowerInvariant(), ($rel -replace '\\','/'), $_.Length
        $manifestLines.Add($line) | Out-Null
    }
    Write-Ok 'Registry exports complete.'

    # -- (f, g, h, i) PnP topology + DEVPKEYs + service config + dependencies
    Write-Step '(f-i) Capture PnP topology, DEVPKEYs, service config, dependencies'
    Capture-PnpTopology         -PnpDir $pnpDir
    Capture-ServiceConfig       -PnpDir $pnpDir
    Capture-DriverDependencies  -PnpDir $pnpDir

    # Hash the pnp/ tree
    Get-ChildItem -Path $pnpDir -Recurse -File | ForEach-Object {
        $hash = Get-FileHash -Path $_.FullName -Algorithm SHA256
        $rel = $_.FullName.Substring($pnpDir.Length).TrimStart('\','/')
        $line = '{0}  pnp/{1}  {2}' -f $hash.Hash.ToLowerInvariant(), ($rel -replace '\\','/'), $_.Length
        $manifestLines.Add($line) | Out-Null
    }
    Write-Ok 'PnP / service / dependency snapshots written.'

    # -- Write manifest -------------------------------------------------------
    Write-Step 'Write manifest.txt (sha256sum-compatible)'
    $manifestLines | Sort-Object | Set-Content -Path $manifestPath -Encoding ascii
    Write-Ok "Manifest: $manifestPath ($($manifestLines.Count) entries)"

    # -- (j) README -----------------------------------------------------------
    Write-Step '(j) Write README.md'
    $captureDateIso = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')
    $readme = @"
# Magic Utilities Trial Capture

**Captured:** $captureDateIso
**Magic Utilities version (file):** $muVersion
**Trial expiry (raw, NOT decoded):** ``$trialExpiryRaw``

> Captured by ``scripts/mm-magicutilities-capture.ps1`` from the
> ``magic-mouse-tray`` project.

## Contents

| Subdir              | What                                                      |
|---------------------|-----------------------------------------------------------|
| ``driver-package/`` | DriverStore FileRepository copy (magicmouse.inf_amd64_*)  |
| ``driver-binary/``  | Active ``MagicMouse.sys`` + catalog files                 |
| ``program-files/``  | Full ``C:\Program Files\MagicUtilities\`` tree            |
| ``registry/``       | ``.reg`` exports (HKLM software, services, driver db,     |
|                     | PnP lockdown, MSI products, custom-bus enum, HKCU)        |
| ``pnp/``            | PnP topology JSON, DEVPKEY dump, ``sc qc/qdescription``,  |
|                     | ``Win32_PnPSignedDriver`` snapshot, ``pnputil`` enum      |
| ``manifest.txt``    | SHA256 manifest (``sha256sum -c`` compatible)             |

## Verify integrity

```bash
# From WSL or Git Bash
cd '<this directory>'
sha256sum -c manifest.txt
```

## Restore sequence (last-resort, kernel-driver-only re-install)

> Run from an elevated PowerShell on a Win11 box where Magic Utilities is
> NOT currently installed.

```powershell
# 1. Verify integrity first (see above).

# 2. Re-stage the driver package into the DriverStore and install it.
#    pnputil resolves dependencies and copies the .sys/.cat/.inf into place.
pnputil /add-driver "<this-dir>\driver-package\<exact-folder>\magicmouse.inf" /install

# 3. (Optional) Re-import service registry keys ONLY if pnputil did not
#    create them. Inspect first:
#      reg query HKLM\SYSTEM\CurrentControlSet\Services\MagicMouse
#    If empty:
reg import "<this-dir>\registry\hklm-services-magicmouse.reg"

# 4. Reboot.

# 5. Pair the Magic Mouse via Settings > Bluetooth & devices.
#    The kernel driver should bind via the BTHENUM PID match
#    (0x030D = MM1, 0x0323 = MM3).
```

## Empirical caveats

- **Kernel-only restore is UNTESTED.** Magic Utilities ships a userland
  service (``MagicUtilitiesService``) that may be required for full mouse
  behaviour. The kernel driver may attach but produce degraded input
  (no scroll smoothing, no gesture recognition, no battery telemetry, etc.).
  If degraded, you can re-import the userland tree from ``program-files/``
  manually, but service registration via ``MagicUtilities_Service.exe --install``
  (or similar) is **not guaranteed to work** outside the original installer.
- **Trial expiry is preserved as-is.** The 8 obfuscated bytes at
  ``HKLM\SOFTWARE\MagicUtilities\App\TrialExpiryDate`` are captured verbatim.
  We make no attempt to decode, freeze, or extend the trial. Doing so would
  violate the EULA.
- **Driver signing.** ``MagicMouse.sys`` is signed by Microsoft (WHQL).
  The signature should remain valid indefinitely for the captured binary.
  This is the primary reason a kernel-only restore is even theoretically
  possible.

## License caveat

Magic Utilities is paid commercial software. **Redistributing the contents
of this capture directory outside the bounds of the Magic Utilities EULA
is NOT authorized.** This snapshot exists for personal preservation only.
Do not share, publish, mirror, upload, or otherwise distribute these files.

## Source footprint reference

- INF package id: ``magicmouse.inf_amd64_82cbbe70c776aec4``
- INF sections: ``MM1_BTH.NT`` (PID 0x030D), ``MM3_BTH.NT`` (PID 0x0323)
- Kernel driver: ``C:\Windows\System32\drivers\MagicMouse.sys`` (KMDF 1.15)
- Userland service: ``MagicUtilitiesService`` →
  ``C:\Program Files\MagicUtilities\Service\MagicUtilities_Service.exe --run``
- Custom bus interface GUID: ``{7D55502A-2C87-441F-9993-0761990E0C7A}``
- Device class GUID: ``{fae1ef32-137e-485e-8d89-95d0d3bd8479}``
- PnP-Lockdown:
  ``HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\PnpLockdownFiles\%SystemRoot%/System32/drivers/MagicMouse.sys``
"@
    $readme | Set-Content -Path $readmePath -Encoding utf8
    Write-Ok "README written: $readmePath"

    # -- Post-flight summary --------------------------------------------------
    Write-Step 'Post-flight summary'
    $allFiles = Get-ChildItem -Path $captureDir -Recurse -File
    $totalBytes = ($allFiles | Measure-Object -Property Length -Sum).Sum
    $fileCount = $allFiles.Count

    Write-Host ''
    Write-Host '================================================================' -ForegroundColor Green
    Write-Host '  CAPTURE COMPLETE'                                                -ForegroundColor Green
    Write-Host '================================================================' -ForegroundColor Green
    Write-Host ("  Location   : {0}" -f $captureDir)
    Write-Host ("  Files      : {0:N0}" -f $fileCount)
    Write-Host ("  Total size : {0:N1} MB ({1:N0} bytes)" -f ($totalBytes / 1MB), $totalBytes)
    Write-Host ("  Manifest   : {0}" -f $manifestPath)
    Write-Host ("  README     : {0}" -f $readmePath)
    Write-Host ''
    Write-Host '  NEXT STEPS' -ForegroundColor Yellow
    Write-Host '  ----------' -ForegroundColor Yellow
    Write-Host '  1. Verify the manifest with sha256sum -c (WSL/Git Bash).'
    Write-Host '  2. Read README.md end to end before any future restore.'
    Write-Host '  3. Consider mirroring the capture dir to encrypted external'
    Write-Host '     storage. Do NOT upload to public/cloud locations — EULA.'
    Write-Host '  4. If you uninstall Magic Utilities later, this capture is'
    Write-Host '     your ONLY recovery path. Treat it accordingly.'
    Write-Host ''

    exit 0
}
catch {
    Write-Host ''
    Write-Err "CAPTURE ABORTED: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray

    # Fail-closed: scrub partial output so we don't leave a misleading half-capture.
    if ($captureDir -and (Test-Path $captureDir)) {
        try {
            Write-Warn2 "Removing partial capture directory: $captureDir"
            Remove-Item -Path $captureDir -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Err "Failed to remove partial capture: $($_.Exception.Message)"
            Write-Err "Manual cleanup required at: $captureDir"
        }
    }
    exit 1
}
