# M13 Method of Procedure (MOP)

**Status:** v1.0 — FINAL (peer-reviewed, NLM-verified, empirically grounded)
**Date:** 2026-04-29
**Linked design spec:** `docs/M13-DESIGN-SPEC.md`
**Linked PRD:** PRD-184 v1.25.0 (`Personal/prd/184-magic-mouse-windows-tray-battery-monitor.md`)
**Linked PSN:** `PSN-0001-hid-battery-driver.yaml` (12 sessions, all hypotheses resolved)
**Linked peer review:** `.ai/peer-reviews/380b61f0-0815-4390-8b91-b4a0e2e8f6b0.yaml` (T3, APEX 7/10)
**NLM notebook:** `91f8a4d2-d24f-4bad-8a4c-fcd22d8fdee1` (M13 Peer Review — SDP injection)
**BCP reference:** BCP-OPS-501 (Change Management) — pre-flight + rollback + health-check pattern.
**Related rules:** AP-24 — backup before any destructive command (non-negotiable).

---

## EMPIRICAL FOUNDATION

> This MOP is written entirely from confirmed data, not assumptions. Every design decision
> traces to a specific measurement. Section 15 (Appendix) lists all empirical sources.

| Fact | Source | Confirmed |
|------|--------|-----------|
| SDP record = 351 bytes, top-level `36 01 5C` (0x36 2-byte length) | bthport-discovery-d0c050cc8c4d.txt | 2026-04-29 |
| Attribute 0x0206 inner sequences use `0x35` (1-byte length) | Same file, offset ~0xA0: `09 02 06 35 8D 35 8B 08 22 25 87` | 2026-04-29 |
| Native descriptor = 135 bytes (`25 87`), Descriptor C = 106 bytes | HidDescriptor.c + trace | 2026-04-29 |
| Battery: COL02 (UP=0xFF00, U=0x0014), RID=0x90, buf[2]=battery% | PSN-0001 M1, battery-probe traces | 2026-04-27 |
| IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE = 0x00410210 | Ghidra RE of applewirelessmouse.sys | 2026-04-29 |
| Apple's filter is the source of A/B descriptor flip | SESSION-12, H-010 CONFIRMED | 2026-04-29 |
| M13 replacing Apple's filter eliminates the flip source | Architecture decision D-016 | 2026-04-29 |
| v3 PID=0x0323, VID=0x004C, MAC=d0c050cc8c4d | PnP enumeration, HID probe | 2026-04-27 |
| v1 PID=0x030D, VID=0x004C — regression control device | PnP enumeration | 2026-04-27 |

---

## 1. BLUF

This MOP is the canonical end-to-end procedure for building, signing, installing, validating,
and rolling back the M13 KMDF lower filter driver on the Magic Mouse v3 (PID 0x0323) test
machine, with Magic Mouse v1 (PID 0x030D) as regression control.

**What M13 does:** Intercepts `IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE` (0x410210) completions
on the BTHENUM HID PDO, rewrites SDP attribute 0x0206 to inject Descriptor C (106 bytes:
RID=0x02 Mouse with scroll + RID=0x90 vendor battery) in place of the native 135-byte
descriptor. This causes HidBth to enumerate scroll + battery simultaneously, without userland
translation, without Apple's filter as a dependency, and without the A/B descriptor flip.

**What M13 does NOT do:** Translate input reports (v3 firmware natively emits RID=0x02
layout), touch any RID other than injecting the descriptor, communicate with userland,
require Magic Utilities or any other third-party driver.

**Three MVPs — each is a boolean gate:**

| MVP | Gate | Pass Condition |
|-----|------|----------------|
| MVP1 | VG-0 | `SdpPatchSuccess > 0` in diagnostic registry — proves IOCTL intercepted and SDP patched |
| MVP2 | VG-1 | Scroll working on v3 (WM_MOUSEWHEEL events, page scrolls) |
| MVP3 | VG-2 | Battery readable: tray shows `OK battery=N% (split)` for v3 |

MVP1 is the primary technical gate. MVP2 and MVP3 are the user-visible outcomes. All must pass
before this is considered production-ready. v1 must not regress at any point (VG-3).

### CRITICAL prerequisite: cert trust install (PRIMARY path)

M13 ships as a self-signed driver (CN=MagicMouseFix, same model used by MagicMouseFix/Rain9333,
empirically validated). Before driver install, run the cert trust script once as admin. This
installs M13's public cert into LocalMachine\Root + LocalMachine\TrustedPublisher. No "Test Mode"
watermark, no BCD edit.

```powershell
# Step 1: Verify thumbprint before trusting
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 "M13-Driver.cer"
Write-Host "Thumbprint: $($cert.Thumbprint)"
# Compare against expected thumbprint in INSTALL.md before proceeding

# Step 2: Install cert trust (admin PowerShell)
.\scripts\install-m12-trust.ps1 -CertFile "M13-Driver.cer"
```

**FALLBACK: Test-signing mode** (if user prefers not to trust M13 cert):

```powershell
bcdedit /set testsigning on
# Reboot required. Desktop shows "Test Mode" watermark.
```

---

## 2. Revision History

| Version | Date | Changes |
|---------|------|---------|
| v1.0 | 2026-04-29 | Initial MOP. Full empirical foundation from 12 prior sessions. SDP format confirmed from bthport-discovery-d0c050cc8c4d.txt. Peer reviewed T3 (APEX 7/10). |

---

## 3. Scope

| Item | Value |
|------|-------|
| Target machine | Lesley's Windows 11 Home dev machine (3 mice: v3, v1, Dell USB) |
| Target devices | Magic Mouse v3 (BTHENUM PID 0x0323) PRIMARY + Magic Mouse v1 (PID 0x030D) REGRESSION CONTROL |
| Dell USB mouse | Unaffected by M13 INF (different hardware ID) — used to confirm system mouse still works during any outage |
| Driver under test | `MagicMouseDriver.sys` (M13), built from `driver/` in this repository |
| Build environment | EWDK 25H2 mounted at `F:\` (or `D:\ewdk25h2` if F: unavailable) |
| Build host | Same Windows 11 Home dev machine |
| Signing (PRIMARY) | Self-signed cert (CN=MagicMouseFix) + cert trust install (install-m12-trust.ps1) |
| Signing (FALLBACK) | Test-signing mode (bcdedit testsigning on) |
| Apple driver | `applewirelessmouse.sys` REMOVED during M13 install — M13 is the sole lower filter |
| HWID | `BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0001004C_PID&0323` |
| M13 DriverVer | `01/01/2027,2.0.0.0` (beats Apple's `04/21/2026`) |
| Service name | `MagicMouseDriver` |
| Pool tag | `MsmD` |

---

## 4. Prerequisites

### 4a. Signing mode (PRIMARY: cert trust / FALLBACK: testsigning)

**PRIMARY (recommended):** cert trust must be installed before driver install. Verify:

```powershell
Get-ChildItem Cert:\LocalMachine\TrustedPublisher |
    Where-Object { $_.Subject -like "*MagicMouseFix*" -or $_.Subject -like "*M13-Driver*" }
# Expected: one cert entry. If empty: run install-m12-trust.ps1 as admin (Section 1).
```

**FALLBACK only:** If using test-signing instead of cert trust:

```powershell
bcdedit | Select-String "testsigning"
# Expected: "testsigning             Yes"
# If No: bcdedit /set testsigning on && Reboot
```

### 4b. EWDK Build Environment

```powershell
# Verify EWDK mount
Test-Path "F:\BuildEnv.cmd"   # or D:\ewdk25h2\BuildEnv.cmd
# Expected: True

