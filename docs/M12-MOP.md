# M12 Method of Procedure (MOP)

**Status:** v1.6 — DRAFT pending user approval (v1.5 + three final additions folded in)
**Date:** 2026-04-28
**Linked design:** `docs/M12-DESIGN-SPEC.md` v1.6
**Linked test plan:** `docs/M12-TEST-PLAN.md` v1.1
**Linked PRD:** PRD-184 v1.31
**Linked NLM pass-1:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-2026-04-28.md`
**Linked NLM pass-2:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS2-2026-04-28.md`
**Linked NLM pass-3:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS3-2026-04-28.md`
**Linked NLM pass-4:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS4-2026-04-28.md`
**BCP reference:** BCP-OPS-501 (Change Management) — pre-flight + rollback + health-check pattern.
**Related rules:** `~/.claude/projects/-home-lesley-projects/memory/feedback_backup_before_destructive_commands.md` (AP-24 — non-negotiable backup gate).

## Revision history

- **v1.6 (2026-04-28):** Aligned to design spec v1.6. Added: (a) VG-14: self-tuning verification -- install on fresh machine, wait 5 min of mouse usage, check WPP log for "self-tuning detected offset N" entry, verify Feature 0x47 returns plausible battery percentage. (b) Sign-off checklist item PRIVACY-1: Privacy Policy reviewed and current. (c) AV/EDR known-issue documented in docs/KNOWN-ISSUES.md (no MOP gate required; documentation only). Test plan linked version bumped v1.0 -> v1.1.
- **v1.5 (2026-04-28):** Aligned to design spec v1.5. Added: (a) CRITICAL testsigning prerequisite block at top of BLUF (Section 1) — upstream issue #1 analysis shows this is the most common install blocker. (b) VG-12: auto-reinit-on-wake test — sleep cycle, confirm shadow refresh after wake. (c) VG-13: battery-polling-fallback test — force shadow stale by disconnect, query Feature 0x47, confirm GET_REPORT issued. (d) BUILD-5 (v1.5): PREfast gate — verify build output shows "0 Code Analysis warnings". (e) BUILD-6 (v1.5): SDV gate — verify sdv-report.xml shows "0 defects" before signing. (f) Pre-build line-endings check (git ls-files --eol). PowerSaver defaults updated: SuspendOnDisplayOff=1, SuspendOnACUnplug=1. Sign-off checklist expanded with v1.5 gates.
- **v1.4 (2026-04-28):** Aligned to design spec v1.4. Service name changed to `MagicMouseM12` (was bare `M12` in v1.3) per DSM Issue 5 (avoid namespace collision). Pre-install Sec 7a expanded: DriverVer rank-loss detection (DSM Issue 1), stale-service detection (Issue 5), DriverStore staged-package cleanup (Issue 6). Post-install Sec 7d expanded: registry-binding verification via `reg query` (Issue 1) + orphan-filter walk (Issue 7). Section 7c-pre Path A documented (registry cache flush, faster than UI unpair). Rollback Sec 8b explicit `sc.exe delete MagicMouseM12` order (Issue 5). NEW gates: VG-8 power-saver functional test (display-off / AC-unplug / sign-out / sleep / shutdown — verify mouse suspends + wakes on click), VG-9 battery-saving 24-hr measurement, VG-10 multi-mouse simultaneous read-out, VG-11 Driver Verifier 0x49bb soak (1000 IOCTL cycles + 100 pair/unpair). NEW failure-mode entries F23-F27 from design spec. Sign-off checklist updated. Bumped to v1.4.
- **v1.3 (2026-04-28):** Aligned to design spec v1.3 (PID branch restored + BRB descriptor rewriter restored). VG-0 dual-state pass condition added (Descriptor B in cache OR Descriptor A + DescriptorBRewritten flag set). VG-1 v1 baseline now exercises NATIVE Feature 0x47 path, not M12 short-circuit — failure here means M12 broke the pass-through (regression in INF binding or queue forwarding). New optional MAX_STALE_MS registry tunable documented. Soft active-poll noted as future work (OQ-D).
- **v1.2 (2026-04-28):** Aligned to design spec v1.2 (applewirelessmouse-baseline reframe). Driver Verifier flags expanded to 0x9bb + IRP completion + IoTarget flags. Pool tag verification step added (`!poolused 4 'M12 '`). EvtIoStop verification step added (forced cancel via Driver Verifier). Empirical battery offset verification step added (LogShadowBuffer debug.log diff at known battery levels). 24-hr soak scope clarified to include BT sleep/wake cycles. VG-0 caps check repurposed: confirms cached SDP descriptor matches applewirelessmouse-baseline (Input=47, Feature=2, LinkColl=2), NOT Mode A — because v1.2 doesn't mutate the descriptor. Section 7c-pre BTHPORT cache wipe demoted to optional (only triggered if VG-0 caps mismatch suggests a stale non-applewirelessmouse cache).
- **v1.1 (2026-04-28):** Added Section 7c-pre (force fresh SDP exchange via BTHPORT cache wipe / unpair-repair) and VG-0 pre-validation gate.
- **v1.0 (2026-04-28):** Initial MOP.

---

## 1. BLUF

This MOP is the canonical end-to-end procedure for building, signing, installing, validating, and rolling back the M12 KMDF lower filter driver on the Magic Mouse v1 (PID 0x030D) and v3 (PID 0x0323) test machine. Every section maps to a single `bash` / `pwsh` command block; every gate is a Pass/Fail boolean; rollback is a single section the operator can run start-to-finish at any failure point. No section depends on userland Magic Utilities being present.

### CRITICAL prerequisite: Test-signing must be enabled

M12 v1 is test-signed for development distribution. Production WHQL signing is deferred (see docs/KNOWN-ISSUES.md).

**Verify**:

```pwsh
bcdedit | findstr testsigning
```

Expected output: `testsigning             Yes`

**If not enabled** (output is `No` or missing):

```pwsh
bcdedit /set testsigning on
```

Then **REBOOT**. After reboot, the desktop bottom-right corner shows "Test Mode" watermark -- that is the indicator test-signing is active.

