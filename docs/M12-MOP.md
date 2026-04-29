# M12 Method of Procedure (MOP)

**Status:** v1.1 — DRAFT pending user approval (NLM peer-review patches applied)
**Date:** 2026-04-28
**Linked design:** `docs/M12-DESIGN-SPEC.md` v1.1
**Linked PRD:** PRD-184 v1.26
**Linked review:** `docs/M12-DESIGN-PEER-REVIEW-NOTEBOOKLM-2026-04-28.md`
**BCP reference:** BCP-OPS-501 (Change Management) — pre-flight + rollback + health-check pattern.
**Related rules:** `~/.claude/projects/-home-lesley-projects/memory/feedback_backup_before_destructive_commands.md` (AP-24 — non-negotiable backup gate).

## Revision history

- **v1.1 (2026-04-28):** Added Section 7c-pre (force fresh SDP exchange via BTHPORT cache wipe / unpair-repair) and VG-0 pre-validation gate (HIDP_GetCaps confirms Mode A landed). Both required because Disable+Enable rebind alone does NOT trigger fresh BT SDP — HidBth re-uses cached descriptor (failure mode F13). Per NLM peer review CHANGES-NEEDED verdict.
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
Test-Path F:\BuildTools\msbuild.exe   # if F: is the EWDK ISO mount
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

Per `feedback_backup_before_destructive_commands.md` and AP-24: this MOP MAY perform `pnputil /delete-driver` operations as part of rollback (Section 8). The recovery backup MUST be verified intact BEFORE we begin. If it is missing or corrupt, this MOP halts.

### 3e. Tray app debug log accessible

```pwsh
Test-Path "$env:APPDATA\MagicMouseTray\debug.log"
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 5
```

The tray must be running and producing log output. The MOP relies on tray log entries as the primary success oracle.

---

## 4. Pre-flight backup (BCP-OPS-501)

Run BEFORE any install/uninstall/PnP operation. Per AP-24, no destructive command runs without these snapshots verified first.

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

**Gate PRE-1:** all five files exist, sizes plausible (HKLM\SYSTEM export typically 50-150 MB). Halt if missing.

Record `$BackupRoot` for use in Sections 8 (rollback) and 9 (post-validation reg-diff).

---

## 5. Build procedure

### 5a. Open EWDK build environment

```pwsh
& F:\LaunchBuildEnv.cmd   # OR D:\ewdk25h2\LaunchBuildEnv.cmd
# After this, $env:Path includes msbuild + WDK tools
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
# Expected exit code 0
```

### 5c. Verify build artefacts

```pwsh
$BuildOut = "C:\Users\Lesley\projects\Personal\magic-mouse-tray\driver\Debug\x64\MagicMouseDriver"
Test-Path "$BuildOut\MagicMouseDriver.sys"   # main binary
Test-Path "$BuildOut\MagicMouseDriver.inf"   # processed INF
# .cat is generated in step 6c (signing) — not present yet.
```

**Gate BUILD-1:** `MagicMouseDriver.sys` and `MagicMouseDriver.inf` both exist in the build output directory.

### 5d. Validate descriptor

```pwsh
& "$env:WindowsSdkDir\Tools\x64\hidparser.exe" "$BuildOut\MagicMouseDriver.inf"
# Or run hidparser against extracted descriptor bytes from a static-init test harness
```

**Gate BUILD-2:** `hidparser.exe` returns success on the static `g_HidDescriptor[]` bytes. No syntax warnings. (This catches descriptor-malformation BSOD risk per design spec failure mode F7.)

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
    # Move to TrustedPublisher + Root for kernel-mode acceptance
    $store = Get-Item Cert:\LocalMachine\TrustedPublisher
    $store.Open("ReadWrite"); $store.Add($cert); $store.Close()
    $store = Get-Item Cert:\LocalMachine\Root
    $store.Open("ReadWrite"); $store.Add($cert); $store.Close()
}
```

### 6b. Sign the .sys

```pwsh
$signtool = "$env:WindowsSdkDir\bin\$env:WindowsSdkVer\x64\signtool.exe"
& $signtool sign `
    /v `
    /s My `
    /n "MagicMouseTray-TestSign" `
    /t http://timestamp.digicert.com `
    /fd sha256 `
    "$BuildOut\MagicMouseDriver.sys"

& $signtool verify /v /pa "$BuildOut\MagicMouseDriver.sys"
# Expected: "Successfully verified"
```

