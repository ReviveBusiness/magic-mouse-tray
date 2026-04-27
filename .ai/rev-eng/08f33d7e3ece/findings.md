# Reverse Engineering — applewirelessmouse.sys

**SHA-256 (prefix):** `08f33d7e3ece`
**Size:** 78424 bytes
**Generated:** 2026-04-27 11:27:15

## PE Sections
```

/mnt/c/Windows/System32/drivers/applewirelessmouse.sys:     file format pei-x86-64

Sections:
Idx Name          Size      VMA               LMA               File off  Algn
  0 .text         0000744a  0000000140001000  0000000140001000  00000400  2**4
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
  1 NONPAGE       00001dcb  0000000140009000  0000000140009000  00007a00  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
  2 .rdata        00000f88  000000014000b000  000000014000b000  00009800  2**4
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  3 .data         00002e00  000000014000c000  000000014000c000  0000a800  2**4
                  CONTENTS, ALLOC, LOAD, DATA
  4 .pdata        000003f0  0000000140010000  0000000140010000  0000d600  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  5 INIT          000005f8  0000000140011000  0000000140011000  0000da00  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, CODE
  6 .rsrc         00000358  0000000140012000  0000000140012000  0000e000  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
  7 .reloc        00000038  0000000140013000  0000000140013000  0000e400  2**2
                  CONTENTS, ALLOC, LOAD, READONLY, DATA
```

## Empirical Signatures (byte patterns)

| Signature | Status | Hits |
|-----------|--------|------|
| `REPORT_ID_0x90` | ✓ FOUND | 4 |
| `PSM_HID_CONTROL_0x0011` | ✓ FOUND | 9 |
| `REPORT_ID_0x47` | ✓ FOUND | 2 |
| `SDP_ATTR_HID_DESCRIPTOR_LIST` | ✓ FOUND | 9 |
| `PSM_SDP_0x0001` | ✓ FOUND | 450 |
| `USAGE_GENERIC_DEVICE_06` | ✓ FOUND | 20 |
| `BRB_L2CA_OPEN_CHANNEL` | ✓ FOUND | 90 |
| `IOCTL_INTERNAL_BTH_SUBMIT_BRB` | ✓ FOUND | 5 |
| `IOCTL_HID_GET_REPORT_DESCRIPTOR` | ✗ absent | 0 |
| `BRB_L2CA_ACL_TRANSFER` | ✓ FOUND | 13 |
| `BATTERY_STRENGTH_USAGE` | ✓ FOUND | 4 |
| `USAGE_VENDOR_FF00` | ✗ absent | 0 |
| `USAGE_PAGE_GENERIC_DESKTOP` | ✓ FOUND | 13 |
| `HID_SERVICE_UUID_0x1124` | ✓ FOUND | 1 |
| `PSM_HID_INTERRUPT_0x0013` | ✓ FOUND | 28 |

## Notable Imports

- `PsCreateSystemThread` — background processing thread

## Strings of interest (filtered)
```
D:\BWA\B69DF622-5A99-0\AppleWirelessMouseWin-7635\srcroot\x64\Release\AppleWirelessMouse.pdb
```

## Descriptor Candidate
_no candidate descriptor blob found_