Without test-signing enabled, M12 will fail to install with "Driver is not signed" or "Hash mismatch" errors. This is the most common install blocker (upstream issue #1 in MagicMouse2DriversWin10x64 with 30+ comments).

---

## 2. Scope

| Item | Value |
|------|-------|
| Target machine | Lesley's Windows 11 Home dev machine (single-node, host-not-VM) |
| Target devices | Apple Magic Mouse v1 (BTHENUM PID 0x030D) + v3 (BTHENUM PID 0x0323) |
| Driver under test | `MagicMouseDriver.sys` (M12), built from this repository |
| Build environment | EWDK 25H2 mounted at `F:\` (or D:\ewdk25h2 if F: unavailable) |
| Build host | Same Windows 11 Home dev machine |
| Test signing | Self-signed cert; production WHQL OUT of scope for this MOP |

---

## 3. Prerequisites

### 3a. Test signing enabled

```pwsh
bcdedit | Select-String "testsigning"
# Expected: "testsigning             Yes"
```

If `No` or absent:

```pwsh
bcdedit /set testsigning on
# Reboot required.
```

### 3b. EWDK mounted

```pwsh
Test-Path F:\BuildTools\msbuild.exe
# OR
Test-Path D:\ewdk25h2\BuildTools\msbuild.exe
```

If neither path is present, mount the EWDK ISO first.

### 3c. Hardware paired

Both Magic Mouse v1 and v3 must be paired, currently bound to the Apple Wireless Mouse driver, and producing input. v1 must be readable by the existing tray (`OK battery=N% (Feature 0x47)` in `%APPDATA%\MagicMouseTray\debug.log`). This is the "before" baseline.

### 3d. Recovery backup verified

```pwsh
$RecoveryPath = "D:\Backups\AppleWirelessMouse-RECOVERY"
Test-Path "$RecoveryPath\AppleWirelessMouse.inf"
Test-Path "$RecoveryPath\AppleWirelessMouse.cat"
Test-Path "$RecoveryPath\AppleWirelessMouse.sys"
# All three must exist. If any are missing, STOP — recovery path is broken.
```

Per `feedback_backup_before_destructive_commands.md` and AP-24: this MOP MAY perform `pnputil /delete-driver` operations as part of rollback (Section 8). The recovery backup MUST be verified intact BEFORE we begin.

### 3e. Tray app debug log accessible

```pwsh
Test-Path "$env:APPDATA\MagicMouseTray\debug.log"
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 5
```

### 3f. WinDbg / kernel debugger ready (NEW v1.2)

Pool-tag verification (`!poolused`) and Driver Verifier triage require WinDbg attached or kernel-mode crash-dump analysis available. Either:

```pwsh
Test-Path "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\windbg.exe"
# OR
Test-Path "F:\Debuggers\x64\windbg.exe"   # via EWDK mount
```

For 24-hr soak triage, configure live-kernel debugging or capture small-memory-dump on bugcheck (default `%SYSTEMROOT%\Minidump\`).

---

## 4. Pre-flight backup (BCP-OPS-501)

```pwsh
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$BackupRoot = "D:\Backups\pre-M12-$ts"
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

# 4a. Snapshot device topology + driver state
& "$env:LOCALAPPDATA\..\..\projects\Personal\magic-mouse-tray\scripts\mm-snapshot-state.ps1" -OutDir $BackupRoot

# 4b. Full HKLM\SYSTEM registry export (per AP-11)
reg export HKLM\SYSTEM "$BackupRoot\HKLM-SYSTEM-pre-M12.reg" /y

# 4c. Driver enumeration
pnputil /enum-drivers > "$BackupRoot\pnputil-enum-drivers.txt"

# 4d. PnP topology
Get-PnpDevice | Where-Object { $_.InstanceId -like "*VID&0001004C*" } |
    Format-List -Property * | Out-File "$BackupRoot\pnp-apple-devices.txt"

# 4e. Tray log snapshot
Copy-Item "$env:APPDATA\MagicMouseTray\debug.log" "$BackupRoot\debug.log.pre"

# 4f. Verify backup
Test-Path "$BackupRoot\HKLM-SYSTEM-pre-M12.reg"
Test-Path "$BackupRoot\debug.log.pre"
Get-ChildItem $BackupRoot | Format-Table Name, Length
```

**Gate PRE-1:** all five files exist, sizes plausible. Halt if missing.

---

## 5. Build procedure

### 5a. Open EWDK build environment

```pwsh
& F:\LaunchBuildEnv.cmd
```

### 5b. Build

```pwsh
cd C:\Users\Lesley\projects\Personal\magic-mouse-tray\driver
msbuild MagicMouseDriver.vcxproj `
    /p:Configuration=Debug `
    /p:Platform=x64 `
    /p:SignMode=Off `
    /verbosity:minimal `
    /m
```

### 5c. Verify build artefacts

```pwsh
$BuildOut = "C:\Users\Lesley\projects\Personal\magic-mouse-tray\driver\Debug\x64\MagicMouseDriver"
Test-Path "$BuildOut\MagicMouseDriver.sys"
Test-Path "$BuildOut\MagicMouseDriver.inf"
```

**Gate BUILD-1:** `MagicMouseDriver.sys` and `MagicMouseDriver.inf` both exist.

### 5d. Validate descriptor (reference-only in v1.2)

```pwsh
& "$env:WindowsSdkDir\Tools\x64\hidparser.exe" "$BuildOut\MagicMouseDriver.inf"
```

**Gate BUILD-2:** `hidparser.exe` returns success on the static `g_HidDescriptor[]` bytes (the 116-byte applewirelessmouse-baseline reference). M12 v1.2 does not actually serve this descriptor — applewirelessmouse-style cached SDP does — but the bytes are validated to confirm M12's design assumptions match the real device descriptor. Helps catch firmware-version drift.

### 5e. Verify pool tag in binary (NEW v1.2)

```pwsh
# Confirm pool tag 'M12 ' (0x2032314D, ASCII "M12 ") is referenced in the .sys file.
Select-String -Path "$BuildOut\MagicMouseDriver.sys" -Pattern "M12 " -SimpleMatch
# Or use dumpbin to confirm pool tag constants in .data section.
```

**Gate BUILD-3:** Binary contains pool tag literal `M12 ` (ASCII bytes 0x4D 0x31 0x32 0x20). MAJ-5 fix verification.

### 5f. Verify WPP TMF generated (NEW v1.4 — Sec 19)

```pwsh
Test-Path "$BuildOut\MagicMouseDriver.tmf"
# Optional: validate TMF parses
& "$env:WindowsSdkDir\bin\$env:WindowsSdkVer\x64\tracewpp.exe" -verify "$BuildOut\MagicMouseDriver.tmf"
```

**Gate BUILD-4 (v1.4):** TMF file exists alongside .sys. Required for `tracefmt` decoding of WPP traces during VG-* testing.

### 5g. PREfast static analyzer gate (NEW v1.5 — GATING for ship per D-S12-43)

```pwsh
# Run PREfast via msbuild (treat PREfast warnings as errors)
msbuild MagicMouseDriver.vcxproj `
    /p:Configuration=Release `
    /p:Platform=x64 `
    /p:RunCodeAnalysis=true `
    /p:CodeAnalysisRuleSet=NativeMinimumRules.ruleset `
    /p:CodeAnalysisTreatWarningsAsErrors=true `
    /p:WppEnabled=true `
    /verbosity:minimal `
    /m

# Check for any residual C6xxx / C28xxx warnings in the build log
$buildLog = Get-Content ".\MagicMouseDriver.log" -ErrorAction SilentlyContinue
$prefastWarnings = $buildLog | Select-String -Pattern "warning C6|warning C28"
if ($prefastWarnings) {
    Write-Error "PREfast warnings found -- HALT. Fix before proceeding to sign."
    $prefastWarnings | ForEach-Object { Write-Error $_ }
} else {
    Write-Output "BUILD-5 PASS: PREfast 0 warnings"
}
```

**Gate BUILD-5 (v1.5):** PREfast reports 0 Code Analysis warnings. This gate is NON-SKIPPABLE for any ship candidate. A dev/debug build without /p:RunCodeAnalysis=true is acceptable for iteration, but the final release build must pass BUILD-5.

### 5h. Verify line endings on driver source (NEW v1.5 — upstream lessons D-S12-49)

```pwsh
# From the EWDK build environment or WSL
git ls-files --eol -- driver/ | Tee-Object line-endings.txt

# Check that .inf files show eol=crlf not eol=lf
$lf_infs = Get-Content line-endings.txt | Where-Object { $_ -match "\.inf" -and $_ -match "eol=lf" }
if ($lf_infs) {
    Write-Error "CRLF violation: .inf file(s) have LF line endings -- signing will fail."
    $lf_infs | ForEach-Object { Write-Error $_ }
    Write-Error "Fix: ensure driver/.gitattributes exists with '*.inf text eol=crlf' and re-checkout."
} else {
    Write-Output "Line endings OK: all .inf files are CRLF"
}
```

**Gate BUILD-6 (v1.5):** All `.inf` files in `driver/` report `eol=crlf` in git ls-files output. Failure = DO NOT SIGN -- signing will fail with hash mismatch.

### 5i. SDV gate (NEW v1.5 — GATING for ship per D-S12-44)

Run SDV before signing. SDV catches deadlocks, IRP completion races, KMDF rule violations.

```pwsh
# Run SDV (from EWDK build environment -- takes 10-30 min)
msbuild MagicMouseDriver.vcxproj `
    /t:sdv `
    /p:inputs="/check:default.sdv" `
    /p:Configuration=Release `
    /p:Platform=x64

# Gate: check sdv-report.xml for defects
[xml]$sdvReport = Get-Content "driver\sdv-report.xml"
$defectCount = [int]$sdvReport.DEFECTS.count
if ($defectCount -gt 0) {
    Write-Error "SDV found $defectCount defects -- HALT. Do not sign until defects resolved."
    $sdvReport.DEFECTS.DEFECT | ForEach-Object { Write-Error "$($_.RULE) $($_.ENTRYPOINT)" }
} else {
    Write-Output "BUILD-7 PASS: SDV 0 defects"
}
```

**Gate BUILD-7 (v1.5):** SDV reports 0 defects. This gate is NON-SKIPPABLE for any ship candidate. Note: SDV run time is 10-30 minutes; schedule accordingly.

---

## 6. Test-sign procedure

### 6a. Generate self-signed cert (one-time)

```pwsh
$CertSubject = "CN=MagicMouseTray-TestSign"
$existing = Get-ChildItem Cert:\CurrentUser\My |
    Where-Object { $_.Subject -eq $CertSubject }

if (-not $existing) {
    $cert = New-SelfSignedCertificate `
        -Subject $CertSubject `
        -Type CodeSigningCert `
        -KeyUsage DigitalSignature `
        -KeyExportPolicy Exportable `
        -CertStoreLocation Cert:\CurrentUser\My `
        -NotAfter (Get-Date).AddYears(2)
    $store = Get-Item Cert:\LocalMachine\TrustedPublisher
    $store.Open("ReadWrite"); $store.Add($cert); $store.Close()
    $store = Get-Item Cert:\LocalMachine\Root
    $store.Open("ReadWrite"); $store.Add($cert); $store.Close()
}
```

### 6b. Sign the .sys (RFC 3161 timestamp per Senior MOP §10 v1.1 review)

```pwsh
$signtool = "$env:WindowsSdkDir\bin\$env:WindowsSdkVer\x64\signtool.exe"
& $signtool sign `
    /v `
    /s My `
    /n "MagicMouseTray-TestSign" `
    /tr http://timestamp.digicert.com `
    /td SHA256 `
    /fd SHA256 `
    "$BuildOut\MagicMouseDriver.sys"

& $signtool verify /v /pa "$BuildOut\MagicMouseDriver.sys"
```

Note v1.2: switched from legacy `/t` (SHA1) to `/tr` (RFC 3161) + `/td SHA256` per Senior driver dev §10 — Win11 22H2+ rejects SHA1-timestamped test-signed kernel drivers at load.

### 6c. Generate + sign catalog

```pwsh
$inf2cat = "$env:WindowsSdkDir\bin\$env:WindowsSdkVer\x86\Inf2Cat.exe"
& $inf2cat /driver:$BuildOut /os:10_X64

& $signtool sign `
    /v `
    /s My `
    /n "MagicMouseTray-TestSign" `
    /tr http://timestamp.digicert.com `
    /td SHA256 `
    /fd SHA256 `
    "$BuildOut\MagicMouseDriver.cat"
```

**Gate SIGN-1:** `signtool verify /v /pa MagicMouseDriver.sys` reports "Successfully verified". Same for `.cat`.

---

## 7. Install procedure

### 7a. Pre-install enumeration check + applewirelessmouse removal (EXPANDED v1.4)

```pwsh
pnputil /enum-drivers | Select-String -Context 0,5 -Pattern "MagicMouse|applewirelessmouse"
```

Expected: shows `applewirelessmouse` (oem<N>.inf) entry. NO existing `MagicMouseDriver` entry.

Per Senior MIN-5: `applewirelessmouse` must be REMOVED from LowerFilters before M12 install (M12's INF appends, would otherwise stack both). Required removal:

```pwsh
# Capture applewirelessmouse oem<N>.inf for rollback
$appleOem = pnputil /enum-drivers |
    Select-String -Context 5,0 "applewirelessmouse" |
    Select-String "Published Name" |
    ForEach-Object { ($_ -split ":")[1].Trim() }

# Verify recovery backup exists per AP-24
foreach ($f in @("AppleWirelessMouse.inf", "AppleWirelessMouse.cat", "AppleWirelessMouse.sys")) {
    if (-not (Test-Path "D:\Backups\AppleWirelessMouse-RECOVERY\$f")) {
        Write-Error "MISSING: D:\Backups\AppleWirelessMouse-RECOVERY\$f -- HALT"
        return
    }
}

# Remove. M12 install (7b) follows.
pnputil /delete-driver "$appleOem" /uninstall
# Note: NOT /force here — let PnP pick up the absence cleanly. /force fallback only if needed.
```

#### 7a.1 (NEW v1.4) DriverVer rank-loss detection per DSM Issue 1

```pwsh
# v1.4 — list all candidate INFs for the v3 hardware ID; flag any with DriverVer >= M12's
$m12DriverVer = [DateTime]"01/01/2027"
$allInfs = pnputil /enum-drivers
$candidates = $allInfs | Select-String -Context 5,5 -Pattern "BTHENUM.*PID&0323"
$flagged = @()
foreach ($block in $candidates) {
    $ver = ($block.Context.PostContext + $block.Context.PreContext) | Select-String "Driver Date|Driver Version"
    # Parse the date and compare; flag if competing >= 01/01/2027
    # (Implementation: parse via .NET DateTime; this is shorthand)
}
if ($flagged.Count -gt 0) {
    Write-Warning "Competing INFs with DriverVer >= M12 found:"
    $flagged | ForEach-Object { Write-Warning $_ }
    Write-Warning "M12 may lose PnP rank tie. Bump M12 DriverVer next release, or accept competing driver, or delete via pnputil /delete-driver (after AP-24 backup)."
}
```

#### 7a.2 (NEW v1.4) Stale `MagicMouseM12` service detection per DSM Issue 5

```pwsh
$svcState = sc.exe query MagicMouseM12 2>$null
if ($LASTEXITCODE -eq 0) {
    $stateLine = $svcState | Select-String "STATE"
    $exitCodeLine = $svcState | Select-String "EXIT_CODE"
    Write-Output "Existing MagicMouseM12 service: $stateLine $exitCodeLine"
    # If STOPPED + EXIT_CODE 31 (binary missing) -> orphan from prior install
    if ($stateLine -match "STOPPED" -and $exitCodeLine -match "\b31\b") {
        Write-Warning "Stale MagicMouseM12 service found (STOPPED, EXIT_CODE 31). Cleaning up."
        sc.exe delete MagicMouseM12
    }
}
```

#### 7a.3 (NEW v1.4) Stale M12 DriverStore package detection per DSM Issue 6

```pwsh
$staleM12 = pnputil /enum-drivers | Select-String -Context 5,5 "MagicMouseDriver"
if ($staleM12) {
    Write-Warning "Found existing MagicMouseDriver package(s) in DriverStore. Cleaning up."
    $staleOems = $staleM12 | Select-String "Published Name" | ForEach-Object { ($_ -split ":")[1].Trim() }
    foreach ($oem in $staleOems) {
        pnputil /delete-driver "$oem" /uninstall /force
    }
}
```

**Gate PRE-INSTALL-1 (NEW v1.4):** rank check passes (no competing DriverVer >= M12), stale service cleaned, stale DriverStore packages cleaned. Halt if any step errored.

### 7b. Stage and install M12

```pwsh
pnputil /add-driver "$BuildOut\MagicMouseDriver.inf" /install
```

Capture published OEM number for rollback:

```pwsh
$published = pnputil /enum-drivers | Select-String -Context 5,0 "MagicMouseDriver" |
    Select-String "Published Name" | ForEach-Object { ($_ -split ":")[1].Trim() }
$published   # e.g., oem15.inf
```

### 7c-pre. (Optional in v1.2) BTHPORT cache invalidation

v1.2 design does NOT mutate the cached SDP descriptor — applewirelessmouse-published descriptor is what M12 expects HidBth to serve. The cache trap (F13) only matters if the cache contains a non-applewirelessmouse descriptor (e.g., MU's Mode A from a prior install). Run VG-0 first; only invalidate the cache if VG-0 caps mismatch.

If VG-0 fails with caps showing Mode A (Input=8, Feature=2, LinkColl=5):

**Path A (preferred — scripted cache wipe, requires verified backup per AP-24):**

```pwsh
$macV1 = "04F13EEEDE10"
$macV3 = "D0C050CC8C4D"
$BthRoot = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices"
foreach ($mac in @($macV1, $macV3)) {
    $cachePath = "$BthRoot\$mac\CachedServices"
    if (Test-Path $cachePath) {
        $bk = "$BackupRoot\BTHPORT-CachedServices-$mac.reg"
        reg export "HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$mac\CachedServices" "$bk" /y
        if ((Get-Item $bk).Length -lt 100) {
            Write-Error "Backup of $cachePath is empty — HALT"
            return
        }
        Remove-ItemProperty -Path $cachePath -Name "00010000" -ErrorAction SilentlyContinue
    }
}
```

**Path B (fallback — operator unpair + re-pair):** remove both Magic Mouse devices from BT settings, then re-pair.

### 7c. Force re-bind

```pwsh
$v1Inst = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&030D*" |
           Where-Object { $_.Status -eq "OK" }).InstanceId
