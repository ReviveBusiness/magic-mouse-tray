# mm-task-runner.ps1 - invoked by the SYSTEM scheduled task 'MM-Dev-Cycle'.
#
# Protocol (filesystem queue, ASCII text, pipe-delimited):
#   Request:  C:\mm-dev-queue\request.txt   "PHASE|NONCE[|arg...]"
#   Result:   C:\mm-dev-queue\result.txt    "EXITCODE|NONCE"
#   Lock:     C:\mm-dev-queue\running.lock  (created on enter, removed on exit)
#
# WSL drops a request, triggers `schtasks /run /tn MM-Dev-Cycle`, and polls
# result.txt for a matching nonce. The nonce prevents reading a stale result
# from a previous run.
#
# Phase 3 build routes (pipe-delimited args after PHASE|NONCE):
#   BUILD|<nonce>|<config>|<platform>[|<sln-path>]
#     config:    Release | Debug
#     platform:  x64
#     sln-path:  optional; defaults to driver\M12.sln on WSL path
#     log:       C:\mm-dev-queue\build-<nonce>.log
#
#   SIGN|<nonce>|<sys-path>|<cat-path>|<pfx-path>|<pfx-pass-env-var>
#     sys-path:       full Windows path to .sys file
#     cat-path:       full Windows path to .cat file
#     pfx-path:       full Windows path to .pfx file
#     pfx-pass-env-var: name of env var holding PFX password (avoids plaintext)
#     log:      C:\mm-dev-queue\sign-<nonce>.log
#
#   DV-CHECK|<nonce>|<driver-name>
#     driver-name: e.g. M12.sys (just the filename, no path)
#     log:      C:\mm-dev-queue\dv-<nonce>.log
#     result 0: Driver Verifier configured (reboot required to activate)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$QueueDir   = 'C:\mm-dev-queue'
$ReqFile    = Join-Path $QueueDir 'request.txt'
$ResFile    = Join-Path $QueueDir 'result.txt'
$LockFile   = Join-Path $QueueDir 'running.lock'
$TaskLog    = 'C:\mm-dev-task.log'

function Log {
    param([string]$Msg)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$ts] $Msg" | Add-Content -Path $TaskLog -Encoding UTF8
}

if (-not (Test-Path $QueueDir)) { New-Item -ItemType Directory $QueueDir -Force | Out-Null }

# Reject concurrent runs (Settings/MultipleInstances=IgnoreNew should prevent
# this anyway, but belt-and-braces against a stale lock from a crashed run)
if (Test-Path $LockFile) {
    $lockAge = (Get-Date) - (Get-Item $LockFile).LastWriteTime
    if ($lockAge.TotalMinutes -lt 30) {
        Log "Concurrent run detected (lock $($lockAge.TotalSeconds)s old) - exiting"
        exit 75
    } else {
        Log "Stale lock found ($($lockAge.TotalMinutes) min old) - removing"
        Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    }
}

New-Item -Path $LockFile -ItemType File -Force | Out-Null
Log "===== task started ====="