# Verify MSBuild available in EWDK
cmd /c "F:\BuildEnv.cmd && msbuild /version"
# Expected: Microsoft (R) Build Engine version 17.x
```

### 4c. Recovery backup verification (AP-24 — NON-NEGOTIABLE)

**Do not proceed past this gate if any backup file is missing.**

```powershell
$RecoveryPath = "D:\Backups\AppleWirelessMouse-RECOVERY"
$RequiredFiles = @(
    "AppleWirelessMouse.inf",
    "AppleWirelessMouse.cat",
    "AppleWirelessMouse.sys"
)
$AllPresent = $true
foreach ($f in $RequiredFiles) {
    $path = "$RecoveryPath\$f"
    if (Test-Path $path) {
        $hash = (Get-FileHash $path -Algorithm SHA256).Hash
        Write-Host "PRESENT: $f ($hash)"
    } else {
        Write-Error "MISSING: $path — HALT per AP-24"
        $AllPresent = $false
    }
}
if (-not $AllPresent) { throw "Recovery backup incomplete — do not proceed" }
```

**Gate PRE-1:** All 3 recovery files present with valid hashes. Hash list committed in `APPLE-DRIVER-RECOVERY-PROCEDURE.md`. FAIL = halt, refresh recovery backup before proceeding.

### 4d. Device topology baseline

```powershell
# Confirm all 3 mice are enumerated
$v1 = Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&030D*" -EA SilentlyContinue
$v3 = Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&0323*" -EA SilentlyContinue
$dell = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*Dell*" -or $_.FriendlyName -like "*USB*mouse*" } -EA SilentlyContinue
Write-Host "v1: $($v1.Status)  v3: $($v3.Status)  Dell: $($dell.Status)"
# Expected: OK OK OK

# Confirm Apple filter is currently installed on v3
Get-PnpDeviceProperty -InstanceId $v3.InstanceId -KeyName "DEVPKEY_Device_LowerFilters" |
    Select-Object Data
# Expected: {applewirelessmouse}
```

**Gate PRE-2:** v1=OK, v3=OK, Dell USB mouse accessible (safety net). Apple filter present on v3. FAIL = investigate device state before proceeding.

### 4e. SDP cache baseline snapshot

```powershell
# Read current HidBth SDP cache for v3 (MAC = d0c050cc8c4d)
$mac = "d0c050cc8c4d"
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$mac\CachedServices\00010000"
if (Test-Path $regPath) {
    $blob = (Get-ItemProperty -Path $regPath).'(default)'
    if ($null -eq $blob) { $blob = (Get-ItemPropertyValue -Path $regPath -Name "(default)" -EA SilentlyContinue) }
    Write-Host "SDP cache blob length: $($blob.Length) bytes"
    Write-Host "First 16 bytes: $(($blob[0..15] | ForEach-Object { $_.ToString('X2') }) -join ' ')"
    # Expected: 351 bytes, first 3: "36 01 5C"
} else {
    Write-Warning "SDP cache not found for MAC $mac — v3 not yet paired or cache cleared"
}
```

**Gate PRE-3 (advisory):** SDP cache = 351 bytes, starts with `36 01 5C`. This is the native record. After M13 installs and v3 is re-paired, this cache will update to the patched record (319 bytes, starts with `36 01 3F`). FAIL = investigate (wrong MAC, cache cleared); proceed anyway — M13 will set cache correctly on first pair/SDP exchange.

### 4f. Tray baseline capture

```powershell
$TrayLog = "$env:APPDATA\MagicMouseTray\debug.log"
if (Test-Path $TrayLog) {
    Copy-Item $TrayLog "$env:APPDATA\MagicMouseTray\debug.log.pre-m13"
    Get-Content $TrayLog -Tail 30
}
# Note: tray should currently show "OK battery=N% (Feature 0x47)" or "(split)" for v1
# and same for v3 (if Apple filter is working).
```

---

## 5. Pre-flight backup (BCP-OPS-501)

Run ALL backup steps before any system modification. Each step creates a timestamped artifact.

```powershell
$BackupRoot = "D:\Backups\M13-Install-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
Write-Host "Backup root: $BackupRoot"

# 5a. Full HKLM\SYSTEM registry export
reg export HKLM\SYSTEM "$BackupRoot\HKLM-SYSTEM-pre-M13.reg" /y
Write-Host "Registry export: DONE"

# 5b. Device topology snapshot (PnP device list)
Get-PnpDevice | Export-Csv "$BackupRoot\pnp-devices-pre-M13.csv" -NoTypeInformation
Write-Host "PnP device snapshot: DONE"

# 5c. Driver store snapshot
pnputil /enum-drivers > "$BackupRoot\driver-store-pre-M13.txt"
Write-Host "Driver store snapshot: DONE"

# 5d. LowerFilters values for v1 and v3
$v1Id = (Get-PnpDevice -InstanceId "BTHENUM\*PID&030D*").InstanceId
$v3Id = (Get-PnpDevice -InstanceId "BTHENUM\*PID&0323*").InstanceId
@{
    v1_InstanceId = $v1Id
    v3_InstanceId = $v3Id
    v1_LowerFilters = (Get-PnpDeviceProperty -InstanceId $v1Id -KeyName DEVPKEY_Device_LowerFilters).Data
    v3_LowerFilters = (Get-PnpDeviceProperty -InstanceId $v3Id -KeyName DEVPKEY_Device_LowerFilters).Data
} | ConvertTo-Json | Set-Content "$BackupRoot\lower-filters-pre-M13.json"
Write-Host "LowerFilters snapshot: DONE"

# 5e. SDP cache blob (raw)
$mac = "d0c050cc8c4d"
$sdpReg = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$mac\CachedServices\00010000"
if (Test-Path $sdpReg) {
    reg export "HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$mac" "$BackupRoot\sdp-cache-pre-M13.reg" /y
    Write-Host "SDP cache backup: DONE"
} else {
    Write-Host "SDP cache backup: SKIPPED (not found)"
}

# 5f. Tray log
if (Test-Path "$env:APPDATA\MagicMouseTray\debug.log") {
    Copy-Item "$env:APPDATA\MagicMouseTray\debug.log" "$BackupRoot\tray-debug-pre-M13.log"
    Write-Host "Tray log backup: DONE"
}

# 5g. Current applewirelessmouse oem INF name (for rollback)
$appleOem = pnputil /enum-drivers |
    Select-String -Context 0,5 "applewirelessmouse" |
    ForEach-Object { $_.Line } |
    Select-String "Published Name" |
    ForEach-Object { ($_ -split ":")[1].Trim() }
if ($appleOem) {
    $appleOem | Set-Content "$BackupRoot\apple-oem-inf-name.txt"
    Write-Host "Apple OEM INF name ($appleOem): saved"
} else {
    Write-Warning "Apple oem INF not found in driver store — Apple filter may not be installed"
}