$v3Inst = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&0323*" |
           Where-Object { $_.Status -eq "OK" }).InstanceId

pnputil /disable-device "$v1Inst"
pnputil /enable-device "$v1Inst"
pnputil /disable-device "$v3Inst"
pnputil /enable-device "$v3Inst"
Start-Sleep -Seconds 5
```

### 7d. Verify M12 is bound (EXPANDED v1.4)

```pwsh
Get-PnpDeviceProperty -InstanceId "$v1Inst" -KeyName DEVPKEY_Device_LowerFilters
Get-PnpDeviceProperty -InstanceId "$v3Inst" -KeyName DEVPKEY_Device_LowerFilters
# Expected: Data column contains "MagicMouseM12"

sc.exe query MagicMouseM12
# Expected: STATE = 4 RUNNING
```

**Gate INSTALL-1:** both v1 and v3 LowerFilters contain `MagicMouseM12`. Service state RUNNING. Halt if either fails.

#### 7d.1 (NEW v1.4) Registry binding verification (DSM Issue 1 mitigation)

`Get-PnpDeviceProperty` queries the live PnP surface; cross-check against the on-disk registry to catch any silent rank-loss:

```pwsh
$v3LfReg = (reg query "HKLM\SYSTEM\CurrentControlSet\Enum\$v3Inst\Device Parameters" /v LowerFilters) -join "`n"
if ($v3LfReg -notmatch "MagicMouseM12") {
    Write-Error "v3 LowerFilters registry value does NOT contain MagicMouseM12. M12 lost PnP rank tie."
    Write-Error "Live PnP surface said: $((Get-PnpDeviceProperty -InstanceId $v3Inst -KeyName DEVPKEY_Device_LowerFilters).Data)"
    Write-Error "Halt. Triage Sec 7a.1 detection step; bump M12 DriverVer or remove competing INF."
    return
}
```

#### 7d.2 (NEW v1.4) Orphan LowerFilter walk (DSM Issue 7)

```pwsh
& "$PSScriptRoot\..\scripts\mm-orphan-filter-walk.ps1"
```

Script lists all `LowerFilters` MULTI_SZ values under v1/v3 BTHENUM device tree; flags any not matching `MagicMouseM12` (e.g., orphan `applewirelessmouse` references on sibling Device Parameters keys). Cleanup is operator-prompted, not automatic.

### 7e. Initial registry tunables (EXPANDED v1.4)

```pwsh
# Defaults are baked into the driver but explicit registration documents intent.
# BATTERY_OFFSET default = 1 (first byte of 46-byte payload).
# FirstBootPolicy default = 0 (STATUS_DEVICE_NOT_READY).
# MAX_STALE_MS default = 0 (v1.3 final — disabled).
# DebugLevel default = 0 (errors only; set to 4 only during VG-4 empirical-offset capture).
$svcParams = "HKLM:\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Parameters"
if (-not (Test-Path $svcParams)) {
    New-Item -Path $svcParams -Force | Out-Null
}
Set-ItemProperty -Path $svcParams -Name BATTERY_OFFSET -Value 1 -Type DWord
Set-ItemProperty -Path $svcParams -Name FirstBootPolicy -Value 0 -Type DWord
Set-ItemProperty -Path $svcParams -Name MAX_STALE_MS -Value 0 -Type DWord
Set-ItemProperty -Path $svcParams -Name DebugLevel -Value 0 -Type DWord