### 6c. Generate + sign catalog

```pwsh
$inf2cat = "$env:WindowsSdkDir\bin\$env:WindowsSdkVer\x86\Inf2Cat.exe"
& $inf2cat /driver:$BuildOut /os:10_X64
# Produces MagicMouseDriver.cat

& $signtool sign `
    /v `
    /s My `
    /n "MagicMouseTray-TestSign" `
    /t http://timestamp.digicert.com `
    /fd sha256 `
    "$BuildOut\MagicMouseDriver.cat"
```

**Gate SIGN-1:** `signtool verify /v /pa MagicMouseDriver.sys` reports "Successfully verified". Same for `.cat`.

---

## 7. Install procedure

Pre-condition: Section 4 (backup) and Section 5-6 (build + sign) both complete and gates passed.

### 7a. Pre-install enumeration check

```pwsh
pnputil /enum-drivers | Select-String -Context 0,5 -Pattern "MagicMouse|applewirelessmouse"
```

Expected: shows the existing `applewirelessmouse` (oem<N>.inf) entry. NO existing `MagicMouseDriver` entry. If a stale M12 install is present from prior testing, run Section 8 rollback first.

### 7b. Stage and install M12

```pwsh
pnputil /add-driver "$BuildOut\MagicMouseDriver.inf" /install
# Expected: "Driver package added successfully" + driver published as oem<N>.inf
```

Capture the published OEM number for rollback:

```pwsh
$published = pnputil /enum-drivers | Select-String -Context 5,0 "MagicMouseDriver" |
    ForEach-Object { ($_.Context.PreContext + $_.Line) -join "`n" }
$published    # extract Published Name = oem<N>.inf
```

### 7c-pre. Force fresh SDP exchange (CRITICAL — added per NLM peer review)

`pnputil /disable-device` + `/enable-device` does NOT trigger a fresh Bluetooth SDP descriptor fetch. HidBth caches the SDP HIDDescriptorList in `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<mac>\CachedServices\00010000` and re-uses it across rebinds (failure mode F13). M12's BRB-level descriptor mutation only fires on fresh SDP — so we must invalidate the cache OR force re-pair.

**Path A (preferred — scripted cache wipe, requires verified backup per AP-24):**

```pwsh
# Backup BTHPORT cache for both mice before wipe
$macV1 = "04F13EEEDE10"   # confirm via Get-PnpDevice or BT settings
$macV3 = "D0C050CC8C4D"
$BthRoot = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices"
foreach ($mac in @($macV1, $macV3)) {
    $cachePath = "$BthRoot\$mac\CachedServices"
    if (Test-Path $cachePath) {
        $bk = "$BackupRoot\BTHPORT-CachedServices-$mac.reg"
        reg export "HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\$mac\CachedServices" "$bk" /y
        # Verify backup non-empty
        if ((Get-Item $bk).Length -lt 100) {
            Write-Error "Backup of $cachePath is empty — HALT"
            return
        }
        Remove-ItemProperty -Path $cachePath -Name "00010000" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "$BthRoot\$mac\DynamicCachedServices" -Name "00010000" -ErrorAction SilentlyContinue
    }
}
```

**Path B (fallback — operator unpair + re-pair):**

If Path A is not validated empirically yet (first-ever M12 install): in Windows BT settings, remove both Magic Mouse devices, then re-pair them. Re-pairing always triggers fresh SDP. Slower (60-90 sec per device, manual UI interaction), but no risk of registry-state ambiguity.

**Decision rule for first run:** use Path B (unpair + re-pair) on the very first M12 install since cache-wipe behaviour is empirically unvalidated. After first M12 install confirms Mode A bound, subsequent re-installs may use Path A.

### 7c. Force re-bind

After 7c-pre completes (cache invalidated OR re-paired), re-enumerate the BTHENUM device. The mice are currently bound to `applewirelessmouse` — to make M12 win the rank battle:

```pwsh
$v1Inst = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&030D*" |
           Where-Object { $_.Status -eq "OK" }).InstanceId
$v3Inst = (Get-PnpDevice -InstanceId "BTHENUM\*VID&0001004C_PID&0323*" |
           Where-Object { $_.Status -eq "OK" }).InstanceId

