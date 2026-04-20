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

If your Magic Mouse connects but scroll doesn't work, you need the Apple wireless mouse driver. Right-click the tray icon and choose **⚠ Install Apple Driver** — it will open the correct driver page.

The driver you need is from [tealtadpole/MagicMouse2DriversWin11x64](https://github.com/tealtadpole/MagicMouse2DriversWin11x64).

## Right-Click Menu

| Item | What it does |
|------|-------------|
| Low Battery Threshold | Set alert level: 10 / 15 / 20 / 25% |
| Start with Windows | Toggle auto-start on login |
| Refresh Now | Force an immediate battery read |
| Test Notification | Send a test toast (debug) |
| ⚠ Install Apple Driver | Opens driver download (shown only if driver missing) |
| Quit | Exit the app |

## How Battery Reading Works

Uses Apple's proprietary HID Input Report `0x90` via direct Win32 P/Invoke (`HidD_GetInputReport`). Standard BLE Battery Service doesn't work for Apple devices on Windows — this is the same approach used by [WinMagicBattery](https://github.com/hank1101444/WinMagicBattery), confirmed working against the COL02 battery collection (COL01 is the pointer, held exclusively by Windows).

## Building from Source

Requires .NET 8 SDK (Windows).

```powershell
dotnet publish -c Release
# Output: bin\Release\net8.0-windows10.0.17763.0\win-x64\publish\MagicMouseTray.exe
```

## Diagnostics

Log file: `%APPDATA%\MagicMouseTray\debug.log`

Key log lines:
- `OK battery=83%` — successful read
- `OPEN_FAILED err=5` — COL01 skipped (normal — Windows holds this handle)
- `DRIVER_CHECK installed=True/False` — driver detection result
- `TOAST_SENT` — notification fired
- `CRITICAL_ALERT_SHOWN` — 1% persistent window shown

## License

MIT