Write-Host ""
Write-Host "Pre-flight backup complete: $BackupRoot"
Write-Host "Verify all files exist before proceeding:"
Get-ChildItem $BackupRoot | Format-Table Name, Length
```

**Gate BACKUP-1:** All files created. No errors. `$BackupRoot` path recorded for rollback reference. FAIL = halt; do not proceed until backup is complete.

---

## 6. Build procedure

Open an EWDK command prompt for all build steps:

```cmd
cmd /c "F:\BuildEnv.cmd && start cmd"
```

All subsequent build steps run in this EWDK command prompt.

### BUILD-1: Clean build

```cmd
cd /d "C:\Users\Lesley\.claude\worktrees\ai-m12-script-tests\driver"
set BuildOut=..\build\x64\Release
msbuild MagicMouseDriver.vcxproj /p:Configuration=Release /p:Platform=x64 /t:Clean,Build /m
```

**Gate BUILD-1:** Exit code 0. `%BuildOut%\MagicMouseDriver.sys` exists.

### BUILD-2: PREfast static analysis (zero warnings required)

```cmd
msbuild MagicMouseDriver.vcxproj /p:Configuration=Release /p:Platform=x64 /p:RunCodeAnalysis=true /m 2>&1 | findstr /i "warning error"
```

**Gate BUILD-2:** Output shows `0 Code Analysis warning(s)`. Any PREfast warning is a FAIL — fix before proceeding. Common PREfast issues: uninitialized output params, missing SAL annotations, locked/unlocked imbalance.

### BUILD-3: SDV (Static Driver Verifier) — optional but strongly recommended

```cmd
msbuild MagicMouseDriver.vcxproj /p:Configuration=Release /p:Platform=x64 /p:EnableSDV=true /m
# Then open sdv-report.xml in Visual Studio or:
type .\sdv\sdv-report.xml | findstr /i "defect"
```

**Gate BUILD-3:** SDV report shows 0 defects. If SDV takes > 30 min, skip and proceed — SDV is a quality gate, not a functional gate for MVP1.

### BUILD-4: Line endings check

```cmd
git ls-files --eol driver\*.c driver\*.h driver\*.inf
```

**Gate BUILD-4:** All `.c`, `.h`, `.inf` files show `w/crlf` or `w/lf` (no mixed line endings). Mixed endings cause CRLF-sensitive WDK tools to fail.

### BUILD-5: Pool tag verification in source

```cmd
findstr /i "MsmD\|ExAllocatePool" driver\Driver.c driver\InputHandler.c
```

**Gate BUILD-5:** Pool tag `'MsmD'` present in allocations. No bare `ExAllocatePool` without tag.

### BUILD-6: Binary size sanity

```powershell
$sys = Get-Item "$BuildOut\MagicMouseDriver.sys"
Write-Host "Driver size: $($sys.Length) bytes"
# Expected: 40 KB – 200 KB (M13 is ~600 LOC, expect ~60-80 KB)
# Anomaly: < 20 KB = linker stripped too much; > 500 KB = wrong config (debug build?)
```

**Gate BUILD-6:** Driver binary 20 KB – 500 KB. Outside range = investigate before signing.

### BUILD-7: Descriptor C byte count verification

```powershell
# Read HidDescriptor.c and verify g_HidDescriptorSize = 106 bytes
$content = Get-Content "driver\HidDescriptor.c" -Raw
if ($content -match 'const ULONG g_HidDescriptorSize\s*=\s*sizeof\(g_HidDescriptor\)') {
    Write-Host "g_HidDescriptorSize: sizeof(g_HidDescriptor) — compile-time computed"
    # Count bytes in g_HidDescriptor[] array definition
    $bytesLine = $content | Select-String -Pattern '0x[0-9A-Fa-f]{2}' -AllMatches
    Write-Host "Hex byte count (approx): $(($content | Select-String -Pattern '0x[0-9A-Fa-f]{2}' -AllMatches).Matches.Count)"
    # Expected: 106 matching hex literals
}
```

**Gate BUILD-7:** Descriptor C = 106 bytes. Mismatch means HidDescriptor.c was modified — re-verify against known-good byte count in Appendix (Section 15).

---

## 7. Sign procedure

### 7a. Generate self-signed cert (if not already done)

```powershell
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject "CN=MagicMouseFix" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -NotAfter (Get-Date).AddYears(5)
Write-Host "Thumbprint: $($cert.Thumbprint)"

# Export public cert for distribution
Export-Certificate -Cert $cert -FilePath "M13-Driver.cer" -Type CERT
Write-Host "Exported: M13-Driver.cer"
```

### 7b. Sign the driver binary

```powershell
$ewdkBin = "F:\Program Files\Windows Kits\10\bin\10.0.26100.0\x64"
$signtool = "$ewdkBin\signtool.exe"
$BuildOut = ".\build\x64\Release"

& $signtool sign `
    /v `
    /s My `
    /n "MagicMouseFix" `
    /tr http://timestamp.digicert.com `
    /td SHA256 `
    /fd SHA256 `
    "$BuildOut\MagicMouseDriver.sys"

& $signtool verify /v /pa "$BuildOut\MagicMouseDriver.sys"
```

**Gate SIGN-1:** `signtool verify` shows "Successfully verified". Failure: timestamp server unreachable → retry or use `/t http://timestamp.digicert.com` (SHA1 fallback only if /tr fails; not preferred on Win11 22H2+).

### 7c. Generate + sign catalog

```powershell
$inf2cat = "F:\Program Files\Windows Kits\10\bin\10.0.26100.0\x86\Inf2Cat.exe"
& $inf2cat /driver:$BuildOut /os:10_X64

& $signtool sign `
    /v `
    /s My `
    /n "MagicMouseFix" `
    /tr http://timestamp.digicert.com `
    /td SHA256 `
    /fd SHA256 `
    "$BuildOut\MagicMouseDriver.cat"

& $signtool verify /v /pa "$BuildOut\MagicMouseDriver.cat"
```

**Gate SIGN-2:** Catalog verifies. `CN=MagicMouseFix` visible in cert chain (not a test-signing cert).

### 7d. Install cert trust (PRIMARY path — admin required)

```powershell
# Already run as part of prerequisites (Section 4a / Section 1 CRITICAL block).
# Verify cert is trusted before proceeding:
$trusted = Get-ChildItem Cert:\LocalMachine\TrustedPublisher |
    Where-Object { $_.Subject -like "*MagicMouseFix*" }
if ($trusted) {
    Write-Host "Cert trust: OK — $($trusted.Thumbprint)"
} else {
    Write-Warning "Cert not in TrustedPublisher — run install-m12-trust.ps1 as admin"
}
```

**Gate SIGN-3:** Cert visible in LocalMachine\TrustedPublisher. FAIL = run install-m12-trust.ps1 before install.

---

## 8. Install procedure

### 8a. Pre-install driver store check

```powershell
pnputil /enum-drivers | Select-String -Context 0,5 -Pattern "MagicMouseDriver|applewirelessmouse"
```

Expected:
- `applewirelessmouse` present (oem<N>.inf) — will be removed in 8b.
- `MagicMouseDriver` NOT present — if present, a stale M13 install exists; run rollback (Section 9) first.

### 8b. DriverVer rank check (ensure M13 wins)

```powershell
$m13Date = [DateTime]"01/01/2027"
$allDrivers = pnputil /enum-drivers
# Find any competing INF for the v3 hardware ID with a newer DriverVer
# M13 uses 01/01/2027 which beats Apple's 04/21/2026
Write-Host "M13 DriverVer: $($m13Date.ToString('MM/dd/yyyy')) — beats Apple 04/21/2026"
# If any competing INF has a date > 01/01/2027, M13 may lose PnP rank.
# Check for Magic Utilities or other BTHENUM filters:
pnputil /enum-drivers | Select-String "BTHENUM.*PID.*0323" -Context 0,3
```

**Gate INST-1:** No competing INF has DriverVer > 01/01/2027. Magic Utilities absent (H-013 CONFIRMED FAIL — MU kernel-only install breaks both scroll and battery).

### 8c. Apple driver removal (AP-24 backup gate — already done in Section 5g)

```powershell
# Verify backup exists before removal
$appleOem = Get-Content "D:\Backups\M13-Install-*\apple-oem-inf-name.txt" -EA Stop
Write-Host "Will remove: $appleOem"