# Per-device CRD-style config (v1.4 — Sec 17.4 + Sec 24.3)
foreach ($pid in @("VID_004C&PID_030D", "VID_004C&PID_0310", "VID_004C&PID_0323")) {
    $devCfg = "HKLM:\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Devices\$pid"
    if (-not (Test-Path $devCfg)) { New-Item -Path $devCfg -Force | Out-Null }
    # Watchdog
    Set-ItemProperty -Path $devCfg -Name WatchdogIntervalSec -Value 30 -Type DWord
    Set-ItemProperty -Path $devCfg -Name StallThresholdSec -Value 120 -Type DWord
    # PowerSaver subkey (Sec 17.4) — defaults match MU's reasonable behavior
    $ps = "$devCfg\PowerSaver"
    if (-not (Test-Path $ps)) { New-Item -Path $ps -Force | Out-Null }
    Set-ItemProperty -Path $ps -Name Enabled -Value 1 -Type DWord
    # v1.5: aggressive defaults per user decision D-S12-45 -- all 5 events default to 1
    Set-ItemProperty -Path $ps -Name SuspendOnDisplayOff -Value 1 -Type DWord
    Set-ItemProperty -Path $ps -Name SuspendOnACUnplug -Value 1 -Type DWord
    Set-ItemProperty -Path $ps -Name SuspendOnSignOut -Value 1 -Type DWord
    Set-ItemProperty -Path $ps -Name SuspendOnSleep -Value 1 -Type DWord
    Set-ItemProperty -Path $ps -Name SuspendOnShutdown -Value 1 -Type DWord
    # SuspendCommandBytes intentionally left empty -- F22 fallback (BT disconnect) until OQ-F resolved
    Set-ItemProperty -Path $ps -Name SuspendCommandBytes -Value ([byte[]]@()) -Type Binary
}
```

**Gate INSTALL-2:** Registry tunables present (parameters subkey + per-device watchdog + PowerSaver subkey for all three PIDs). Reboot or PnP cycle picks them up at next AddDevice.

---

## 8. Rollback procedure

Run AT ANY FAILURE POINT in Sections 5-7-9. Idempotent.

### 8a. Verify recovery backup before any destructive command

```pwsh
$RecoveryPath = "D:\Backups\AppleWirelessMouse-RECOVERY"
foreach ($f in @("AppleWirelessMouse.inf", "AppleWirelessMouse.cat", "AppleWirelessMouse.sys")) {
    if (-not (Test-Path "$RecoveryPath\$f")) {
        Write-Error "MISSING: $RecoveryPath\$f -- HALT"
        return
    }
}
```

### 8b. Remove M12 (EXPANDED v1.4 — DSM Issues 5+6)

```pwsh
# Order matters: delete the INF first (releases binding), then the service entry (Issue 5).
$M12Oem = pnputil /enum-drivers |
    Select-String -Context 5,0 "MagicMouseDriver" |
    Select-String "Published Name" |
    ForEach-Object { ($_ -split ":")[1].Trim() }

if ($M12Oem) {
    pnputil /delete-driver "$M12Oem" /uninstall /force
}

# v1.4 — explicit service delete per DSM Issue 5 (orphan service entry persists otherwise)
$svcQuery = sc.exe query MagicMouseM12 2>$null
if ($LASTEXITCODE -eq 0) {
    sc.exe delete MagicMouseM12
}

# v1.4 — verify cleanup
if ((sc.exe query MagicMouseM12 2>$null) -match "MagicMouseM12") {
    Write-Warning "MagicMouseM12 service still present after sc.exe delete. May require reboot."
}
if (pnputil /enum-drivers | Select-String "MagicMouseDriver") {
    Write-Warning "MagicMouseDriver INF still present in DriverStore after pnputil delete-driver."
}
```

### 8c. Restore Apple driver

```pwsh
$appleStillThere = pnputil /enum-drivers | Select-String "applewirelessmouse"
if (-not $appleStillThere) {
    pnputil /add-driver "$RecoveryPath\AppleWirelessMouse.inf" /install
}
```

### 8d. Force re-bind to Apple driver

```pwsh
$v1Inst = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&030D*").InstanceId
$v3Inst = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&0323*").InstanceId
pnputil /disable-device "$v1Inst"; pnputil /enable-device "$v1Inst"
pnputil /disable-device "$v3Inst"; pnputil /enable-device "$v3Inst"
Start-Sleep -Seconds 5
```

### 8e. Confirm baseline

```pwsh
Get-PnpDeviceProperty -InstanceId "$v1Inst" -KeyName DEVPKEY_Device_LowerFilters
Get-PnpDeviceProperty -InstanceId "$v3Inst" -KeyName DEVPKEY_Device_LowerFilters
# Expected: applewirelessmouse on both
```

### 8f. Reg-diff

```pwsh
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
reg export HKLM\SYSTEM "$BackupRoot\HKLM-SYSTEM-post-rollback-$ts.reg" /y
bash -c "diff <(grep -v '^Windows' $BackupRoot/HKLM-SYSTEM-pre-M12.reg) <(grep -v '^Windows' $BackupRoot/HKLM-SYSTEM-post-rollback-$ts.reg) | head -100"
```

**Gate ROLLBACK-1:** Both mice show `applewirelessmouse` in LowerFilters; reg-diff shows no significant drift. Tray reports v1 battery `OK battery=N% (Feature 0x47)`.

---

## 9. Validation gates (success criteria)

### VG-0: Cached SDP descriptor matches applewirelessmouse-baseline (UPDATED v1.2)

v1.2 design does not mutate the descriptor; instead it expects the device's published descriptor (Input=47, Feature=2, LinkColl=2). VG-0 verifies the cached SDP descriptor is the correct one before any further validation.

```pwsh
$v1HidPdo = (Get-PnpDevice | Where-Object { $_.InstanceId -like "HID\*VID&0001004C_PID&030D*" -and $_.Status -eq "OK" }).InstanceId
$v3HidPdo = (Get-PnpDevice | Where-Object { $_.InstanceId -like "HID\*VID&0001004C_PID&0323*" -and $_.Status -eq "OK" }).InstanceId

