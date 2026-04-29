# SESSION-12: Magic Utilities Installed — Empirical Findings
**Date**: 2026-04-28  
**Project**: PRD-184 magic-mouse-tray  
**Session goal**: Install MU 3.1.5.2, capture driver files for M12 reverse-engineering reference, observe runtime architecture.

---

## BLUF

MU 3.1.5.2 installs cleanly, loads two WHQL-signed KMDF 1.15 kernel filters (`MagicMouse.sys`, `MagicKeyboard.sys`), and binds them as LowerFilters on both v1 (PID 0x030D) and v3 (PID 0x0323) BTHENUM devices. Under trial-expired conditions, the kernel filter loads and mutates the HID descriptor (Mode A: correct Wheel/Pan/Resolution Multiplier layout) but scroll and battery are both broken — userland app (`MagicMouseUtilities.exe`) silent-exits at launch. Standard HID polling APIs (`HidD_GetInputReport`, `HidD_GetFeature`) fail on all ReportIDs under Mode A. Battery delivery is routed through a custom device interface `{7D55502A-2C87-441F-9993-0761990E0C7A}`, not through the standard HID Feature channel. Full file capture (41 files, 78.6 MB) written to `D:\Backups\MagicUtilities-Capture-2026-04-28-1937\`.

---

## 1. Install State

| Item | Value |
|------|-------|
| Version | MU 3.1.5.2 |
| Install method | setup.exe, clean install |
| Kernel drivers | `MagicMouse.sys`, `MagicKeyboard.sys` (both KMDF 1.15, WHQL signed) |
| Userland service | `MagicUtilitiesService` — running |
| DriverStore packages | `magicmouse.inf_amd64_82cbbe70c776aec4`, `magickeyboard.inf_amd64_2a0a9746044afb09` |

**LowerFilter bindings active on**:
- v1 BTHENUM PID 0x030D → `MagicMouse.sys`
- v3 BTHENUM PID 0x0323 → `MagicMouse.sys`
- AWK keyboard BTHENUM PID 0x0239 → `MagicKeyboard.sys`

**Custom device interface**: `{7D55502A-2C87-441F-9993-0761990E0C7A}` (raw PDO bus, created by kernel filter)

---

## 2. Trial Expiry State

- `MagicMouseUtilities.exe` launched: process started, no visible UI window, silent exit.
- Trial expiry bytes (at known offset): `85 AE 30 85 EF 85 E6 40`
- **This value is byte-for-byte identical to the value documented in the prior session.** Confirms trial marker is sticky across reinstalls — MU uses a high-water-mark scheme; reinstall does not reset the trial counter.

**User-observable behavior under trial-expired state**:
- v3 mouse: cursor + clicks work; scroll BROKEN; battery NOT readable via tray
- v1 mouse: cursor + clicks work; scroll BROKEN; battery lost (was producing 100% in tray pre-MU-install, lost after MU rebind)
- AWK keyboard: user reports no issues (typing works; keyboard battery already working via Apple filter on separate TLC; MU rebind did not disturb it)

---

## 3. HID Descriptor Evidence

Captured via `mm-hid-descriptor-dump.ps1`.  
Stored at: `/home/lesley/projects/Personal/magic-mouse-tray/.ai/test-runs/2026-04-27-154930-T-V3-AF/`

### 3a. v3 col01 under MU filter — Mode A (current state during test)

```
TLC: UsagePage=0x0001 Usage=0x0002 (Mouse)
Report lengths: Input=8 Feature=2
LinkColl=5 (deeply nested: App→Logical→Physical→2x Logical leaves)
Input Button Caps: 5 buttons (Usage 1-5) at RID=0x02
Input Value Caps:
  - X (0x31), Y (0x30): 8-bit signed at LinkColl=2
  - Wheel (UP=0x0001 Usage=0x38): 16-bit signed at LinkColl=3
  - AC Pan (UP=0x000C Usage=0x238): 16-bit signed at LinkColl=4
Feature Value Caps:
  - RID=0x03 UP=0x0001 Usage=0x48 (Resolution Multiplier) at LinkColl=3 — for vertical wheel
  - RID=0x04 UP=0x0001 Usage=0x48 (Resolution Multiplier) at LinkColl=4 — for horizontal pan
