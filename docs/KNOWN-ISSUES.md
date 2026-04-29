# M12 Known Issues

## Mouse cursor sensitivity is low

**Symptom**: Mouse pointer movement feels slow / requires more physical motion than expected.

**Root cause**: This is inherited from the underlying HID input report layout (RID=0x02). The Apple wireless mouse stack reports cursor delta in 8-bit signed range with hardware-level scaling. Windows mouse-pointer-speed slider applies a multiplier on top, but the underlying resolution is fixed at the firmware level.

**Workaround**: Settings -> Mouse -> adjust pointer speed slider. For finer control, install third-party tools like X-Mouse Button Control.

**Resolution path**: M12 v2 may add per-device sensitivity scaling via the CRD config (`Devices\<PID>\PointerSensitivity` REG_DWORD). Tied to the v2 click handling milestone, which parses RID=0x29 input reports directly and could rescale before forwarding.

**Reference**: Upstream issue #4 (`MagicMouse2DriversWin10x64`).

---

## Scroll direction is "natural" (Mac-style) -- want traditional Windows scroll

**Symptom**: Scrolling up moves content down (Mac-style "natural" scroll).

**Workaround (no M12 change needed)**: Windows already supports per-device scroll inversion. Open Device Manager -> expand HID -> find your Magic Mouse instance -> Properties -> Details tab -> set Property to "Device instance path" -> note the path. Then in Registry Editor:

```
HKLM\SYSTEM\CurrentControlSet\Enum\<DeviceInstancePath>\Device Parameters\FlipFlopWheel = 1 (REG_DWORD)
```

Reboot. Scroll direction is now flipped.

Alternative: tools like X-Mouse Button Control or "Apple Magic Mouse Utilities" (paid) provide GUI for this.

**Why M12 doesn't implement directly**: Windows already provides this; duplicating it adds maintenance burden without value.

**Reference**: Upstream issue #7.

---

## Doesn't work on Windows 11 ARM64 (Copilot+ PC, Snapdragon X)

**Symptom**: M12 fails to install on Windows 11 ARM64 devices.

**Root cause**: M12 v1 ships only an x64 build. ARM64 Windows requires a separate driver build with the ARM64 KMDF toolchain.

**Workaround**: None for v1. Use only the basic Windows-default Bluetooth HID driver, which provides cursor + click but no scroll on Magic Mouse v3.

**Resolution path**: M12 v2 may add ARM64 build target. Requires Phase 3+ build harness expansion + retest matrix.

**Reference**: Upstream issue #13.

---

## Smart zoom / pinch gestures not supported

**Symptom**: Single-finger and 2-finger gestures (smart zoom, swipe) not interpreted by Windows.

**Root cause**: M12 v1 passes through the Apple-driver Mode B descriptor (Wheel + Pan only). Smart zoom requires parsing the RID=0x29 vendor blob with multi-touch state tracking -- the v2 click-handling milestone work.

**Workaround**: Use 2-finger horizontal swipe for back/forward navigation in browsers (Windows handles this via Pan capability already).

**Resolution path**: M12 v2 click handling milestone (~500-1000 LOC additional).

**Reference**: Upstream issue #10.

---

## Magic Utilities residue can break scroll for days after uninstall

**Symptom**: User installs Magic Utilities then uninstalls; scroll on Apple driver works for a few days, then stops.

**Root cause**: MU leaves orphan registry entries, custom bus enum, possibly stuck driver-store packages. Apple driver eventually loses scroll-init due to BTHPORT cache or LowerFilter chain corruption.

**Workaround if installing M12 after MU was uninstalled**: M12's pre-install procedure (per MOP) detects + cleans MU residue:
- `sc.exe delete MagicMouse` (if orphan service entry exists)
- `sc.exe delete MagicKeyboard` (same)
- `pnputil /enum-drivers | findstr -i magic` then `pnputil /delete-driver <oem>.inf /uninstall /force` for any leftover MU packages
- Registry cleanup: `reg delete HKLM\SOFTWARE\MagicUtilities /f`
- Custom bus enum cleanup: `reg delete "HKLM\SYSTEM\CurrentControlSet\Enum\{7D55502A-2C87-441F-9993-0761990E0C7A}" /f`

**Reference**: Upstream issue #2; Session 12 incident docs.

---

## Driver signature error on install ("Hash mismatch", "Driver is not signed")

**Symptom**: pnputil reports signature verification failure during install.

**Root causes (priority order)**:
1. testsigning is not enabled in BCD: `bcdedit /set testsigning on` then reboot
2. .inf file line endings were modified (CRLF -> LF or vice versa) -- common when downloading via git or copy-paste
3. The .cat file is missing or stale relative to the .sys

**Workarounds**:
1. Enable testsigning per BCD edit above (M12 ships test-signed in v1 -- production WHQL submission deferred)
2. Verify line endings: open .inf in Notepad++ or `file <inf>` should report CRLF
3. Re-download M12 release ZIP; do NOT extract via git clone (git mangles line endings unless `.gitattributes` enforced -- which we do for `driver/`)

**M12 v1 install procedure**: enables testsigning automatically as part of MOP pre-flight if not already on; warns user if reboot needed.

**Reference**: Upstream issue #1 (most-commented).

---

## Antivirus / EDR may flag M12 as suspicious

**Symptom**: Windows Defender, CrowdStrike, SentinelOne, or similar EDR flags M12.sys as a "potentially unwanted program" or kernel modification, blocks install or quarantines after install.

**Root cause**: Kernel filter drivers are a category that EDRs aggressively monitor -- by design, since malicious rootkits also live at kernel level. M12 is signed and benign, but cert provenance + signature characteristics may not match an EDR's allowlist.

**Workarounds (priority order)**:

1. **Whitelist M12.sys + INF in Defender / EDR**:
   - Open Windows Security -> Virus & threat protection -> Manage settings -> Add or remove exclusions
   - Add `C:\Windows\System32\drivers\M12.sys` (file)
   - Add `C:\Windows\System32\DriverStore\FileRepository\m12.inf_amd64_*\` (folder)
   - Restart device

2. **Verify signature**: `signtool verify /v /pa C:\Windows\System32\drivers\M12.sys` -- should show "Successfully verified" with trusted publisher

3. **For corporate-managed EDR**: contact IT to whitelist via central policy. Provide M12 source + cert thumbprint for verification.

**Why M12 is safe**:
- Open-source under MIT license -- code is auditable at https://github.com/ReviveBusiness/magic-mouse-tray
- No network code
- No persistence mechanisms beyond standard service registry
- Test-signed (v1) or attestation-signed (future v2) -- Microsoft trust chain
- Source code review encouraged before any organization deploys

**Reference**: General Windows kernel-driver / EDR interaction; not specific to upstream issues.