& "$PSScriptRoot\..\scripts\mm-hid-descriptor-dump.ps1" -InstanceId $v1HidPdo
& "$PSScriptRoot\..\scripts\mm-hid-descriptor-dump.ps1" -InstanceId $v3HidPdo

# Expected for both v1 and v3 (applewirelessmouse-baseline / "Mode B"):
#   InputReportByteLength = 47   (RID=0x27 vendor blob defines max)
#   FeatureReportByteLength = 2  (RID=0x47 battery)
#   LinkCollections = 2          (App + Physical/Pointer)
#   InputValueCaps includes RID=0x02 (X, Y, Pan, Wheel) AND RID=0x27 (vendor blob)
#   FeatureValueCaps = 1 (RID=0x47 battery)
```

**Gate VG-0 (v1.3 dual-state):** PASS condition is EITHER:
- (i) both mice show applewirelessmouse-baseline caps (Input=47, Feature=2, LinkColl=2). M12's BRB rewriter took the fast-path (cache already had Descriptor B from prior `applewirelessmouse`). Proceed to VG-1.
- (ii) both mice show split caps (Descriptor A: COL01 Input=8 + COL02 Vendor) AND `Get-WinEvent` for the M12 ETW provider OR M12's debug log shows a `BRB_REWRITE_OK` event for each device (M12 actively rewrote the SDP TLV during this session's pairing/SDP exchange). Proceed to VG-1.

```pwsh
# v1.3 — check M12 BRB rewriter telemetry
Get-WinEvent -ProviderName "M12-Driver" -MaxEvents 50 -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -in 100,101,102 } |  # 100=BRB_REWRITE_OK, 101=BRB_REWRITE_SKIPPED, 102=BRB_REWRITE_FAILED
    Format-Table TimeCreated, Id, Message
```

FAIL conditions:
- Caps show Descriptor A AND no BRB_REWRITE_OK event: stale BTHPORT cache from pre-M12 era. Run Section 7c-pre Path A (cache wipe) or Path B (unpair/repair) to force fresh SDP — M12 BRB rewriter then injects Descriptor B.
- Caps show Mode A (Input=8 single-TLC, Feature=2, LinkColl=5): residual MU/Mode-A injection. Run Section 7c-pre, re-bind, retry.
- Caps show other variant: device firmware drift. Capture `mm-hid-descriptor-dump.ps1` output, halt, triage.

### VG-1: v1 regression baseline (v1.3 — native Feature 0x47 pass-through)

In v1.3, v1's Feature 0x47 path is M12 ForwardRequest → native firmware (per design Sec 7d PID branch). VG-1 validates that M12's queue forwarding doesn't drop or corrupt v1's working pass-through.

```pwsh
Get-Process MagicMouseTray -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process "C:\Path\To\MagicMouseTray.exe"
Start-Sleep -Seconds 30

Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 50 |
    Select-String "pid&030d.*battery=.*\(Feature 0x47\)"
# Expected: "OK ... pid&030d ... battery=NN% (Feature 0x47)"
```

**Gate VG-1:** v1 produces `OK battery=N% (Feature 0x47)` within 30 seconds, AND the percentage matches the same value the tray reported BEFORE M12 install (compare against `debug.log.pre` in `$BackupRoot`). PASS = M12 didn't regress v1's working baseline. FAIL = halt; either INF binding misrouted v1 IRPs, or queue forwarding dropped them, or the PID branch logic is wrong.

### VG-2: v3 target outcome

```pwsh
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 50 |
    Select-String "pid&0323.*battery=.*\(Feature 0x47\)"
```

**Gate VG-2:** v3 produces `OK battery=N% (Feature 0x47)` within 60 seconds.

### VG-3: Scroll on both mice

| Device | Action | Expected |
|--------|--------|----------|
| v1 | 2-finger swipe up + down + sideways | Page scrolls smoothly; cursor stays steady; left+right click work |
| v3 | Same | Same |

**Gate VG-3:** Both mice scroll fluidly. Quantitative: `WM_MOUSEWHEEL` event count >= 30 in a 3-second 2-finger gesture. v1.2 note: scroll is native pass-through (RID=0x02 unmodified) so VG-3 mostly proves the filter doesn't drop or corrupt input — it shouldn't, since M12 doesn't touch RID=0x02 IRPs.

### VG-4: Empirical battery offset confirmation (NEW v1.2)

The `BATTERY_OFFSET` default is a hypothesis (offset 1 in the 46-byte payload). VG-4 confirms or corrects it.

```pwsh
# Pre-condition: charge or discharge mouse to a known battery level (read from a SECOND
# host or the MU 3.1.5.x trial app pre-expiry — anything that doesn't depend on M12).
$known_pct = 80   # operator-supplied

# Capture LogShadowBuffer entries from debug.log (M12 logs cached payload hex on every
# Feature 0x47 query). These look like:
#   [M12] Shadow.Payload[0..45]: 32 41 00 ... <hex>
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 200 |
    Select-String "Shadow.Payload" | Select-Object -First 5

# Operator: extract the hex bytes from the most-recent line. For each byte position N
# (0..45), check whether the value plausibly matches $known_pct via the formula
# (raw - 1) * 100 / 64 where raw in [1..65]. The byte position with a matching value
# is the BATTERY_OFFSET.
#
# Run a second capture at a different battery level (e.g., charge to 100% or
# discharge to 20%) to confirm the offset. Same byte position must change in the
# expected direction.
```

**Gate VG-4:** debug.log Shadow.Payload at a known battery level contains a byte that translates (per the formula) to within ±5% of the known level, and a SECOND capture at a different known level confirms the SAME byte position changes accordingly.

If default `BATTERY_OFFSET=1` matches: no action.

If a different offset matches:

```pwsh
$svcParams = "HKLM:\SYSTEM\CurrentControlSet\Services\M12\Parameters"
Set-ItemProperty -Path $svcParams -Name BATTERY_OFFSET -Value <correct_offset> -Type DWord
pnputil /disable-device "$v3Inst"; pnputil /enable-device "$v3Inst"
# Re-run VG-2 to confirm tray now shows correct percentage.
```

If no byte position matches: `TranslateBatteryRaw()` formula likely non-linear; capture a wider battery sweep, log the raw -> %known mapping, decide on a lookup table for Phase 3.

### VG-5: Pool tag verification (NEW v1.2)

```
!poolused 4 'M12 '
```

Run in WinDbg attached as live kernel debugger, or against a memory dump.

**Gate VG-5:** at least one allocation tagged `M12 ` enumerates. Confirms MAJ-5 fix is wired up. Zero allocations is acceptable if M12 hasn't needed manual pool yet (most v1.2 paths use stack or WDF object context).

### VG-6: EvtIoStop verification under Driver Verifier (NEW v1.2)

Driver Verifier with IRP-tracking flags forces IRP cancellation on PnP stop. Confirms CRIT-3 fix.

```pwsh
verifier /flags 0x9bb /driver MagicMouseDriver.sys
# 0x9bb = standard flags
# Reboot.
```

After reboot, induce a BT disconnect (e.g., `Get-PnpDevice -InstanceId $v3Inst | Disable-PnpDevice -Confirm:$false`). Driver Verifier asserts on IRP cancellation paths.

**Gate VG-6:** No bugcheck during forced disable/enable. `verifier /query` shows zero violations against M12. Disable verifier after pass: `verifier /reset`.

### VG-7: 24-hour soak (BT sleep/wake cycles)

After VG-1, VG-2, VG-3, VG-4, VG-5, VG-6 pass, leave the system running with both mice idle. Mouse goes to sleep after ~2 minutes of inactivity (BT disconnect). Tray polls every 2 hours when battery > 50%.

```pwsh
# After 24 hours:
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 200 |
    Select-String "FEATURE_BLOCKED|OPEN_FAILED|err="
