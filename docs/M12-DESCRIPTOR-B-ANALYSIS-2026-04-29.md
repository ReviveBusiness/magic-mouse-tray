# M12 Descriptor-B Analysis — Apple Magic Mouse 2024 HID Descriptor

**Date**: 2026-04-29  
**Source A**: Live registry `HKLM:\...\D0C050CC8C4D\CachedServices\'00010000'` (351 bytes)  
**Source B**: `/mnt/d/Backups/AppleWirelessMouse-RECOVERY/AppleWirelessMouse.sys` (PE32+, v6.2.0.0)  
**Current code**: `driver/HidDescriptor.c` on branch `ai/m12-script-tests`

---

## 1. Hex Dump — SDP Cached Descriptor (135 bytes at record offset 176)

SDP attribute 0x0206 (HIDDescriptorList) header at record offset 160:
```
09 02 06 35 8D 35 8B 08 22 25 87
```
Size byte `0x87` = 135. Descriptor body:

```
Offset 000: 05 01 09 02 A1 01 85 12 05 09 19 01 29 02 15 00
Offset 016: 25 01 95 02 75 01 81 02 95 01 75 06 81 03 05 01
Offset 032: 09 01 A1 00 16 01 F8 26 FF 07 36 01 FB 46 FF 04
Offset 048: 65 13 55 0D 09 30 09 31 75 10 95 02 81 06 75 08
Offset 064: 95 02 81 01 C0 06 02 FF 09 55 85 55 15 00 26 FF
Offset 080: 00 75 08 95 40 B1 A2 C0 06 00 FF 09 14 A1 01 85
Offset 096: 90 05 84 75 01 95 03 15 00 25 01 09 61 05 85 09
Offset 112: 44 09 46 81 02 95 05 81 01 75 08 95 01 15 00 26
Offset 128: FF 00 09 65 81 02 C0
```

---

## 2. HID Descriptor Parser Walkthrough — SDP Cached Descriptor

```
[  0] 05 01              Usage Page (GenericDesktop)
[  2] 09 02              Usage (Mouse)
[  4] A1 01              Collection (Application)
[  6] 85 12                *** Report ID (0x12 = 18) ***   <-- BT transport RID
[  8] 05 09                Usage Page (Buttons)
[ 10] 19 01                Usage Minimum (Button 1)
[ 12] 29 02                Usage Maximum (Button 2)         <-- 2 buttons only
[ 14] 15 00                Logical Minimum (0)
[ 16] 25 01                Logical Maximum (1)
[ 18] 95 02                Report Count (2)
[ 20] 75 01                Report Size (1)
[ 22] 81 02                Input (Data,Var,Abs) [2 bits]
[ 24] 95 01                Report Count (1)
[ 26] 75 06                Report Size (6)
[ 28] 81 03                Input (Const) [6-bit pad]
[ 30] 05 01                Usage Page (GenericDesktop)
[ 32] 09 01                Usage (Pointer)
[ 34] A1 00                Collection (Physical)
[ 36] 16 01 F8               Logical Minimum (-2047)       <-- INT16, not INT8
[ 39] 26 FF 07               Logical Maximum (2047)
[ 42] 36 01 FB               Physical Minimum (-1279)      <-- physical units: mm × 0.001
[ 45] 46 FF 04               Physical Maximum (1279)
[ 48] 65 13                  Unit (SI Linear: cm)
[ 50] 55 0D                  Unit Exponent (-3)            <-- 0.001 scale
[ 52] 09 30                  Usage (X)
[ 54] 09 31                  Usage (Y)
[ 56] 75 10                  Report Size (16)
[ 58] 95 02                  Report Count (2)
[ 60] 81 06                  Input (Data,Var,Rel) [32 bits = 4 bytes]  <-- X+Y as INT16
[ 62] 75 08                  Report Size (8)
[ 64] 95 02                  Report Count (2)
[ 66] 81 01                  Input (Const) [16-bit pad]   <-- NO wheel, NO AC Pan
[ 68] C0                   End Collection (Physical)
[ 69] 06 02 FF             Usage Page (Vendor 0xFF02)      <-- vendor control
[ 72] 09 55                Usage (0x55)
[ 74] 85 55                  *** Report ID (0x55 = 85) ***
[ 76–86]                     Feature(Data,Var) 64 bytes   <-- touch surface config
[ 87] C0                   End Collection (Application/Mouse)
[ 88] 06 00 FF             Usage Page (0xFF00)
[ 91] 09 14                Usage (0x14)
[ 93] A1 01                Collection (Application)        <-- battery TLC
[ 95] 85 90                  *** Report ID (0x90 = 144) ***
[ 97] 05 84                  Usage Page (PowerDevice)
[ 99] 75 01                  Report Size (1)
[101] 95 03                  Report Count (3)
[103] 15 00                  Logical Minimum (0)
[105] 25 01                  Logical Maximum (1)
[107] 09 61                  Usage (PresentStatus 0x61)    <-- power flags
[109] 05 85                  Usage Page (BatterySystem)
[111] 09 44                  Usage (RemainingCapacity 0x44)
[113] 09 46                  Usage (RunTimeToEmpty 0x46)
[115] 81 02                  Input (Data,Var,Abs) [3 bits: status flags]
[117] 95 05                  Report Count (5)
[119] 81 01                  Input (Const) [5-bit pad]     <-- = 1 byte total flags
[121] 75 08                  Report Size (8)
[123] 95 01                  Report Count (1)
[125] 15 00                  Logical Minimum (0)
[127] 26 FF 00               Logical Maximum (255)
[130] 09 65                  Usage (AbsoluteStateOfCharge 0x65)  <-- battery %
[132] 81 02                  Input (Data,Var,Abs) [8 bits]
[134] C0                   End Collection
```

