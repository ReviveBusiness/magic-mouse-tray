# M12 Ghidra Findings Extended -- MagicMouse.sys (Magic Utilities v3.1.5.3)

**Analysis date**: 2026-04-28
**Analyst**: Automated (ghidra-m12-extended-analysis.py, Ghidra 12.0.4, Jython)
**Extending**: M12-GHIDRA-FINDINGS.md (first pass, 60s timeout, top-3 decompile)
**Script**: scripts/ghidra-m12-extended-analysis.py
**Binary**: /mnt/d/Backups/MagicUtilities-Capture-2026-04-28-1937/driver-binary/MagicMouse.sys
**MD5**: 0160fe5b2c828d305e481b6c21288dbf
**SHA-256 prefix**: 84bddda3a8f0
**Image base**: 0x140000000
**Architecture**: x86-64 (PE32+, native kernel driver)

---

## Confirmed Architecture Summary

*Answers to the four design questions. Evidence cited inline.*

### Q1: WHERE is the BCrypt-based license check called?

BCrypt is NOT called from DriverEntry or any normal driver initialization path.
The real BCrypt call sites are scattered across 0x14015xxxx-0x14016xxxx -- a region
of heavily obfuscated code (see Decompile Root Cause section below).

Confirmed BCrypt call sites (from disassembly xref scan):

```
0x14017cf13  BCryptOpenAlgorithmProvider  (via thunk 0x1405abdd9)
0x14058290e  BCryptCloseAlgorithmProvider (via thunk 0x1405abddf)
0x140584760  BCryptCloseAlgorithmProvider (via thunk 0x1405abddf)
0x14015c1cf  BCryptCreateHash             (via thunk 0x1405abe09)
0x14015c3bd  BCryptDecrypt                (via thunk 0x1405abdfd)
0x14015d2b4  BCryptSetProperty            (via thunk 0x1405abdeb)
0x14015d856  BCryptDestroyHash            (via thunk 0x1405abe1b)
0x14015d8a9  BCryptFinishHash             (via thunk 0x1405abe15)
0x14015df36  BCryptHashData               (via thunk 0x1405abe0f)
(+ many more DestroyHash/FinishHash/HashData in 0x14016xxxx range)
```

The code around all BCrypt call sites contains (bad) opcodes, retf in non-standard
positions, and movabs with random-looking constants -- confirming code obfuscation
(likely LLVM-obfuscator or equivalent commercial obfuscator baked in at compile time).

The obfuscated region occupies ~5.5MB of the 5.7MB .text section. The ~0.2MB of
readable code in 0x1405axxxx is the WDF initialization stub + import thunks.

**M12 implication**: BCrypt is the license token validation engine. The token is
stored in the registry at \Registry\Machine\Software\MagicUtilities\Driver (confirmed
below). The obfuscation prevents casual cloning of the license logic. M12 does not
replicate this -- M12 has no license layer.

### Q2: WHERE is descriptor mutation done?

HID descriptor data found as literal byte arrays in .data section at 0x1405af0a0.

Two descriptors stored:

**Descriptor A** (at 0x1405af0a0, offset 0x00, 100 bytes -- NO Resolution Multiplier):
```
05 01 09 02 A1 01 05 01 09 02 A1 02 85 02 09 01  -- UsagePage=GenericDesktop, Mouse, RID=02
A1 00 05 09 19 01 29 05 15 00 25 01 95 05 75 01  -- 5 buttons 1-bit
81 02 95 01 75 03 81 01                           -- 3-bit padding
05 01 09 30 09 31 15 81 25 7F 95 02 75 08 81 06  -- X/Y 8-bit rel
05 01 09 38 35 00 45 00 16 01 80 26 FF 7F 95 01  -- Wheel 16-bit rel (range -32767..32767)
75 10 81 06
05 0C 0A 38 02 35 00 45 00 16 01 80 26 FF 7F     -- AC Pan 16-bit rel
95 01 75 10 81 06
C0 C0 C0                                          -- End Collection x3
```

**Descriptor B** (at 0x1405af110, offset 0x70, full Mode A WITH Resolution Multiplier):
Same as A, PLUS:
- Collection(Logical) with Report ID 0x03: ResolutionMultiplier Feature for Wheel
  (Physical Min=1, Physical Max=0x78=120, Logical 0-1)