# Remove Apple's filter driver package
pnputil /delete-driver "$appleOem" /uninstall
# Note: /uninstall triggers device re-bind on paired devices.
# Do NOT use /force here — let PnP pick up the removal cleanly. /force is fallback only.

# Verify removal
$stillThere = pnputil /enum-drivers | Select-String "applewirelessmouse"
if ($stillThere) {
    Write-Warning "Apple driver still in store after /uninstall — try: pnputil /delete-driver $appleOem /force"
} else {
    Write-Host "Apple driver removed from store: OK"
}
```

**Gate INST-2:** Apple driver absent from driver store after removal. FAIL = use /force fallback; if still present after /force, reboot and retry.

### 8d. M13 install

```powershell
$BuildOut = ".\build\x64\Release"
pnputil /add-driver "$BuildOut\MagicMouseDriver.inf" /install

# Verify M13 is in driver store
pnputil /enum-drivers | Select-String -Context 0,5 "MagicMouseDriver"
# Expected: entry with "MagicMouseDriver.inf", dated 01/01/2027
```

**Gate INST-3:** `MagicMouseDriver` appears in driver store. FAIL = check build output — INF may have syntax errors (`pnputil /add-driver` outputs specific error code on failure).

### 8e. Force v3 re-bind to M13

```powershell
$v3Id = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&0323*").InstanceId

# Disable then enable to trigger PnP re-bind
pnputil /disable-device "$v3Id"
Start-Sleep -Seconds 3
pnputil /enable-device "$v3Id"
Start-Sleep -Seconds 5

# Verify LowerFilters shows MagicMouseDriver (not applewirelessmouse)
$lf = Get-PnpDeviceProperty -InstanceId "$v3Id" -KeyName DEVPKEY_Device_LowerFilters
Write-Host "v3 LowerFilters: $($lf.Data -join ', ')"
# Expected: MagicMouseDriver
```

**Gate INST-4:** v3 LowerFilters = `{MagicMouseDriver}`. Apple's filter absent. FAIL = PnP didn't re-bind; try unpair/repair cycle (Section 8f).

### 8f. SDP cache invalidation (if needed)

HidBth caches the SDP response in BTHPORT registry. M13 will intercept and patch on the NEXT SDP exchange. Two paths:

**Path A (preferred — registry wipe):** Clears the cache, forces HidBth to re-query SDP on next connect.

```powershell
$mac = "d0c050cc8c4d"
$sdpKey = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$mac\CachedServices"

# Backup first (redundant safety)
reg export "HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$mac" `
    "D:\Backups\sdp-cache-wipe-backup.reg" /y

Remove-Item -Path $sdpKey -Recurse -Force
Write-Host "SDP cache cleared — HidBth will re-query on next connect"
```

**Path B (fallback — unpair/repair cycle):**

```
Bluetooth Settings → Remove device "Magic Mouse" → Re-pair
```

After path A or B: M13's OnSdpQueryComplete will fire during the SDP exchange, inject Descriptor C, and update the cache with the patched 319-byte record.

### 8g. Post-install verification

```powershell
# Verify M13 service started
$svc = Get-Service MagicMouseDriver -EA SilentlyContinue
if ($svc.Status -eq "Running") {
    Write-Host "MagicMouseDriver service: Running"
} else {
    Write-Warning "Service not running — check Event Viewer (System log) for driver load errors"
}

# Verify diagnostic registry created
$diagPath = "HKLM:\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Diag"
if (Test-Path $diagPath) {
    Write-Host "Diagnostic registry: Present"
    Get-ItemProperty -Path $diagPath | Format-List
} else {
    Write-Warning "Diagnostic registry not yet created (created on first IOCTL intercept)"
}

# Verify Parameters\EnableInjection = 1
$paramPath = "HKLM:\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Parameters"
if (Test-Path $paramPath) {
    $ei = (Get-ItemProperty -Path $paramPath -Name EnableInjection -EA SilentlyContinue).EnableInjection
    Write-Host "EnableInjection: $ei"
    # Expected: 1
}
```

---

## 9. Rollback procedure

**Rollback is idempotent. Run all steps from any failure point.**

```powershell
$RecoveryPath = "D:\Backups\AppleWirelessMouse-RECOVERY"
$BackupRoot = (Get-ChildItem "D:\Backups\M13-Install-*" | Sort-Object CreationTime -Descending | Select-Object -First 1).FullName

Write-Host "Recovery path: $RecoveryPath"
Write-Host "Pre-install backup: $BackupRoot"
```

### 9a. Remove M13 driver

```powershell
$m13Oem = pnputil /enum-drivers |
    Select-String -Context 0,5 "MagicMouseDriver" |
    ForEach-Object { $_.Line } |
    Select-String "Published Name" |
    ForEach-Object { ($_ -split ":")[1].Trim() }

if ($m13Oem) {
    pnputil /delete-driver "$m13Oem" /uninstall
    Write-Host "M13 removed: $m13Oem"
} else {
    Write-Host "M13 not in driver store — skip"
}

# Delete service if orphaned
sc.exe query MagicMouseDriver
sc.exe stop MagicMouseDriver 2>$null
sc.exe delete MagicMouseDriver 2>$null
Write-Host "MagicMouseDriver service cleanup: done"
```

### 9b. Restore Apple driver

```powershell
$appleAlreadyThere = pnputil /enum-drivers | Select-String "applewirelessmouse"
if (-not $appleAlreadyThere) {
    pnputil /add-driver "$RecoveryPath\AppleWirelessMouse.inf" /install
    Write-Host "Apple driver restored"
} else {
    Write-Host "Apple driver already present — skip"
}
```

### 9c. Force re-bind to Apple driver

```powershell
$v1Id = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&030D*").InstanceId
$v3Id = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&0323*").InstanceId

foreach ($id in @($v1Id, $v3Id)) {
    if ($id) {
        pnputil /disable-device "$id"
        Start-Sleep -Seconds 2
        pnputil /enable-device "$id"
    }
}
Start-Sleep -Seconds 5
```

### 9d. Verify rollback

```powershell
$v1Id = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&030D*").InstanceId
$v3Id = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&0323*").InstanceId

$v1LF = (Get-PnpDeviceProperty -InstanceId "$v1Id" -KeyName DEVPKEY_Device_LowerFilters).Data
$v3LF = (Get-PnpDeviceProperty -InstanceId "$v3Id" -KeyName DEVPKEY_Device_LowerFilters).Data

Write-Host "v1 LowerFilters: $($v1LF -join ', ')"
Write-Host "v3 LowerFilters: $($v3LF -join ', ')"
# Expected: applewirelessmouse on both
```

### 9e. Registry diff

```powershell
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
reg export HKLM\SYSTEM "$BackupRoot\HKLM-SYSTEM-post-rollback-$ts.reg" /y
Write-Host "Post-rollback reg export saved"
# Diff vs pre-M13: any significant drift needs investigation
```