# Disable + Enable each device — triggers AddDevice with the new INF rank
pnputil /disable-device "$v1Inst"
pnputil /enable-device "$v1Inst"
pnputil /disable-device "$v3Inst"
pnputil /enable-device "$v3Inst"
Start-Sleep -Seconds 5
```

### 7d. Verify M12 is bound

```pwsh
Get-PnpDeviceProperty -InstanceId "$v1Inst" `
    -KeyName DEVPKEY_Device_LowerFilters
Get-PnpDeviceProperty -InstanceId "$v3Inst" `
    -KeyName DEVPKEY_Device_LowerFilters
# Expected: Data column contains "MagicMouseDriver"

sc.exe query MagicMouseDriver
# Expected: STATE = 4 RUNNING
```

**Gate INSTALL-1:** both v1 and v3 LowerFilters contain `MagicMouseDriver`. Service state RUNNING. Halt if either fails.

---

## 8. Rollback procedure

Run this section AT ANY FAILURE POINT in Sections 5-7-9. Idempotent — safe to re-run.

### 8a. Verify recovery backup before any destructive command (AP-24 gate)

```pwsh
$RecoveryPath = "D:\Backups\AppleWirelessMouse-RECOVERY"
foreach ($f in @("AppleWirelessMouse.inf", "AppleWirelessMouse.cat", "AppleWirelessMouse.sys")) {
    if (-not (Test-Path "$RecoveryPath\$f")) {
        Write-Error "MISSING: $RecoveryPath\$f -- HALTING ROLLBACK; restore the backup first."
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

### 8c. Restore Apple driver (only if it was deleted during testing)

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

### 8f. Reg-diff against pre-M12 snapshot

```pwsh
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
reg export HKLM\SYSTEM "$BackupRoot\HKLM-SYSTEM-post-rollback-$ts.reg" /y
bash -c "diff <(grep -v '^Windows' $BackupRoot/HKLM-SYSTEM-pre-M12.reg) <(grep -v '^Windows' $BackupRoot/HKLM-SYSTEM-post-rollback-$ts.reg) | head -100"
```

Expected: only minor PnP transient changes (timestamps, DeviceContainer GUIDs). No structural difference. Significant drift = follow-up investigation; baseline isn't fully restored.

**Gate ROLLBACK-1:** Both mice show `applewirelessmouse` in LowerFilters; reg-diff shows no significant drift. Tray (after restart) reports v1 battery = `OK battery=N% (Feature 0x47)`.

---

## 9. Validation gates (success criteria)

Run AFTER Section 7 (install) succeeds. These are the binary success oracles.

### VG-0: Mode A descriptor confirmation (pre-validation, added per NLM peer review)

Before restarting the tray, confirm M12's BRB-level mutation actually landed on both mice. If HIDP_GetCaps still reports Mode B (47-byte input, 1 link collection), the BRB injection didn't fire — most likely BTHPORT cache trap (F13) — and Section 7c-pre needs to be re-run with Path B (unpair + re-pair).

```pwsh
$v1HidPdo = (Get-PnpDevice | Where-Object { $_.InstanceId -like "HID\*VID&0001004C_PID&030D*" -and $_.Status -eq "OK" }).InstanceId
$v3HidPdo = (Get-PnpDevice | Where-Object { $_.InstanceId -like "HID\*VID&0001004C_PID&0323*" -and $_.Status -eq "OK" }).InstanceId

& "$PSScriptRoot\..\scripts\mm-hid-descriptor-dump.ps1" -InstanceId $v1HidPdo
& "$PSScriptRoot\..\scripts\mm-hid-descriptor-dump.ps1" -InstanceId $v3HidPdo

# Expected for both v1 and v3:
#   InputReportByteLength = 8
#   FeatureReportByteLength = 2
#   LinkCollections = 5
#   InputValueCaps = 4 (X, Y, Wheel, AC Pan)
#   FeatureValueCaps = 2 (RID 0x03 + 0x04 Resolution Multipliers)
```

**Gate VG-0:** both mice show Mode A caps (Input=8, Feature=2, LinkColl=5). PASS = proceed to VG-1. FAIL = halt; M12 mutation didn't land. Re-run Section 7c-pre with Path B; if still failing, check `sc.exe query MagicMouseDriver` (must be RUNNING) and ETW trace for BRB injection events; if injection fires but caps don't change, BTHPORT cache wasn't actually invalidated — escalate.

### VG-1: v1 regression baseline

```pwsh
# Restart tray to refresh DriverHealthChecker
Get-Process MagicMouseTray -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process "C:\Path\To\MagicMouseTray.exe"
Start-Sleep -Seconds 30

Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 50 |
    Select-String "pid&030d.*battery=.*\(Feature 0x47\)"
# Expected: "OK ... pid&030d ... battery=NN% (Feature 0x47)"
```

**Gate VG-1:** v1 produces `OK battery=N% (Feature 0x47)` within 30 seconds of tray start. PASS = green-light v3 testing. FAIL = halt; v1 regression is a M12 bug; do not proceed.

### VG-2: v3 target outcome

```pwsh
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 50 |
    Select-String "pid&0323.*battery=.*\(Feature 0x47\)"
# Expected: "OK ... pid&0323 ... battery=NN% (Feature 0x47)"
```

**Gate VG-2:** v3 produces `OK battery=N% (Feature 0x47)` within 60 seconds of tray start. PASS = M12 delivers PRD-184's primary feature.

### VG-3: Scroll on both mice

Manual test, 10 seconds per device, in a browser (Edge or Chrome) on a long page (e.g., MDN reference doc):

| Device | Action | Expected |
|--------|--------|----------|
| v1 | 2-finger swipe up + down + sideways | Page scrolls smoothly in all directions; no dropped events; cursor stays steady; left+right click work |
| v3 | Same | Same |

**Gate VG-3:** Both mice scroll fluidly with no perceptible loss. Quantitative metric: `WM_MOUSEWHEEL` event count >= 30 in a 3-second 2-finger gesture (per M13 G1 #1 decision). Use `scripts/mm-wheel-count.ps1` if needed.

### VG-4: 24-hour soak

After VG-1, VG-2, VG-3 pass, leave the system running with both mice idle. Tray polls every 2 hours when battery > 50% (per AdaptivePoller tier).

```pwsh
# After 24 hours:
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 200 |
    Select-String "FEATURE_BLOCKED|OPEN_FAILED|err="
# Expected: zero matches (or only transient ones during sleep/wake)

Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Tail 200 |
    Select-String "OK.*battery=.*\(Feature 0x47\)" |
    Measure-Object | Select-Object Count
# Expected: >= 12 successful reads (one per ~2 hr per mouse over 24 hr)
```

**Gate VG-4:** Sustained `OK battery=N% (Feature 0x47)` reads on both mice for 24 hours. Sleep/wake cycles tolerated. Zero BSOD events.

---

## 10. Health checks

Run continuously during VG-4 soak.

### 10a. BSOD watch

```pwsh
Get-WinEvent -LogName System -MaxEvents 20 -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -eq 1001 -or $_.LevelDisplayName -eq "Critical" } |
    Select-Object TimeCreated, Id, Message
```

Expected: empty.

### 10b. Driver Verifier (optional but recommended for first install)

```pwsh
verifier /flags 0x9bb /driver MagicMouseDriver.sys
# 0x9bb = standard flags + force IRQL checking + I/O verification
# Reboot required after enabling.
```

After 24 hr soak, disable:

```pwsh
verifier /reset
# Reboot required.
```

Any BSOD during verifier-on soak surfaces a real bug; halt and triage.

### 10c. Tray log monitoring

```pwsh
Get-Content "$env:APPDATA\MagicMouseTray\debug.log" -Wait -Tail 20
# Watch in a side terminal for the duration of validation
```

Expected: regular `OK battery=...` entries. Any `FEATURE_BLOCKED`, `OPEN_FAILED`, or `err=87` indicates a partial regression worth investigating before full sign-off.

### 10d. Service health

```pwsh
sc.exe query MagicMouseDriver
# State should remain RUNNING
sc.exe queryex MagicMouseDriver | Select-String "STATE|EXIT_CODE"
# EXIT_CODE = 0
```

---

## 11. Failure modes and recovery

| Failure | Symptom | Recovery action |
|---------|---------|-----------------|
| Build fails (msbuild error) | exit != 0 | Read msbuild log; fix code; rebuild. No system mutation occurred. |
| Signing fails (signtool error 0x800B0100) | cert chain not trusted | Cert wasn't installed to TrustedPublisher + Root; re-run Section 6a. |
| `pnputil /add-driver` fails (signature) | Error 0xE0000247 (NoCert) | Test signing not enabled (3a) or .cat not signed (6c). Re-verify, retry. |
| M12 doesn't bind after Disable+Enable | LowerFilters missing M12 | Apple INF outranks. Run Section 8 rollback, then run M12 INF with `pnputil /add-driver /install /force` flag. If still rank-loses, requires Apple INF removal — STOP, escalate, do not auto-delete (AP-24). |
| BSOD on bind | bugcheck 0xC4 / 0x9F | Force-shutdown, boot to Safe Mode, run Section 8b-c-d (rollback). Triage from `MEMORY.DMP`. |
| v1 regresses (VG-1 fails) | v1 tray log shows err=87 or OPEN_FAILED on PID 030D | M12 bug: PID branch not routing v1 to pass-through. Run Section 8 rollback. Fix code. Rebuild. |
| v3 produces no battery (VG-2 fails) | v3 tray log shows FEATURE_BLOCKED | Either: (a) M12's HandleGetFeature47_ActivePoll path isn't being hit (PID branch wrong), (b) downstream GET_REPORT on 0x90 timing out, (c) buffer marshalling bug. Capture `Tail 50` of debug.log + driver ETW; rollback; triage. |
| v3 scroll dropped events (VG-3 fails) | Scroll feels "stuck" or skips | Translation algorithm bug — most likely TouchState reset on a state we missed. Capture raw input report 0x12 hex via WinDbg; compare to Linux algorithm trace; fix; rebuild. |
| Reg-diff post-rollback shows unexpected drift | reg-diff section 8f produces > 5 unrelated entries | Phase 1 cleanup-style drift — recoverable. Inspect each delta; restore individually if needed; rerun reg-diff. |

---

## 12. Sign-off checklist

Operator (Lesley or designate) initials each line on completion. Proceed only when all are checked.

```
[ ] PRE-1: Pre-flight backup verified (Section 4 gate PRE-1)
[ ] BUILD-1: MagicMouseDriver.sys + .inf in build output
[ ] BUILD-2: hidparser.exe validates g_HidDescriptor[]
[ ] SIGN-1:  signtool verify successful on .sys + .cat
[ ] 7c-pre: BTHPORT cache invalidated (Path A) OR mice re-paired (Path B)
[ ] INSTALL-1: M12 LowerFilters bound to v1 + v3, service RUNNING
[ ] VG-0: HIDP_GetCaps shows Mode A (Input=8, Feature=2, LinkColl=5) on both mice
[ ] VG-1: v1 produces OK battery (Feature 0x47) within 30s
[ ] VG-2: v3 produces OK battery (Feature 0x47) within 60s
[ ] VG-3: scroll fluid on both mice (10-second test each)
[ ] VG-4: 24-hour soak, >= 12 OK reads, zero err= entries, zero BSOD
[ ] HEALTH-10a: no BSOD events in System log over soak window
[ ] HEALTH-10d: service state RUNNING throughout soak

Operator: ____________________________  Date: __________

Sign-off complete -> M12 ratified for personal-use deployment.
WHQL submission is OUT of scope and tracked separately.
```

---

## 13. Appendix: command quick-reference

| Operation | Command |
|-----------|---------|
| Capture pre-state | `pnputil /enum-drivers > pre.txt; reg export HKLM\SYSTEM pre.reg /y` |
| Build | `msbuild MagicMouseDriver.vcxproj /p:Configuration=Debug /p:Platform=x64` |
| Sign .sys | `signtool sign /v /s My /n "MagicMouseTray-TestSign" /fd sha256 /t http://timestamp.digicert.com MagicMouseDriver.sys` |
| Build .cat | `inf2cat /driver:$BuildOut /os:10_X64` |
| Install | `pnputil /add-driver MagicMouseDriver.inf /install` |
| Force rebind | `pnputil /disable-device <id>; pnputil /enable-device <id>` |
| Verify bind | `Get-PnpDeviceProperty -InstanceId <id> -KeyName DEVPKEY_Device_LowerFilters` |
| Service status | `sc.exe query MagicMouseDriver` |
| Tray log tail | `Get-Content $env:APPDATA\MagicMouseTray\debug.log -Tail 50` |
| Uninstall | `pnputil /delete-driver oem<N>.inf /uninstall /force` |
| Reset signing test mode | `bcdedit /set testsigning off` (reboot) |
