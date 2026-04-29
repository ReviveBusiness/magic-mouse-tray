# M12: Magic Utilities reference capture plan

**BLUF**: Install Magic Utilities on the host to extract its KMDF driver binary and INF as reverse-engineering reference material for writing our own M12 KMDF filter driver — then uninstall. We do not ship MU's driver; we learn from it.

---

## Empirical context

Phase E (Session 11, 2026-04-28) produced the definitive evidence that we need a kernel driver:

- Mode A (Descriptor A / `applewirelessmouse` filter inactive-state) → battery readable via `HidD_GetInputReport(0x90)` byte[2]; scroll NOT synthesized.
- Mode B (Descriptor B / `applewirelessmouse` filter active-state) → scroll synthesized at Win32 input layer; battery collection (vendor 0xFF00 TLC, COL02) stripped from the HID tree.
- These modes are **mutually exclusive** under Apple's `applewirelessmouse.sys` v6.2.0.0. See AP-21 in `Personal/magic-mouse-tray/.ai/playbooks/autonomous-agent-team.md`.
- 588 probe attempts across 6 channels in Mode B returned 0 battery readings (full inventory: `docs/v3-BATTERY-EMPIRICAL-PROOF-AND-PATHS.md`).
- v3 firmware (PID 0x0323) does NOT back Feature ReportID 0x47 that Apple's filter generates as a phantom capability in Mode B.
- v1 and v3 post-filter HID descriptors are byte-identical (confirmed in `docs/DESCRIPTOR-A-vs-B-DIFF.md`). The mutual-exclusion is firmware-level, not descriptor-level.
- No registry tunable exists (`Services\applewirelessmouse\Parameters` is empty).

Full findings: `docs/PHASE-E-FINDINGS.md`, `docs/DESCRIPTOR-A-vs-B-DIFF.md`, `docs/v3-BATTERY-EMPIRICAL-PROOF-AND-PATHS.md`.

---

## Why install Magic Utilities (vs clean-room M12)

Clean-room M12 is viable — ~50 LOC translation logic + ~400 LOC KMDF scaffold — but requires:

1. Knowing exactly which KMDF APIs MU uses to intercept `IOCTL_HID_GET_REPORT_DESCRIPTOR` and issue a downstream `GET_REPORT(Input, 0x90)` to satisfy an upstream `GET_REPORT(Feature, 0x47)`.
2. Knowing how MU's INF binds both v1 PID 0x030D and v3 PID 0x0323 without inheriting Apple's `applewirelessmouse` over-match behaviour.
3. Knowing how MU handles the firmware gap (v1 backs 0x47 natively; v3 doesn't — MU must branch on PID or probe firmware state at `AddDevice` time).

MU's `MagicMouse.sys` (v3.1.5.3, 2024-11-05, WHQL-signed) was empirically observed binding to both v1+v3 with both scroll AND battery working (registry artefact from 2026-04-03 in `docs/REGISTRY-DIFF-AND-PNP-EVIDENCE.md`). It solves exactly the problem M12 needs to solve.

**MU install on host** lets us:
- Read the INF directly — service registration, hardware ID matching, DDInstall sections, AddReg.
- Run `dumpbin /imports MagicMouse.sys` to confirm KMDF version and which WDF/HID APIs are used.
- Run `strings MagicMouse.sys` to surface IOCTL codes, debug strings, and version-branch logic.
- Load `MagicMouse.sys` in Ghidra to trace the `EvtIoDeviceControl` handler that performs the 0x47→0x90 GET_REPORT redirect and the v1-vs-v3 firmware-gap branch.

The captured artefacts reduce M12 from a 2-4 week research effort to an estimated **4-8 hour agentic coding session** with clear API targets.

**Why host instead of Windows Sandbox**: the user is on Windows 11 Home, which does not include Windows Sandbox.

**Trial status**: MU's 28-day trial is already expired. The userland (`MagicMouseUtilities.exe` tray app, `MagicUtilitiesService.exe`) refuses to launch because it reads `HKLM\SOFTWARE\MagicUtilities\App\TrialExpiryDate` and rejects the expired timestamp. The kernel driver installs unconditionally during `setup.exe` execution because driver installation does not check trial state. We do not manipulate the trial registry marker (see AP-23).

---

## Capture procedure

Script: `scripts/mm-magicutilities-capture.ps1` (663 lines, PS5.1 syntax-clean, fail-closed).

**Pre-capture steps:**
1. Run `setup.exe` as administrator to install Magic Utilities. Accept all UAC prompts.
2. Reboot if prompted (driver installation typically requires a reboot to bind).
3. After reboot, run the capture script from an elevated PowerShell prompt:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& .\scripts\mm-magicutilities-capture.ps1
```

**What the script captures** (output to `D:\Backups\MagicUtilities-Capture-<YYYY-MM-DD-HHMM>\`):

| Artefact | Path | Purpose |
|----------|------|---------|
| `MagicMouse.sys` v3.1.5.3 | `C:\Windows\System32\DriverStore\FileRepository\magicmouse.inf_amd64_*\` | Kernel binary for RE |
| `magicmouse.inf` | Same DriverStore dir | INF template for M12 INF |
| `MagicMouse.cat` | Same DriverStore dir | Signing artifact (reference only) |
| Registry exports | `HKLM\SOFTWARE\MagicUtilities\`, `HKLM\SYSTEM\CurrentControlSet\Services\MagicMouse\` | Service reg patterns |
| PnP topology JSON | via `Get-PnpDevice` | Confirm binding for both PIDs |
| DEVPKEY dump v1+v3 | `LowerFilters`, `Service`, driver stack | Validate MU binds both PIDs |
| SHA256 manifest | `manifest.txt` | Integrity check |

Script pre-flight: admin check, MU install presence, ~2 GB free space, output dir non-existence. Partial captures cleaned up on exception.

---

## INF reference extraction

From `magicmouse.inf`, extract and study:

| Section | What to look for | What to copy into M12 INF |
|---------|-----------------|--------------------------|
| `[Models]` | Hardware IDs for `PID&030D` (v1) and `PID&0323` (v3) | Copy verbatim — both PIDs must bind |
| `[DDInstall]` | `AddService` directive — service name, service type, load order group | Adapt (service name → `MagicMouseFilter` or similar) |
| `[DDInstall.HW]` | `AddReg` writing `LowerFilters` | Copy structure; confirm it targets the BTHENUM Enum key (not class key) |
| `[ServiceInstall]` | `ServiceType`, `StartType`, `LoadOrderGroup` | Use `0x1` (SERVICE_KERNEL_DRIVER), `0x3` (DEMAND_START), `"PnP Filter"` |
| `[Strings]` | Provider, DriverDesc strings | Replace with our own |

**What to skip from MU's INF:**
- Any `ClassGuid` referencing `{7D55502A-2C87-441F-9993-0761990E0C7A}` — that is MU's custom bus enumerator GUID. We don't need it; we bind directly to BTHENUM devices.
- `Include=` and `Needs=` directives referencing MU-proprietary INFs.
- Any `AddComponent` or `AddSoftware` directives (userland installer hooks).

---

## Reverse-engineering procedure

### Step 1: dumpbin (PE import table)

From EWDK command environment at `D:\ewdk25h2\`:

```cmd
dumpbin /imports MagicMouse.sys
```

**Expected output sections:**
- `Wdf01000.sys` — KMDF framework. Note which KMDF version (KMDF 1.x where x indicates minimum OS).
- `hidparse.sys` or `hidclass.sys` — HID parsing APIs (`HidP_GetCaps`, `HidP_GetValueCaps`, `HidP_GetUsages`).
- `ntoskrnl.exe` — kernel APIs (`ExAllocatePool2`, `IoCompleteRequest`, `KeAcquireSpinLock`).
- Specific `Wdf*` functions of interest: `WdfRequestRetrieveOutputBuffer`, `WdfRequestComplete`, `WdfIoTargetSendIoctlSynchronously`, `WdfFdoInitSetFilter`.

Log the full import list to `.ai/re-artefacts/dumpbin-imports.txt`.

### Step 2: strings (literal string extraction)

```cmd
strings -n 8 MagicMouse.sys > strings-output.txt
```

Or from EWDK:

```cmd
dumpbin /rawdata:5 MagicMouse.sys
```

**Look for:**
- IOCTL hex codes (e.g. `0x000B0003` = `IOCTL_HID_GET_REPORT_DESCRIPTOR`, `0x000B0192` = `IOCTL_HID_GET_FEATURE`)
- WPP debug strings — these often contain function names and logic branch labels
- PID references (`0x030D`, `0x0323`) — confirm firmware-gap branching is in the binary
- Version strings confirming `3.1.5.3`
- Registry key paths (MU may read per-device config from `HKLM\SOFTWARE\MagicUtilities\Devices\...`)

Log to `.ai/re-artefacts/strings-output.txt`.

### Step 3: Ghidra static analysis

1. Download Ghidra from https://ghidra-sre.org (free, NSA-developed, no cost).
2. Install to `D:\ghidra\` (does not require admin).
3. Create a new project: `File → New Project → Non-Shared → magic-mouse-re`.
4. Import `MagicMouse.sys`: `File → Import File`. Ghidra auto-detects PE/COFF format.
5. Run auto-analysis with defaults (accept all analyzers). This resolves Windows kernel symbols via PDB import from Microsoft's symbol server — ensure network access is available, or pre-download PDBs via `symchk.exe`.

**Navigation targets:**

| Target | How to navigate | What to look for |
|--------|----------------|-----------------|
| `DriverEntry` | Symbol tree → Functions → `DriverEntry` | KMDF `WdfDriverCreate` call; `EvtDriverDeviceAdd` registration |
| `EvtDriverDeviceAdd` | Called from `DriverEntry` | `WdfFdoInitSetFilter()` call (confirms filter mode); lower I/O queue creation |
| `EvtIoDeviceControl` | Registered as queue callback | The IOCTL dispatch switch — find `case 0xB0192` (GET_FEATURE) or equivalent |
| GET_REPORT redirect handler | Inside the IOCTL case | The function that translates `GET_REPORT(Feature, 0x47)` → `GET_REPORT(Input, 0x90)` and reformats the response |
| PID-branch logic | Near `AddDevice`-equivalent or device-init callback | `if (pid == 0x030D) { ... } else if (pid == 0x0323) { ... }` — the firmware-gap handler |

**Key code pattern to find** (the ~50 LOC we need to clone):

```
// Pseudocode from Ghidra decompiler — adjust names to match actual decompilation
NTSTATUS HandleGetFeatureReport(WDFREQUEST request, size_t outputLen) {
    HID_XFER_PACKET pkt;
    WdfRequestRetrieveInputBuffer(request, sizeof(pkt), &pkt, NULL);
    
    if (pkt.reportId != 0x47) {
        // pass-through to lower driver
        return ForwardRequest(request);
    }
    
    // Rewrite: issue GET_INPUT_REPORT(0x90) to lower device
    HID_XFER_PACKET inputPkt = { .reportId = 0x90, ... };
    status = WdfIoTargetSendIoctlSynchronously(lowerTarget, IOCTL_HID_GET_INPUT_REPORT, &inputPkt, ...);
    
    // Extract battery % from buf[2], reformat as 0x47 feature response
    ...
    WdfRequestComplete(request, STATUS_SUCCESS);
}
```

Log Ghidra decompiler output for all four target functions to `.ai/re-artefacts/ghidra-decompiled/`.

---

## Translation logic to clone (the core 50 LOC)

The 0x47→0x90 GET_REPORT redirect is the minimum viable M12 implementation:

1. M12 registers as a lower filter under HidBth (via INF `LowerFilters` AddReg).
2. M12's `EvtIoDeviceControl` intercepts `IOCTL_HID_GET_FEATURE` where `reportId == 0x47`.
3. M12 issues `IOCTL_HID_GET_INPUT_REPORT` with `reportId = 0x90` to the lower device (the raw BT HID PDO below HidBth).
4. M12 extracts `buf[2]` (battery %) from the 3-byte Input 0x90 response.
5. M12 constructs a valid Feature 0x47 response buffer and completes the original request.
6. All other IOCTLs pass through unmodified (`WdfRequestForwardToIoQueue` or `WdfRequestSend` to lower target).

v1-vs-v3 firmware gap: v1 firmware backs Feature 0x47 natively. When M12 receives a GET_FEATURE(0x47) from HidClass and the device is v1 (PID 0x030D), the pass-through path returns the native response without M12 intervening. When the device is v3 (PID 0x0323), M12 intercepts and performs the translation. PID is available at `AddDevice` time via `WdfDeviceGetHardwareRegistryKey` or from the instance ID.

---

## v1 mouse as regression control

v1 (PID 0x030D, known-working with both scroll and battery under Magic Utilities) serves as the known-good baseline throughout M12 development.

- M12 INF must bind both `PID&030D` and `PID&0323`.
- After every M12 build iteration, validate v1 first: `OK battery=N% (Feature 0x47)` in debug.log + scroll working.
- Only after v1 passes, test v3.
- If M12 breaks v1, the pass-through path (for v1's native 0x47 support) is broken. Fix that before proceeding.

v1 regression failure = a separate bug from v3 translation failure. Diagnose independently.

---

## Post-capture cleanup sequence

**Immediately after capture script completes and manifest is verified:**

1. Uninstall Magic Utilities via `Settings → Apps → Magic Utilities → Uninstall` (or via its own uninstaller).
2. Verify MU driver is removed: `pnputil /enum-drivers | Select-String "magicmouse"` → should return nothing.
3. Confirm `C:\Windows\System32\DriverStore\FileRepository\magicmouse.inf_amd64_*` is gone.
4. The mice will auto-rebind to `applewirelessmouse` via Windows PnP (it is still in the DriverStore as `AppleWirelessMouse.inf`). If auto-rebind does not occur, re-pair the mouse via Bluetooth Settings.
5. Verify Apple filter is back: `Get-PnpDeviceProperty -KeyName DEVPKEY_Device_LowerFilters` on the v3 BTHENUM PDO should show `applewirelessmouse`.
6. Run `scripts/mm-accept-test.ps1` to confirm baseline is restored (scroll works, battery reads in Mode A if currently in Descriptor A state).

**MU driver will conflict with M12** if left installed — same hardware IDs mean PnP will choose by Driver Rank. Uninstall before any M12 install.

---

## M12 build sequence

Estimated total: 4-8 hours agentic with Ghidra analysis complete.

1. **Capture** — run `setup.exe` → reboot → `mm-magicutilities-capture.ps1` → verify manifest.
2. **RE** — `dumpbin /imports`, `strings`, Ghidra analysis → log to `.ai/re-artefacts/`.
3. **Uninstall MU** — steps above.
4. **Write INF** — adapt MU's `magicmouse.inf` structure into `driver/MagicMouseFilter.inf`. Both PIDs. Lower filter. Correct `ServiceType`/`StartType`/`LoadOrderGroup`.
5. **Write driver scaffold** — `DriverEntry`, `EvtDriverDeviceAdd` (`WdfFdoInitSetFilter` + queue setup), `EvtIoDeviceControl` (pass-through + 0x47 intercept skeleton).
6. **Write translation logic** — implement `HandleGetFeature47` based on Ghidra-derived pattern.
7. **Write v1 pass-through branch** — PID check at `AddDevice`; if v1, skip translation.
8. **Build** — from EWDK command environment (`D:\ewdk25h2\`): `msbuild driver\MagicMouseFilter.vcxproj /p:Configuration=Debug /p:Platform=x64`.
9. **Validate descriptor** — `hidparser.exe driver\MagicMouseFilter.inf` must pass clean.
10. **Test-sign** — `inf2cat.exe /driver:driver\ /os:10_X64` → `signtool sign /fd sha256 /a` with test cert.
11. **Install on v1 first** — `pnputil /add-driver MagicMouseFilter.inf /install`. Verify v1 produces `OK battery=N% (Feature 0x47)` in debug.log + scroll working.
12. **Install on v3** — verify same.
13. **Sleep/wake + reboot tests** — confirm both mice survive suspend-resume and cold boot.

---

## EULA / legal position

We are NOT:
- Redistributing MU's `MagicMouse.sys` or any MU binary.
- Shipping MU code in M12.
- Bypassing MU's license check.
- Reproducing MU's source code verbatim.

We ARE:
- Installing MU under its standard trial mechanism (driver install does not check trial state).
- Using the installed binary as a reference to understand the API patterns required for hardware interoperability.
- Writing a clean-room implementation (M12) that achieves the same hardware interaction using independently-written code.

Legal basis for reverse engineering for interoperability:

| Jurisdiction | Statute | Applicability |
|---|---|---|
| USA | DMCA §1201(f) — `17 U.S.C. § 1201(f)` | Circumvention permitted when necessary to achieve interoperability of an independently created computer program with other programs |
| Canada | Copyright Act §30.61 — `R.S.C. 1985, c. C-42, s. 30.61` | Reproduction for sole purpose of achieving interoperability of an independently created program |
| EU | Software Directive 2009/24/EC Art. 6 | Decompilation permitted to obtain information necessary for interoperability |

The interoperability target is **Apple Magic Mouse hardware** (a physical device), not MU's software. M12 is an independently created program. The captured binary is used only to derive interface information (KMDF API usage patterns, IOCTL codes, HID report translation logic) — not as a source for copying.

**Do NOT** decode or reproduce MU's EULA-enforcement logic, serial number scheme, or userland business logic. We have no interest in and no need for any of that.

---

## Validation oracle

M12 success is binary: the existing tray app's debug.log must produce:

```
OK battery=N% (Feature 0x47)
```

...for **both** v1 (PID 0x030D) and v3 (PID 0x0323) within 30 seconds of mouse connection.

The `(Feature 0x47)` suffix is emitted by `unifiedAppleBattery` path in `MouseBatteryReader.cs` when `HidD_GetFeature` on ReportID 0x47 returns a valid non-zero battery value. This path is already implemented; M12 simply needs to ensure the Feature 0x47 response is correctly synthesized from Input 0x90 data.

Secondary acceptance: `mm-accept-test.ps1` AC-01 through AC-08 all pass on both mice with M12 installed.

---

## Risk register

| Risk | Severity | Recovery |
|------|----------|---------|
| MU setup.exe installs userland that modifies registry or device stack in ways that conflict with subsequent RE | Low | Run `mm-magicutilities-capture.ps1` before any MU post-install changes can occur; capture script runs immediately after reboot |
| MU driver conflicts with `applewirelessmouse` during RE window (before uninstall) | Medium | Expected — MU displaces Apple filter. This is the desired state during RE. Do not run tray app until MU is uninstalled and Apple filter rebinds. |
| Capture script misses a file (DriverStore path varies by GUID suffix) | Low | Script uses glob `magicmouse.inf_amd64_*`; fail-closed; SHA256 manifest verifies completeness. Check manifest before uninstalling MU. |
| Windows Update installs a new MU or Apple driver during RE window | Low | Windows Update is paused 7 days (from Phase 0). Verify pause is still active before running setup.exe. |
| Ghidra analysis is inconclusive (obfuscated binary, stripped symbols) | Medium | Fall back to KMDF documentation + Linux `hid-magicmouse.c` pattern + Windows HID filter driver samples. The dumpbin import list alone narrows API surface significantly even without symbol names. |
| M12 driver causes BSOD on test install | Medium | Test in VM first if available (WSL2 does not expose raw Bluetooth; skip if no VHD option). Recovery: boot to safe mode, `pnputil /delete-driver MagicMouseFilter.inf /uninstall /force`. |
| MU EULA challenge | LEGAL — low technical risk | We are not redistributing any MU binary or code. Legal position documented above. Keep capture artefacts local and non-distributed. |
| v3 PID 0x0323 byte layout for Report 0x12 differs from Ghidra-derived assumption | Medium | Capture raw Report 0x12 ETW trace on Windows before writing `TranslateTouch()`. Known pre-existing blocker from Sessions 6-7 (PRD-184 Decision 2026-04-27 "PID 0323 Report 0x12 byte layout unconfirmed"). |

---

## File index

| File | Role |
|------|------|
| `scripts/mm-magicutilities-capture.ps1` | Capture script (663 lines, PS5.1, fail-closed) |
| `docs/MAGIC-UTILITIES-PRESERVE-PLAN.md` | Original preserve plan — now SUPERSEDED; see that file |
| `docs/PHASE-E-FINDINGS.md` | Empirical evidence that kernel driver is required |
| `docs/DESCRIPTOR-A-vs-B-DIFF.md` | A/B descriptor state comparison; confirms mutual exclusion |
| `docs/v3-BATTERY-EMPIRICAL-PROOF-AND-PATHS.md` | 588 probe attempts / 0 hits in Mode B; paths forward |
| `docs/REGISTRY-DIFF-AND-PNP-EVIDENCE.md` | Three-era registry diff; MU binding evidence from 2026-04-03 |
| `KMDF-PLAN.md` | M12 KMDF driver plan (INF analysis, EWDK setup, driver skeleton) |
| `PSN-0001-hid-battery-driver.yaml` | Problem session note; H-013, AP-22, AP-23, D-014, D-015 |
| `driver/` | M12 driver source (post-capture) |
| `.ai/re-artefacts/` | dumpbin output, strings output, Ghidra decompiled functions |