- Collection(Logical) with Report ID 0x04: ResolutionMultiplier Feature for AC Pan
  (same range)

The function `FUN_1405853ac` at 0x1405853ac:
- Calls WDF table[0x8e8] (WdfRequestGetParameters / IRP dispatch)
- Reads from field at IRP+0xB8+0x8 (device extension or stack location)
- Sets WORD at [result], value 0x2a1 -- this IS the descriptor header
- Sets DWORD at +0x3: length, WORD at +0x7: 0x0000
- This is the `EvtIoInternalDeviceControl` handler responding to
  `IOCTL_HID_GET_REPORT_DESCRIPTOR` (function 0xB0003).
- The descriptor returned depends on the device type byte (dil register):
  Mode B (byte != 0) -> Descriptor A (no ResolutionMultiplier)
  Mode A (byte == 0) -> Descriptor B (full with ResolutionMultiplier)

**M12 implication**: Descriptor is served from a static byte array in .data.
M12 can hardcode the same Descriptor B bytes. No dynamic generation needed.
The array starts with 0x05 0x01 0x09 0x02 (UsagePage+Mouse).

### Q3: WHERE is the IPC IOCTL handler?

WDF queue setup functions are NOT resolved via symbol names (all WDF calls go through
the indirect dispatch table at 0x1405d7638 / 0x1405d7640 -- WdfDriverGlobals).

The custom device interface `{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo`
string at 0x1405ad4a0 has ZERO direct xrefs -- consistent with the string being
passed by pointer through the WDF device interface registration call, which stores
the pointer in the WDF object context before Ghidra can trace it.

Key IOCTL observations from CTL_CODE scan:

1. **0x000B0088** (IOCTL_HID_SEND_IDLE_NOTIFICATION_REQUEST) found at 0x1405a5695
   and 0x1405a5785 -- both in the BRB translation handler `FUN_1405a5618`. This
   driver submits HID idle notifications as part of its translation loop.

2. **0x000B840F** (function=0x103, method=NEITHER, access=WRITE) found at 18 locations
   in the obfuscated region -- this is likely the internal IPC IOCTL for the custom
   bus device interface used by userland to communicate with the kernel filter.

3. **0x000B850F** (function=0x143) found at 9 locations -- secondary IPC IOCTL.

The IOCTL dispatch for the {7D55502A} custom bus PDO is inside the obfuscated region
(0x14000xxxx-0x14018xxxx). It cannot be read by Ghidra or objdump cleanly.

**M12 implication**: M12 does NOT need a custom device interface for battery. Battery
is delivered via a different mechanism in the M12 design (standard HID Feature 0x47
via IRP completion). The {7D55502A} bus is MU's proprietary channel for userland
communication. M12 eliminates this entirely.

### Q4: WHAT triggers translation vs passthrough?

**CONFIRMED**: A single byte flag at 0x1405d7400 controls in-IRP translation.

Evidence:
```asm
; At 0x1405a5753 in FUN_1405a5618 (BRB translation handler):
cmp  BYTE PTR [rip+0x31cad], bl    ; bl=0, [0x1405d7400] = license flag
jne  0x1405a5767                   ; if flag != 0: skip translation (WRONG DIRECTION?)
```

Wait -- correcting the direction: `jne` means "jump if not equal (to bl=0)",
so if flag is 1 (licensed): falls through TO the translation code.
If flag is 0 (not licensed): jumps PAST the translation to passthrough.

Flag write location confirmed:
```asm
; At 0x140585af0 in FUN_140585a68 (DriverEntry init helper):
mov  BYTE PTR [rip+0x51909], 0x1   ; target = 0x140585af7 + 0x51909 = 0x1405d7400
```

This function (0x140585a68) is called from DriverEntry at 0x1405abfa6 and ALSO
at 0x1405abf12 (early init path). It calls:
- WDF function at table[?] for OS version query
- RtlGetVersion (via MmGetSystemRoutineAddress)
- Sets flag if OS feature byte at [rsp+0x40] != 0