**Gate ROLLBACK-1:** v1 and v3 both show `applewirelessmouse` in LowerFilters. Tray reports `OK battery=N%` for v1 (Feature 0x47 path). No BSOD events. Dell USB mouse still works.

---

## 10. Validation Gates (Success Criteria)

### MVP1 — VG-0: Diagnostic — SdpPatchSuccess > 0

**This is the primary M13 technical gate. Pass here proves the full IOCTL intercept + SDP patch pipeline is working.**

```powershell
# Wait for mouse to connect and complete SDP exchange (up to 60s after enable)
Start-Sleep -Seconds 30

# Read diagnostic counters
$diagPath = "HKLM:\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Diag"
if (-not (Test-Path $diagPath)) {
    Write-Warning "Diagnostic registry not found — driver may not have intercepted any IOCTLs yet"
    Write-Warning "Try: pnputil /disable-device $v3Id; Start-Sleep 3; pnputil /enable-device $v3Id"
} else {
    $diag = Get-ItemProperty -Path $diagPath
    Write-Host "IoctlInterceptCount : $($diag.IoctlInterceptCount)"
    Write-Host "SdpScanHits         : $($diag.SdpScanHits)"
    Write-Host "SdpPatchSuccess     : $($diag.SdpPatchSuccess)"
    Write-Host "LastSdpBufSize      : $($diag.LastSdpBufSize)"
    Write-Host "LastPatchStatusHex  : $($diag.LastPatchStatusHex)"
    $b = $diag.LastSdpBytes
    if ($b) {
        Write-Host "LastSdpBytes[0..7]  : $(($b[0..7] | ForEach-Object { $_.ToString('X2') }) -join ' ')"
        # Expected after patch: 36 01 3F ... (319 bytes, 0x36 top-level)
        # Expected pre-patch native: 36 01 5C ... (351 bytes)
    }
}
```

Or use the diagnose-m13.ps1 script:

```powershell
.\diagnose-m13.ps1
# Expected output:
#   PASS  IoctlInterceptCount  = N  (>0)
#   PASS  SdpScanHits          = N  (>0)
#   PASS  SdpPatchSuccess      = N  (>0)
#   LastSdpBytes[0]: 36 (SDP_SEQ_2B) — correct top-level wrapper
```