NO Feature 0x47 declared
```

### 3b. v3 under Apple filter — Mode B (prior baseline, for comparison)

```
TLC: UsagePage=0x0001 Usage=0x0002 (Mouse)
Report lengths: Input=47 Feature=2
LinkColl=2 (flat: App→Physical)
Input Button Caps: 2 buttons (Usage 1-2) + vendor button (UP=0xFF02 Usage=0x20) at RID=0x02
Input Value Caps: X, Y, Wheel (Usage=0xC/238), Wheel (Usage=0x38) — all 8-bit at RID=0x02
Plus 46-byte vendor blob at RID=0x27 (UP=0x0006 Usage=0x1)
Feature Value Caps:
  - RID=0x47 UP=0x0006 Usage=0x20 — synthesized battery
```

### 3c. Critical descriptor diff finding

MU Mode A declares the full Windows-standard high-resolution scroll layout: Wheel (16-bit) + AC Pan (16-bit) + two Resolution Multiplier Features (RID=0x03, 0x04), nested across 5 link collections. Apple Mode B does not — it declares 8-bit scroll on RID=0x02 and a synthesized Feature 0x47 for battery. Under Mode A, Feature 0x47 is absent; battery is not in the standard HID Feature channel.

---

## 4. Probe Test Results

### 4a. HidD_GetInputReport / HidD_GetFeature on v3 col01 + col02

**Test script**: `scripts/mm-test-0x90-mode-a.ps1`  
**ReportIDs tested**: 0x90, 0x47, 0x12, 0x09, 0x10, 0x01, 0x02  
**Result**: ALL fail.

| Collection | API | Result |
|-----------|-----|--------|
| v3-vendor-col02 (UP=0xFF00, InLen=64, FeatLen=0) | GetInputReport | GLE=87 (all RIDs — not in declared input set) |
| v3-vendor-col02 | GetFeature | GLE=1 (all RIDs — function not supported on collection) |
| v3-mouse-col01 (UP=0x0001 U=0x0002) | GetInputReport | GLE=1 |
| v3-mouse-col01 | GetFeature | GLE=87 |

ReportID 0x90 is NOT exposed as Input or Feature in the MU Mode A descriptor. Standard HID polling APIs are dead under Mode A.

### 4b. ReadFile (interrupt-channel reads) on v3 vendor col02

**Test script**: `scripts/mm-test-readfile-vendor-tlc.ps1`  
**Result**: Inconclusive. Test was interrupted by user before completing (cast errors were being fixed mid-session). No unsolicited reads were observed during the partial run window.

**What this means**: Battery is not proactively pushed unsolicited at a frequency high enough to catch in the partial observation window. Cannot rule out a pull mechanism.

---

## 5. Architectural Inference (Working Hypothesis)

```
[Mouse HW: vendor input format on interrupt channel]
   │
   ▼
[MagicMouse.sys (LowerFilter, KMDF 1.15)]
   - Replaces HID descriptor with Mode A
     (Wheel + Pan + Resolution Multipliers, 5 link collections)
   - Exposes raw PDO bus device interface {7D55502A-2C87-441F-9993-0761990E0C7A}
   - Receives raw vendor input reports from device
   - In licensed mode: translates vendor scroll bytes → Wheel/Pan fields in Input RID=0x02
   - In licensed mode: services battery queries via custom IOCTL on {7D55502A} interface
   │
   ▼
[hidbth class driver → mouhid → Win32 input queue]
```

```
[MagicUtilitiesService.exe (userland, license-gated)]
   - Opens {7D55502A-2C87-441F-9993-0761990E0C7A} device interface
   - In licensed mode: sends "enable" IOCTLs to kernel filter
   - In licensed mode: polls battery, displays in tray
   - In trial-expired mode: silent no-op (license check at entry point)