try {
    if (-not (Test-Path $ReqFile)) {
        Log "No request file - exiting cleanly"
        exit 0
    }

    $raw = (Get-Content $ReqFile -Raw -Encoding ASCII).Trim()
    if (-not $raw) {
        Log "Empty request - exiting"
        exit 0
    }

    $parts = $raw -split '\|'
    $phase = $parts[0].Trim()
    $nonce = if ($parts.Count -gt 1) { $parts[1].Trim() } else { 'no-nonce' }
    Log "Request parsed: phase='$phase' nonce='$nonce' args=$($parts.Count - 2)"

    $rc = 0

    # BUILD route: invoke EWDK msbuild against M12.sln (or any .sln on WSL path)
    # Request format: BUILD|<nonce>|<config>|<platform>[|<sln-path>]
    if ($phase -eq 'BUILD') {
        $config   = if ($parts.Count -gt 2) { $parts[2].Trim() } else { 'Release' }
        $platform = if ($parts.Count -gt 3) { $parts[3].Trim() } else { 'x64' }
        $defaultSln = '\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\driver\M12.sln'
        $solution = if ($parts.Count -gt 4 -and $parts[4].Trim()) { $parts[4].Trim() } else { $defaultSln }
        $buildLog = Join-Path $QueueDir "build-$nonce.log"
        # Use SetupBuildEnv.cmd (one-shot env setup), NOT LaunchBuildEnv.cmd (cmd /k interactive)
        # Senior-dev review CRIT-1: LaunchBuildEnv hangs the queue indefinitely.
        $ewdk     = 'F:\BuildEnv\SetupBuildEnv.cmd'

        Log "BUILD config=$config platform=$platform solution=$solution"

        if (-not (Test-Path $ewdk)) {
            $msg = "ERROR: EWDK SetupBuildEnv not found at $ewdk - is the ISO mounted?"
            Log $msg
            $msg | Set-Content $buildLog -Encoding ASCII
            $rc = 1
        } else {
            $cmdLine = "call `"$ewdk`" >NUL 2>&1 && msbuild `"$solution`" /p:Configuration=$config /p:Platform=$platform /v:minimal"
            Log "Invoking: cmd /c $cmdLine"
            try {
                cmd /c $cmdLine > $buildLog 2>&1
                $rc = $LASTEXITCODE
                if ($null -eq $rc) { $rc = 0 }
            } catch {
                "Exception: $_" | Add-Content $buildLog -Encoding ASCII
                Log "Exception in BUILD: $_"
                $rc = 99
            }
        }
        Log "BUILD exited $rc; log at $buildLog"
    }
    # SIGN route: signtool sign .sys + .cat with a PFX cert
    # Request format: SIGN|<nonce>|<sys-path>|<cat-path>|<pfx-path>|<pfx-pass-env-var>
    elseif ($phase -eq 'SIGN') {
        $sysPath    = if ($parts.Count -gt 2) { $parts[2].Trim() } else { '' }
        $catPath    = if ($parts.Count -gt 3) { $parts[3].Trim() } else { '' }
        $pfxPath    = if ($parts.Count -gt 4) { $parts[4].Trim() } else { '' }
        $pfxPassVar = if ($parts.Count -gt 5) { $parts[5].Trim() } else { '' }
        $signLog    = Join-Path $QueueDir "sign-$nonce.log"
        $signtool   = 'F:\Program Files\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'
        $tsUrl      = 'http://timestamp.digicert.com'

        Log "SIGN sys=$sysPath cat=$catPath pfx=$pfxPath passvar=$pfxPassVar"

        if (-not (Test-Path $signtool)) {
            $msg = "ERROR: signtool not found at $signtool"
            Log $msg
            $msg | Set-Content $signLog -Encoding ASCII
            $rc = 1
        } elseif (-not $sysPath -or -not $catPath -or -not $pfxPath) {
            $msg = "ERROR: SIGN requires sys-path, cat-path, and pfx-path args"
            Log $msg
            $msg | Set-Content $signLog -Encoding ASCII
            $rc = 2
        } else {
            $pfxPass = if ($pfxPassVar) { [Environment]::GetEnvironmentVariable($pfxPassVar) } else { '' }
            $passArgs = if ($pfxPass) { @('/p', $pfxPass) } else { @() }
            try {
                "=== Sign $sysPath ===" | Set-Content $signLog -Encoding ASCII
                & $signtool sign /fd sha256 /tr $tsUrl /td sha256 /f $pfxPath @passArgs $sysPath 2>&1 | Add-Content $signLog -Encoding ASCII
                $rc = $LASTEXITCODE
                if ($null -eq $rc) { $rc = 0 }
                "=== Sign $catPath ===" | Add-Content $signLog -Encoding ASCII
                & $signtool sign /fd sha256 /tr $tsUrl /td sha256 /f $pfxPath @passArgs $catPath 2>&1 | Add-Content $signLog -Encoding ASCII
                $rc2 = $LASTEXITCODE
                if ($null -eq $rc2) { $rc2 = 0 }
                if ($rc -eq 0) { $rc = $rc2 }
            } catch {
                "Exception: $_" | Add-Content $signLog -Encoding ASCII
                Log "Exception in SIGN: $_"
                $rc = 99
            }
        }
        Log "SIGN exited $rc; log at $signLog"
    }
    # DV-CHECK route: configure Driver Verifier for a named driver
    # Request format: DV-CHECK|<nonce>|<driver-name>
    # Result 0 = verifier configured; actual enforcement requires reboot
    elseif ($phase -eq 'DV-CHECK') {
        $driverName = if ($parts.Count -gt 2) { $parts[2].Trim() } else { '' }
        $dvLog      = Join-Path $QueueDir "dv-$nonce.log"
        $dvFlags    = '0x49bb'

        Log "DV-CHECK driver=$driverName flags=$dvFlags"

        if (-not $driverName) {
            $msg = "ERROR: DV-CHECK requires driver-name arg (e.g. M12.sys)"
            Log $msg
            $msg | Set-Content $dvLog -Encoding ASCII
            $rc = 2
        } else {
            try {
                "=== verifier /flags $dvFlags /driver $driverName ===" | Set-Content $dvLog -Encoding ASCII
                & verifier /flags $dvFlags /driver $driverName /standard /reset 2>&1 | Add-Content $dvLog -Encoding ASCII
                $rc = $LASTEXITCODE
                if ($null -eq $rc) { $rc = 0 }
                "=== verifier /query ===" | Add-Content $dvLog -Encoding ASCII
                & verifier /query 2>&1 | Add-Content $dvLog -Encoding ASCII
            } catch {
                "Exception: $_" | Add-Content $dvLog -Encoding ASCII
                Log "Exception in DV-CHECK: $_"
                $rc = 99
            }
        }
        Log "DV-CHECK exited $rc; log at $dvLog"
    }
    # Special phase prefix "SNAPSHOT:Stack" routes to mm-bt-stack-snapshot.ps1
    elseif ($phase -like 'SNAPSHOT:*') {
        $snapScript = 'D:\mm3-driver\scripts\mm-bt-stack-snapshot.ps1'
        if (-not (Test-Path $snapScript)) {
            Log "ERROR: mm-bt-stack-snapshot.ps1 not found at $snapScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $snapScript"
        try {
            & $snapScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-bt-stack-snapshot.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "WPPDECODE:*" routes to mm-test-A3-wpp-decode.ps1
    elseif ($phase -like 'WPPDECODE:*') {
        $wppScript = 'D:\mm3-driver\scripts\mm-test-A3-wpp-decode.ps1'
        if (-not (Test-Path $wppScript)) {
            Log "ERROR: mm-test-A3-wpp-decode.ps1 not found at $wppScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $wppScript"
        try {
            & $wppScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-test-A3-wpp-decode.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "ETWBTH:*" routes to mm-test-A2-etw-bth-hid.ps1
    elseif ($phase -like 'ETWBTH:*') {
        $eScript = 'D:\mm3-driver\scripts\mm-test-A2-etw-bth-hid.ps1'
        if (-not (Test-Path $eScript)) {
            Log "ERROR: mm-test-A2-etw-bth-hid.ps1 not found at $eScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $eScript"
        try {
            & $eScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-test-A2-etw-bth-hid.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "PROCMONIO:*" routes to mm-test-C-procmon-iotest.ps1
    elseif ($phase -like 'PROCMONIO:*') {
        $pmScript = 'D:\mm3-driver\scripts\mm-test-C-procmon-iotest.ps1'
        if (-not (Test-Path $pmScript)) {
            Log "ERROR: mm-test-C-procmon-iotest.ps1 not found at $pmScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $pmScript"
        try {
            & $pmScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-test-C-procmon-iotest.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "CTRDUMP:*" routes to mm-container-dump.ps1
    elseif ($phase -like 'CTRDUMP:*') {
        $cdScript = 'D:\mm3-driver\scripts\mm-container-dump.ps1'
        if (-not (Test-Path $cdScript)) {
            Log "ERROR: mm-container-dump.ps1 not found at $cdScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $cdScript"
        try {
            & $cdScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-container-dump.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "DEVMGR:*" routes to mm-devmgr-dump.ps1
    elseif ($phase -like 'DEVMGR:*') {
        $dmScript = 'D:\mm3-driver\scripts\mm-devmgr-dump.ps1'
        if (-not (Test-Path $dmScript)) {
            Log "ERROR: mm-devmgr-dump.ps1 not found at $dmScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $dmScript"
        try {
            & $dmScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-devmgr-dump.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "EVTLOG:*" routes to mm-pnp-eventlog.ps1
    elseif ($phase -like 'EVTLOG:*') {
        $eScript = 'D:\mm3-driver\scripts\mm-pnp-eventlog.ps1'
        if (-not (Test-Path $eScript)) {
            Log "ERROR: mm-pnp-eventlog.ps1 not found at $eScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $eScript"
        try {
            & $eScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-pnp-eventlog.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "SVCCTRL:Action" routes to mm-svc-control.ps1
    elseif ($phase -like 'SVCCTRL:*') {
        $svcAction = ($phase -split ':', 2)[1]
        $svcScript = 'D:\mm3-driver\scripts\mm-svc-control.ps1'
        if (-not (Test-Path $svcScript)) {
            Log "ERROR: mm-svc-control.ps1 not found at $svcScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $svcScript Action=$svcAction"
        try {
            & $svcScript -Action $svcAction
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-svc-control.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "HIDREAD:*" routes to mm-hid-feature-read.ps1
    elseif ($phase -like 'HIDREAD:*') {
        $hrScript = 'D:\mm3-driver\scripts\mm-hid-feature-read.ps1'
        if (-not (Test-Path $hrScript)) {
            Log "ERROR: mm-hid-feature-read.ps1 not found at $hrScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $hrScript"
        try {
            & $hrScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-hid-feature-read.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "BATPROBE:*" routes to mm-battery-probe-deep.ps1
    elseif ($phase -like 'BATPROBE:*') {
        $bpScript = 'D:\mm3-driver\scripts\mm-battery-probe-deep.ps1'
        if (-not (Test-Path $bpScript)) {
            Log "ERROR: mm-battery-probe-deep.ps1 not found at $bpScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $bpScript"
        try {
            & $bpScript
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-battery-probe-deep.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "DISCOVER:Target" routes to mm-bthport-discover.ps1
    elseif ($phase -like 'DISCOVER:*') {
        $target = ($phase -split ':', 2)[1]
        $discScript = 'D:\mm3-driver\scripts\mm-bthport-discover.ps1'
        if (-not (Test-Path $discScript)) {
            Log "ERROR: mm-bthport-discover.ps1 not found at $discScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $discScript Target=$target"
        try {
            if ($target -eq 'All') {
                & $discScript -AllDevices
            } else {
                & $discScript -Mac $target
            }
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-bthport-discover.ps1: $_"
            $rc = 99
        }
    }
    # Special phase prefix "FLIP:Mode" routes to mm-state-flip.ps1 (LowerFilters mutation)
    elseif ($phase -like 'FLIP:*') {
        $mode = ($phase -split ':', 2)[1]
        $flipScript = 'D:\mm3-driver\scripts\mm-state-flip.ps1'
        if (-not (Test-Path $flipScript)) {
            Log "ERROR: mm-state-flip.ps1 not found at $flipScript"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $flipScript Mode=$mode"
        try {
            & $flipScript -Mode $mode
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-state-flip.ps1: $_"
            $rc = 99
        }
    } else {
        # Default: route to mm-dev.ps1 -Phase $phase
        $candidates = @(
            'D:\mm3-driver\scripts\mm-dev.ps1',
            'C:\mm3-pkg\scripts\mm-dev.ps1'
        )
        $devScript = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $devScript) {
            Log "ERROR: mm-dev.ps1 not found in candidates"
            "127|$nonce" | Set-Content $ResFile -Encoding ASCII
            exit 127
        }
        Log "Using $devScript"

        try {
            & $devScript -Phase $phase -NoElevate
            $rc = $LASTEXITCODE
            if ($null -eq $rc) { $rc = 0 }
        } catch {
            Log "Exception running mm-dev.ps1: $_"
            $rc = 99
        }
    }

    Log "Phase '$phase' exited $rc"
    "$rc|$nonce" | Set-Content $ResFile -Encoding ASCII
    exit $rc

} finally {
    Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    Log "===== task complete ====="
}
