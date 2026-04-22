# Magic Mouse Battery Tray

Free Windows tray app that shows Apple Magic Mouse battery percentage on Windows 11. No subscription required.

![Tray icon showing 83% battery](docs/screenshot-tray.png)

## The Problem

Apple Magic Mouse on Windows 11 has no native battery indicator. Magic Mouse Utilities — the only working solution — requires a paid subscription that breaks scroll entirely when the trial expires.

## Features

- Battery % in tray icon (color-coded: green → yellow → orange → red as battery drains)
- Tooltip shows device name, battery %, and time until next poll
- Adaptive polling: checks every 2h at >50%, tightening to 5m below 10%
- Low battery toast notification at your configured threshold (10/15/20/25%)
- Cascading alerts: second toast fires automatically at 10% critical if your threshold is higher
- Persistent warning window at 1% that stays visible until you plug in the Lightning cable
- Driver health detection: warns if the Apple scroll driver isn't installed
- Start with Windows toggle (no installer required — just a registry entry)
- Single .exe, no dependencies, no install friction

## Supported Mice

| Model | Bluetooth PID | Status |
|-------|--------------|--------|
| Magic Mouse 2024 (USB-C) | 0x0323 | ✅ Confirmed |
| Magic Mouse v1 (AA battery) | 0x030D | ✅ Confirmed |
| Magic Mouse v2 | 0x0269 | ⚠ Included, not tested (device not available) |

## Install

1. Download `MagicMouseTray.exe` from [Releases](../../releases)
2. Run it — no installer, no admin rights required
3. Tray icon appears immediately

**Requires**: Windows 10 1809+ (build 17763) or Windows 11, x64

## Scroll Not Working?

Scroll requires the Apple wireless mouse filter driver (`applewirelessmouse.sys`) to be installed **and bound** to your specific mouse model. The fix differs by model.

### Magic Mouse v1 / v2 (PID 030D, 0269)

Install the driver from [tealtadpole/MagicMouse2DriversWin11x64](https://github.com/tealtadpole/MagicMouse2DriversWin11x64). The tray app will show **⚠ Install Apple Driver** in the right-click menu if the driver is missing.

### Magic Mouse 2024 (USB-C, PID 0323)

The tealtadpole driver does not cover PID 0323 — the INF was written in 2019 and the 2024 model was never added. Even with the driver installed, scroll will not work until the patched INF is applied.

**Fix** (one-time, requires admin):

1. **Boot with Driver Signature Enforcement disabled** — Start → Power → hold Shift → Restart → Troubleshoot → Advanced Options → Startup Settings → Restart → press **F7**

2. **Run the fix script** in an elevated PowerShell:
   ```powershell
   .\sign-and-install.ps1
   ```
   The script: creates a self-signed code cert, generates and signs a catalog for the patched INF (adds PID 0323), enables test signing mode, and installs the driver package.

3. **Remove and re-pair the mouse** in Bluetooth Settings.

4. **Reboot normally** — test signing activates, driver persists.

**After confirming scroll works**, you can remove the test-signing watermark:
```powershell
bcdedit /set testsigning off
# then reboot
```
> Note: re-enabling test signing is required if you ever need to reinstall the driver.

## Right-Click Menu

| Item | What it does |
|------|-------------|
| Low Battery Threshold | Set alert level: 10 / 15 / 20 / 25% |
| Start with Windows | Toggle auto-start on login |
| Refresh Now | Force an immediate battery read |
| Test Notification | Send a test toast (debug) |
| ⚠ Install Apple Driver | Opens driver download (shown if driver missing) |
| ⚠ Driver not bound — scroll fix needed | Opens this README's scroll fix section (driver installed but not bound) |
| ⚠ Unknown mouse model — check for app update | Opens Releases page (future Apple mouse with unknown PID) |
| Quit | Exit the app |

## How Battery Reading Works

Uses Apple's proprietary HID Input Report `0x90` via direct Win32 P/Invoke (`HidD_GetInputReport`). Standard BLE Battery Service doesn't work for Apple devices on Windows — this is the same approach used by [WinMagicBattery](https://github.com/hank1101444/WinMagicBattery), confirmed working against the COL02 battery collection (COL01 is the pointer, held exclusively by Windows).

## Building from Source

Requires .NET 8 SDK (Windows).

```powershell
dotnet publish -c Release
# Output: bin\Release\net8.0-windows10.0.17763.0\win-x64\publish\MagicMouseTray.exe
```

## SmartScreen Warning

When you first run `MagicMouseTray.exe`, Windows may show "We can't verify who created this file." This is normal for unsigned open-source software — click **Run**.

If you downloaded the file and it shows the full SmartScreen block ("Windows protected your PC"), click **More info → Run anyway**. Alternatively, right-click the file → Properties → check **Unblock** → OK.

**For developers building from source on WSL**: Windows treats the WSL filesystem as a network path, which always triggers this dialog. Copy the built exe to a local Windows path (e.g. `C:\Temp\`) before running to avoid it.

## Diagnostics

Log file: `%APPDATA%\MagicMouseTray\debug.log`

Key log lines:
- `OK battery=83%` — successful read
- `OPEN_FAILED err=5` — COL01 skipped (normal — Windows holds this handle)
- `DRIVER_CHECK status=Ok/NotInstalled/NotBound/UnknownAppleMouse` — driver detection result
- `DRIVER_CHECK unknown_apple_pid=0xXXXX` — future/unknown Apple mouse PID detected
- `TOAST_SENT` — notification fired
- `CRITICAL_ALERT_SHOWN` — 1% persistent window shown

## License

MIT