# Expected: zero matches (or only transient ones during sleep/wake)

Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 200 |
    Select-String "OK.*battery=.*\(Feature 0x47\)" |
    Measure-Object | Select-Object Count
# Expected: >= 12 successful reads
```

Specific BT sleep/wake validation:
- Operator manually puts mouse to sleep (turn off, leave 5 min, turn on) at least 3 times.
- After each wake: tray must produce `OK battery` within 60 sec.

**Gate VG-7:** Sustained `OK battery` reads on both mice for 24 hours. Sleep/wake cycles tolerated. Zero BSOD events. Driver Verifier off (re-enable for a final sanity boot if desired).

### VG-8: Power-saver functional test (NEW v1.4 — Power Saver brief)

Validates each configured power-saver event triggers suspend + wake works.

| Sub-test | Action | Expected |
|---|---|---|
| 8.1 Display off | Wait for screen timeout (or `Set-Display -Off`) | Mouse suspends within 5s; tray log records `POWER_SUSPEND_DISPLAY_OFF`. (Skip if `SuspendOnDisplayOff=0` default.) |
| 8.2 AC unplug | Disconnect AC adapter (laptop on battery) | Mouse suspends within 5s; tray log records `POWER_SUSPEND_AC_UNPLUG`. (Skip if `SuspendOnACUnplug=0` default.) |
| 8.3 Sign out | `shutdown /l` | Mouse suspends before session ends; tray log records `POWER_SUSPEND_SIGN_OUT` (via tray-app bridge per F26). |
| 8.4 Sleep | `Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Application]::SetSuspendState('Suspend', $false, $false)` | Mouse suspends; on resume, mouse wakes on click within 2s. Tray log records `POWER_SUSPEND_SLEEP` + `POWER_WAKE`. |
| 8.5 Shutdown | `shutdown /s /t 60`, cancel before timer | Mouse receives suspend command before shutdown completes. (If shutdown completes, log not retrievable post-boot — skip gating.) |
| 8.6 Manual suspend | `mm-suspend.exe` (CLI) | IOCTL_M12_SUSPEND succeeds; mouse suspends; click wakes. |
| 8.7 Wake on click | After any of 8.1-8.6 | Mouse wakes; first RID=0x27 frame arrives within 2s of click; tray reads battery within next adaptive interval. |

**Gate VG-8:** all enabled-by-default sub-tests pass (8.3, 8.4, 8.5, 8.6, 8.7). 8.1, 8.2 only tested if operator opts in. Per-event log line in tray debug.log + WPP capture matches expected event name.

**Failure mode**: if vendor suspend command bytes are unknown (OQ-F unresolved), F22 fallback (BT disconnect via `WdfIoTargetClose`) is exercised instead. Operator confirms via WPP log: `POWER_SUSPEND_FALLBACK_BT_DISCONNECT` event recorded; mouse still wakes on click via re-pair.

### VG-9: Battery-saving 24-hr measurement (NEW v1.4 — Power Saver brief)

Measures whether power-saver actually saves battery vs disabled.

```pwsh
# Run 1: power-saver disabled (control)
$ps = "HKLM:\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Devices\VID_004C&PID_0323\PowerSaver"
Set-ItemProperty -Path $ps -Name Enabled -Value 0 -Type DWord
pnputil /disable-device $v3Inst; pnputil /enable-device $v3Inst
# ... 24 hours ...
# Capture: starting battery %, ending battery %, hours of computer-on time

# Run 2: power-saver enabled (treatment)
Set-ItemProperty -Path $ps -Name Enabled -Value 1 -Type DWord
pnputil /disable-device $v3Inst; pnputil /enable-device $v3Inst
# ... 24 hours ...
# Capture same.

# Compare battery drift per hour: treatment / control. Target: treatment <= 0.5 * control.
```

**Gate VG-9:** treatment (power-saver enabled) consumes <= 50% of control (disabled) battery drift per hour over 24 hours. Modest target — primary value is qualitative (does it work at all?), not quantitative.

If F22 fallback is used (vendor command unknown), VG-9 still meaningful — BT disconnect during configured events should reduce drift even if not as efficient as native suspend.

### VG-10: Multi-mouse simultaneous read-out (NEW v1.4 — Production Hygiene brief)

Validates per-DEVICE_CONTEXT shadow buffer + spinlock provide multi-mouse independence.

**Pre-condition**: both v1 (PID 0x030D) and v3 (PID 0x0323) paired and in active use.

```pwsh
# Capture 30 minutes of tray reads — both mice in use simultaneously
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 500 |
    Select-String -Pattern "pid&030d.*battery=|pid&0323.*battery="
# Expected: interleaved OK reads for both mice; no read for one mouse blocks the other.
# Both mice produce >= 5 successful reads in the 30-min window.
```

```pwsh
# WPP per-device correlation check (Sec 19.5)
logman start M12-multi -p {8D3C1A92-B04E-4F18-9A23-7E5D4F892C12} -o multi.etl -ets
# ... 30 min ...
logman stop M12-multi -ets
tracefmt multi.etl -p <tmf-dir> -o multi-decoded.txt
# Verify: each WPP entry includes Device->Pid; events for v1 and v3 are independent (no Pid=0xFFFF or shared-context errors).
```

**Gate VG-10:** both mice produce successful battery reads in the same window; WPP entries are correctly attributed per-device.

### VG-11: Driver Verifier 0x49bb soak (NEW v1.4 — Production Hygiene brief)

```pwsh
verifier /flags 0x49bb /driver MagicMouseDriver.sys
# 0x49bb decoded:
#   0x9bb base (special pool, IRQL, IO verification, deadlock, IRP logging — VG-6 base)
#   0x10000 security checks
#   0x40000 IRP logging
# Reboot.
```

After reboot, run automated harness `scripts/test-cycle.ps1`:

- 1000 Feature 0x47 IOCTL cycles via tray polling forced rapid (override interval to 1 sec)
- 100 pair / unpair cycles via `pnputil /disable-device + /enable-device + remove-device + scan-devices` rotation

```pwsh
& "$PSScriptRoot\..\scripts\test-cycle.ps1" -Feature47Cycles 1000 -PairUnpairCycles 100
verifier /query
```

**Gate VG-11:** zero violations across all cycles. Zero BSOD. `verifier /query` reports zero flagged drivers. Disable: `verifier /reset` after pass.

### VG-12: Auto-reinit-on-wake validation (NEW v1.5 — auto-reinit feature D-S12-41)

Validates that shadow buffer is invalidated + re-primed after system sleep/wake cycle.

```pwsh
# Pre-condition: v3 mouse connected and producing battery reads (VG-2 passed)

# Step 1: confirm shadow valid (WPP log shows shadow.Valid=TRUE)
logman start M12-wake-test -p {8D3C1A92-B04E-4F18-9A23-7E5D4F892C12} -o wake-test.etl -ets

# Step 2: induce sleep
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::SetSuspendState('Suspend', $false, $false)

# Step 3: wake (move mouse or press keyboard)
# Wait 30 seconds for reconnect + re-prime
Start-Sleep -Seconds 30

# Step 4: query Feature 0x47 from tray
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 20 |
    Select-String "pid&0323.*battery="

logman stop M12-wake-test -ets
tracefmt wake-test.etl -p <tmf-dir> -o wake-decoded.txt

# Gate check: WPP log must show EvtDeviceD0Entry event with "shadow invalidated"
# followed by either a M12_TryPrimeShadowBuffer success or an organic RID=0x27 frame
Select-String -Path wake-decoded.txt -Pattern "shadow invalidated|PrimeShadowBuffer|RID=0x27"
```

**Gate VG-12:** WPP log shows `shadow invalidated` on wake. Battery read (tray log `OK battery=N%`) succeeds within 60s of wake. No BSOD during sleep/wake cycle.

### VG-13: Battery polling fallback for cold shadow buffer (NEW v1.5 — fallback feature D-S12-42)

Validates that the `ColdShadowThresholdMs` (60s default) path issues GET_REPORT and populates shadow before completing Feature 0x47.

```pwsh
# Step 1: verify mouse connected but shadow cold (force it by PnP disable+enable)
pnputil /disable-device $v3Inst
Start-Sleep -Seconds 2
pnputil /enable-device $v3Inst
# After enable, shadow.Valid=FALSE (EvtDeviceD0Entry invalidates it)
# Do NOT move the mouse -- avoid organic RID=0x27 frames