**Gate VG-0 (MVP1):**
- PASS: `SdpPatchSuccess > 0`
- FAIL conditions:
  - `IoctlInterceptCount = 0`: M13 not intercepting IOCTLs. Check LowerFilters (gate INST-4). Check EnableInjection=1.
  - `IoctlInterceptCount > 0` but `SdpScanHits = 0`: IOCTL intercepted but scanner didn't find 0x0206 attribute. Check `LastSdpBytes[0..7]` — if byte[0] is not `09 02 06`, wrong IOCTL or wrong offset. Run Path A (cache wipe, Section 8f) to force fresh SDP.
  - `SdpScanHits > 0` but `SdpPatchSuccess = 0`: Found attribute but patch failed. `LastPatchStatusHex` shows reason. Most likely: buffer too small (won't happen — C=106 < native=135) or descriptor size miscalculation.

### MVP2 — VG-1: Scroll working on v3

```powershell
# Verify HID descriptor enumeration
$v3HidPdo = (Get-PnpDevice | Where-Object {
    $_.InstanceId -like "HID\*VID_004C*PID_0323*" -and $_.Status -eq "OK"
}).InstanceId

Write-Host "v3 HID PDO: $v3HidPdo"

# Check link collections (should have 2: col01 Mouse + col02 Vendor battery)
# Use mm-hid-descriptor-dump.ps1 if available:
# & ".\scripts\mm-hid-descriptor-dump.ps1" -InstanceId $v3HidPdo

# Functional test:
Write-Host ""
Write-Host "FUNCTIONAL TEST: Place v3 Magic Mouse on desk."
Write-Host "1. Open a web browser (Chrome, Edge)"
Write-Host "2. Two-finger swipe UP — page should scroll up"
Write-Host "3. Two-finger swipe DOWN — page should scroll down"
Write-Host "4. Left-click: works"
Write-Host "5. Right-click: works"
Write-Host "6. Cursor movement: smooth X/Y"
Write-Host ""
Write-Host "Optionally: spy WM_MOUSEWHEEL events via Spy++ or custom WndProc log"
```

**Gate VG-1 (MVP2):** v3 scrolls UP and DOWN. Left/right click work. Cursor moves. Minimum: 10 scroll events in 5s of continuous swipe.

FAIL conditions:
- No scroll at all: Descriptor C not injected (VG-0 must pass first). Or HidBth still using old cached descriptor — run Path A cache wipe + unpair/repair.
- Cursor doesn't move: RID=0x02 input report not processed. Possible descriptor parse failure — dump descriptor and compare byte-for-byte with Appendix 15.3.
- Left-click but no scroll: Wheel/ACPan usage declarations malformed — check HidDescriptor.c against known-good 106-byte sequence.

### MVP3 — VG-2: Battery readable on v3 via COL02

```powershell
# Start or restart MagicMouseTray
Get-Process MagicMouseTray -EA SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process "C:\path\to\MagicMouseTray.exe"
Start-Sleep -Seconds 60  # Allow first poll cycle

# Check tray log
$TrayLog = "$env:APPDATA\MagicMouseTray\debug.log"
Get-Content $TrayLog -Tail 50 |
    Select-String "pid.*0323.*battery=|split|OK.*0323"
# Expected: "OK ... pid&0323 ... battery=NN% (split)"
```

```powershell
# Manual battery probe via PowerShell (independent of tray app):
# HidD_GetInputReport(0x90) on COL02 (UP=0xFF00, U=0x0014)
# This is the same path used by MouseBatteryReader.GetBatteryLevel() in MagicMouseTray

$v3ColPath = (Get-PnpDevice | Where-Object {
    $_.InstanceId -like "HID\*VID_004C*PID_0323*"
}).InstanceId | ForEach-Object {
    # Find col02: UP=0xFF00 U=0x0014
    # (Full script: scripts\mm-battery-probe.ps1)
    Write-Host "HID PDO: $_"
}
```

**Gate VG-2 (MVP3):** Tray shows `OK battery=N% (split)` for v3 within 60 seconds. The `(split)` tag confirms COL02 was found and HidD_GetInputReport(0x90) returned buf[2] as valid battery percentage.

FAIL conditions:
- Tray shows `NO_MOUSE_FOUND` or `OPEN_FAILED` for v3: COL02 not enumerated. VG-0 must pass first.
- Tray shows `READ_FAILED`: HidD_GetInputReport failed (err=5 = access denied, or err=87 = invalid parameter). err=5 means COL01 selected instead of COL02; err=87 means RID=0x90 not in descriptor (descriptor injection may have failed — check VG-0).
- `battery=0%` or out-of-range: buf[2] is 0 or >100. Check probe log — may be wrong report byte offset (confirmed: buf[2] on a 3-byte report [RID, flags, battery%]).

### VG-3: v1 regression baseline

v1 uses Feature 0x47 path (Apple's filter or native passthrough — v1 was not rebind to M13 since HWID differs).

```powershell
# Verify v1 still uses applewirelessmouse filter
$v1Id = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&030D*").InstanceId
$v1LF = (Get-PnpDeviceProperty -InstanceId "$v1Id" -KeyName DEVPKEY_Device_LowerFilters).Data
Write-Host "v1 LowerFilters: $($v1LF -join ', ')"
# Expected: applewirelessmouse (M13 INF does NOT bind to PID 0x030D)

# v1 functional test
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 50 |
    Select-String "pid.*030d.*battery=|OK.*030d"
# Expected: "OK battery=N% (Feature 0x47)" within 60 seconds

# v1 scroll functional test
Write-Host "FUNCTIONAL TEST: Place v1 Magic Mouse on desk."
Write-Host "1. Two-finger swipe UP/DOWN — page should scroll"
Write-Host "2. Left/right click — both work"
```

**Gate VG-3:** v1 LowerFilters = applewirelessmouse (not M13). v1 battery = `OK battery=N% (Feature 0x47)`. v1 scroll works. FAIL = M13 INF accidentally bound to v1 (INF HWID wrong) — check INF and rebuild.

### VG-4: Dell USB mouse unaffected

```powershell
# Verify Dell USB mouse is still enumerated and functional
Get-PnpDevice | Where-Object { $_.FriendlyName -like "*mouse*" -and $_.FriendlyName -notlike "*Magic*" }
# Expected: USB HID mouse, Status=OK
# Functional: move mouse, left/right click — both work
```

**Gate VG-4:** Dell USB mouse enumerated, cursor moves. FAIL = system mouse broken (M13 binding leaked — impossible by design since INF HWID is BTHENUM-specific, but verify).

### VG-5: Pool tag verification

```
# In WinDbg (live kernel debugger or memory dump):
!poolused 4 'MsmD'
```

**Gate VG-5:** At least one `MsmD` allocation present while driver is loaded. Zero is acceptable if all paths used stack or WDF object context.

### VG-6: Driver Verifier soak

```powershell
# Enable Driver Verifier for M13
verifier /flags 0x9BB /driver MagicMouseDriver.sys
# 0x9BB = standard flags: Special pool, pool tracking, force IRQL checking, deadlock detection, security checks, DDI compliance, irp logging

# Reboot required
# After reboot: induce BT disconnect to exercise IRP cancellation:
pnputil /disable-device $v3Id
Start-Sleep -Seconds 5
pnputil /enable-device $v3Id

# Run for 30+ minutes. Check for verifier violations:
verifier /query
# Expected: Verified Drivers: MagicMouseDriver.sys — 0 violations

# Disable after pass:
verifier /reset
# Reboot.
```

**Gate VG-6:** No bugcheck during forced disable/enable cycle. `verifier /query` shows 0 violations. This gate is a PASS/FAIL on Driver Verifier — proceed to VG-7 only after verifier shows clean.

### VG-7: 24-hour soak

After MVP1-3 + VG-3 + VG-4 all pass:

```powershell
# Leave system running with both mice idle for 24 hours.
# Specific BT sleep/wake validation (run manually 3× during soak):
# - Turn v3 off, wait 5 min, turn on
# - Tray must show OK battery within 60s of each wake

# After 24 hours:
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 200 |
    Select-String "OPEN_FAILED|err=" | Measure-Object | Select-Object Count
# Expected: 0 (or only transient disconnect at sleep/wake boundary)

Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 200 |
    Select-String "OK.*split" | Measure-Object | Select-Object Count
# Expected: >= 12 successful v3 battery reads over 24h
```

**Gate VG-7:** Sustained `OK battery (split)` for v3 and `OK battery (Feature 0x47)` for v1 over 24 hours. Zero BSOD. Zero verifier violations. Sleep/wake cycles: mouse recovers within 60s after each wake.

---

## 11. Registry Tunables

| Key | Path | Default | Purpose |
|-----|------|---------|---------|
| EnableInjection | HKLM\...\MagicMouseDriver\Parameters | 1 | Set to 0 to disable SDP patching (pure passthrough) without uninstalling |
| (read-only) IoctlInterceptCount | HKLM\...\MagicMouseDriver\Diag | auto | Total IOCTL_BTH_SDP_SERVICE_SEARCH_ATTRIBUTE completions intercepted |
| (read-only) SdpScanHits | HKLM\...\MagicMouseDriver\Diag | auto | Times ScanForSdpHidDescriptor found 0x0206 attribute |
| (read-only) SdpPatchSuccess | HKLM\...\MagicMouseDriver\Diag | auto | Times PatchSdpHidDescriptor succeeded |
| (read-only) LastSdpBufSize | HKLM\...\MagicMouseDriver\Diag | auto | Byte count of last SDP response buffer |
| (read-only) LastPatchStatusHex | HKLM\...\MagicMouseDriver\Diag | auto | NTSTATUS of last patch attempt (0=success) |
| (read-only) LastSdpBytes | HKLM\...\MagicMouseDriver\Diag | auto | First 64 bytes of last SDP buffer (binary, for triage) |

**Disable injection without uninstalling:**

```powershell
Set-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Parameters" `
    -Name EnableInjection `
    -Value 0 `
    -Type DWord
pnputil /disable-device $v3Id; Start-Sleep 2; pnputil /enable-device $v3Id
```

---

## 12. Health Checks (Post-Install Steady State)

Run after any system change (reboot, Windows Update, driver update):

```powershell
# Health check script — run after any system change
$checks = @{}

# Check 1: M13 in driver store
$m13 = pnputil /enum-drivers | Select-String "MagicMouseDriver"
$checks['M13_InDriverStore'] = [bool]$m13

# Check 2: LowerFilters correct
$v3Id = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&0323*").InstanceId
$v3LF = (Get-PnpDeviceProperty -InstanceId $v3Id -KeyName DEVPKEY_Device_LowerFilters).Data
$checks['v3_LowerFilters_M13'] = ($v3LF -contains "MagicMouseDriver")

# Check 3: Service running
$svc = Get-Service MagicMouseDriver -EA SilentlyContinue
$checks['M13_ServiceRunning'] = ($svc.Status -eq "Running")

# Check 4: SdpPatchSuccess > 0 (at least once since boot)
$diag = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\MagicMouseDriver\Diag" -EA SilentlyContinue
$checks['SdpPatchSuccess_GT0'] = ($diag.SdpPatchSuccess -gt 0)

# Check 5: v1 not accidentally bound to M13
$v1Id = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&030D*").InstanceId
$v1LF = (Get-PnpDeviceProperty -InstanceId $v1Id -KeyName DEVPKEY_Device_LowerFilters).Data
$checks['v1_LowerFilters_Apple'] = ($v1LF -contains "applewirelessmouse")

foreach ($k in $checks.Keys) {
    $status = if ($checks[$k]) { "PASS" } else { "FAIL" }
    Write-Host "[$status] $k"
}
```

---

## 13. Failure Modes

| Code | Symptom | Root Cause | Resolution |
|------|---------|------------|------------|
| F-01 | `IoctlInterceptCount = 0` | Driver not in LowerFilters chain | Verify INF installed, v3 re-bound (Section 8e) |
| F-02 | `SdpScanHits = 0`, `IoctlInterceptCount > 0` | IOCTL intercepted but 0x0206 not found in response | Cache wipe (Section 8f Path A) + re-pair. Check LastSdpBytes[0..10] against expected pattern |
| F-03 | `SdpPatchSuccess = 0`, `SdpScanHits > 0` | Found attribute but patch failed | Check LastPatchStatusHex. STATUS_BUFFER_TOO_SMALL = buffer exhausted (won't happen: C=106 < A=135). STATUS_INVALID_PARAMETER = geometry check failed |
| F-04 | No scroll on v3 | Descriptor C not in effect; HidBth using cached native descriptor | VG-0 must pass first. Run Section 8f cache wipe + unpair/repair |
| F-05 | `READ_FAILED err=5` | tray probing COL01 (Mouse, Windows-owned) instead of COL02 | Verify RID=0x90 is in Descriptor C (BUILD-7). Update tray app COL enumeration logic |
| F-06 | `READ_FAILED err=87` | RID=0x90 not in enumerated descriptor | VG-0 failed (descriptor not injected). Fix VG-0 first |
| F-07 | `battery=0%` or impossible value | buf[2] is wrong byte offset | Confirmed: 3-byte report [0x90, flags, battery%]. buf[2] is correct. Check for alternative descriptor layout (turn on detailed tray logging) |
| F-08 | BSOD 0x9F or WDF assertion | Driver unload race during PnP remove | Driver Verifier (VG-6) will expose. Fix: verify EvtIoStop + WdfRequestMarkCancelable patterns |
| F-09 | BSOD 0x3B | IRQL violation in completion routine | PREfast (BUILD-2) should catch. Fix: verify all DISPATCH_LEVEL code is spinlock-safe |
| F-10 | Windows Update reverts LowerFilters | Windows Update replaced INF | Re-run install (Section 8d–8e). Consider signing + attestation for durable install |
| F-11 | v1 LowerFilters shows MagicMouseDriver | INF HWID accidentally targets PID 0x030D | Check MagicMouseDriver.inf — HWID must be `*_PID&0323*` only. Rebuild + reinstall |
| F-12 | EnableInjection reset to 0 after reboot | INF didn't set registry default | Verify INF [MagicMouseDriver.AddReg] section has `HKR,Parameters,EnableInjection,0x00010001,1` |
| F-13 | Diagnostic registry not created | Driver loaded but timer not firing | Check diagnostic timer init (EvtDeviceAdd). EnableInjection=0 suppresses timer |
| F-14 | Apple driver removal fails with access denied | Driver in use by another process | Stop MagicMouseTray. Retry pnputil /delete-driver /force. Reboot if still locked |
| F-15 | M13 install fails: "Access is denied" (0x80070005) | Unsigned driver, cert not trusted | Verify cert trust (Section 4a, 7d). Or fall back to test-signing mode |
| F-16 | SDP cache not updating after install | M13 installed but SDP exchange happened before M13 loaded | Run cache wipe (Section 8f Path A) and force re-pair |
| F-17 | Scroll works but button clicks dropped | Report descriptor bit-field misaligned | Compare Descriptor C byte-for-byte vs Appendix 15.3. Any single-bit error causes report misparse |
| F-18 | Mouse cursor drifts or jumps | X/Y field encoding wrong | Descriptor C uses INT8 (signed, 8-bit) for X/Y. If cursor jumps: verify 0x15 0x81 0x25 0x7F for each axis |
| F-19 | No horizontal scroll | AC Pan (0x0238 Consumer) not in descriptor | Verify bytes `05 0C 0A 38 02` in Descriptor C (Appendix 15.3) |
| F-20 | AV/EDR flags M13 | Unsigned/self-signed kernel driver | Known. Add M13 exclusion in AV. See KNOWN-ISSUES.md |
| F-21 | Descriptor A restored after reboot | SDP cache persisted with native descriptor | M13 hasn't intercepted since reboot. Connect mouse; wait for SDP exchange; VG-0 will show SdpPatchSuccess |

---

## 14. Sign-Off Checklist

Complete every item before declaring M13 production-ready. Each item is Pass/Fail.

### Pre-build
- [ ] PRE-1: Recovery backup present (3 files, hashes match)
- [ ] PRE-2: Device topology baseline: v1=OK, v3=OK, Dell=OK
- [ ] PRE-3: SDP cache baseline captured (`HKLM-SYSTEM-pre-M13.reg`)
- [ ] PRE-4: Tray log backed up
- [ ] PRE-5: `$BackupRoot` directory created with all 7 backup artifacts

### Build
- [ ] BUILD-1: Clean build exit code 0; `MagicMouseDriver.sys` present
- [ ] BUILD-2: PREfast: 0 Code Analysis warnings
- [ ] BUILD-3: SDV: 0 defects (or waived if SDV timed out)
- [ ] BUILD-4: Line endings: no mixed CRLF/LF
- [ ] BUILD-5: Pool tag `MsmD` present in source
- [ ] BUILD-6: Binary size 20 KB–500 KB
- [ ] BUILD-7: Descriptor C = 106 bytes

### Sign
- [ ] SIGN-1: `signtool verify /pa MagicMouseDriver.sys` shows "Successfully verified"
- [ ] SIGN-2: Cert chain shows `CN=MagicMouseFix` (not test cert)
- [ ] SIGN-3: Cert in LocalMachine\TrustedPublisher

### Install
- [ ] INST-1: DriverVer 01/01/2027 beats all competing INFs for PID 0x0323
- [ ] INST-2: Apple driver removed from driver store
- [ ] INST-3: M13 in driver store (pnputil /enum-drivers shows MagicMouseDriver)
- [ ] INST-4: v3 LowerFilters = {MagicMouseDriver}

### Validation (MVPs first)
- [ ] VG-0 / MVP1: `SdpPatchSuccess > 0` in diagnostic registry — IOCTL intercepted + SDP patched
- [ ] VG-1 / MVP2: v3 scroll working (WM_MOUSEWHEEL, page scrolls UP and DOWN)
- [ ] VG-2 / MVP3: v3 battery `OK battery=N% (split)` in tray log
- [ ] VG-3: v1 regression: `OK battery=N% (Feature 0x47)`, scroll works
- [ ] VG-4: Dell USB mouse unaffected
- [ ] VG-5: Pool tag `MsmD` visible in `!poolused` (advisory)
- [ ] VG-6: Driver Verifier soak 30+ min, 0 violations
- [ ] VG-7: 24-hour soak, zero BSOD, >= 12 OK battery reads on v3

### Rollback verified
- [ ] ROLLBACK-1: Dry-run rollback on staging (or confirm: rollback procedure tested at least once)

### Documentation
- [ ] DOC-1: `PSN-0001-hid-battery-driver.yaml` updated (Session 13 entry, all gates)
- [ ] DOC-2: PRD-184 M13 milestone updated (pass/fail for MVP1-3)
- [ ] DOC-3: NOTEBOOKLM.md updated (notebook 91f8a4d2 entry updated)
- [ ] DOC-4: M13-DESIGN-SPEC.md version bumped (empirical SDP format facts embedded)
- [ ] DOC-5: KNOWN-ISSUES.md updated (AV/EDR, any new failure modes discovered)

---

## 15. Appendix — Empirical Data Summary

### 15.1 SDP Record (v3 Magic Mouse, MAC d0c050cc8c4d)

**Source:** `tests/2026-04-27-154930-T-V3-AF/bthport-discovery-d0c050cc8c4d.txt`

```
Total length: 351 bytes

Bytes [0..2]:    36 01 5C     → SDP_SEQ_2B, length=0x015C=348 (top-level AttributeLists)
                               ↑ This is 0x36 (2-byte length), NOT 0x35

Bytes [~0xA0]:   09 02 06     → UINT16 attribute 0x0206 (HIDDescriptorList)
                 35 8D        → outer SEQUENCE, 0x35 (1-byte length), length=0x8D=141
                 35 8B        → inner SEQUENCE, 0x35 (1-byte length), length=0x8B=139
                 08 22        → UINT8 0x22 = HID_REPORT_DESCRIPTOR_TYPE
                 25 87        → TEXT_STRING, 0x35 (1-byte length), length=0x87=135 bytes
                 <135 bytes>  → native HID descriptor (Descriptor A)
```

**Post-patch expected:**
```
Top-level:       36 01 3F     → length=0x013F=319 (351-32=319... wait: delta=-29, 348-29=319=0x013F ✓)
Attribute 0x0206:
                 35 70        → outer SEQUENCE, length=0x70=112  (was 0x8D=141)
                 35 6E        → inner SEQUENCE, length=0x6E=110  (was 0x8B=139)
                 08 22        → unchanged
                 25 6A        → TEXT_STRING, length=0x6A=106     (was 0x87=135)
                 <106 bytes>  → Descriptor C (injected)
```

Delta calculation:
- Descriptor size change: 106-135 = -29 bytes
- TEXT_STRING len: 135→106 (-29)
- inner SEQUENCE payload: 2+2+135=139→2+2+106=110 (-29)
- outer SEQUENCE payload: 2+139=141→2+110=112 (-29)
- Top-level length: 348→319 (-29)
- All four length fields each decrement by 29. ✓

### 15.2 Battery Report (COL02 — confirmed)

**Source:** PSN-0001 M1 (2026-04-17 feasibility), battery probe traces 2026-04-27

```
Report ID:     0x90
Report type:   Input (HidD_GetInputReport)
Buffer:        [0x90, <flags>, <battery%>]  (3 bytes total)
Battery field: buf[2] (byte index 2)
Collection:    COL02 — UP=0xFF00, U=0x0014
Access:        COL02 only (COL01 = HidD_GetInputReport err=5 = Windows-owned)
```

**In Descriptor A state (native, 135 bytes):**
- COL02 enumerated: YES (UP=0xFF00, U=0x0014, RID=0x90, InLen=3)
- HidD_GetInputReport(0x90) returns: [0x90, 0x00, battery%] — buf[2] = 84% confirmed

**In Descriptor B state (Apple filter, 116 bytes):**
- COL02 enumerated: NO (stripped by Apple's descriptor)
- HidD_GetInputReport(0x90) returns: err=87 (INVALID PARAMETER)

**In Descriptor C state (M13 injection, 106 bytes):**
- COL02 enumerated: YES (RID=0x90 present in Descriptor C)
- HidD_GetInputReport(0x90): expected to return buf[2] = battery% (same as Descriptor A path)

### 15.3 Descriptor C — Byte Sequence (106 bytes)

**Source:** `driver/HidDescriptor.c` g_HidDescriptor[]

```
TLC1: Generic Desktop Mouse (UP=0x01 U=0x02), RID=0x02
  05 01       Usage Page (Generic Desktop)
  09 02       Usage (Mouse)
  A1 01       Collection (Application)
    85 02     Report ID (0x02)
    09 01     Usage (Pointer)
    A1 00     Collection (Physical)
      // 5 buttons (bits 0-4) + 3-bit pad
      05 09   Usage Page (Button)
      19 01   Usage Minimum (1)
      29 05   Usage Maximum (5)
      15 00   Logical Minimum (0)
      25 01   Logical Maximum (1)
      75 01   Report Size (1)
      95 05   Report Count (5)
      81 02   Input (Data, Variable, Absolute)
      75 03   Report Size (3) — pad
      95 01   Report Count (1)
      81 03   Input (Constant)
      // X/Y — INT8 relative
      05 01   Usage Page (Generic Desktop)
      09 30   Usage (X)
      09 31   Usage (Y)
      15 81   Logical Minimum (-127)
      25 7F   Logical Maximum (127)
      75 08   Report Size (8)
      95 02   Report Count (2)
      81 06   Input (Data, Variable, Relative)
      // AC Pan (Consumer 0x0238) — INT8
      05 0C   Usage Page (Consumer)
      0A 38 02 Usage (AC Pan, 0x0238)
      15 81   Logical Minimum (-127)
      25 7F   Logical Maximum (127)
      75 08   Report Size (8)
      95 01   Report Count (1)
      81 06   Input (Data, Variable, Relative)
      // Wheel — INT8
      05 01   Usage Page (Generic Desktop)
      09 38   Usage (Wheel)
      15 81   Logical Minimum (-127)
      25 7F   Logical Maximum (127)
      75 08   Report Size (8)
      95 01   Report Count (1)
      81 06   Input (Data, Variable, Relative)
    C0         End Collection (Physical)
  C0           End Collection (Application)

TLC2: Vendor Battery (UP=0xFF00 U=0x14), RID=0x90
  06 00 FF    Usage Page (Vendor 0xFF00)
  09 14       Usage (0x14)
  A1 01       Collection (Application)
    85 90     Report ID (0x90)
    09 01     Usage (0x01)
    09 02     Usage (0x02)
    15 00     Logical Minimum (0)
    26 FF 00  Logical Maximum (255)
    75 08     Report Size (8)
    95 02     Report Count (2) — 2 vendor bytes (flags + battery%)
    81 02     Input (Data, Variable, Absolute)
  C0           End Collection (Application)
```

Total: 106 bytes = sizeof(g_HidDescriptor). ✓

### 15.4 Key PSN-0001 Findings (12 sessions)

| Finding | Status | Implication for M13 |
|---------|--------|---------------------|
| H-010: Two descriptor variants (A=battery, B=scroll+Apple) | CONFIRMED | M13 Descriptor C combines both; eliminates flip source |
| H-013: MU kernel-only install breaks scroll AND battery | CONFIRMED FAIL | Never install Magic Utilities with M13 |
| D-016: M13 pure kernel filter, no userland split | Decision | ~600 LOC, no tray changes needed for scroll |
| IOCTL=0x410210 confirmed by Ghidra RE | CONFIRMED | M13 intercepts correct IOCTL |
| SDP 0x35 inner sequences confirmed from bthport trace | CONFIRMED | Scanner works as-is; no 0x36 fallback needed |
| AP-24: Backup before destructive commands | Anti-pattern | Always verify recovery backup before Apple driver removal |

---

## 16. Open Questions (Not Blocking MVP1-3)

| ID | Question | Resolution path |
|----|----------|-----------------|
| OQ-1 | AC Pan (horizontal scroll, 0x0238) — does v3 firmware emit negative values correctly? | Verify with Spy++/WH_MOUSE hook after VG-1 |
| OQ-2 | Does HidBth cache the patched 319-byte record durably (survives reboot)? | Verify after cold reboot: check LastSdpBufSize=319 on first intercept post-reboot |
| OQ-3 | Does M13 persist across Windows Update? | Windows Update may reinstall Apple's INF. Add health check to tray app startup |
| OQ-4 | v2 Magic Mouse (PID 0x0269) — does Descriptor C work? | Out of scope (device not owned). INF can be extended if user reports v2 issues |
| OQ-5 | Button 4/5 (back/forward) — do they work? | Descriptor C includes 5 buttons. Verify after VG-1 |

---

*MOP written from empirical data. No assumptions. Every claim traces to a specific measurement or code path.*
*Author: Claude Sonnet 4.6 / Lesley Murfin — 2026-04-29*