### TLCs in SDP descriptor

| TLC | Usage Page/Usage | RID | Input bytes | Layout |
|-----|-----------------|-----|-------------|--------|
| Mouse | GenDesktop/0x02 | 0x12 | 7 | [0x12, btn_byte, X_lo, X_hi, Y_lo, Y_hi, pad, pad] |
| Vendor ctrl | (within Mouse) | 0x55 | 0 (feature only) | 64-byte feature |
| Battery | 0xFF00/0x14 | 0x90 | 2 | [0x90, flags_byte, battery_%] |

---

## 3. Total Declared Report Sizes

| RID | Declared input bits | Data bytes | Full report (with RID prefix) |
|-----|--------------------:|:----------:|------------------------------|
| 0x12 (18) Mouse | 56 | 7 | `[0x12, b0, b1, b2, b3, b4, b5, b6]` |
| 0x55 (85) Vendor | 0 | 0 (feature) | N/A input |
| 0x90 (144) Battery | 16 | 2 | `[0x90, flags, battery_%]` |

**RID=0x12 layout**: `[0x12, buttons_byte, X_lo, X_hi, Y_lo, Y_hi, 0x00, 0x00]`  
— 2 buttons in bits 0–1 of buttons_byte, bits 2–7 pad; X/Y as signed INT16; 2 trailing padding bytes.

**Battery buf[2]**: confirmed = battery %. `HidD_GetInputReport` on RID=0x90 returns `[0x90, flags, %]`.

---

## 4. Apple Binary Descriptor (applewirelessmouse.sys @ offset 0xA850, 116 bytes)

This is the descriptor Apple uses for the **USB/processed** path (not the raw BT SDP descriptor):

```
[  0] 05 01 09 02 A1 01     Usage Page GenDesktop / Usage Mouse / Collection Application
[  6] 85 02                   *** Report ID (0x02) ***
[  8] 05 09 19 01 29 02       Buttons 1–2 (2 buttons)
[14–28]                       2-bit data + 5-bit pad + 1-bit vendor pad = 8 bits (1 byte)
[30] 06 02 FF 09 20           Vendor page 0xFF02, usage 0x20
[35] 95 01 75 01 81 03        1-bit constant Input (padding)
[41] 05 01 09 01 A1 00        Usage GenDesktop/Pointer, Collection Physical
[47] 15 81 25 7F              Logical -127..127
[51] 09 30 09 31              X, Y
[55] 75 08 95 02 81 06        2 × INT8 relative [16 bits]
[61] 05 0C 0A 38 02           Usage Page Consumer, Usage AC Pan (0x0238)  <-- IN SAME TLC
[66] 75 08 95 01 81 06        1 × INT8 relative [8 bits]
[72] 05 01 09 38              Usage GenDesktop/Wheel
[76] 75 08 95 01 81 06        1 × INT8 relative [8 bits]
[82] C0                       End Physical
     (vendor feature RID=0x47 and data RID=0x27 follow)
```

**RID=0x02 report**: `[0x02, buttons_byte, X, Y, ACPan, Wheel]` = 5 data bytes.

---

## 5. Cross-Reference and Comparison to g_HidDescriptor[]

### Binary descriptor vs SDP cached