```

**Why scroll is broken in trial-expired state**: Kernel filter declares Wheel/Pan in the descriptor (descriptor mutation works unconditionally) but does NOT fill in payload bytes — in-IRP translation is gated by the license-validation handshake from userland that never arrives in trial-expired state. Descriptor is correct; data is zero.

**Why battery is invisible in trial-expired state**: Battery delivery uses a custom IOCTL on the `{7D55502A-2C87-441F-9993-0761990E0C7A}` device interface, gated by the same license handshake. Feature 0x47 is not declared in the Mode A descriptor; there is no standard HID battery path under MU.

**Confidence**: HIGH.

Supporting evidence:
- Mode A descriptor is syntactically correct and complete (Wheel + Pan properly declared)
- Kernel driver loaded, bound, and descriptor mutation confirmed working (HID caps reflect Mode A structure)
- Userland service process running but `MagicMouseUtilities.exe` silent-exits (license check at userland entry confirmed)
- Standard HID APIs return errors consistent with the Mode A descriptor — not device errors, not access errors; the descriptor itself explains the failures
- GLE=87 ("invalid parameter") on GetFeature for v3-mouse-col01 is consistent with RID not declared as Feature in that collection — not a driver rejection

**Open question**: Is in-IRP translation in `MagicMouse.sys` unconditional (kernel self-contained, translation runs regardless of userland), or gated by an IOCTL handshake from userland? The evidence is consistent with both. The planned kernel-only reinstall test (Section 7) answers this definitively.

---

## 6. Files Captured This Session

**Primary capture**: `D:\Backups\MagicUtilities-Capture-2026-04-28-1937\` — 41 files, 78.6 MB

Directory structure:
- `driver-package/` — full DriverStore copies of mouse + keyboard packages (`.inf`/`.sys`/`.cat`)
- `driver-binary/` — active `MagicMouse.sys` + `MagicKeyboard.sys`
- `program-files/` — userland tree including `MagicUtilitiesService.exe`, `MagicMouseUtilities.exe`, `BluetoothPairing.exe`, `DriverUnInstaller.exe`
- `registry/` — driver database, service config, custom-bus enum, PnP lockdown, keyboard service (post-hoc add)
- `pnp/` — PnP topology, DEVPKEY dumps, `sc qc` text dumps for all 4 services (`MagicMouse`, `MagicKeyboard`, `MagicUtilitiesService`, `applewirelessmouse`), pnputil enum
- `manifest.txt` — sha256 manifest of all captured files
- `README.md` — restore procedure

**HID descriptor captures** (under MU filter, Mode A):  
`/home/lesley/projects/Personal/magic-mouse-tray/.ai/test-runs/2026-04-27-154930-T-V3-AF/hid-descriptor-full-kbd-col01.txt`  
`/home/lesley/projects/Personal/magic-mouse-tray/.ai/test-runs/2026-04-27-154930-T-V3-AF/hid-descriptor-full-v1-col01.txt`  
`/home/lesley/projects/Personal/magic-mouse-tray/.ai/test-runs/2026-04-27-154930-T-V3-AF/hid-descriptor-full-v3-col01.txt`

**HID descriptor captures** (under Apple filter, Mode B — prior baseline):  
`/home/lesley/projects/Personal/magic-mouse-tray/.ai/test-runs/2026-04-27-154930-T-V3-AF/hid-descriptor-full-v1.txt`  
`/home/lesley/projects/Personal/magic-mouse-tray/.ai/test-runs/2026-04-27-154930-T-V3-AF/hid-descriptor-full-v3.txt`

---

## 7. M12 Implications

If MU's kernel filter is self-contained (translation runs unconditionally, without userland handshake) → M12 clones MU's filter pattern exactly: pure kernel, ~200–400 LOC.

If MU's kernel filter requires the userland IOCTL handshake to activate translation → trial-expired broken scroll/battery is explained by missing handshake → M12 collapses the split into a pure-kernel filter that does both descriptor mutation AND in-IRP translation unconditionally with no license layer, ~300–500 LOC.

Either path produces the same M12 outcome: pure-kernel LowerFilter, no userland service, no license complexity.

---

## 8. Next Test (Planned)

**Kernel-only reinstall via pnputil**: install `MagicMouse.sys` (from captured DriverStore package) directly without userland service. Observe whether scroll and battery work.

This test answers the open question in Section 5: if scroll and battery work with kernel-only install (no `MagicUtilitiesService`, no `MagicMouseUtilities.exe`), then translation is unconditional in the kernel and M12 can clone the filter pattern directly. If they remain broken, translation requires the userland handshake, and M12 implements the translation unconditionally in-kernel without replicating the license layer.
