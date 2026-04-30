---
created: 2026-04-29
modified: 2026-04-29
type: blocker-analysis
status: BLOCKED — architecture fundamentally wrong
---

# M12 Architectural Blocker — 2026-04-29

## TL;DR

After ~12 hours of build/install/test cycles on the live device, we have **proof that the BRB-lower-filter SDP descriptor injection mechanism does not work on this Bluetooth stack.** Every successful enumeration (COL01 mouse + COL02 vendor battery) we observed under M12 was Apple's *native* descriptor declaration, not our injection. M12 as currently architected cannot deliver scroll on Magic Mouse 2024 over BT.

System ended the day on Apple's `applewirelessmouse.sys` driver (working: cursor + scroll). M12 is not installed.

## How we found out

### Linux's 0xF1 SET_REPORT does not apply on Windows BT

Empirical: `xxd` on both `applewirelessmouse.sys` and `MagicMouse.sys` (MagicUtilities). The byte sequence `F1 02 01` (Linux's `feature_mt_mouse2` for PID 0x0323) is **absent from both binaries**. The Linux `magicmouse_enable_multitouch()` mechanism does not transfer to the Windows BT path.

### Per NotebookLM corpus query (today)

- **Apple's `applewirelessmouse.sys`**: sends NO command to the device. v3 firmware *natively* synthesizes scroll on `RID=0x02` (8-bit X/Y/AC-Pan/Wheel fields). Apple's filter just replaces the SDP HID descriptor at pairing time with a 116-byte "Descriptor B" that maps RID=0x02 to standard Generic Desktop Mouse usages.
- **MagicUtilities `MagicMouse.sys`**: enables RID=0x12 multi-touch via Feature Report **0x55** (NOT 0xF1) sent from the userland service via `HidD_SetFeature`. Out of scope for M12.

Source: `docs/M12-DESCRIPTOR-B-ANALYSIS-2026-04-29.md` and the corpus citations noted in tonight's night-run log.

### Our SDP injection never reached HidBth

Empirical evidence from tonight:

1. After re-pair + clearing the BTHPORT `CachedServices` registry key, the cache repopulated with the **same** 351-byte SDP service record containing Apple's RID=0x12 descriptor at offset 176 — **NOT our injected RID=0x02 descriptor**.

2. Trace ring buffer captured zero SDP-shaped frames during pairing. The buffer (16 slots × 16 bytes per frame, 1 Hz registry flush) showed only 9-byte `A1 12 ...` HID interrupt frames during cursor motion.

3. The "successful" COL02 vendor battery enumeration we kept seeing under every M12 build was actually Apple's *native* descriptor (which already declares RID=0x90 vendor at offset 261 in the 351-byte SDP record). It looked like our injection was working because the device declares the same TLC natively.

So: our descriptor injection at the BRB layer never actually intercepted the SDP HIDDescriptorList exchange. SDP traffic flows through a path our M12 lower filter does not see — likely a BTHPORT-level fast-path or a higher-layer query that doesn't propagate as `BRB_L2CA_ACL_TRANSFER` IRPs.

### Other things tried tonight, all dead-ends

- Per-request BRB context stash (FIX-4) — fine, but irrelevant when injection doesn't fire
- Multi-family adversarial review producing 4/4 APPROVE on the descriptor design — academic; the descriptor never landed
- Apple-pattern INF (`Include=hidbth.inf, Needs=HIDBTH_Inst.NT`) — fixed v1 install bug, didn't address SDP path
- Kernel-side BTHDDI SET_REPORT injection (BthAllocateBrb + IRP) — submitted with `STATUS_INVALID_PARAMETER` from BthEnum, plus we now know this entire approach (Linux's 0xF1 path) doesn't apply on Windows
- Descriptor with RID=0x02 mouse-with-embedded-AC-Pan/Wheel matching Apple's binary at offset 0xA850 — built, signed, installed, BT cache cleared, mouse re-paired, cache repopulated with the device's native RID=0x12 descriptor (not ours)

## What's actually needed for M12 to work

The architectural fix is identifying **where** Apple's filter intercepts the descriptor exchange. Likely candidates:

1. **HidClass-layer hook on `IOCTL_HID_GET_REPORT_DESCRIPTOR`** — Apple's filter may register above HidBth, not below
2. **A `QUERY_INTERFACE` minor function on a BTH profile interface** that BthEnum calls during attach
3. **A custom IOCTL the BTH stack exposes for descriptor override** that's outside the BRB submit path
4. **BTHPORT-internal SDP cache pre-population** (Apple's filter may write to that registry key directly during install)

Resolving this requires deeper Ghidra analysis of `applewirelessmouse.sys` than we have so far. Tonight's superficial `xxd`/string scan was insufficient. Specifically: trace which `IRP_MJ_*` paths Apple's `DriverEntry` registers for, and what callbacks it sets in any QUERY_INTERFACE responses.

## What we *did* validate tonight (worth keeping)

| Mechanism | Status |
|---|---|
| Admin queue (`mm-task-runner.ps1`) phases — ROLLBACK-M12, INSTALL-DRIVER, UNINSTALL-DRIVER, SIGN-FILE, RESTART-DEVICE, CLEAR-BT-SDP-CACHE | All working — no UAC clicks needed for any operation; rollback is one command |
| Per-device kernel trace ring buffer → registry → user-mode read | Working pattern, useful for any future driver work |
| BTHDDI profile driver QI from a KMDF lower filter | Compiled and ran; got `STATUS_INVALID_PARAMETER` on submit, but the IRP plumbing is correct |
| Apple-pattern INF (`Include=hidbth.inf`) | Working; M12 cleanly attaches as filter without becoming function driver |
| Cert + signing infrastructure (legacy CSP via SYSTEM-context queue) | Working; signtool-via-SYSTEM bypasses the LocalMachine\My ACL issue |

## Files

- Source on branch `ai/m12-script-tests` at HEAD `b269d5d` (worktree was pruned mid-session; trace + BTHDDI scaffolding implemented but not committed before the prune — would need re-implementation if continued)
- Driver bundle staged at `D:\mm3-driver\m12-build-final\` (last build's signed `.sys`+`.cat`, currently uninstalled)
- Reverse-engineering reports: `docs/M12-DESCRIPTOR-B-ANALYSIS-2026-04-29.md`, `docs/M12-V9-DESIGN-2026-04-29.md`
- Mouse state: Apple's `applewirelessmouse` driver bound on both v1 (PID 0x030D) and v3 (PID 0x0323), cursor + scroll working

## Recommendation for next session

1. **Do not** continue iterating on the BRB-lower-filter SDP injection approach.
2. **Do** dispatch a focused Ghidra agent on `applewirelessmouse.sys` to find the exact injection mechanism (look for `IoSetCompletionRoutine` calls registered for IRP_MJ_PNP / IRP_MJ_INTERNAL_DEVICE_CONTROL with IOCTL codes outside `IOCTL_INTERNAL_BTH_SUBMIT_BRB`).
3. Battery readout via the existing `applewirelessmouse` filter MIGHT already be feasible — Apple's native descriptor declares RID=0x90 vendor with the right usages. The tray app's `HidD_GetInputReport(0x90)` should work directly. Worth testing tomorrow before any further M12 work.
