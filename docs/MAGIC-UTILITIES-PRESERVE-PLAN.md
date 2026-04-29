# Magic Utilities preserve-and-restore plan (last resort)

**Status: SUPERSEDED — 2026-04-28 (Session 12)**

The production path is now **M12 clean-room KMDF filter driver** (see `docs/M12-MAGIC-UTILITIES-REFERENCE-PLAN.md`). The original preserve-and-ship approach below is no longer the plan.

**Reframe**: MU install is still executed — but as a **reverse-engineering reference** for M12, not as a production driver to ship. The capture script (`scripts/mm-magicutilities-capture.ps1`) and driver extraction steps remain valid. What changes is what happens after capture: we uninstall MU, write our own clean-room driver, and never ship MU's binary. See `docs/M12-MAGIC-UTILITIES-REFERENCE-PLAN.md` for the full M12 plan.

**Why superseded**: Trial already expired (userland dead; driver installs but app won't run). Shipping MU's kernel binary as a production solution carries EULA risk, creates a maintenance dependency on a third-party trial artifact, and leaves no upgrade path. Building M12 from the captured material eliminates all three problems.

**Historical context preserved below** for reference.

---

**Status (original):** documented. **Use only as a last resort** if all other paths fail. Magic Utilities is a paid third-party product with a per-device-per-year subscription model. Their EULA likely prohibits redistributing or re-using the driver files outside the licensed install.

This plan documents the technical mechanism. The decision to execute it is the user's, after reviewing Magic Utilities' Terms of Service.

---

## Context — why this is on the table

Empirical findings from Phase E:
- v3 Magic Mouse battery is readable via the vendor 0xFF00 TLC ReportID 0x90 Input report when COL02 PDO is enumerated as a separate HID child (Descriptor A state).
- The Apple `applewirelessmouse.sys` driver mutates the descriptor for v3 (its binary has no PID 0x0323 hardcoded; INF over-matched). When the descriptor flips to Descriptor B (after DSM property writes), COL02 is gone, battery is unreadable, scroll still works.
- Magic Utilities `MagicMouse.sys` (v3.1.5.3, 2024-11-05) is signed by Microsoft WHQL and was empirically bound to v1+v3 in April 2026 with both scroll AND battery working.
- License enforcement appears to live entirely in the userland (`MagicUtilitiesService.exe` + `MagicMouseUtilities.exe` tray + obfuscated `TrialExpiryDate` registry value). The kernel driver `MagicMouse.sys` has an empty `Services\MagicMouse\Parameters` registry subkey — no license-checked tunables.

This means: the kernel driver alone, without the userland service or tray app, **may** be sufficient to provide scroll + battery support. We could:
1. Install Magic Utilities (28-day free trial, no payment).
2. Capture the driver package + registry footprint.
3. Validate that the driver works without the userland during the trial.
4. Uninstall Magic Utilities normally.
5. Reinstall just the kernel driver from the saved package.

**Whether this is technically viable is empirically tested in step 3.** Whether it's permitted under the EULA is the user's call.

## License caveat — read first

- Magic Utilities is **per-device per-year subscription** (~$4-9/year per device).
- 28-day free trial available.
- Their EULA almost certainly prohibits redistribution and may prohibit using the driver outside the licensed install context.
- Single-machine personal use of preserved files is **less defensible** than paying for a yearly license. It's a license violation in spirit even if not enforced technically.
- This plan is documented for technical completeness, not as a recommendation.

## Technical viability summary

| Component | Required at runtime? | Capture? |
|---|---|---|
| `MagicMouse.sys` (~6 MB KMDF kernel driver) | YES (provides scroll + battery) | YES — DriverStore + System32\drivers copy |
| `MagicMouse.inf` + `MagicMouse.cat` | YES (PnP install needs them) | YES — DriverStore copy |
| `MagicUtilitiesService.exe` (userland service) | **PROBABLY NOT** — needs validation in step 3 | YES (for reference; not for restore) |
| `MagicMouseUtilities.exe` (tray app) | NO | YES (for reference) |
| `HKLM\SOFTWARE\MagicUtilities\Driver` (per-device flags) | YES — driver reads `BthSmoothScrolling=1` etc | YES — reg export |
| `HKLM\SOFTWARE\MagicUtilities\Devices\dt{MM1,MM3}-{MAC}` | UNKNOWN — driver may read these | YES — reg export |
| `HKLM\SOFTWARE\MagicUtilities\App\TrialExpiryDate` (obfuscated) | userland reads this; driver doesn't | YES (capture as-is, don't decode) |
| `HKLM\SYSTEM\CurrentControlSet\Services\MagicMouse` | YES — service definition | Auto-recreated by `pnputil /add-driver /install` |
| `HKLM\SYSTEM\DriverDatabase\DriverPackages\magicmouse.inf_amd64_…` | YES | Auto-recreated by `pnputil /add-driver /install` |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\PnpLockdownFiles\…\MagicMouse.sys` | YES (Windows file protection) | Auto-recreated |
| INF sections `MM1_BTH.NT` + `MM3_BTH.NT` | YES — explicit PID 0x030D and 0x0323 sections | Inside the INF |

## Capture script — `scripts/mm-magicutilities-capture.ps1`

Already written. Captures:

1. **Driver package**: `C:\Windows\System32\DriverStore\FileRepository\magicmouse.inf_amd64_*` — recursive copy + SHA256 manifest
2. **Active driver binary**: `C:\Windows\System32\drivers\MagicMouse.sys` + any `MagicMouse*.cat`
3. **Userland tree** (reference only): `C:\Program Files\MagicUtilities\` — recursive
4. **Registry exports** (.reg via `reg.exe export`):
   - `HKLM\SOFTWARE\MagicUtilities\` (all subkeys)
   - `HKLM\SYSTEM\CurrentControlSet\Services\MagicMouse\`
   - `HKLM\SYSTEM\CurrentControlSet\Services\MagicUtilitiesService\`
   - `HKLM\SYSTEM\DriverDatabase\DriverPackages\magicmouse.inf_amd64_*\`
   - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\PnpLockdownFiles\` (containing MagicMouse.sys entry)
   - `HKLM\SOFTWARE\Classes\Installer\Products\*` (filtered by ProductName ≈ "Magic Utilities")
   - `HKLM\SYSTEM\CurrentControlSet\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}\` (custom bus enumerator)
   - `HKCU\Software\MagicUtilities\` (per-user, optional)
5. **PnP topology** (JSON): all Magic-related InstanceIds with their full child trees
6. **DEVPKEY dump** for v1+v3 BTHENUM PDOs (LowerFilters, Service, drivers etc.)
7. **Service config**: `sc qc` and `sc qdescription` for both services
8. **Driver dependencies**: Win32_PnPSignedDriver + MagicMouse.sys VersionInfo + `pnputil /enum-drivers`
9. **README.md** in capture root with date, version, restore commands, EULA caveat

Output: `D:\Backups\MagicUtilities-Capture-<YYYY-MM-DD-HHMM>\` with subdirs `driver-package/`, `driver-binary/`, `program-files/`, `registry/`, `pnp/`, plus `manifest.txt` (sha256sum-c compatible) and `README.md`.

Pre-flight: admin check, install presence, free space (~2 GB), output dir non-existence. Fail-closed — partial captures get cleaned up on exception.

## Validation step (do this DURING the trial)

Before deciding to preserve the package long-term, validate empirically:

1. **Install Magic Utilities** (28-day trial, no payment).
2. **Verify scroll + battery on v3** for 30 minutes of normal use.
3. **Check Procmon** during normal use, filtered to `MagicUtilities_Service.exe` and `MagicMouseUtilities.exe`. Note every IOCTL/registry/file op. The expectation is the userland reads/writes config + handles tray UI but doesn't act as a heartbeat for the kernel driver.
4. **Stop both userland processes** (`Stop-Service MagicUtilitiesService`, kill `MagicMouseUtilities.exe`). Verify scroll + battery STILL work.
5. **If still works** → kernel driver is self-sufficient. Preserve plan is technically viable. Run `scripts/mm-magicutilities-capture.ps1` to capture.
6. **If scroll or battery breaks when userland is stopped** → kernel driver depends on userland. Preserve plan needs revisiting.

Step 5/6 is the empirical ground truth. Without doing this we don't know.

## Restore sequence (if/when needed)

Assuming step 5 above succeeded:

```powershell
# 1. Run as admin
# 2. Pick the saved capture dir
$capRoot = 'D:\Backups\MagicUtilities-Capture-2026-XX-XX-HHMM'
$infPath = Get-ChildItem -Path "$capRoot\driver-package" -Filter 'magicmouse.inf' -Recurse | Select-Object -First 1 -ExpandProperty FullName

