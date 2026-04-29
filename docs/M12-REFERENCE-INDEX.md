# M12 Reference Index

## BLUF

Consolidated specifications, kernel driver frameworks, HID standards, and reverse-engineered reference materials for M12 KMDF filter driver development. Feeds Phase 2 (design spec) and Phase 3 (implementation). References are read-only, clean-room implementation only per AP-22/AP-23 anti-patterns.

---

## Microsoft KMDF + WDF Documentation

### WDF Core
- [WDF Index (Microsoft Learn)](https://learn.microsoft.com/en-us/windows-hardware/drivers/wdf/) — KMDF 1.33 baseline, framework overview, supported OS versions
- [Introduction to Framework Objects](https://learn.microsoft.com/en-us/windows-hardware/drivers/wdf/introduction-to-framework-objects) — object model, reference counting, parent-child hierarchy, lifetime management
- [Framework Object Hierarchy](https://learn.microsoft.com/en-us/windows-hardware/drivers/wdf/framework-object-hierarchy) — WDFDRIVER, WDFDEVICE, WDFQUEUE, WDFREQUEST, parent-child relationships
- [KMDF Version History](https://learn.microsoft.com/en-us/windows-hardware/drivers/wdf/kmdf-version-history) — KMDF 1.15 (Windows 10), 1.33 (Windows 11), API changes per version
  * KMDF 1.15: baseline for filter drivers, public WDF source code, Inflight Trace Recorder (IFR) support
  * KMDF 1.33: latest, PoFx improvements, SystemManagedIdleTimeout enhancements

### Driver Development
- [Sending I/O Requests to Lower Drivers](https://learn.microsoft.com/en-us/windows-hardware/drivers/wdf/sending-i-o-requests-to-lower-drivers) — WdfIoTargetSendIoctlSynchronously, request forwarding, synchronous/asynchronous patterns, completion routines

### Installation and Device Management
- [Device and Driver Installation (Microsoft Learn)](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/) — roadmap, driver selection, ranking, installation process
- [INF File Sections and Directives](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-file-sections-and-directives) — [Models], [DDInstall], [DDInstall.HW], [ServiceInstall], AddReg, AddService, hardware ID matching

---

## HID Specifications and Architecture

### Official HID Standards
- USB HID 1.11 Specification — **local: /tmp/m12-refs/hid1_11.pdf** (1.0 MB)
  * Report descriptor structure, collections, usage pages, input/output/feature reports
  * Report IDs, field values, packing rules
  * Bluetooth HID profile inheritance
- USB HID Usage Tables 1.4 — **local: /tmp/m12-refs/hut1_4.pdf** (4.3 MB)
  * Mouse usage page (0x0001, Usage 0x0002), button caps, coordinate systems
  * Wheel, AC Pan (Usage 0x238), Resolution Multiplier (Usage 0x48)
  * Vendor-defined pages (0xFF00+)

### Microsoft HID Architecture and Documentation
- [HID Architecture (Microsoft Learn)](https://learn.microsoft.com/en-us/windows-hardware/drivers/hid/hid-architecture) — hidclass.sys, HID clients, transport minidrivers, stack layout
- [HID Transport Overview](https://learn.microsoft.com/en-us/windows-hardware/drivers/hid/hid-transports) — Bluetooth HID (Hidbth.sys), USB HID (Hidusb.sys), BLE (HidBthLE.dll)
  * Hidbth.sys: in-box Bluetooth HID minidriver, 64 KB report limit
  * Report descriptor length limits (65535 bytes), TLC limits (21845)
- [HID Over I2C Guide](https://learn.microsoft.com/en-us/windows-hardware/drivers/hid/hid-over-i2c-guide) — HID miniport patterns, device enumeration, ACPI resources ordering

---

## Bluetooth HID Profile

### Specifications (READ-ONLY)
- Bluetooth HID Profile 1.1 (Bluetooth SIG) — free download at https://www.bluetooth.org/
  * L2CAP CID 0x11 (Control channel), 0x13 (Interrupt channel)
  * HID data formats, control signaling, virtual cable semantics

### Windows Implementation Reference
- Hidbth.sys driver reference (in Windows DriverStore)
  * Transport minidriver for Bluetooth devices
  * Handles pairing state, device discovery, report delivery
  * Used by applewirelessmouse.sys and other HID filters

---

## Linux Apple Magic Mouse Driver (GPL-2.0, READ-ONLY)

### Source Reference
- **Local: /tmp/m12-refs/hid-magicmouse.c** (32 KB)
  * Copyright: Michael Poole, Chase Douglas
  * Version control: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/hid/hid-magicmouse.c
  * Module parameters: emulate_3button, emulate_scroll_wheel, scroll_speed, scroll_acceleration
  * Platform-specific handling: trackpad coordinate transformation, click emulation
- **Kernel git history**: git log drivers/hid/hid-magicmouse.c at https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/
  * Check commit history for firmware/device version handling
  * Scroll multiplier constants and tuning parameters

**License note**: GPL-2.0 source code. Do NOT copy verbatim. Use for API patterns and algorithms only. M12 is independent clean-room implementation.

---

## Windows Driver Signing and Installation Tools

### SignTool Reference
- [SignTool (Microsoft Learn)](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool) — code signing tool
  * `signtool sign /fd SHA256 /a <driver.sys>` — sign driver with test certificate
  * `/t` (legacy timestamp server), `/tr` (RFC 3161 timestamp), `/td SHA256` (digest algorithm)
  * `/n "Subject Name"` — select certificate by subject
  * `/f <cert.pfx> /p <password>` — sign with PFX file

### PnPUtil Reference
- [PnPUtil Command Syntax (Microsoft Learn)](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax) — driver installation and enumeration
  * `/add-driver <inf> /install /reboot` — install driver from INF, auto-install on matching devices
  * `/delete-driver <oem#.inf> /uninstall /force` — remove driver from DriverStore
  * `/enum-drivers` — list installed drivers with their status
  * `/enum-devices /instanceid <id> /drivers` — enumerate devices with matching drivers

### Driver Verifier Reference
- [Driver Verifier (Microsoft Learn)](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/driver-verifier) — runtime kernel driver verification
  * `verifier /standard /driver MagicMouseFilter.sys` — enable verification on driver
  * Detects pool corruption, illegal function calls, IRP violations
  * Essential for pre-install validation

---

## Windows Kernel Debugging and Analysis Tools

### Static Analysis
- dumpbin — PE import table analysis
  * `dumpbin /imports MagicMouse.sys` — list KMDF version, WDF APIs, hidclass/hidparse dependencies
  * Expected imports: Wdf01000.sys (KMDF), ntoskrnl.exe, hidclass.sys
- strings — literal string extraction from binary
  * `strings -n 8 MagicMouse.sys` — find IOCTL codes, version strings, debug paths
  * Look for: 0x000B0003 (IOCTL_HID_GET_REPORT_DESCRIPTOR), 0x000B0192 (IOCTL_HID_GET_FEATURE)

### Decompilation Reference
- Ghidra — free, open-source reverse engineering tool
  * Download: https://ghidra-sre.org
  * Import PE binaries, auto-analyze with Microsoft PDB symbols
  * Targets: DriverEntry, EvtDriverDeviceAdd, EvtIoDeviceControl (IOCTL dispatch)
  * Key pattern to identify: 0x47→0x90 GET_REPORT redirect logic

---

## Local Project Artifacts Already Captured

### Magic Utilities Reference Capture (Trial Expired, KMDF 1.15)
- **Location**: D:\Backups\MagicUtilities-Capture-2026-04-28-1937\
  * Size: 78.6 MB, 41 files
  * Kernel driver: MagicMouse.sys v3.1.5.3, WHQL-signed
  * INF template: magicmouse.inf (multi-PID, both v1 0x030D and v3 0x0323)
  * Service configuration: registry exports (HKLM\SYSTEM\CurrentControlSet\Services\MagicMouse)
  * Userland: MagicUtilitiesService.exe, MagicMouseUtilities.exe (trial-locked, do NOT run post-uninstall)
- **Captured via**: /scripts/mm-magicutilities-capture.ps1 (663 lines, fail-closed)
- **Post-capture action**: UNINSTALL via Settings > Apps > Uninstall (do NOT manipulate trial registry)

### HID Descriptor Captures
- **Mode A (MagicMouse filter active, trial expired)**:
  * /tmp/magic-mouse-tray/.ai/test-runs/2026-04-27-154930-T-V3-AF/hid-descriptor-full-v3-col01.txt
  * Layout: Input 8 bytes, Feature 2 bytes, 5 link collections
  * Wheel (16-bit), AC Pan (16-bit), Resolution Multipliers (RID 0x03, 0x04)
  * NO Feature ReportID 0x47 declared (unlike Mode B)
- **Mode B (applewirelessmouse filter active, baseline)**:
  * /tmp/magic-mouse-tray/.ai/test-runs/2026-04-27-154930-T-V3-AF/hid-descriptor-full-v3.txt
  * Input 47 bytes (includes vendor blob RID 0x27), Feature 2 bytes
  * Feature ReportID 0x47 (synthesized battery)
  * 8-bit Wheel at RID 0x02

### Ghidra Analysis Project
- **Location**: .ai/M12-MagicMouse.{gpr,rep}
  * MagicMouse.sys v3.1.5.3 imported and auto-analyzed
  * Symbol resolution enabled (Microsoft PDB server)
  * Navigation targets: DriverEntry, EvtDriverDeviceAdd, EvtIoDeviceControl, PID-branching logic
  * Decompiled 0x47→0x90 redirect pattern (50 LOC target)

---

## Reverse-Engineering Findings

### Session 12 Empirical Evidence (2026-04-28)
- **Reference doc**: /docs/SESSION-12-MU-INSTALLED-EMPIRICAL-FINDINGS.md
  * Mode A descriptor mutation works (kernel filter applies it unconditionally)
  * Trial-expired userland service breaks scroll and battery (IOCTL handshake gate)
  * Battery delivery via custom device interface {7D55502A-2C87-441F-9993-0761990E0C7A}, not standard HID
  * v1 (0x030D) native Feature 0x47 support, v3 (0x0323) firmware gap confirmed
  * All standard HID probe attempts fail under Mode A (GLE=87, GLE=1 on wrong APIs)
  * Kernel driver self-contained hypothesis: filter descriptor mutation unconditional, translation gate status TBD

### M12 Design Implications
- **Pure-kernel architecture** (~300-500 LOC KMDF scaffold + 50 LOC translation logic)
- **Lower filter pattern** (WdfFdoInitSetFilter, register on HidBth parent)
- **No userland service required** (translation occurs unconditionally in kernel or with internal gating)
- **v1/v3 firmware gap handling** (PID-based branch, v1 pass-through, v3 0x47→0x90 redirect)
- **INF template** derived from captured magicmouse.inf, with custom M12-specific strings and service name

---

## Known Gaps and Out-of-Scope Items

| Gap | Reason | Mitigation |
|---|---|---|
| Native v3 firmware HID descriptor (BT firmware) | Requires Bluetooth sniffer (hardware not in scope) | Capture pre-filter descriptor from Windows + reverse behavior |
| WHQL submission process | Certification out of scope for dev driver | Use test-signing with test certificate for development |
| Userland MagicMouseUtilities compatibility | Not required; M12 is kernel-only solution | Existing tray app can read Feature 0x47 via M12 without changes |
| Detailed trial-marker format | Irrelevant; no trial logic in M12 | Not pursued per AP-23 (avoid license circumvention) |

---

## Reference Fetching Summary

**Total sources cataloged**: 19 primary references (12 Microsoft Learn, 2 USB PDFs, 1 Linux source, 4 other)

**Fetched artifacts**: 
- USB HID 1.11 spec: 1.0 MB
- USB HID Usage Tables 1.4: 4.3 MB
- Linux hid-magicmouse.c: 32 KB
- WebFetch summaries: 9 Microsoft Learn pages (metadata extracted, content summarized)

**Failed fetches**: 2
- IOCTL_HID_* directive list (404, alternate not found)
- KMDF object summary by type (404, information merged into other docs)

**License compliance**:
- Linux GPL-2.0 source: linked, NOT vendored, READ-ONLY reference only
- Microsoft documentation: citation + links, public CC license
- USB specs: direct download links (public domain from USB-IF)
- Magic Utilities binary: internal reference only, NOT redistributed (AP-22)

---

## How to Use This Index

1. **Phase 2 (Design Spec)**: Read Microsoft WDF + HID sections + Magic Utilities findings. Define INF structure, KMDF scaffolding, IO queue layout, callback signatures.

2. **Phase 3 (Implementation)**: Use KMDF version history to target KMDF 1.15 (Windows 10 baseline). Reference Ghidra decompilation for 0x47→0x90 pattern. Follow hid-magicmouse.c for algorithm ideas (NOT code copy). Use SignTool + PnPUtil references for build/test/install workflow.

3. **Reverse-Engineering Verification**: If stuck on architecture decision, check Session 12 findings PDF for empirical constraints (Mode A descriptor, userland vs kernel gating, battery interface location).

4. **Reference Binary Analysis**: MagicMouse.sys at D:\Backups\... — use dumpbin /imports, strings, Ghidra as documented above. INF at same path; extract to M12-TEMPLATE.inf.

---

**Document version**: 1.0  
**Last updated**: 2026-04-28  
**Session**: ai/m12-references worktree  
**Compiler**: Claude Haiku 4.5 (M12 reference gathering mission)