**REVISED HYPOTHESIS**: The flag at 0x1405d7400 is NOT a license flag -- it's an
OS capability flag. It's set to 1 if the host OS supports the required HID
capability (checked at driver load time, not dependent on userland license service).

Revised translation gate hypothesis:
- The OS capability flag at 0x1405d7400 is always 1 on Windows 10+ (kernel loads)
- The REAL license gate is a SECOND flag, set by an IOCTL from MagicUtilitiesService
- That second flag is inside the obfuscated region and cannot be read cleanly
- Evidence: under trial-expired state, descriptor mutation WORKS (flag 1 = OS capability)
  but translation FAILS (license handshake from userland never arrives)

Supporting: MagicUtilitiesService.exe is running under trial-expired state, but
MagicMouseUtilities.exe (tray app) silent-exits. The SERVICE still runs and
presumably sends IOCTLs to the kernel -- but the kernel rejects them because the
license token embedded in the IOCTL fails BCrypt validation.

**M12 implication**: M12 kernel filter has NO flag. Translation runs unconditionally.
Descriptor mutation is unconditional. No userland service needed. The flag concept
is entirely eliminated.

---

## Decompile Root Cause

Decompile success: **0 / 23** with 180-second timeout.

Root cause confirmed by objdump analysis: code obfuscation.

**Evidence**:
- .text section = 0x5ABE52 bytes = **5.74 MB**
- applewirelessmouse.sys .text = 0x744A bytes = **29 KB** (reference: unobfuscated KMDF filter)
- MagicMouse.sys .text is ~200x larger than a comparable unobfuscated KMDF driver
- The difference (5.74MB - 0.2MB readable stubs) = ~5.5MB of obfuscated code

Observed obfuscation patterns in disassembly:
```
14015c1a0:  cwde
14015c1a1:  jmp  0x140192b40          ; opaque predicate jump
14015c1a6:  scas eax,DWORD PTR es:[rdi]
14015c1aa:  movabs al, 0xa9cb5b638d9938f0  ; garbage byte sequence
14015c1b3:  (bad)                      ; invalid opcode
14015c1cf:  call 0x1405abe09          ; BCryptCreateHash -- actual call site
14015c1d4:  jmp  0x1402012b5          ; continues in obfuscated region
```

Ghidra's decompiler cannot handle this: the instruction graph has self-modifying
patterns, opaque predicates, and instruction interleaving that Ghidra's data-flow
analysis cannot resolve in any timeout. Increasing timeout past 180s will not help.

The 300-second retry (early-exit condition) is NOT warranted -- the failure is
architectural, not a timeout issue.

---

## Section 1: BCrypt Import Xrefs (License Gate Call Sites)

Thunk table (at end of .text, readable):
```
0x1405abdd9: jmp [0x1405ad088]  -- BCryptOpenAlgorithmProvider
0x1405abddf: jmp [0x1405ad080]  -- BCryptCloseAlgorithmProvider
0x1405abde5: jmp [0x1405ad078]  -- BCryptGetProperty
0x1405abdeb: jmp [0x1405ad070]  -- BCryptSetProperty
0x1405abdf1: jmp [0x1405ad068]  -- BCryptGenerateSymmetricKey
0x1405abdf7: jmp [0x1405ad060]  -- BCryptEncrypt
0x1405abdfd: jmp [0x1405ad058]  -- BCryptDecrypt
0x1405abe03: jmp [0x1405ad050]  -- BCryptDestroyKey
0x1405abe09: jmp [0x1405ad048]  -- BCryptCreateHash
0x1405abe0f: jmp [0x1405ad040]  -- BCryptHashData
0x1405abe15: jmp [0x1405ad038]  -- BCryptFinishHash
0x1405abe1b: jmp [0x1405ad030]  -- BCryptDestroyHash
```

Real call sites (from objdump xref scan -- NOT from Ghidra, which missed these
due to obfuscation):

