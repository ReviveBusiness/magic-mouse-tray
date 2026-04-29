# Apple Wireless Mouse Driver — Recovery Procedure

**Last updated**: 2026-04-28  
**Session**: 12 (PRD-184 magic-mouse-tray)  
**Related incident**: `INCIDENT-2026-04-28-APPLE-INF-DELETION.md`

---

## BLUF

If the Magic Mouse v3 or v1 loses scroll (bound to wrong driver) or `pnputil /enum-drivers` shows no `applewirelessmouse.inf`, use this runbook to restore the Apple HID driver from backup. Primary source is `D:\Backups\AppleWirelessMouse-RECOVERY\`. Full reinstall takes under 5 minutes.

---

## 1. When to Use This Runbook

Use this procedure if any of the following are true:

- `pnputil /enum-drivers | findstr -i apple` returns no results
- Magic Mouse v3 scroll is broken after a driver change operation
- Magic Mouse v1 scroll is broken after a driver change operation
- Device Manager shows the mouse bound to a non-Apple driver (e.g., `BTHLEDevice`, `MagicMouse`, or `HidUsb` without Apple as provider)
- You ran `pnputil /delete-driver oem*.inf /force` on an INF that turned out to be Apple's

Do NOT use this procedure if scroll is broken for other reasons (e.g., MU userland service running — that is a separate issue).

---

## 2. Prerequisites

- **Admin PowerShell** — right-click PowerShell, "Run as administrator"
- **Test signing** — verify status before proceeding:

```powershell
bcdedit | findstr testsigning
```

Expected output if enabled: `testsigning    Yes`

Test signing must be enabled if restoring from the `.ai/snapshots/` INF-only fallback (no catalog). It is not required when restoring from `D:\Backups\AppleWirelessMouse-RECOVERY\` (which includes the original CAT file).

---

## 3. Recovery Sources (Priority Order)

Attempt sources in order. Stop at the first that works.

| Priority | Source | Location | Completeness |
|---|---|---|---|
| PRIMARY | Full backup (INF + SYS + CAT) | `D:\Backups\AppleWirelessMouse-RECOVERY\AppleWirelessMouse.inf` | Full — use this first |
| FALLBACK 1 | Zip archive | `D:\Backups\MagicMouse2DriversWin11x64-master.zip` | Full — extract, then use INF from extracted folder |
| FALLBACK 2 | Snapshot INF (INF only, no SYS/CAT) | `C:\Users\Lesley\projects\Personal\magic-mouse-tray\.ai\snapshots\mm-state-20260427T235903Z\oem0-applewirelessmouse.inf` (use latest timestamp) | Partial — INF only; requires `.sys` already in DriverStore or manual staging; may require testsigning |
| FALLBACK 3 | Re-download | Search GitHub for `MagicMouse2DriversWin11x64-master` | Full — download zip, extract, use INF |

**Note on FALLBACK 2**: The snapshot INFs were captured from a live DriverStore and contain the full INF text, but `pnputil /add-driver` requires the `.sys` referenced in the INF to be co-located or already present in DriverStore. If `applewirelessmouse.sys` is absent, this fallback requires manual `.sys` staging or test-signed catalog bypass. Use FALLBACK 1 or 2 before resorting to this.

---

## 4. Recovery Commands

Run the following in an admin PowerShell session.

### Step 1 — Add driver to DriverStore and install

```powershell
pnputil /add-driver "D:\Backups\AppleWirelessMouse-RECOVERY\AppleWirelessMouse.inf" /install
```

This stages the INF + SYS + CAT into DriverStore and installs. Expected output includes a new `oem*.inf` assignment and "Driver package added successfully."

If using FALLBACK 1 (zip), extract first:

```powershell
Expand-Archive "D:\Backups\MagicMouse2DriversWin11x64-master.zip" -DestinationPath "D:\Backups\MagicMouse2DriversWin11x64-master" -Force
pnputil /add-driver "D:\Backups\MagicMouse2DriversWin11x64-master\MagicMouse2DriversWin11x64-master\AppleWirelessMouse.inf" /install
```

(Adjust path to match the extracted folder structure.)

### Step 2 — Remove and rescan BT device instances

The mouse instances must be removed so PnP re-evaluates driver rank and rebinds to the newly installed Apple driver.

```powershell
pnputil /remove-device "BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&0001004c_PID&0323\9&73b8b28&0&D0C050CC8C4D_C00000000"
pnputil /remove-device "BTHENUM\{00001124-0000-1000-8000-00805f9b34fb}_VID&000205ac_PID&030d\9&73b8b28&0&04F13EEEDE10_C00000000"
pnputil /scan-devices
```

**Machine-specific caveat**: The device instance IDs above are valid for the current dev machine (Magic Mouse v3 VID 004c PID 0323, Magic Mouse v1 VID 05ac PID 030d). On a different machine, or if hardware IDs have changed, query first:

```powershell
Get-PnpDevice | Where-Object { $_.InstanceId -like "BTHENUM*PID*0323*" -or $_.InstanceId -like "BTHENUM*PID*030d*" } | Select-Object InstanceId, Status, FriendlyName
```

Use the returned `InstanceId` values in the `pnputil /remove-device` calls.

---

## 5. Verification

After recovery, verify in this order:

1. **Confirm Apple INF is registered**:

```powershell
pnputil /enum-drivers | findstr -i apple
```

Expected: line showing `AppleWirelessMouse.inf` with provider `Apple Inc.`

2. **Scroll v3** — move Magic Mouse v3, confirm pointer moves and scroll works in a browser or text editor

3. **Scroll v1** — if v1 is paired, confirm same

4. **Tray debug log** — if the tray app is running, check for battery readout:

```powershell
Get-Content "C:\ProgramData\magic-mouse-tray\debug.log" -Tail 20
```

Look for `OK battery=` entries. Battery err=87 is expected when Apple's driver is installed without the MU descriptor mutation — this is the known baseline state (Mode B, 47-byte input descriptor).

---

## 6. Cleanup — Removing a Conflicting MU Kernel Driver

If Magic Utilities kernel INF was installed as part of the test that triggered this recovery (e.g., `oem52.inf`), remove it after Apple's INF is confirmed restored:

```powershell
# Identify the MU INF number
pnputil /enum-drivers | findstr -i magic

