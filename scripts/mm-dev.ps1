<#
.SYNOPSIS
    Magic Mouse driver development cycle - state/build/sign/install/capture in one script.

.DESCRIPTION
    Enforces the loop: Understand state -> Implement -> Test -> Understand state.
    Every step is timestamped and logged to $SessionLog.

    Run from WSL:
        powershell.exe -ExecutionPolicy Bypass -File "D:\mm3-driver\scripts\mm-dev.ps1" -Phase Full

    Run directly (Admin PowerShell):
        .\mm-dev.ps1 -Phase Full
        .\mm-dev.ps1 -Phase State
        .\mm-dev.ps1 -Phase Build
        .\mm-dev.ps1 -Phase Install
        .\mm-dev.ps1 -Phase Capture

.PARAMETER Phase
    State    - Snapshot current PnP + driver state
    Build    - EWDK msbuild (Rebuild)
    Sign     - signtool sign .sys + .cat
    Install  - Remove old driver, install new, restart device
    Verify   - Post-install health check (LowerFilters, COL01 status, oem package)
    Rollback - Remove our filter driver entirely (recovery path)
    Capture  - (Re)start DebugView capturing to $DebugLog
    Full     - State -> Build -> Sign -> Install -> Verify -> State
    Log      - Tail last 40 lines of session log
    Debug    - Tail last 40 MagicMouse lines from debug log
#>
param(
    [ValidateSet('State','Build','Sign','Install','Verify','Rollback','Capture','Full','Log','Debug')]
    [string]$Phase = 'Full',

    [string]$EwdkRoot   = 'F:\',
    [string]$PkgDir     = 'D:\mm3-pkg',
    [string]$SessionLog = 'C:\mm-dev-session.log',
    [string]$DebugLog   = 'C:\mm3-debug.log',
    [string]$Thumbprint = '609447610A54605BE39AB32CFADB661023FD3ED0',
    [string]$TimestampUrl = 'http://timestamp.digicert.com',
    [string]$VendorPid  = 'VID&0001004c_PID&0323',  # Magic Mouse 2024 - used for device autodetect
    [string]$DbgViewExe = 'C:\SysinternalsSuite\Dbgview.exe',
    [string]$SignToolExe = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
    [switch]$NoElevate    # internal flag — set when re-launched as admin to prevent infinite recursion
)

# ---------------------------------------------------------------------------
# Self-elevation — re-launch as admin if needed (UAC prompt once per call)
# ---------------------------------------------------------------------------
function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin) -and -not $NoElevate) {
    Write-Host "[mm-dev] Not Administrator - elevating via UAC (accept the prompt)..." -ForegroundColor Yellow

    # Build relaunch arg list — preserve all bound params + add -NoElevate sentinel
    $relaunchArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSCommandPath",'-NoElevate')
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) {
            if ($v.IsPresent) { $relaunchArgs += "-$k" }
        } else {
            $relaunchArgs += "-$k"
            $relaunchArgs += "$v"
        }
    }
    if (-not ($PSBoundParameters.ContainsKey('Phase'))) {
        $relaunchArgs += '-Phase'; $relaunchArgs += "$Phase"
    }

    try {
        $proc = Start-Process -FilePath 'powershell.exe' `
                              -ArgumentList $relaunchArgs `
                              -Verb RunAs -Wait -PassThru `
                              -WindowStyle Normal
        Write-Host "[mm-dev] Elevated phase exited with code $($proc.ExitCode)" -ForegroundColor Cyan
        Write-Host "[mm-dev] Session log: $SessionLog" -ForegroundColor Cyan
        exit $proc.ExitCode
    } catch {
        Write-Host "[mm-dev] Elevation cancelled or failed: $_" -ForegroundColor Red
        exit 2
    }
}

# Auto-detect device ID by VID/PID (avoids hardcoded MAC that breaks on re-pair)
function Resolve-DeviceId {
    $devs = pnputil /enum-devices /connected 2>&1 | Out-String
    $blocks = $devs -split "(?=Instance ID:)"
    foreach ($b in $blocks) {
        if ($b -match "Instance ID:\s+(BTHENUM\\\{00001124[^\r\n]*$VendorPid[^\r\n]*)" ) {
            return $Matches[1].Trim()
        }
    }
    return $null
}

# Derive driver source root from script location (scripts\ -> repo root)
$DriverRoot = Split-Path -Parent $PSScriptRoot
$BuildOut   = Join-Path $DriverRoot 'x64\Debug'
$VcxProj    = Join-Path $DriverRoot 'MagicMouseDriver.vcxproj'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts][$Level] $Msg"
    Add-Content -Path $SessionLog -Value $line -Encoding UTF8
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        'HEAD'  { Write-Host "`n$line" -ForegroundColor Cyan }
        default { Write-Host $line }
    }
}

