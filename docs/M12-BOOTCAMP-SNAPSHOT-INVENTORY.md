# M12 BootCamp Snapshot Inventory

**Generated**: 2026-04-28
**Runtime**: ~12 minutes
**Mac model used**: iMac20,1 (first attempt succeeded)

## BootCamp ESD Summary

- **Product folder**: `BootCamp-001-04272`
- **Total size**: 1.5 GB (uncompressed)
- **Download size**: 836 MB (compressed)
- **Extraction date**: 2020-07-24 18:15:16 UTC (from ISO metadata)
- **Product distribution ID**: `001-04272` (Apple CDN reference)

## AppleWirelessMouse Driver Analysis

### Version Information

| Field | Value |
|-------|-------|
| DriverVer | **08/08/2019, 6.1.7700.0** |
| File path | `$WinPEDriver$/AppleWirelessMouse/` |
| Driver binary | `AppleWirelessMouse.sys` |
| Catalog | `applewirelessmouse.cat` |

### Hardware IDs Supported

The driver supports the following Bluetooth mouse device IDs:

1. **PID 0x030d** (VID 05ac) — Apple Wireless Mouse v1
2. **PID 0x0310** (VID 05ac) — Apple Wireless Mouse v2
3. **PID 0x0269** (VID 004c) — Older Apple mouse variant

### Version 3 (PID 0x0323) Coverage

**Result: NOT SUPPORTED**

The BootCamp-001-04272 ESD does NOT include support for Magic Mouse 3 (PID 0x0323). The driver was last updated 08/08/2019, over 6 years before Magic Mouse 3 was released.

### Comparison vs Rain9333 Reference

| Attribute | BootCamp-001-04272 | Rain9333 Zip | Verdict |
|-----------|---|---|---|
| DriverVer date | 08/08/2019 | 04/21/2026 | **Older by 6.8 years** |
| DriverVer version | 6.1.7700.0 | 6.2.0.0 | **Older (6.1 vs 6.2)** |
| v3 support (0x0323) | NO | YES | **Rain9333 is newer** |

**Verdict: BootCamp-001-04272 is significantly OLDER than Rain9333.**

---

## Full Apple Driver Bundle

**Total Apple drivers in ESD**: 21 .inf files across two locations:

### WinPE Driver Folder (`$WinPEDriver$/`)

| Driver | DriverVer | Notes |
|--------|-----------|-------|
| AppleAudio | 05/28/2020, 6.1.8000.3 | Multiple audio codec variants |
| AppleAudio_188B106B | (Codec-specific, no explicit DriverVer) | Cirrus codec |
| AppleAudio_188C106B | (Codec-specific, no explicit DriverVer) | Cirrus codec |
| AppleDFR | 11/14/2019, 6.1.7800.1 | Function Row display |
| AppleMultiTouchTrackPad | 11/07/2019, 6.1.7800.0 | Standard trackpad |
| AppleMultiTouchTrackPadPro | 01/08/2020, 6.1.7800.2 | Pro trackpad |
| AppleSSD | (No DriverVer found) | SSD/NVMe driver |
| AppleUSBVHCI | 05/04/2020, 6.1.7800.9 | USB host controller |
| AppleWirelessMouse | 08/08/2019, 6.1.7700.0 | **v1 & v2 only, NOT v3** |
| AppleWirelessTrackpad | 06/21/2018, 6.1.7000.0 | Wireless trackpad |

### BootCamp Driver Folder (`BootCamp/Drivers/Apple/`)

| Driver | DriverVer | Notes |
|--------|-----------|-------|
| AppleCamera | 09/30/2016, 6.1.6500.0 | FaceTime/Thunderbolt camera |
| AppleDisplayNullDriver | 10/01/2019, 6.1.7700.0 | Display configuration |
| AppleHAL | 02/25/2019, 6.1.7500.0 | Hardware abstraction layer |
| AppleKeyManager | 06/20/2018, 6.1.7001.0 | Key management service |
| AppleKeyboard | 11/11/2019, 6.1.7800.0 | Magic Keyboard driver |
| AppleKeyboardInternalUSB | 03/09/2020, 6.1.8000.1 | Internal wired keyboard |
| AppleKeyboardMagic2 | 11/11/2019, 6.1.7800.0 | Magic Keyboard 2 driver |
| AppleNullDriver | 08/19/2019, 6.1.7700.0 | Null/stub driver |
| AppleProDisplayXDRUSBCompositeDevice | 08/22/2019, 6.1.7600.0 | Pro Display XDR USB device |
| AppleThunderboltNullDriver | 01/15/2020, 6.1.7800.0 | Thunderbolt stub |

### Other Drivers

- **Asix** (AppleUSBEthernet.inf) | 02/01/2008, 3.10.3.10 | USB Ethernet

---

## Key Findings

1. **BootCamp-001-04272 is from 2020** (July 24, 2020 ISO timestamp). This is the ESD for iMac (20-inch, 2019) models, released well before Magic Mouse 3 (2024).

2. **No Magic Mouse v3 support** — The AppleWirelessMouse driver only recognizes PIDs 0x030d, 0x0310, and 0x0269. PID 0x0323 is absent.

3. **Rain9333 is the newer reference** — The Rain9333 zip contains drivers dated 2026-04-21 with version 6.2.x, vs this 2019-2020 vintage (version 6.1.x).

4. **What we DON'T have in BootCamp-001-04272**:
   - Magic Mouse v3 driver (PID 0x0323)
   - Any post-2020 driver updates
   - Support for newer iMac Pro models (iMac21,x and later)

5. **What we DO have**:
   - Complete WinPE boot drivers
   - All standard input device drivers (keyboard, trackpad, mouse v1/v2)
   - Audio, USB, display, camera, Thunderbolt support
   - A stable, tested ESD baseline from mid-2020

---

## Recommendation

**Use Rain9333 as primary reference** for Magic Mouse v3 / M12 work. The BootCamp-001-04272 ESD is suitable for reference/comparison but does not provide the v3 driver needed for the tray project.

For new driver development targeting v3, compare against Rain9333's infrastructure and driver structure, then update as needed per M12 requirements.