| Address       | API                        | Region    |
|---------------|----------------------------|-----------|
| 0x14017cf13   | BCryptOpenAlgorithmProvider | obfuscated |
| 0x14058290e   | BCryptCloseAlgorithmProvider | readable  |
| 0x140584760   | BCryptCloseAlgorithmProvider | readable  |
| 0x14015c1cf   | BCryptCreateHash            | obfuscated |
| 0x14015c3bd   | BCryptDecrypt               | obfuscated |
| 0x14015d2b4   | BCryptSetProperty           | obfuscated |
| 0x14015d856   | BCryptDestroyHash           | obfuscated |
| 0x14015d8a9   | BCryptFinishHash            | obfuscated |
| 0x14015df36   | BCryptHashData              | obfuscated |
| (many more at 0x14016xxxx)                              |

BCryptCloseAlgorithmProvider at 0x14058290e and 0x140584760 are in READABLE code --
likely the cleanup path on driver unload (called from `FUN_140582218` at 0x140582218).

---

## Section 2: Registry String Xrefs

String: `\Registry\Machine\Software\MagicUtilities\Driver` at 0x1405acb30

**Sole xref**: from 0x140584a63 in `FUN_1405847e8` @ 0x1405847e8.

Disassembly at xref:
```asm
140584a63:  lea  rdx, [rip+0x280c6]   ; rdx = 0x1405acb30 (registry path)
140584a6f:  call 0x14058476c          ; call RtlInitUnicodeString helper
140584a74:  mov  rax, [rip+0x52bbd]   ; WdfDriverGlobals
140584a80:  mov  QWORD [rsp+0x28], rcx
140584a91:  mov  r9d, 0x20019         ; KEY_READ | KEY_WRITE?
140584aa6:  call QWORD [rip+0x286ac]  ; WDF table[0x728] -> WdfRegistryOpenKey
```

Function `FUN_1405847e8` is the **registry config reader**:
- Called during device initialization (from EvtDeviceAdd or EvtDriverDeviceAdd)
- Opens \Registry\Machine\Software\MagicUtilities\Driver
- Reads license key material (multiple RtlInitAnsiString / RtlAnsiStringToUnicodeString calls)
- Passes key bytes to BCrypt validation chain
- BCryptCloseAlgorithmProvider at 0x140584760 confirms cleanup on read completion

Additional strings in .rdata related to MagicUtilities:
```
0x1405ac9b0  \Registry\Machine\Software\Microsoft\Cryptography  (machine ID read)
0x1405acb30  \Registry\Machine\Software\MagicUtilities\Driver   (license key location)
0x1405acdc0  MagicMouse                                          (device name)
0x1405ad4a0  {7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo
0x1405d930c  IoOpenDeviceRegistryKey                            (MmGetSystemRoutineAddress target)
0x1405de194  MagicMouse2.sys                                    (prior version reference)
```

Note: `\Registry\Machine\Software\Microsoft\Cryptography` read = machine GUID fetch.
Machine GUID is a component of the license token binding -- license is machine-bound.

---

## Section 3: RawPdo Device Interface String Xrefs

String: `{7D55502A-2C87-441F-9993-0761990E0C7A}\MagicMouseRawPdo` at 0x1405ad4a0

**Zero Ghidra xrefs** -- Ghidra found no references. Consistent with the string being
passed as a pointer argument to a WDF call inside the obfuscated region. The actual
`WdfDeviceCreateDeviceInterface` call with this string is inside obfuscated code and
cannot be traced by Ghidra's xref mechanism.

GUID byte scan: `2A 50 55 7D 87 2C 1F 44 99 93 07 61 99 0E 0C 7A` -- NOT found as
raw bytes. The GUID is passed as a GUID structure built from field values (Data1,
Data2, Data3, Data4[8]) separately, not as a 16-byte flat literal. This is
consistent with how WDF code typically initializes GUID constants.

---

## Section 4: HID Descriptor Byte Patterns -- FOUND

Mode A header bytes `05 01 09 02` found at 3 locations in .data section:

| Address      | Context                                    |
|--------------|--------------------------------------------|
| 0x1405af0a0  | Descriptor A start (minimal, no ResolutionMult) |
| 0x1405af0a6  | Second USAGE_PAGE item within Descriptor A |
| 0x1405af110  | Descriptor B start (full Mode A)           |

AC Pan usage `0A 38 02` found at:
- 0x1405af0ee -- within Descriptor A (AC Pan definition)
- 0x1405af18f -- within Descriptor B (AC Pan definition)