function Write-Section {
    param([string]$Title)
    $bar = '=' * 60
    $line = "$bar`n=== $Title`n$bar"
    Add-Content -Path $SessionLog -Value $line -Encoding UTF8
    Write-Host "`n$line" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# STATE
# ---------------------------------------------------------------------------
function Get-DriverState {
    Write-Section "STATE SNAPSHOT - $(Get-Date -Format 'HH:mm:ss')"

    # PnP devices matching our mouse
    Write-Log "--- PnP devices (Magic Mouse 0x0323) ---"
    $devs = pnputil /enum-devices /connected 2>&1
    $relevant = $devs | Select-String -Pattern '0323|MagicMouse|Magic Mouse|COL01|COL02|oem52' -Context 0,5
    if ($relevant) {
        $relevant | ForEach-Object { Write-Log $_.Line }
    } else {
        Write-Log "(no matching connected devices)" 'WARN'
    }

    # Our driver package
    Write-Log "--- Installed driver package ---"
    $pkgs = pnputil /enum-drivers 2>&1
    $ourPkg = ($pkgs | Select-String -Pattern 'MagicMouse|magicmouse' -Context 0,6)
    if ($ourPkg) {
        $ourPkg | ForEach-Object { Write-Log $_.Line }
    } else {
        Write-Log "(MagicMouseDriver not installed)" 'WARN'
    }

    # COL01 / COL02 status
    Write-Log "--- HID child devices ---"
    $col = pnputil /enum-devices 2>&1 | Select-String 'COL01|COL02' -Context 0,4
    if ($col) {
        $col | ForEach-Object { Write-Log $_.Line }
    } else {
        Write-Log "(COL01/COL02 not found)" 'WARN'
    }

    # LowerFilters registry
    Write-Log "--- LowerFilters registry ---"
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\9&73b8b28&0&D0C050CC8C4D_C00000000'
    try {
        $lf = (Get-ItemProperty $regPath -ErrorAction Stop).LowerFilters
        Write-Log "LowerFilters = $($lf -join ', ')" $(if ($lf -contains 'MagicMouseDriver') {'OK'} else {'WARN'})
    } catch {
        Write-Log "Registry key not found (device not paired?)" 'WARN'
    }

    # Built artifact info
    Write-Log "--- Build artifact ---"
    $sys = Join-Path $BuildOut 'MagicMouseDriver.sys'
    if (Test-Path $sys) {
        $fi = Get-Item $sys
        Write-Log "MagicMouseDriver.sys  size=$($fi.Length)  modified=$($fi.LastWriteTime)" 'OK'
    } else {
        Write-Log "MagicMouseDriver.sys not found at $BuildOut" 'WARN'
    }

    # Last debug entries
    Write-Log "--- Last 15 MagicMouse debug lines ---"
    if (Test-Path $DebugLog) {
        $lines = Get-Content $DebugLog | Select-String 'MagicMouse' | Select-Object -Last 15
        if ($lines) { $lines | ForEach-Object { Write-Log $_.Line } }
        else { Write-Log "(no MagicMouse entries yet)" }
    } else {
        Write-Log "(debug log not found - DebugView not running?)" 'WARN'
    }

    Write-Log "State snapshot complete." 'OK'
}

# ---------------------------------------------------------------------------
# BUILD
# ---------------------------------------------------------------------------
function Build-Driver {
    Write-Section "BUILD - $(Get-Date -Format 'HH:mm:ss')"

    if (-not (Test-Path $VcxProj)) {
        Write-Log "vcxproj not found: $VcxProj" 'ERROR'
        return $false
    }

    $ewdkBatchEnv = Join-Path $EwdkRoot 'LaunchBuildEnv.cmd'
    if (-not (Test-Path $ewdkBatchEnv)) {
        Write-Log "EWDK not found at $EwdkRoot - check -EwdkRoot parameter" 'ERROR'
        return $false
    }

    Write-Log "Running EWDK msbuild (Rebuild)..."
    $buildCmd = "`"$ewdkBatchEnv`" && msbuild `"$VcxProj`" /p:Configuration=Debug /p:Platform=x64 /t:Rebuild /nologo /v:minimal"
    $output = cmd /c $buildCmd 2>&1
    $output | ForEach-Object { Add-Content -Path $SessionLog -Value $_ -Encoding UTF8 }

    $sys = Join-Path $BuildOut 'MagicMouseDriver.sys'
    if (Test-Path $sys) {
        Write-Log "Build succeeded: $sys" 'OK'
        return $true
    } else {
        Write-Log "Build FAILED - .sys not produced. See session log for details." 'ERROR'
        # Show last 20 lines of build output
        $output | Select-Object -Last 20 | ForEach-Object { Write-Log $_ 'ERROR' }
        return $false
    }
}

# ---------------------------------------------------------------------------
# SIGN
# ---------------------------------------------------------------------------
function Sign-Driver {
    Write-Section "SIGN - $(Get-Date -Format 'HH:mm:ss')"

    if (-not (Test-Path $SignToolExe)) {
        # Try to find signtool in common WDK locations
        $candidates = @(
            'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
            'C:\Program Files (x86)\Windows Kits\10\bin\x64\signtool.exe'
        )
        $SignToolExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $SignToolExe) {
            Write-Log "signtool.exe not found - install Windows SDK/WDK" 'ERROR'
            return $false
        }
    }

    $targets = @(
        (Join-Path $BuildOut 'MagicMouseDriver.sys'),
        (Join-Path $BuildOut 'MagicMouseDriver.cat')
    )

    $ok = $true
    foreach ($target in $targets) {
        if (-not (Test-Path $target)) {
            Write-Log "Not found, skipping: $target" 'WARN'
            continue
        }
        Write-Log "Signing: $(Split-Path -Leaf $target)"
        $result = & $SignToolExe sign /v /sha1 $Thumbprint /fd SHA256 /t $TimestampUrl $target 2>&1
        $result | ForEach-Object { Add-Content -Path $SessionLog -Value $_ -Encoding UTF8 }
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Signed OK: $(Split-Path -Leaf $target)" 'OK'
        } else {
            Write-Log "Sign FAILED: $(Split-Path -Leaf $target)" 'ERROR'
            $ok = $false
        }
    }
    return $ok
}