# Step 2: set DebugLevel=3 to capture shadow activity
Set-ItemProperty -Path $svcParams -Name DebugLevel -Value 3 -Type DWord

# Step 3: immediately query Feature 0x47 (before 60s threshold elapses)
$elapsed = Measure-Command {
    & scripts\mm-hid-feature-read.ps1 -InstanceId $v3Inst -ReportId 0x47
}

# Step 4: check WPP log
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 20 |
    Select-String "PrimeShadowBuffer|ColdShadowThreshold|shadow cold"
```

**Gate VG-13:** When shadow is cold at the time of Feature 0x47 query:
- WPP log shows `shadow cold` + `PrimeShadowBufferSync` call.
- Either: PrimeShadow succeeds within 500ms timeout and tray receives `OK battery=N%` in the same poll; OR: PrimeShadow times out and tray receives `STATUS_DEVICE_NOT_READY` (acceptable -- mouse may not be responsive within 500ms of reconnect).
- Zero BSOD. No deadlock (5-second watchdog on the sync call).

Reset: `Set-ItemProperty -Path $svcParams -Name DebugLevel -Value 0 -Type DWord`

---

### VG-14: Self-tuning battery offset detection (NEW v1.6 -- self-tuning feature D-S12-52)

Validates that on a fresh install (BatteryByteOffset absent or 0xFFFFFFFF), the driver enters LEARNING mode, captures frames, selects the offset, writes to CRD config, and logs the result.

```pwsh
# Step 1: ensure fresh LEARNING mode by removing BatteryByteOffset from CRD config
$crdPath = "HKLM:\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Devices\<HardwareKey>"
Remove-ItemProperty -Path $crdPath -Name BatteryByteOffset -ErrorAction SilentlyContinue

# Step 2: set DebugLevel=3 to capture LEARNING events
Set-ItemProperty -Path $svcParams -Name DebugLevel -Value 3 -Type DWord

# Step 3: PnP cycle to trigger EvtDriverDeviceAdd (reads BatteryByteOffset, enters LEARNING)
pnputil /disable-device $v3Inst
Start-Sleep -Seconds 2
pnputil /enable-device $v3Inst

# Step 4: use the mouse normally for 5 minutes
# (or use the test harness to inject synthetic RID=0x27 frames if hardware is not available)
Write-Host "Use the mouse for 5 minutes, then check the log..."
Start-Sleep -Seconds 300

# Step 5: check WPP log for self-tuning decision
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 30 |
    Select-String "self-tuning detected|LearningMode|BatteryByteOffset"

# Step 6: verify CRD config was written
Get-ItemProperty -Path $crdPath -Name BatteryByteOffset
```

**Gate VG-14:** After 5 minutes of normal mouse use (or 100 RID=0x27 synthetic frames):
- WPP log shows `self-tuning detected offset N` where N is in [0..45].
- CRD registry key `BatteryByteOffset` is present at the detected offset value.
- Subsequent Feature 0x47 query returns plausible battery percentage (not `STATUS_DEVICE_NOT_READY` and not 0% / 100% stuck).
- If zero candidates detected: WPP shows warning + fallback to offset 0; tray shows N/A until VG-4 manual override applied (acceptable degradation path).

Reset: `Set-ItemProperty -Path $svcParams -Name DebugLevel -Value 0 -Type DWord`

---

## 10. Health checks

### 10a. BSOD watch

```pwsh
Get-WinEvent -LogName System -MaxEvents 20 -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -eq 1001 -or $_.LevelDisplayName -eq "Critical" } |
    Select-Object TimeCreated, Id, Message