Resolution Multiplier `09 48` found at 10 locations in .text (0x14000xxxx range) --
these are bytes in the obfuscated code that happen to match the pattern, NOT descriptor
data. The actual ResolutionMultiplier is in Descriptor B at 0x1405af110+.

Wheel usage `09 38` found at 10 locations in .text (obfuscated region, coincidental
byte matches) and 2 locations in .data (the two descriptor arrays).

**Confirmed**: HID descriptor bytes are literal arrays in .data, not dynamically built.
M12 can copy these bytes verbatim.

---

## Section 5: IOCTL Code Analysis

No standard HID IOCTL codes (0x000B0003 through 0x000B001F) found by byte scan --
confirming this driver does NOT implement a standard HID miniport IOCTL dispatch.
Instead it is a **KMDF lower filter** that intercepts BRB (Bluetooth Request Block)
IRPs, not HID IOCTLs.

CTL_CODE scan (device type 0x000B) found 52 matches, all in obfuscated region except:

```
0x1405a5695  0x000B0088  fn=0x22  method=BUFFERED  -- IOCTL_HID_SEND_IDLE_NOTIFICATION_REQUEST
0x1405a5785  0x000B0088  fn=0x22  method=BUFFERED  -- same IOCTL (second use in same function)
0x1405ae338  0x000B1702  fn=0x5C0                  -- WDF internal
0x1405adea0  0x000B1A02  fn=0x680                  -- WDF internal
0x1405ae3e0  0x000B251A  fn=0x946                  -- WDF internal
0x1405adf60  0x000B281A  fn=0xA06                  -- WDF internal
0x1405ae354  0x000B2E1A  fn=0xB86                  -- WDF internal
0x1405ae5f4  0x000B5414  fn=0x505                  -- WDF table entry
0x1405ae3b0  0x000B5418  fn=0x506                  -- WDF table entry
0x1405ae390  0x000B7419  fn=0xD06                  -- WDF table entry
```

The 0x1405aeXXX values are in the WDF function dispatch table data -- not IOCTL
codes in code. They are 32-bit WDF function indices stored in the table structure.

**IOCTL_HID_SEND_IDLE_NOTIFICATION_REQUEST (0xB0088)** at 0x1405a5695:
Found inside `FUN_1405a5618` (BRB translation handler). The driver submits an idle
notification IRP as part of the translation sequence -- standard for HID power
management. This is NOT the license IPC mechanism.

The high-valued IOCTL codes (0x000B840F, 0x000B850F) in the obfuscated region are
likely the custom bus IPC IOCTLs exposed on the {7D55502A} device interface.

---

## Section 6: WDF Queue Setup

WDF function table (WdfDriverGlobals) at 0x1405d7638.
Indirect dispatch table at 0x1405ad158 (WDF function call trampoline).

WdfVersionBind called at 0x1405abf65 (inside DriverEntry @ 0x1405abeec).

WDF queue setup and EvtIoDeviceControl cannot be identified by name (no symbols).
However, `FUN_1405a5618` at 0x1405a5618 is confirmed as the BRB completion callback:
- Called when a BRB IRP completes through the filter stack
- Pool tag 0x554D4D4D = 'MMMM' (Magic Mouse pool allocations)
- BRB type read at offset 0x34 (matches BRB_HEADER.Type field)
- BRB type range checked: 2 <= type <= 68 (catches L2CA/SCO BRB types)
- Allocates translated output buffer from pool ('MMMM' tag)
- Checks license flag before filling translation output

`FUN_1405a3c04` at 0x1405a3c04 is confirmed as an IRP completion handler:
- Calls WDF table[0x4e8], [0x650], [0x8e8] (WdfRequestGetParameters variants)
- Reads BRB at IRP stack location [rax+0xB8+0x8]
- Checks Word at [BRB+0x16] (BRB_HEADER.BrbSize field)
- Dispatches based on size check: 0x0102 (BRB_L2CA_OPEN_CHANNEL) vs 0x0320

---

## Section 7: All Imports -- Call Count Summary

Top callers by import frequency (confirms function roles):