# ---------------------------------------------------------------------------
# INSTALL
# ---------------------------------------------------------------------------
function Get-CurrentOemPackage {
    # Robust line-by-line parse of pnputil /enum-drivers to find our oem*.inf number
    $out = pnputil /enum-drivers 2>&1
    $currentOem = $null
    foreach ($line in $out) {
        if ($line -match 'Published Name:\s+(oem\d+\.inf)') {
            $candidate = $Matches[1]
        }
        if ($line -match 'magicmousedriver\.inf' -and $candidate) {
            $currentOem = $candidate
            break
        }
    }
    return $currentOem
}

function Install-Driver {
    Write-Section "INSTALL - $(Get-Date -Format 'HH:mm:ss')"

    $currentOem = Get-CurrentOemPackage
    if ($currentOem) {
        Write-Log "Removing current package: $currentOem"
        $out = pnputil /delete-driver $currentOem /uninstall /force 2>&1
        $out | ForEach-Object { Add-Content -Path $SessionLog -Value $_ -Encoding UTF8 }
        Write-Log "Removed $currentOem" 'OK'
    } else {
        Write-Log "No existing MagicMouseDriver package found - fresh install" 'INFO'
    }

    # Copy stamped artifacts to PkgDir
    if (-not (Test-Path $PkgDir)) { New-Item -ItemType Directory $PkgDir | Out-Null }
    Write-Log "Copying build artifacts to $PkgDir"
    Copy-Item "$BuildOut\*" $PkgDir -Recurse -Force
    Write-Log "Copied." 'OK'

    # Install from stamped INF (has updated DriverVer timestamp)
    $stampedInf = Join-Path $PkgDir 'MagicMouseDriver.inf'
    if (-not (Test-Path $stampedInf)) {
        Write-Log "Stamped INF not found at $stampedInf" 'ERROR'
        return $false
    }

    Write-Log "Installing driver package..."
    $out = pnputil /add-driver $stampedInf /install 2>&1
    $out | ForEach-Object {
        Add-Content -Path $SessionLog -Value $_ -Encoding UTF8
        Write-Log $_
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Log "pnputil /add-driver failed (exit $LASTEXITCODE)" 'ERROR'
        return $false
    }

    # Resolve device ID dynamically (handles re-pair / new MAC)
    $devId = Resolve-DeviceId
    if (-not $devId) {
        Write-Log "Device not currently connected - install added, but cannot restart device" 'WARN'
        Write-Log "Connect the mouse, then run: .\mm-dev.ps1 -Phase Verify" 'INFO'
        return $true
    }

    Write-Log "Restarting device: $devId"
    $out = pnputil /restart-device $devId 2>&1
    $out | ForEach-Object { Add-Content -Path $SessionLog -Value $_ -Encoding UTF8 }
    Write-Log "Device restart sent." 'OK'

    Start-Sleep -Seconds 3
    Write-Log "Install complete." 'OK'
    return $true
}