The binary at 0xA850 (RID=0x02) is **not** the SDP descriptor (RID=0x12). They are different descriptors for different transport phases:
- SDP (RID=0x12): what the BT stack negotiates at pairing. Raw INT16 axes, no scroll.
- Binary (RID=0x02): what the driver presents to HidClass post-translation. INT8 axes, with AC Pan+Wheel.

They do **not** match byte-for-byte. Apple's driver translates RID=0x12 reports into RID=0x02 reports before exposing them up the HID stack. Our driver does the same thing at the kernel level.

### Our g_HidDescriptor[] vs Apple binary descriptor

| Feature | Apple binary (0xA850) | Our g_HidDescriptor[] |
|---------|----------------------|----------------------|
| Mouse TLC RID | 0x02 | 0x01 |
| Buttons | 2 | 3 |
| X/Y | INT8 in Physical subcollection | INT8 in Physical subcollection |
| AC Pan (0x0238) | **Inside Mouse TLC** (same RID) | **Separate Consumer TLC** (RID=0x02) |
| Wheel (0x38) | Inside Mouse TLC | Inside Mouse TLC |
| Report layout | [RID, btn, X, Y, Pan, Wheel] | TLC1:[0x01,btn,X,Y,Whl] TLC2:[0x02,Pan] |

### Critical architectural difference

Apple puts AC Pan **inside** the Mouse GenDesktop/0x02 TLC in the binary descriptor. Our code puts AC Pan in a separate Consumer TLC.

This matters because: `mouhid.sys` opens the Mouse TLC exclusively. If AC Pan is inside the Mouse TLC, `mouhid.sys` reads the whole report including Pan. Our separate Consumer TLC approach is architecturally sound — Consumer TLCs are opened shared — but the **report byte lengths differ**:

- Apple binary RID=0x02: 5 data bytes (btn + X + Y + Pan + Wheel)
- Our TLC1 RID=0x01: 4 data bytes (btn + X + Y + Wheel), TLC2 RID=0x02: 1 data byte (Pan)

If `TranslateTouch()` currently emits 5-byte reports (mimicking Apple's layout) but our descriptor declares only 4-byte reports for RID=0x01, HidClass will reject the report with a size mismatch.

---

## Single Most Actionable Change

**Add Wheel to TLC1 and collapse AC Pan into TLC1 (matching Apple binary)**, OR verify that `TranslateTouch()` emits reports exactly matching the current declared layout.

The concrete fix depends on which side is wrong:

**If `TranslateTouch()` is emitting `[0x01, btn, X, Y, Wheel]` (4 bytes)**: the descriptor TLC1 is correct. The issue is elsewhere.

**If HidClass is dropping reports**: the most likely cause is that our TLC1 (RID=0x01) reports are being sized to 4 bytes but something upstream sends 5-byte reports, or vice versa.

**The single change to make**:

Change TLC1's Report ID from `0x01` to `0x02` to match Apple's binary descriptor RID. This is **not** about AC Pan placement — it's about whether the kernel's HID input mapper (`mouhid.sys`) is binding to the right RID. Apple's processed descriptor uses RID=0x02 for the Mouse TLC. If `mouhid.sys` is looking for a specific RID when choosing which TLC to bind, matching Apple's RID=0x02 for the Mouse TLC is the empirically correct choice.

In `HidDescriptor.c` line 43, change:
```c
0x85, 0x01,        //   Report ID (1)
```
to:
```c
0x85, 0x02,        //   Report ID (2)
```

And update TLC2 (Consumer/AC Pan) to a different RID that doesn't collide — use RID=0x03.

**Rationale**: Apple's applewirelessmouse.sys (the working driver) declares its Mouse TLC as RID=0x02 in the descriptor it presents to HidClass. Our driver uses RID=0x01. If mouhid.sys applies any RID-specific matching heuristic, mismatching here would cause it to fail to bind the TLC or to size reports incorrectly. This is the one structural RID difference between our working-Apple-path and our path.

If this is already ruled out, the next candidate is collapsing AC Pan into TLC1 (matching Apple's binary layout exactly).

---

## Files referenced

- Registry: `HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\D0C050CC8C4D\CachedServices\00010000` (live, 351 bytes)
- Binary: `/mnt/d/Backups/AppleWirelessMouse-RECOVERY/AppleWirelessMouse.sys` offset `0xA850`, 116 bytes
- Our descriptor: `/home/lesley/projects/Personal/magic-mouse-tray/driver/HidDescriptor.c`