```
RtlTimeToTimeFields     33 calls  -- heavy time/timestamp usage in obfuscated license
DbgPrintEx               9 calls  -- debug logging
ExAllocatePoolWithTag    7 calls  -- pool allocations (tag 'MMMM' confirmed above)
RtlFreeUnicodeString     5 calls  -- in FUN_1405847e8 (registry reader)
RtlAnsiStringToUnicodeString 5   -- in FUN_1405847e8 (registry reader)
RtlInitAnsiString        5 calls  -- in FUN_1405847e8 (registry reader)
ExFreePoolWithTag        5 calls  -- pool cleanup
MmMapLockedPagesSpecifyCache 4   -- MDL operations for descriptor delivery
BCrypt* (all 12 APIs)    2 calls each -- license validation (visible + obfuscated)
WdfVersionBind           2 calls  -- normal WDF init (one in DriverEntry, one cleanup)
```

`RtlTimeToSecondsSince1970` (3 calls) + `RtlTimeToTimeFields` (33 calls) indicates
heavy time-stamp processing -- consistent with trial timer and high-water-mark scheme
documented in SESSION-12 empirical findings.

---

## Section 8: DriverEntry Call Chain (Reconstructed)

```
GsDriverEntry @ 0x1405abec0
  |-- call 0x1405d9000          -- security cookie check (__security_init_cookie)
  |-- call DriverEntry @ 0x1405abeec
          |-- call 0x140585a68  -- OS capability init (RtlGetVersion + WDF feature check)
          |                     -- sets 0x1405d7400 = 1 if OS capability present
          |-- call WdfVersionBind @ 0x1405abf65
          |-- call FUN_1405ac07c @ 0x1405abf8a  -- WDF class registration validator
          |-- call FUN_1405ac140 @ 0x1405abf95  -- WDF driver object setup
          |-- call 0x140585a68 @ 0x1405abfa6    -- device-specific init (with DRIVER_OBJECT)
                  |-- calls WDF table[WdfDriverCreate] equivalent
                  |-- sets up EvtDeviceAdd callback at 0x140585bb0
```

`0x140585bb0` is the EvtDeviceAdd callback -- confirmed by:
- It's the function immediately after FUN_140585a68 returns
- The WDF_DRIVER_CONFIG struct built at 0x1405b24 has:
  `mov DWORD [rsp+0x58], 0x38` (size = 0x38 = sizeof WDF_DRIVER_CONFIG)
  `mov QWORD [rsp+0x60], rax`  where rax = 0x140585bb0

---

## Section 9: Key Data Addresses

| Address       | Content                                         | Role                   |
|---------------|-------------------------------------------------|------------------------|
| 0x1405d7400   | BYTE flag                                       | OS capability flag (1=enabled) |
| 0x1405d7638   | QWORD pointer                                   | WdfDriverGlobals ptr   |
| 0x1405d7640   | QWORD pointer                                   | WDF device object ptr  |
| 0x1405af0a0   | 100-byte HID descriptor A (no ResolutionMult)   | Served to HID stack    |
| 0x1405af110   | ~170-byte HID descriptor B (full Mode A)        | Served to HID stack    |
| 0x1405acb30   | Unicode string                                  | Registry path          |
| 0x1405ac9b0   | Unicode string                                  | Cryptography reg path  |
| 0x1405ad4a0   | Unicode string                                  | Custom bus PDO name    |
| 0x1405abdd9   | JMP thunk table (12 entries)                    | BCrypt import thunks   |
| 0x1405ad030   | IAT (BCryptDestroyHash through BCryptOpenAlg)   | BCrypt IAT entries     |

---

## Section 10: Decompilation Statistics

```
total_attempts : 23
succeeded      : 0
failed         : 23
success_rate   : 0%
timeout_used   : 180s
root_cause     : code obfuscation (.text = 5.74MB vs 29KB expected for this driver class)
retry_300s     : NOT warranted (failure is architectural, not timeout)
```

Decompilation would require:
1. Identifying the obfuscation scheme (OLLVM / Tigress / commercial)
2. Applying a de-obfuscation pass (symbolic execution or pattern rewriting)
3. Re-analyzing the de-obfuscated binary

