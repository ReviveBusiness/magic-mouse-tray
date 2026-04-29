# M12 Method of Procedure (MOP)

**Status:** v1.3 — DRAFT pending user approval (NLM pass-2 blocking issues resolved)
**Date:** 2026-04-28
**Linked design:** `docs/M12-DESIGN-SPEC.md` v1.3
**Linked PRD:** PRD-184 v1.27
**Linked NLM pass-1:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-2026-04-28.md`
**Linked NLM pass-2:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-PASS2-2026-04-28.md`
**BCP reference:** BCP-OPS-501 (Change Management) — pre-flight + rollback + health-check pattern.
**Related rules:** `~/.claude/projects/-home-lesley-projects/memory/feedback_backup_before_destructive_commands.md` (AP-24 — non-negotiable backup gate).

## Revision history

- **v1.3 (2026-04-28):** Aligned to design spec v1.3 (PID branch restored + BRB descriptor rewriter restored). VG-0 dual-state pass condition added (Descriptor B in cache OR Descriptor A + DescriptorBRewritten flag set). VG-1 v1 baseline now exercises NATIVE Feature 0x47 path, not M12 short-circuit — failure here means M12 broke the pass-through (regression in INF binding or queue forwarding). New optional MAX_STALE_MS registry tunable documented. Soft active-poll noted as future work (OQ-D).
- **v1.2 (2026-04-28):** Aligned to design spec v1.2 (applewirelessmouse-baseline reframe). Driver Verifier flags expanded to 0x9bb + IRP completion + IoTarget flags. Pool tag verification step added (`!poolused 4 'M12 '`). EvtIoStop verification step added (forced cancel via Driver Verifier). Empirical battery offset verification step added (LogShadowBuffer debug.log diff at known battery levels). 24-hr soak scope clarified to include BT sleep/wake cycles. VG-0 caps check repurposed: confirms cached SDP descriptor matches applewirelessmouse-baseline (Input=47, Feature=2, LinkColl=2), NOT Mode A — because v1.2 doesn't mutate the descriptor. Section 7c-pre BTHPORT cache wipe demoted to optional (only triggered if VG-0 caps mismatch suggests a stale non-applewirelessmouse cache).
- **v1.1 (2026-04-28):** Added Section 7c-pre (force fresh SDP exchange via BTHPORT cache wipe / unpair-repair) and VG-0 pre-validation gate.
- **v1.0 (2026-04-28):** Initial MOP.

---

## 1. BLUF

This MOP is the canonical end-to-end procedure for building, signing, installing, validating, and rolling back the M12 KMDF lower filter driver on the Magic Mouse v1 (PID 0x030D) and v3 (PID 0x0323) test machine. Every section maps to a single `bash` / `pwsh` command block; every gate is a Pass/Fail boolean; rollback is a single section the operator can run start-to-finish at any failure point. No section depends on userland Magic Utilities being present.

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

### 7a. Pre-install enumeration check + applewirelessmouse removal (UPDATED v1.2)

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

### 7d. Verify M12 is bound

```pwsh
Get-PnpDeviceProperty -InstanceId "$v1Inst" -KeyName DEVPKEY_Device_LowerFilters
Get-PnpDeviceProperty -InstanceId "$v3Inst" -KeyName DEVPKEY_Device_LowerFilters
# Expected: Data column contains "M12"

sc.exe query M12
# Expected: STATE = 4 RUNNING
```

**Gate INSTALL-1:** both v1 and v3 LowerFilters contain `M12`. Service state RUNNING. Halt if either fails.

### 7e. Initial registry tunables (NEW v1.2)

```pwsh
# Defaults are baked into the driver but explicit registration documents intent.
# BATTERY_OFFSET default = 1 (first byte of 46-byte payload).
# FirstBootPolicy default = 0 (STATUS_DEVICE_NOT_READY).
# MAX_STALE_MS default = 10000 (10 sec; 0 disables staleness check).
$svcParams = "HKLM:\SYSTEM\CurrentControlSet\Services\M12\Parameters"
if (-not (Test-Path $svcParams)) {
    New-Item -Path $svcParams -Force | Out-Null
}
Set-ItemProperty -Path $svcParams -Name BATTERY_OFFSET -Value 1 -Type DWord
Set-ItemProperty -Path $svcParams -Name FirstBootPolicy -Value 0 -Type DWord
Set-ItemProperty -Path $svcParams -Name MAX_STALE_MS -Value 0 -Type DWord
# NOTE: Default 0 = disabled (v1.3 final per NLM pass-3). Setting to 10000 (10 sec) would
# cause NOT_READY whenever mouse is asleep (>2 min idle = no fresh RID=0x27 frames).
# Recommended only if empirical 24-hr soak shows stale-cache corruption — start with 7200000 (2 hr).
```

**Gate INSTALL-2:** Registry tunables present. Reboot or PnP cycle picks them up at next AddDevice.

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

### 8b. Remove M12

```pwsh
$M12Oem = pnputil /enum-drivers |
    Select-String -Context 5,0 "MagicMouseDriver" |
    Select-String "Published Name" |
    ForEach-Object { ($_ -split ":")[1].Trim() }

if ($M12Oem) {
    pnputil /delete-driver "$M12Oem" /uninstall /force
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

---

## 12. Sign-off checklist

```
[ ] PRE-1: Pre-flight backup verified
[ ] BUILD-1: MagicMouseDriver.sys + .inf in build output
[ ] BUILD-2: hidparser.exe validates 116-byte reference descriptor
[ ] BUILD-3: pool tag 'M12 ' present in binary
[ ] SIGN-1:  signtool verify successful (RFC 3161 SHA256)
[ ] 7a:      applewirelessmouse removed from LowerFilters
[ ] 7e:      registry tunables BATTERY_OFFSET + FirstBootPolicy + MAX_STALE_MS set
[ ] INSTALL-1: M12 LowerFilters bound to v1 + v3, service RUNNING
[ ] VG-0:    HIDP_GetCaps shows applewirelessmouse-baseline (Input=47, Feature=2, LinkColl=2)
[ ] VG-1:    v1 produces OK battery (Feature 0x47) within 30s
[ ] VG-2:    v3 produces OK battery (Feature 0x47) within 60s
[ ] VG-3:    scroll fluid on both mice
[ ] VG-4:    BATTERY_OFFSET confirmed via debug.log diff at known battery levels
[ ] VG-5:    pool tag 'M12 ' verifiable in WinDbg !poolused
[ ] VG-6:    no Driver Verifier violations under flags 0x9bb during forced disable
[ ] VG-7:    24-hour soak with BT sleep/wake cycles, >= 12 OK reads, zero err= entries, zero BSOD
[ ] HEALTH-10a: no BSOD events in System log
[ ] HEALTH-10d: service state RUNNING throughout

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
| Service status | `sc.exe query M12` |
| Tray log tail | `Get-Content $env:APPDATA\MagicMouseTray\debug.log -Tail 50` |
| Set battery offset | `Set-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Services\M12\Parameters -Name BATTERY_OFFSET -Value N -Type DWord` |
| Pool tag enumerate (WinDbg) | `!poolused 4 'M12 '` |
| Driver Verifier on | `verifier /flags 0x9bb /driver MagicMouseDriver.sys` |
| Driver Verifier off | `verifier /reset` |
| Uninstall | `pnputil /delete-driver oem<N>.inf /uninstall /force` |
| Reset signing test mode | `bcdedit /set testsigning off` (reboot) |