# ---------------------------------------------------------------------------
# VERIFY - post-install health check
# ---------------------------------------------------------------------------
function Verify-Install {
    Write-Section "VERIFY - $(Get-Date -Format 'HH:mm:ss')"
    $allOk = $true

    # 1. oem package present?
    $oem = Get-CurrentOemPackage
    if ($oem) {
        Write-Log "oem package: $oem" 'OK'
    } else {
        Write-Log "No MagicMouseDriver oem package installed" 'ERROR'
        $allOk = $false
    }

    # 2. Device connected?
    $devId = Resolve-DeviceId
    if (-not $devId) {
        Write-Log "Device not connected - cannot verify runtime state" 'WARN'
        return $allOk
    }
    Write-Log "Device: $devId" 'OK'

    # 3. LowerFilters has MagicMouseDriver?
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$devId"
    try {
        $lf = (Get-ItemProperty $regPath -ErrorAction Stop).LowerFilters
        if ($lf -contains 'MagicMouseDriver') {
            Write-Log "LowerFilters: $($lf -join ',') (MagicMouseDriver bound)" 'OK'
        } else {
            Write-Log "LowerFilters: $($lf -join ',') - MagicMouseDriver NOT bound" 'ERROR'
            $allOk = $false
        }
    } catch {
        Write-Log "Cannot read LowerFilters at $regPath" 'ERROR'
        $allOk = $false
    }

    # 4. COL01 (mouse) Started?
    $col01 = pnputil /enum-devices /connected 2>&1 | Out-String
    if ($col01 -match "VID&0001004c_PID&0323&Col01[^\r\n]*\r?\n[^\r\n]*\r?\n[\s\S]{0,400}?Status:\s+(\w+)") {
        $status = $Matches[1]
        if ($status -eq 'Started') {
            Write-Log "COL01 (HID-compliant mouse): Started" 'OK'
        } else {
            Write-Log "COL01: $status (expected Started)" 'ERROR'
            $allOk = $false
        }
    } else {
        Write-Log "COL01 not found - HID enumeration failed" 'ERROR'
        $allOk = $false
    }

    if ($allOk) {
        Write-Log "VERIFY PASSED - driver bound, COL01 started" 'OK'
    } else {
        Write-Log "VERIFY FAILED - see findings above" 'ERROR'
    }
    return $allOk
}

# ---------------------------------------------------------------------------
# ROLLBACK - recovery path: remove our filter entirely
# ---------------------------------------------------------------------------
function Rollback-Driver {
    Write-Section "ROLLBACK - $(Get-Date -Format 'HH:mm:ss')"
    $oem = Get-CurrentOemPackage
    if (-not $oem) {
        Write-Log "Nothing to roll back - no MagicMouseDriver package installed" 'OK'
        return $true
    }
    Write-Log "Removing $oem (filter driver) - this restores native HidBth behavior"
    $out = pnputil /delete-driver $oem /uninstall /force 2>&1
    $out | ForEach-Object { Add-Content -Path $SessionLog -Value $_ -Encoding UTF8; Write-Log $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Log "pnputil /delete-driver failed (exit $LASTEXITCODE)" 'ERROR'
        return $false
    }
    $devId = Resolve-DeviceId
    if ($devId) {
        Write-Log "Restarting device to drop filter binding..."
        pnputil /restart-device $devId 2>&1 | ForEach-Object { Add-Content -Path $SessionLog -Value $_ -Encoding UTF8 }
    }
    Write-Log "Rollback complete." 'OK'
    return $true
}