# 3. Install the driver package via pnputil (uses the saved .cat for signature validation)
pnputil /add-driver $infPath /install

# 4. Optional: restore the per-device config from saved registry export
reg import "$capRoot\registry\HKLM_SOFTWARE_MagicUtilities.reg"

# 5. Force PnP rebind on v3 mouse (Disable + Enable BTHENUM PDO)
$v3 = Get-PnpDevice | Where-Object { $_.InstanceId -like 'BTHENUM*VID&0001004C_PID&0323*' -and $_.Class -eq 'HIDClass' }
Disable-PnpDevice -InstanceId $v3.InstanceId -Confirm:$false
Start-Sleep -Seconds 3
Enable-PnpDevice -InstanceId $v3.InstanceId -Confirm:$false

# 6. Verify
Get-PnpDevice -InstanceId $v3.InstanceId | Select FriendlyName, Status, Service
# expect: Apple Wireless Mouse / OK / HidBth + LowerFilters: MagicMouse
```

Notably, this sequence does **not** install or run:
- `MagicUtilitiesService.exe` (the userland Windows service)
- `MagicMouseUtilities.exe` (the tray app)
- Any executable from `C:\Program Files\MagicUtilities\`

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Kernel driver depends on userland service | Medium | Validation step 4 catches this before commit |
| Microsoft Update overwrites with applewirelessmouse | Medium | Set higher Driver Rank in INF, or `Exclude` rule on applewirelessmouse for v3 PIDs |
| Magic Utilities ships future driver with license enforcement | Low (binary captured is frozen) | No automatic updates after preserve |
| EULA violation | LEGAL — user's call | Document in capture README |
| Capture script bugs lose data | Low | Fail-closed, manifest with SHA256 lets you verify integrity |

## Fallback if validation fails

If step 4 of validation shows the kernel driver requires the userland: the preserve plan is dead. Options revert to:

- Custom KMDF filter (Phase M12) — 2-4 weeks driver dev
- Userland scroll synthesis + remove applewirelessmouse from v3 (Phase 4A) — 1-2 weeks tray code
- Detect Descriptor B + recycle (Option 2 from `docs/v3-BATTERY-EMPIRICAL-PROOF-AND-PATHS.md`) — 1-2 days tray code (workaround, not root-cause)

## File index

- `scripts/mm-magicutilities-capture.ps1` — the 663-line capture script (validated PS5.1 syntax)
- `docs/v3-BATTERY-EMPIRICAL-PROOF-AND-PATHS.md` — empirical proof v3 battery isn't readable today + path inventory
- `docs/REGISTRY-DIFF-AND-PNP-EVIDENCE.md` — three-era registry comparison (Nov 2025 → Apr 03 → Apr 27)
- `.ai/test-runs/2026-04-27-154930-T-V3-AF/regdiff/MAGICUTILITIES-FULL-DUMP.txt` — full registry footprint extracted from April 3 backup