# Remove it (substitute the correct oem*.inf number)
pnputil /delete-driver oem52.inf /uninstall /force
```

This is safe at this point because Apple's INF is restored and backed up. The `/uninstall` flag removes the driver from any currently bound devices before deleting the package.

---

## 7. Driver Provenance

The `AppleWirelessMouse.inf` and `applewirelessmouse.sys` files in `D:\Backups\AppleWirelessMouse-RECOVERY\` are **not** from Apple Inc. They are from the open-source GitHub project `MagicMouse2DriversWin11x64` (search GitHub for that project name).

The project README states: "Drivers that would work with Windows 10 x64 and fix scrolling for Apple Magic Mouse 2." It includes a special thanks to `brigadier` (timsutton's Apple driver extractor tool), suggesting the `.sys` may be derived from an Apple Boot Camp or macOS driver binary.

The INF `ProviderName` field says `Apple Inc.` and the INF declares standard HID hardware IDs. The catalog signer is a third party, not Apple. The driver is not WHQL-signed by Microsoft for Windows 11 — testsigning or manual catalog bypass may be required on systems with Secure Boot driver signing enforcement.

This provenance is relevant for PRD-184 M13+ work: the open-source `applewirelessmouse.sys` demonstrates that descriptor mutation + scroll translation can be implemented as a third-party kernel filter without Apple's official driver. It is a read-only behavioral reference alongside `hid-magicmouse.c` (Linux, GPL-2) and `MagicMouse.sys` from Magic Utilities (closed-source, Ghidra target).

---

## 8. Keeping the Backup Current

After any driver update that changes `applewirelessmouse.inf` or `applewirelessmouse.sys`:

1. Copy the new files from DriverStore to `D:\Backups\AppleWirelessMouse-RECOVERY\`
2. Update the `SOURCE-README.txt` in that directory with the new version and date
3. Run `scripts/capture-state.ps1` to snapshot the updated state