# ---------------------------------------------------------------------------
# DEBUG CAPTURE
# ---------------------------------------------------------------------------
function Start-DebugCapture {
    Write-Section "CAPTURE - $(Get-Date -Format 'HH:mm:ss')"

    # Ensure kernel debug filter is set (force-replace if existing key is wrong type)
    $regKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Debug Print Filter'
    if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }
    try {
        Remove-ItemProperty -Path $regKey -Name 'DEFAULT' -ErrorAction SilentlyContinue
    } catch { }
    New-ItemProperty -Path $regKey -Name 'DEFAULT' -PropertyType DWord -Value 8 -Force | Out-Null
    Write-Log "Debug print filter set (DEFAULT=8 DWord)" 'OK'

    # Kill existing DebugView
    Get-Process -Name Dbgview -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500

    # Clear old log
    if (Test-Path $DebugLog) { Remove-Item $DebugLog -Force }
    Write-Log "Old debug log cleared." 'OK'

    # Start DebugView
    if (-not (Test-Path $DbgViewExe)) {
        Write-Log "DebugView not found at $DbgViewExe - download Sysinternals Suite" 'ERROR'
        return $false
    }

    Start-Process $DbgViewExe -ArgumentList "/accepteula /t /k /l `"$DebugLog`"" -WindowStyle Minimized
    Start-Sleep -Milliseconds 800

    $proc = Get-Process -Name Dbgview -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Log "DebugView started (PID $($proc.Id)) -> logging to $DebugLog" 'OK'
        return $true
    } else {
        Write-Log "DebugView did not start" 'ERROR'
        return $false
    }
}

# ---------------------------------------------------------------------------
# SHOW LOGS
# ---------------------------------------------------------------------------
function Show-SessionLog {
    Write-Section "SESSION LOG (last 40 lines)"
    if (Test-Path $SessionLog) {
        Get-Content $SessionLog | Select-Object -Last 40
    } else {
        Write-Log "No session log yet." 'WARN'
    }
}

function Show-DebugLog {
    Write-Section "DEBUG LOG - MagicMouse entries (last 40)"
    if (Test-Path $DebugLog) {
        $lines = Get-Content $DebugLog | Select-String 'MagicMouse' | Select-Object -Last 40
        if ($lines) { $lines | ForEach-Object { Write-Host $_.Line } }
        else { Write-Log "(no MagicMouse entries)" 'WARN' }
    } else {
        Write-Log "Debug log not found - run: .\mm-dev.ps1 -Phase Capture" 'WARN'
    }
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
Write-Log "=== mm-dev.ps1 Phase=$Phase ===" 'HEAD'

$exitCode = 0
switch ($Phase) {
    'State'    { Get-DriverState }
    'Build'    { if (-not (Build-Driver))   { $exitCode = 1 } }
    'Sign'     { if (-not (Sign-Driver))    { $exitCode = 1 } }
    'Install'  { if (-not (Install-Driver)) { $exitCode = 1 } }
    'Verify'   { if (-not (Verify-Install)) { $exitCode = 1 } }
    'Rollback' { if (-not (Rollback-Driver)){ $exitCode = 1 } }
    'Capture'  { if (-not (Start-DebugCapture)) { $exitCode = 1 } }
    'Log'      { Show-SessionLog }
    'Debug'    { Show-DebugLog }
    'Full' {
        Get-DriverState
        $ok = Build-Driver
        if ($ok) { $ok = Sign-Driver }
        if ($ok) { $ok = Install-Driver }
        if ($ok) { $ok = Verify-Install }
        Get-DriverState
        if ($ok) {
            Write-Log "Full cycle complete - run Capture phase to start DebugView, then test." 'OK'
        } else {
            Write-Log "Full cycle FAILED - check session log: $SessionLog" 'ERROR'
            $exitCode = 1
        }
    }
}

Write-Log "Done. Session log: $SessionLog (exit=$exitCode)"
exit $exitCode