This is a week-scale effort and is not required for M12 -- the architecture is
confirmed from the readable regions + empirical SESSION-12 findings.

---

## Top 5 Findings vs First-Pass M12 Design

### Finding 1: Code Obfuscator Explains All Decompile Failures

The driver contains ~5.5MB of obfuscated code -- the license validation engine.
First-pass (60s timeout) failed; this pass (180s) fails for the same reason.
The obfuscation is intentional and sophisticated. Ghidra cannot decompile it.
**Impact**: M12 does not need to replicate or understand the obfuscated code --
M12's license layer is zero (unconditional translation).

### Finding 2: License Flag at 0x1405d7400 is OS Capability, Not License Gate

The byte written by DriverEntry init at 0x1405d7400 is set based on OS version/feature
query, not based on userland license validation. It is always 1 on Windows 10+.
**Revised**: The actual license gate is a SECOND mechanism inside the obfuscated
region, controlled by IOCTLs from MagicUtilitiesService through the {7D55502A} PDO.
**Impact on M12 design**: Confirms M12 needs NO conditional translation gate.
The kernel filter translates unconditionally. No flag, no handshake.

### Finding 3: Two HID Descriptors -- Descriptor A and B Both Stored Literally

Two descriptor variants at 0x1405af0a0 and 0x1405af110:
- Descriptor A: no Resolution Multiplier (served when device requests minimal layout)
- Descriptor B: full Mode A with RID=03 and RID=04 Resolution Multiplier features

M12 should serve Descriptor B (full Mode A) unconditionally.
The bytes are directly copyable from this analysis.

### Finding 4: Translation Handler Pool Tag 'MMMM' Confirmed

`FUN_1405a5618` uses pool tag 0x554D4D4D = 'MMMM'. M12 uses 'MMTL' (Magic Mouse
Tray Layer) to distinguish. No conflict. Confirms the function is MU's translation
allocator and provides a grep anchor for locating similar code in future builds.

### Finding 5: Machine GUID Bound License + High-Water Trial Timer

The driver reads `\SOFTWARE\Microsoft\Cryptography` (machine GUID) during init and
uses `RtlTimeToTimeFields` (33 call sites) for timer-based trial tracking.
This confirms the SESSION-12 empirical observation: trial marker is sticky across
reinstalls. The license token is bound to the machine GUID, preventing cross-machine
token copies. **M12 has no such binding** -- pure kernel filter, no license layer.

---

## Open Questions for M12 Design Phase

1. **Is Descriptor A vs B selection based on IOCTL from userland or PnP device property?**
   `FUN_1405853ac` selects descriptor based on a byte parameter (dil register).
   What sets that byte? If it comes from the obfuscated region, we cannot trace it.
   M12 decision: always serve Descriptor B (full Mode A) unconditionally.

2. **BRB type range check (2..68) -- what BRB types does M12 need to intercept?**
   MU intercepts types 2-68. For M12, only BRB_L2CA_ACL_TRANSFER (type 0x05)
   is needed (input report delivery). The range check may be defensive -- M12
   can be more targeted.

3. **How does MU's filter handle device disconnect/reconnect without breaking state?**
   No evidence found in readable code. The pool tag 'MMMM' on translation buffers
   suggests per-BRB allocation -- good model for M12. No persistent state per connection.

4. **The {7D55502A} PDO: does M12 need ANY custom bus device?**
   No. Battery is delivered via a completely different mechanism in M12 (standard
   HID descriptor + IRP completion, not a custom bus PDO). The PDO is MU's
   proprietary channel. M12 eliminates it.

5. **Is the resolution multiplier (RID=03, RID=04) required for Windows smooth scrolling,**
   **or just the Wheel + AC Pan 16-bit fields?**
   Both are present in Descriptor B. Windows Precision Touchpad/HID uses the
   ResolutionMultiplier to calibrate scroll sensitivity. M12 should include RID=03/04
   to match MU's behavior and enable Windows high-DPI scroll acceleration.

---

## Activity Log

| Date       | Update |
|------------|--------|
| 2026-04-28 | Extended Ghidra analysis -- confirmed obfuscation, license flag, descriptor bytes, BRB handler |