```

### 10b. Driver Verifier (UPDATED v1.2)

```pwsh
# Recommended flags for first install
verifier /flags 0x9bb /driver MagicMouseDriver.sys
# 0x9bb decoded:
#   0x001 special pool
#   0x002 force IRQL checking
#   0x008 I/O verification
#   0x010 deadlock detection      <-- catches CRIT-2 if it regressed
#   0x080 IRP logging              <-- catches CRIT-3 if EvtIoStop regressed
#   0x100 disk integrity (n/a)
#   0x200 enhanced I/O verification
#   0x400 (reserved for advanced WDF checks if available)
# Reboot required.
```

After 24 hr soak: `verifier /reset` then reboot.

### 10c. Tray log monitoring

```pwsh
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Wait -Tail 20
```

### 10d. Service health

```pwsh
sc.exe query M12
sc.exe queryex M12 | Select-String "STATE|EXIT_CODE"
```

### 10e. Pool tag continuity (NEW v1.2)

Periodically during soak (every few hours):

```
!poolused 4 'M12 '
```

Should be stable or trending — sustained growth = leak.

---

## 11. Failure modes and recovery

| Failure | Symptom | Recovery action |
|---------|---------|-----------------|
| Build fails | exit != 0 | Read msbuild log; fix code; rebuild. No system mutation. |
| Signing fails | cert chain not trusted | Re-run Section 6a. |
| `pnputil /add-driver` fails (signature) | Error 0xE0000247 | Test signing not enabled or .cat not signed. Re-verify, retry. |
| M12 doesn't bind after Disable+Enable | LowerFilters missing M12 | Apple INF outranks. Run Section 8 rollback, then run M12 INF with `/force`. |
| BSOD on bind | bugcheck 0xC4 / 0x9F / 0x3B | Force-shutdown, boot Safe Mode, run Section 8b-c-d. Triage from `MEMORY.DMP`. Common 0xC4: Driver Verifier IRP/IoTarget violation — re-check CRIT-1..CRIT-4 implementation. |
| v1 regresses (VG-1 fails) | v1 tray log shows err=87 | Likely `BATTERY_OFFSET` mismatch v1 vs v3. Capture LogShadowBuffer for v1, compute v1-specific offset, set `BATTERY_OFFSET` per-device-instance via PnP `Parameters` subkey. |
| v3 produces no battery (VG-2) | v3 tray log shows STATUS_DEVICE_NOT_READY | Either: (a) Shadow.Valid=FALSE persistently — RID=0x27 not arriving (check VG-0 caps), (b) FirstBootPolicy mismatch — set to 1 to fall back to `[0x47, 0x00]`. |
| Battery percentage wrong (VG-2 + VG-4 mismatch) | Tray shows e.g. 100% when device is 20% | Wrong `BATTERY_OFFSET`. Re-run VG-4 capture, identify correct offset, update registry, re-bind. |
| v3 scroll dropped events (VG-3) | Scroll feels stuck | Surprising — M12 doesn't touch scroll. Likely a HidBth or HidClass bug; capture WinDbg trace; consider compatibility issue. |
| Reg-diff post-rollback drift | > 5 unrelated entries | Inspect each delta; restore individually; rerun reg-diff. |
| Driver Verifier triggers 0xC4 on first bind | DV detected violation | Most likely CRIT-3 regression (missing EvtIoStop on a queue). Check Verifier dump; fix in code; rebuild. |
| Pool tag `M12 ` not enumerable post-install (VG-5 zero hits) | M12 not allocating from manual pool | Acceptable in v1.2 — most paths use WDF context. Consider non-blocking. |
| F22: Vendor suspend command unknown (VG-8 fallback) | mouse doesn't enter low-power state on suspend event | F22 BT-disconnect fallback fires automatically when `SuspendCommandBytes` empty. Tray-app log `POWER_SUSPEND_FALLBACK_BT_DISCONNECT`. Once OQ-F resolved, populate `SuspendCommandBytes` REG_BINARY at PowerSaver subkey. |
| F23: Competing INF rank loss (post-install verify fails) | `MagicMouseM12` not in LowerFilters | Re-run Sec 7a.1 detection step. Bump M12 DriverVer (e.g., to `01/01/2028, 1.1.0.0`) and rebuild, OR remove competing INF (after AP-24 backup-verify). |
| F24: Orphan `MagicMouseM12` service after rollback | sc.exe query shows STOPPED + EXIT_CODE 31 | Sec 8b includes explicit `sc.exe delete`. If still present after reboot, delete via registry: `reg delete HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseM12 /f`. |
| F25: Sticky `applewirelessmouse` in sibling LowerFilters | mm-orphan-filter-walk.ps1 reports orphan reference | Cleanup script removes `applewirelessmouse` from sibling Device Parameters keys. Non-fatal (cosmetic). |
| F26: Sign-out suspend not triggered | tray shows mouse never went to sleep at sign-out | Tray-app must be running at sign-out for the WTSRegisterSessionNotification bridge. If tray not running, verify M12 service registered for SERVICE_CONTROL_SESSIONCHANGE (fallback path). Phase 3 implementation choice. |
| F27: Watchdog WARNING spam | log fills with stall-detected events | Operator raises `StallThresholdSec` from 120 to higher (e.g., 600 = 10 min) at `HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Devices\<HardwareKey>\StallThresholdSec`. PnP cycle to reload. |
| Power-saver enabled but VG-9 shows no measurable savings | treatment battery drift == control | Likely F22 fallback in use (vendor command unknown). BT-disconnect fallback is less efficient. Resolve OQ-F. |
| Multi-mouse VG-10 fails — one mouse blocks the other | shadow contention or shared spinlock | Verify DEVICE_CONTEXT is per-instance (each PnP node gets its own context). Check INF didn't somehow declare a singleton. WPP log shows shared device pointer = bug. |
| DV 0x49bb VG-11 violation | special pool / IRP logging / security check fired | Triage from `MEMORY.DMP`. Common: Sec 18 IOCTL handler missing range check; Sec 23.2 DEVICE_CONTEXT signature not initialized; Sec 3b' BRB rewriter abandon condition missed. |

---

## 12. Sign-off checklist

```
[ ] PRE-1:        Pre-flight backup verified
[ ] PRE-INSTALL-1 (v1.4): rank-loss check + stale service + DriverStore staged-package cleanup
[ ] BUILD-1:      MagicMouseDriver.sys + .inf in build output
[ ] BUILD-2:      hidparser.exe validates 116-byte reference descriptor
[ ] BUILD-3:      pool tag 'M12 ' present in binary
[ ] BUILD-4 (v1.4): TMF file generated alongside .sys (WPP support, Sec 19)
[ ] BUILD-5 (v1.5): PREfast 0 Code Analysis warnings (gate per D-S12-43)
[ ] BUILD-6 (v1.5): .inf files confirmed CRLF via git ls-files --eol (gate per D-S12-49)
[ ] BUILD-7 (v1.5): SDV 0 defects in sdv-report.xml (gate per D-S12-44)
[ ] SIGN-1:       signtool verify successful (RFC 3161 SHA256)
[ ] 7a:           applewirelessmouse removed from LowerFilters
[ ] 7a.1 (v1.4):  no competing INF with DriverVer >= 01/01/2027
[ ] 7a.2 (v1.4):  no stale MagicMouseM12 service
[ ] 7a.3 (v1.4):  no stale MagicMouseDriver INF in DriverStore
[ ] 7e:           registry tunables BATTERY_OFFSET + FirstBootPolicy + MAX_STALE_MS + DebugLevel set
[ ] 7e (v1.4):    per-device Watchdog + PowerSaver subkeys created for all 3 PIDs
[ ] 7e (v1.5):    PowerSaver defaults verified: SuspendOnDisplayOff=1, SuspendOnACUnplug=1
[ ] INSTALL-1:    MagicMouseM12 LowerFilters bound to v1 + v3, service RUNNING
[ ] 7d.1 (v1.4):  registry binding cross-check (reg query) confirms M12 wins rank
[ ] 7d.2 (v1.4):  orphan-filter walk reports clean BTHENUM tree
[ ] VG-0:         HIDP_GetCaps shows applewirelessmouse-baseline (Input=47, Feature=2, LinkColl=2)
[ ] VG-1:         v1 produces OK battery (Feature 0x47) within 30s
[ ] VG-2:         v3 produces OK battery (Feature 0x47) within 60s
[ ] VG-3:         scroll fluid on both mice
[ ] VG-4:         BATTERY_OFFSET confirmed via debug.log diff at known battery levels
[ ] VG-5:         pool tag 'M12 ' verifiable in WinDbg !poolused
[ ] VG-6:         no Driver Verifier violations under flags 0x9bb during forced disable
[ ] VG-7:         24-hour soak with BT sleep/wake cycles, >= 12 OK reads, zero err= entries, zero BSOD
[ ] VG-8 (v1.4):  power-saver functional test (sleep/sign-out/shutdown/manual + wake on click)
[ ] VG-9 (v1.4):  battery-saving 24-hr A/B (treatment <= 50% control drift)
[ ] VG-10 (v1.4): multi-mouse simultaneous read-out (v1+v3 independent)
[ ] VG-11 (v1.4): Driver Verifier 0x49bb soak: 1000 IOCTL + 100 pair/unpair = 0 violations
[ ] VG-12 (v1.5): auto-reinit-on-wake: shadow invalidated + battery read OK within 60s post-wake
[ ] VG-13 (v1.5): battery-polling-fallback: cold shadow triggers GET_REPORT; no deadlock
[ ] VG-14 (v1.6): self-tuning offset: WPP log shows "self-tuning detected offset N" within 5 min of use; Feature 0x47 returns plausible percentage
[ ] PRIVACY-1 (v1.6): docs/PRIVACY-POLICY.md reviewed and current; no network connections added since last review
[ ] HEALTH-10a:   no BSOD events in System log
[ ] HEALTH-10d:   service state RUNNING throughout

Operator: ____________________________  Date: __________

Sign-off complete -> M12 ratified for personal-use deployment.
WHQL submission OUT of scope.
```

---

## 13. Appendix: command quick-reference

| Operation | Command |
|-----------|---------|
| Capture pre-state | `pnputil /enum-drivers > pre.txt; reg export HKLM\SYSTEM pre.reg /y` |
| Build | `msbuild MagicMouseDriver.vcxproj /p:Configuration=Debug /p:Platform=x64` |
| Sign .sys | `signtool sign /v /s My /n "MagicMouseTray-TestSign" /tr http://timestamp.digicert.com /td SHA256 /fd SHA256 MagicMouseDriver.sys` |
| Build .cat | `inf2cat /driver:$BuildOut /os:10_X64` |
| Install | `pnputil /add-driver MagicMouseDriver.inf /install` |
| Force rebind | `pnputil /disable-device <id>; pnputil /enable-device <id>` |
| Verify bind | `Get-PnpDeviceProperty -InstanceId <id> -KeyName DEVPKEY_Device_LowerFilters` |
| Service status | `sc.exe query MagicMouseM12` |
| Tray log tail | `Get-Content $env:APPDATA\MagicMouseTray\debug.log -Tail 50` |
| Set battery offset | `Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Parameters -Name BATTERY_OFFSET -Value N -Type DWord` |
| Pool tag enumerate (WinDbg) | `!poolused 4 'M12 '` |
| Driver Verifier (basic) | `verifier /flags 0x9bb /driver MagicMouseDriver.sys` |
| Driver Verifier (v1.4 ship) | `verifier /flags 0x49bb /driver MagicMouseDriver.sys` |
| Driver Verifier off | `verifier /reset` |
| Uninstall | `pnputil /delete-driver oem<N>.inf /uninstall /force; sc.exe delete MagicMouseM12` |
| Reset signing test mode | `bcdedit /set testsigning off` (reboot) |
| WPP capture start | `logman start M12 -p {8D3C1A92-B04E-4F18-9A23-7E5D4F892C12} -o capture.etl -ets` |
| WPP capture stop + decode | `logman stop M12 -ets; tracefmt capture.etl -p <tmf-dir> -o decoded.txt` |
| Set DebugLevel for offset workflow | `Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Parameters -Name DebugLevel -Value 4 -Type DWord` |
| Manual suspend (CLI) | `mm-suspend.exe` (sends IOCTL_M12_SUSPEND) |
| Orphan filter walk | `& scripts\mm-orphan-filter-walk.ps1` |
| Registry binding cross-check | `reg query "HKLM\SYSTEM\CurrentControlSet\Enum\<Inst>\Device Parameters" /v LowerFilters` |
