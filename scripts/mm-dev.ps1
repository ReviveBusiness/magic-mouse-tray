#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Magic Mouse driver development cycle — state/build/sign/install/capture in one script.

.DESCRIPTION
    Enforces the loop: Understand state → Implement → Test → Understand state.
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
    State    — Snapshot current PnP + driver state
    Build    — EWDK msbuild (Rebuild)
    Sign     — signtool sign .sys + .cat
    Install  — Remove old driver, install new, restart device
    Capture  — (Re)start DebugView capturing to $DebugLog
    Full     — State → Build → Sign → Install → State
    Log      — Tail last 40 lines of session log
    Debug    — Tail last 40 MagicMouse lines from debug log
#>
param(
    [ValidateSet('State','Build','Sign','Install','Capture','Full','Log','Debug')]
    [string]$Phase = 'Full',

    [string]$EwdkRoot   = 'F:\',
    [string]$PkgDir     = 'D:\mm3-pkg',
    [string]$SessionLog = 'C:\mm-dev-session.log',
    [string]$DebugLog   = 'C:\mm3-debug.log',
    [string]$Thumbprint = '609447610A54605BE39AB32CFADB661023FD3ED0',
    [string]$TimestampUrl = 'http://timestamp.digicert.com',
    [string]$DeviceId   = 'BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\9&73b8b28&0&D0C050CC8C4D_C00000000',
    [string]$DbgViewExe = 'C:\SysinternalsSuite\Dbgview.exe',
    [string]$SignToolExe = 'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'
)

# Derive driver source root from script location (scripts\ → repo root)
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
    Write-Section "STATE SNAPSHOT — $(Get-Date -Format 'HH:mm:ss')"

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
        Write-Log "(debug log not found — DebugView not running?)" 'WARN'
    }

    Write-Log "State snapshot complete." 'OK'
}

# ---------------------------------------------------------------------------
# BUILD
# ---------------------------------------------------------------------------
function Build-Driver {
    Write-Section "BUILD — $(Get-Date -Format 'HH:mm:ss')"

    if (-not (Test-Path $VcxProj)) {
        Write-Log "vcxproj not found: $VcxProj" 'ERROR'
        return $false
    }

    $ewdkBatchEnv = Join-Path $EwdkRoot 'LaunchBuildEnv.cmd'
    if (-not (Test-Path $ewdkBatchEnv)) {
        Write-Log "EWDK not found at $EwdkRoot — check -EwdkRoot parameter" 'ERROR'
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
        Write-Log "Build FAILED — .sys not produced. See session log for details." 'ERROR'
        # Show last 20 lines of build output
        $output | Select-Object -Last 20 | ForEach-Object { Write-Log $_ 'ERROR' }
        return $false
    }
}

# ---------------------------------------------------------------------------
# SIGN
# ---------------------------------------------------------------------------
function Sign-Driver {
    Write-Section "SIGN — $(Get-Date -Format 'HH:mm:ss')"

    if (-not (Test-Path $SignToolExe)) {
        # Try to find signtool in common WDK locations
        $candidates = @(
            'C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe',
            'C:\Program Files (x86)\Windows Kits\10\bin\x64\signtool.exe'
        )
        $SignToolExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $SignToolExe) {
            Write-Log "signtool.exe not found — install Windows SDK/WDK" 'ERROR'
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
function Install-Driver {
    Write-Section "INSTALL — $(Get-Date -Format 'HH:mm:ss')"

    # Find current installed oem package
    $pkgs = pnputil /enum-drivers 2>&1
    $oemMatch = $pkgs | Select-String 'magicmousedriver\.inf' -Context 10,0
    $currentOem = if ($oemMatch) {
        ($oemMatch.Context.PreContext | Select-String 'oem\d+\.inf').Matches[0].Value
    } else { $null }

    if ($currentOem) {
        Write-Log "Removing current package: $currentOem"
        $out = pnputil /delete-driver $currentOem /uninstall /force 2>&1
        $out | ForEach-Object { Add-Content -Path $SessionLog -Value $_ -Encoding UTF8 }
        Write-Log "Removed $currentOem" 'OK'
    } else {
        Write-Log "No existing MagicMouseDriver package found — fresh install" 'INFO'
    }

    # Copy stamped artifacts to PkgDir
    if (-not (Test-Path $PkgDir)) { New-Item -ItemType Directory $PkgDir | Out-Null }
    Write-Log "Copying build artifacts to $PkgDir"
    Copy-Item "$BuildOut\*" $PkgDir -Force
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

    # Restart device
    Write-Log "Restarting device..."
    $out = pnputil /restart-device $DeviceId 2>&1
    $out | ForEach-Object { Add-Content -Path $SessionLog -Value $_ -Encoding UTF8 }
    Write-Log "Device restart sent." 'OK'

    Start-Sleep -Seconds 3
    Write-Log "Install complete." 'OK'
    return $true
}

# ---------------------------------------------------------------------------
# DEBUG CAPTURE
# ---------------------------------------------------------------------------
function Start-DebugCapture {
    Write-Section "CAPTURE — $(Get-Date -Format 'HH:mm:ss')"

    # Ensure kernel debug filter is set
    $regKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Debug Print Filter'
    if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }
    Set-ItemProperty -Path $regKey -Name 'DEFAULT' -Value 8 -Type DWord
    Write-Log "Debug print filter set (DEFAULT=8)" 'OK'

    # Kill existing DebugView
    Get-Process -Name Dbgview -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500

    # Clear old log
    if (Test-Path $DebugLog) { Remove-Item $DebugLog -Force }
    Write-Log "Old debug log cleared." 'OK'

    # Start DebugView
    if (-not (Test-Path $DbgViewExe)) {
        Write-Log "DebugView not found at $DbgViewExe — download Sysinternals Suite" 'ERROR'
        return $false
    }

    Start-Process $DbgViewExe -ArgumentList "/accepteula /t /k /l `"$DebugLog`"" -WindowStyle Minimized
    Start-Sleep -Milliseconds 800

    $proc = Get-Process -Name Dbgview -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Log "DebugView started (PID $($proc.Id)) → logging to $DebugLog" 'OK'
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
    Write-Section "DEBUG LOG — MagicMouse entries (last 40)"
    if (Test-Path $DebugLog) {
        $lines = Get-Content $DebugLog | Select-String 'MagicMouse' | Select-Object -Last 40
        if ($lines) { $lines | ForEach-Object { Write-Host $_.Line } }
        else { Write-Log "(no MagicMouse entries)" 'WARN' }
    } else {
        Write-Log "Debug log not found — run: .\mm-dev.ps1 -Phase Capture" 'WARN'
    }
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------
Write-Log "=== mm-dev.ps1 Phase=$Phase ===" 'HEAD'

switch ($Phase) {
    'State'   { Get-DriverState }
    'Build'   { Build-Driver }
    'Sign'    { Sign-Driver }
    'Install' { Install-Driver }
    'Capture' { Start-DebugCapture }
    'Log'     { Show-SessionLog }
    'Debug'   { Show-DebugLog }
    'Full' {
        Get-DriverState
        $ok = Build-Driver
        if ($ok) { $ok = Sign-Driver }
        if ($ok) { $ok = Install-Driver }
        Get-DriverState
        if ($ok) {
            Write-Log "Full cycle complete — run Capture phase to start DebugView, then test." 'OK'
        } else {
            Write-Log "Full cycle FAILED — check session log: $SessionLog" 'ERROR'
        }
    }
}

Write-Log "Done. Session log: $SessionLog"
